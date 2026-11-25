-- Align with CLAUDE.md Phase 1 scope.
--   * External portfolio links are Phase 2 -> drop profile columns.
--   * Winning-result upload is strictly gated until the uploader has rated
--     every teammate (storage + sep_claim_files).
--   * SEP claims track a UPH Mobile sync status.

-- ---------------------------------------------------------------------------
-- Out of scope: external portfolio links
-- ---------------------------------------------------------------------------
alter table public.profiles drop column if exists portfolio_url;
alter table public.profiles drop column if exists linkedin_url;

-- ---------------------------------------------------------------------------
-- Result upload gate
-- ---------------------------------------------------------------------------
create or replace function public.has_rated_all_teammates(p_team uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_team_member(p_team)
     and not exists (
       select 1 from public.team_members m
        where m.team_id = p_team
          and m.profile_id <> auth.uid()
          and not exists (
            select 1 from public.peer_ratings r
             where r.team_id = p_team and r.rater_id = auth.uid() and r.ratee_id = m.profile_id
          )
     );
$$;
grant execute on function public.has_rated_all_teammates(uuid) to authenticated;

drop policy if exists "bearch sep proofs upload" on storage.objects;
create policy "bearch sep proofs upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'sep-proofs'
    and public.has_rated_all_teammates(public.storage_entity(objects.name))
  );

drop policy if exists "members attach sep files" on public.sep_claim_files;
create policy "members attach sep files" on public.sep_claim_files
  for insert to authenticated
  with check (exists (
    select 1 from public.sep_claims s
     where s.id = claim_id
       and s.status = 'submitted'
       and public.has_rated_all_teammates(s.team_id)
  ));

-- ---------------------------------------------------------------------------
-- UPH Mobile sync status
-- ---------------------------------------------------------------------------
-- not_synced: claim not verified yet
-- pending:    verified by Student Affairs, waiting for the UPH Mobile push
-- synced / failed: set by the future UPH Mobile integration
alter table public.sep_claims
  add column uph_mobile_sync_status text not null default 'not_synced'
    check (uph_mobile_sync_status in ('not_synced', 'pending', 'synced', 'failed')),
  add column uph_mobile_synced_at timestamptz;

create or replace function public.queue_uph_mobile_sync()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'verified' and old.status <> 'verified' and new.uph_mobile_sync_status = 'not_synced' then
    new.uph_mobile_sync_status := 'pending';
  end if;
  return new;
end;
$$;

create trigger sep_claims_queue_sync before update on public.sep_claims
  for each row execute function public.queue_uph_mobile_sync();
