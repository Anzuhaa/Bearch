-- Competition submission, duplicate detection helpers and admin validation.
--
-- Flow:
--   1. Student inserts a competition as 'draft' (+ proof files).
--   2. App calls the check-duplicate Edge Function. It runs
--      find_duplicate_candidates() (organizer + category + timeline + fuzzy
--      name, pg_trgm), asks Gemini to judge the top candidates, and writes
--      duplicate_status = clear | possible_duplicate | check_failed.
--   3. submit_competition(): a possible duplicate needs an override reason.
--      If the AI check never ran / failed, status becomes check_failed and the
--      admin reviews it manually (fallback).
--   4. Admin approves/rejects with admin_review_competition(); the duplicate
--      flag + override reason are visible in the admin queue.

-- Lowercase, strip edition numbers / years / roman numerals and punctuation,
-- so "Hology 8.0" and "Hology 9.0" normalise to the same string.
create or replace function public.normalize_competition_name(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select trim(regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(lower(coalesce(p, '')), '[0-9]+([.,][0-9]+)?', ' ', 'g'),
             '\m[ivx]+\M', ' ', 'g'),
           '[^a-z ]+', ' ', 'g'),
         '\s+', ' ', 'g'));
$$;

-- Rule-based candidate search. Score in [0,1]:
--   0.50 * normalized-name similarity
-- + 0.25 * organizer similarity
-- + 0.10 * same category
-- + 0.15 * timeline proximity (deadlines <= 45 days apart -> 1, <= 120 -> 0.5)
create or replace function public.find_duplicate_candidates(p_competition uuid, p_limit integer default 5)
returns table (
  competition_id uuid,
  name text,
  organizer text,
  category public.competition_category,
  registration_deadline date,
  status public.competition_status,
  name_similarity real,
  organizer_similarity real,
  same_category boolean,
  days_apart integer,
  rule_score numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select c.* from public.competitions c where c.id = p_competition
  ),
  cand as (
    select o.id,
           o.name,
           o.organizer,
           o.category,
           o.registration_deadline,
           o.status,
           extensions.similarity(lower(o.name), lower(me.name)) as raw_name_sim,
           extensions.similarity(public.normalize_competition_name(o.name),
                                 public.normalize_competition_name(me.name)) as norm_name_sim,
           extensions.similarity(lower(o.organizer), lower(me.organizer)) as org_sim,
           (o.category = me.category) as same_cat,
           abs(o.registration_deadline - me.registration_deadline) as days
      from public.competitions o, me
     where o.id <> me.id
       and o.status in ('approved', 'pending')
       and (
         extensions.similarity(public.normalize_competition_name(o.name),
                               public.normalize_competition_name(me.name)) > 0.3
         or (extensions.similarity(lower(o.organizer), lower(me.organizer)) > 0.5 and o.category = me.category)
       )
  )
  select cand.id,
         cand.name,
         cand.organizer,
         cand.category,
         cand.registration_deadline,
         cand.status,
         cand.raw_name_sim,
         cand.org_sim,
         cand.same_cat,
         cand.days,
         round((0.50 * cand.norm_name_sim
              + 0.25 * cand.org_sim
              + case when cand.same_cat then 0.10 else 0 end
              + case when cand.days <= 45 then 0.15 when cand.days <= 120 then 0.075 else 0 end)::numeric, 3)
    from cand
   order by 11 desc
   limit greatest(1, least(p_limit, 20));
$$;

-- Student submits a draft for validation.
create or replace function public.submit_competition(p_competition uuid, p_override_reason text default null)
returns public.competition_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_comp public.competitions;
  r record;
begin
  select * into v_comp from public.competitions where id = p_competition for update;
  if not found or v_comp.submitted_by is distinct from v_uid then
    raise exception 'Competition not found.' using errcode = 'P0002';
  end if;
  if v_comp.status <> 'draft' then
    raise exception 'This competition was already submitted.' using errcode = 'P0001';
  end if;
  if v_comp.registration_deadline < public.today_wib() then
    raise exception 'Registration deadline has already passed.' using errcode = 'P0001';
  end if;
  if v_comp.guidebook_url is null
     and not exists (select 1 from public.competition_files f where f.competition_id = p_competition) then
    raise exception 'Attach the official poster or guidebook as proof of legitimacy.' using errcode = 'P0001';
  end if;
  if v_comp.duplicate_status = 'possible_duplicate' and coalesce(trim(p_override_reason), '') = '' then
    raise exception 'Possible duplicate found. Add a reason to submit anyway.' using errcode = 'P0001';
  end if;

  update public.competitions
     set status = 'pending',
         submitted_at = now(),
         duplicate_override_reason = nullif(trim(p_override_reason), ''),
         -- AI check never ran or failed: fall back to manual admin review.
         duplicate_status = case when duplicate_status = 'not_checked' then 'check_failed'
                                 else duplicate_status end
   where id = p_competition;

  for r in select p.id from public.profiles p where p.role = 'admin' loop
    perform public.notify(r.id, 'competition_submitted', 'New competition to validate',
      v_comp.name || ' · ' || v_comp.organizer
        || case when v_comp.duplicate_status = 'possible_duplicate' then ' · possible duplicate' else '' end,
      jsonb_build_object('competition_id', p_competition));
  end loop;

  return 'pending';
end;
$$;

-- Admin decision. Works on pending submissions and on admin-created drafts.
create or replace function public.admin_review_competition(
  p_competition uuid,
  p_approve boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_comp public.competitions;
begin
  if not public.is_admin() then
    raise exception 'Admins only.' using errcode = '42501';
  end if;
  select * into v_comp from public.competitions where id = p_competition for update;
  if not found or v_comp.status not in ('pending', 'draft') then
    raise exception 'Competition is not awaiting review.' using errcode = 'P0001';
  end if;
  if not p_approve and coalesce(trim(p_note), '') = '' then
    raise exception 'Give a reason when rejecting.' using errcode = 'P0001';
  end if;

  update public.competitions
     set status = case when p_approve then 'approved'::public.competition_status
                       else 'rejected'::public.competition_status end,
         reviewed_by = v_uid,
         reviewed_at = now(),
         review_note = nullif(trim(p_note), '')
   where id = p_competition;

  if v_comp.submitted_by is not null and v_comp.submitted_by <> v_uid then
    perform public.notify(v_comp.submitted_by,
      case when p_approve then 'competition_approved' else 'competition_rejected' end,
      case when p_approve then 'Competition published' else 'Competition not approved' end,
      v_comp.name || case when p_approve then ' is live. Lobbies can open now.'
                          else ': ' || coalesce(p_note, '') end,
      jsonb_build_object('competition_id', p_competition));
  end if;
end;
$$;
