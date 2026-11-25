-- Fix: in team_availability_heatmap the 23:00 bucket compared against
-- `time '00:00' + 24h`, which wraps to 00:00, so every slot that started
-- before 23:00 counted as free at 23:00. Compare slot coverage with
-- intervals measured from midnight instead (no wrap-around).

create or replace function public.team_availability_heatmap(p_team uuid)
returns table (weekday smallint, slot_start time, free_count integer, member_count integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (public.is_team_member(p_team) or public.is_admin()) then
    raise exception 'Only team members can see the team calendar.' using errcode = '42501';
  end if;

  return query
  with members as (
    select m.profile_id from public.team_members m where m.team_id = p_team
  )
  select d::smallint,
         (time '00:00' + make_interval(hours => h)),
         (select count(*)::integer from members m
           where exists (
             select 1 from public.availability_slots s
              where s.profile_id = m.profile_id and s.weekday = d
                and (s.start_time - time '00:00') <= make_interval(hours => h)
                and (s.end_time - time '00:00') >= least(make_interval(hours => h + 1), interval '23:59:59')
           )),
         (select count(*)::integer from members)
    from generate_series(1, 7) d, generate_series(6, 23) h
   order by 1, 2;
end;
$$;
