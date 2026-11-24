-- Storage buckets + RLS. Object paths are always "<entity uuid>/<file name>":
--   competition-proofs/<competition_id>/poster.png
--   chat-attachments/<team_id>/<uuid>-file.pdf
--   report-evidence/<report_id>/<uuid>-screenshot.png
--   sep-proofs/<team_id>/certificate.pdf
--   avatars/<profile_id>/avatar.jpg   (public bucket)

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('competition-proofs', 'competition-proofs', false, 10485760,
     array['application/pdf', 'image/png', 'image/jpeg', 'image/webp']),
  ('chat-attachments', 'chat-attachments', false, 26214400, null),
  ('report-evidence', 'report-evidence', false, 52428800, null),
  ('sep-proofs', 'sep-proofs', false, 10485760,
     array['application/pdf', 'image/png', 'image/jpeg', 'image/webp']),
  ('avatars', 'avatars', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

create or replace function public.storage_entity(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select public.try_uuid(split_part(p_name, '/', 1));
$$;
grant execute on function public.storage_entity(text) to authenticated;

-- Is the caller a party (reporter / reported) of this report, or an admin?
create or replace function public.is_report_party(p_report uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.reports r
     where r.id = p_report and auth.uid() in (r.reporter_id, r.reported_id)
  );
$$;
grant execute on function public.is_report_party(uuid) to authenticated;

-- competition-proofs
create policy "bearch proofs read" on storage.objects
  for select to authenticated
  using (bucket_id = 'competition-proofs' and public.can_see_competition(public.storage_entity(name)));
create policy "bearch proofs upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'competition-proofs'
    and exists (
      select 1 from public.competitions c
       -- qualify: inside this subquery a bare "name" would be competitions.name
       where c.id = public.storage_entity(objects.name)
         and c.submitted_by = auth.uid()
         and c.status in ('draft', 'pending')
    )
  );

-- chat-attachments
create policy "bearch chat files read" on storage.objects
  for select to authenticated
  using (bucket_id = 'chat-attachments'
         and (public.is_team_member(public.storage_entity(name)) or public.is_admin()));
create policy "bearch chat files upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'chat-attachments' and public.is_team_member(public.storage_entity(name)));

-- report-evidence
create policy "bearch evidence read" on storage.objects
  for select to authenticated
  using (bucket_id = 'report-evidence' and public.is_report_party(public.storage_entity(name)));
create policy "bearch evidence upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'report-evidence' and public.is_report_party(public.storage_entity(name)));

-- sep-proofs
create policy "bearch sep proofs read" on storage.objects
  for select to authenticated
  using (bucket_id = 'sep-proofs'
         and (public.is_team_member(public.storage_entity(name)) or public.is_admin()));
create policy "bearch sep proofs upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'sep-proofs' and public.is_team_member(public.storage_entity(name)));

-- avatars (public read via bucket flag; write own folder only)
create policy "bearch avatar upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and public.storage_entity(name) = auth.uid());
create policy "bearch avatar update" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and public.storage_entity(name) = auth.uid());
create policy "bearch avatar delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and public.storage_entity(name) = auth.uid());
