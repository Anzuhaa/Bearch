-- Reference + demo data for local development (`supabase db reset`).
-- No real student data here. Demo competitions are inserted as already approved.

insert into public.allowed_email_domains (domain) values
  ('student.uph.edu'),
  ('uph.edu')
on conflict do nothing;

-- Add Student Affairs / judge accounts here to make them admins on first sign-in:
-- insert into public.email_allowlist (email, role, note) values ('someone@uph.edu', 'admin', 'Student Affairs');

insert into public.majors (name, faculty) values
  ('Informatics', 'Faculty of Computer Science'),
  ('Information Systems', 'Faculty of Computer Science'),
  ('Mathematics (Data Science)', 'Faculty of Science and Technology'),
  ('Statistics', 'Faculty of Science and Technology'),
  ('Visual Communication Design', 'School of Design'),
  ('Product Design', 'School of Design'),
  ('Management', 'Faculty of Economics and Business'),
  ('Accounting', 'Faculty of Economics and Business'),
  ('Law', 'Faculty of Law'),
  ('International Relations', 'Faculty of Social and Political Sciences'),
  ('Communication Science', 'Faculty of Social and Political Sciences'),
  ('Medicine', 'Faculty of Medicine'),
  ('Psychology', 'Faculty of Psychology'),
  ('Hospitality Management', 'School of Hospitality and Tourism'),
  ('Industrial Engineering', 'Faculty of Science and Technology')
on conflict do nothing;

insert into public.skills (name, kind) values
  ('Python', 'hard'),
  ('SQL', 'hard'),
  ('Data Analysis', 'hard'),
  ('Data Visualization', 'hard'),
  ('Machine Learning', 'hard'),
  ('R', 'hard'),
  ('Excel Modeling', 'hard'),
  ('Financial Modeling', 'hard'),
  ('React / TypeScript', 'hard'),
  ('Flutter', 'hard'),
  ('Backend Development', 'hard'),
  ('Frontend Development', 'hard'),
  ('Mobile Development', 'hard'),
  ('UI/UX Design', 'hard'),
  ('Figma', 'hard'),
  ('Illustration', 'hard'),
  ('Video Editing', 'hard'),
  ('Copywriting', 'hard'),
  ('Business Case Analysis', 'hard'),
  ('Market Research', 'hard'),
  ('Public Policy', 'hard'),
  ('Legal Research', 'hard'),
  ('Scientific Writing', 'hard'),
  ('Pitching', 'soft'),
  ('Public Speaking', 'soft'),
  ('Communication', 'soft'),
  ('Leadership', 'soft'),
  ('Time Management', 'soft'),
  ('Negotiation', 'soft'),
  ('Critical Thinking', 'soft'),
  ('Teamwork', 'soft'),
  ('Creativity', 'soft')
on conflict do nothing;

-- Placeholder SEP points. Replace with the official UPH SEP guideline.
insert into public.sep_point_rules (level, placement, points) values
  ('campus', 'winner_1', 40), ('campus', 'winner_2', 30), ('campus', 'winner_3', 25),
  ('campus', 'finalist', 15), ('campus', 'participant', 5),
  ('regional', 'winner_1', 60), ('regional', 'winner_2', 50), ('regional', 'winner_3', 40),
  ('regional', 'finalist', 25), ('regional', 'participant', 10),
  ('national', 'winner_1', 100), ('national', 'winner_2', 80), ('national', 'winner_3', 70),
  ('national', 'finalist', 40), ('national', 'participant', 15),
  ('international', 'winner_1', 150), ('international', 'winner_2', 120), ('international', 'winner_3', 100),
  ('international', 'finalist', 60), ('international', 'participant', 20)
on conflict do nothing;

-- Demo competitions (approved, no submitter).
insert into public.competitions
  (name, organizer, category, level, description, official_url, prize,
   registration_deadline, event_start, event_end, team_min, team_max, status, duplicate_status)
values
  ('UPH STACK Hackathon 2026', 'UPH Faculty of Computer Science', 'technology', 'campus',
   'Case 1 · Smarter Campus and Learning: build a solution that improves student life at UPH.',
   'https://stack.uph.edu', 'Rp 15.000.000', '2026-12-12', '2026-12-14', '2026-12-15', 3, 5, 'approved', 'clear'),
  ('Gemastik XIX: Smart City', 'Kemdikbudristek', 'technology', 'national',
   'National ICT competition, smart city software development track.',
   'https://gemastik.kemdikbud.go.id', null, '2027-01-05', null, null, 3, 3, 'approved', 'clear'),
  ('National Business Case Competition', 'Universitas Indonesia', 'business', 'national',
   'Solve a real company case and pitch to a panel of executives.',
   null, null, '2026-12-20', null, null, 3, 4, 'approved', 'clear'),
  ('Hology 8.0 UI/UX Design Sprint', 'Universitas Brawijaya', 'design', 'national',
   '48-hour national UI/UX sprint for university students (2025 season).',
   'https://hology.ub.ac.id', null, '2025-12-15', null, null, 2, 3, 'approved', 'clear'),
  ('PKM-KC 2027 Funding Round', 'Belmawa', 'science', 'national',
   'Program Kreativitas Mahasiswa: Karsa Cipta research funding.',
   null, null, '2027-02-28', null, null, 3, 5, 'approved', 'clear'),
  ('Youth Social Innovation Challenge', 'ASEAN Foundation', 'social_impact', 'regional',
   'Design a social innovation for youth communities in ASEAN.',
   null, null, '2027-01-10', null, null, 2, 4, 'approved', 'clear')
on conflict do nothing;
