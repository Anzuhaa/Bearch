import { PGlite } from '@electric-sql/pglite';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import fs from 'node:fs';
import path from 'node:path';

// Usage: npm test   (from supabase/tests). Applies all migrations + seed to an
// in-memory Postgres (PGlite) with small Supabase stubs, then runs scenarios.
const repo = process.argv[2] ?? path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const db = new PGlite({ extensions: { pg_trgm } });

const stub = `
create schema if not exists extensions;
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create role supabase_auth_admin nologin;
grant usage on schema public, extensions to anon, authenticated, service_role;
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.role() returns text language sql stable as $$ select current_setting('request.jwt.claim.role', true) $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
create schema storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated; grant all on storage.objects to authenticated;
create schema cron; create table cron.job(jobname text, schedule text, command text);
create function cron.schedule(n text, s text, c text) returns bigint language sql as $$ insert into cron.job values (n,s,c); select 1::bigint $$;
create publication supabase_realtime;
`;

let pass = 0, fail = 0;
const ok = (name, cond, extra = '') => {
  if (cond) { pass++; console.log('  ✓', name); } else { fail++; console.log('  ✗', name, extra); }
};
const q = async (sql, params) => (await db.query(sql, params)).rows;
const one = async (sql, params) => (await q(sql, params))[0];
const expectErr = async (name, fn, match) => {
  try { await fn(); ok(name, false, '(no error)'); }
  catch (e) { ok(name, !match || String(e.message).includes(match), e.message); }
};
async function as(uid, fn) {
  await db.exec(`select set_config('request.jwt.claim.sub','${uid}',false); set role authenticated;`);
  try { return await fn(); } finally { await db.exec(`reset role; select set_config('request.jwt.claim.sub','',false);`); }
}

console.log('Applying stubs + migrations');
await db.exec(stub);
const migDir = path.join(repo, 'supabase/migrations');
for (const f of fs.readdirSync(migDir).sort()) {
  let sql = fs.readFileSync(path.join(migDir, f), 'utf8');
  sql = sql.replace(/create extension if not exists pg_cron[^;]*;/, '');
  try { await db.exec(sql); console.log('  applied', f); }
  catch (e) { console.log('  FAILED', f, e.message, e.position ? `pos ${e.position}: ${sql.slice(e.position - 200, Number(e.position) + 100)}` : ''); process.exit(1); }
}
await db.exec(fs.readFileSync(path.join(repo, 'supabase/seed.sql'), 'utf8'));
console.log('  seed ok');

console.log('Auth');
await expectErr('non-UPH email rejected', () => q(`insert into auth.users(email) values ('x@gmail.com')`), 'Only verified UPH');
await q(`insert into public.email_allowlist(email, role) values ('staff@uph.edu', 'admin'), ('judge@example.com', 'student')`);
const mk = async (email, name) => (await one(`insert into auth.users(email, raw_user_meta_data) values ($1, $2) returning id`, [email, { full_name: name }])).id;
const satria = await mk('satria.jagad@student.uph.edu', 'Satria Jagad Samudra');
const josh = await mk('joshelius@student.uph.edu', 'Joshelius Joshua Kusno');
const rizki = await mk('rizki@student.uph.edu', 'Muhammad Rizki Al Fatih');
const samuel = await mk('samuel@student.uph.edu', 'Samuel Archie Tandy Rerung');
const nadia = await mk('nadia@student.uph.edu', 'Nadia Putri');
const angela = await mk('angela@student.uph.edu', 'Angela Lim');
const admin = await mk('staff@uph.edu', 'Student Affairs');
ok('admin role from allowlist', (await one(`select role from profiles where id=$1`, [admin])).role === 'admin');
ok('student role default', (await one(`select role from profiles where id=$1`, [rizki])).role === 'student');
const judge = await mk('judge@example.com', 'Judge');
ok('allowlisted non-UPH email gets student role', (await one(`select role from profiles where id=$1`, [judge])).role === 'student');

const major = async (n) => (await one(`select id from majors where name=$1`, [n])).id;
const skill = async (n) => (await one(`select id from skills where name=$1`, [n])).id;
const setup = async (id, m, skills, slots) => {
  await q(`update profiles set major_id=$2, onboarded=true where id=$1`, [id, await major(m)]);
  for (const [s, l] of skills) await q(`insert into profile_skills(profile_id, skill_id, level) values ($1,$2,$3)`, [id, await skill(s), l]);
  for (const [d, a, b] of slots) await q(`insert into availability_slots(profile_id, weekday, start_time, end_time) values ($1,$2,$3,$4)`, [id, d, a, b]);
};
await setup(satria, 'Informatics', [['Python', 3]], [[2, '19:00', '22:00'], [4, '19:00', '22:00']]);
await setup(josh, 'Information Systems', [['React / TypeScript', 2]], [[2, '18:00', '22:00'], [4, '19:00', '21:00']]);
await setup(rizki, 'Mathematics (Data Science)', [['Data Analysis', 3], ['Python', 3], ['SQL', 2]], [[2, '19:00', '22:00'], [4, '19:00', '22:00']]);
await setup(samuel, 'Visual Communication Design', [['UI/UX Design', 3], ['Figma', 3], ['Pitching', 2]], [[1, '10:00', '15:00'], [6, '09:00', '17:00']]);
await setup(nadia, 'Accounting', [['Data Visualization', 1]], []);
await setup(angela, 'Statistics', [['Data Analysis', 3], ['R', 3]], [[6, '09:00', '12:00']]);

console.log('RLS basics');
await as(rizki, async () => {
  await expectErr('student cannot change own role', () => q(`update profiles set role='admin' where id=$1`, [rizki]), 'permission denied');
  await q(`update profiles set full_name='Rizki' where id=$1`, [rizki]);
  ok('student can edit own name', (await one(`select full_name from profiles where id=$1`, [rizki])).full_name === 'Rizki');
  const n = (await one(`select count(*)::int c from profiles where id=$1 and full_name='Rizki'`, [rizki])).c;
  ok('visible', n === 1);
  await q(`update profiles set full_name='hack' where id=$1`, [satria]);
  ok('cannot edit others (RLS filters)', (await one(`select full_name from profiles where id=$1`, [satria])).full_name !== 'hack');
});

console.log('Lobby lifecycle');
const stack = (await one(`select id from competitions where name='UPH STACK Hackathon 2026'`)).id;
const team = await as(satria, async () => (await one(`select public.create_team($1,'Bear Invasion','Building a matchmaking app',4) id`, [stack])).id);
ok('team created', !!team);
await as(satria, async () => {
  await q(`select public.request_join(t.id) from teams t where false`); // noop
  const recs = await q(`select * from public.recommend_candidates($1)`, [team]);
  ok('no required skills + no AI cache -> empty (fallback text)', recs.length === 0);
});
await as(josh, () => q(`select public.request_join($1,'hi')`, [team]));
await as(satria, async () => {
  const req = (await one(`select id from join_requests where profile_id=$1`, [josh])).id;
  await q(`select public.decide_join_request($1,true)`, [req]);
});
ok('josh joined', (await one(`select count(*)::int c from team_members where team_id=$1`, [team])).c === 2);

// AI cache present -> ranking works
await q(`update competitions set inferred_skill_ids = array[(select id from skills where name='Data Analysis'),(select id from skills where name='UI/UX Design'),(select id from skills where name='Python'),(select id from skills where name='Pitching')] where id=$1`, [stack]);
await as(satria, async () => {
  const recs = await q(`select full_name, match_score, reasons, cross_major, availability_overlap from public.recommend_candidates($1)`, [team]);
  console.log('    recs:', recs.map(r => `${r.full_name} ${r.match_score} [${r.reasons.join(' | ')}]`));
  ok('rizki ranked first', recs[0]?.full_name === 'Rizki');
  ok('cross-major reason present', recs[0]?.reasons.some(x => x.includes('cross-major')));
  ok('overlap computed', recs[0]?.availability_overlap === 100, recs[0]?.availability_overlap);
});
// leader-set skills override AI
await as(satria, () => q(`insert into team_required_skills(team_id, skill_id, role_label) values ($1, (select id from skills where name='UI/UX Design'), 'UI/UX Designer')`, [team]));
await as(satria, async () => {
  const src = await q(`select distinct source from public.team_matching_skills($1)`, [team]);
  ok('leader skills take precedence over AI', src.length === 1 && src[0].source === 'leader');
  const recs = await q(`select full_name from public.recommend_candidates($1)`, [team]);
  ok('samuel first with UI/UX requirement', recs[0]?.full_name === 'Samuel Archie Tandy Rerung');
});

await as(rizki, () => q(`select public.request_join($1)`, [team]));
await as(samuel, () => q(`select public.request_join($1)`, [team]));
await as(nadia, () => q(`select public.request_join($1)`, [team]));
await as(satria, async () => {
  const req = (await one(`select id from join_requests where profile_id=$1 and status='pending'`, [rizki])).id;
  await q(`select public.decide_join_request($1,true)`, [req]);
  await q(`select public.send_invite($1,$2,'Data Analyst','hi')`, [team, angela]);
});
ok('slots: 4 - 3 members - 1 invite = 0', (await one(`select public.team_open_slots($1) s`, [team])).s === 0);
await as(satria, async () => {
  const req = (await one(`select id from join_requests where profile_id=$1 and status='pending'`, [samuel])).id;
  await expectErr('approve blocked when slots reserved', () => q(`select public.decide_join_request($1,true)`, [req]), 'No open slots');
});
await as(rizki, async () => {
  await expectErr('non-leader cannot lock', () => q(`select public.lock_team($1)`, [team]), 'Only the team leader');
  await expectErr('no direct member insert', () => q(`insert into team_members(team_id, profile_id, competition_id) values ($1,$2,$3)`, [team, nadia, stack]), 'permission denied');
});
await as(satria, () => q(`select public.lock_team($1)`, [team]));
const statuses = await q(`select p.full_name, r.status from join_requests r join profiles p on p.id=r.profile_id where team_id=$1 order by 1`, [team]);
ok('pending requests auto-rejected on lock', statuses.filter(s => s.status === 'auto_rejected').length === 2, JSON.stringify(statuses));
ok('pending invite cancelled', (await one(`select status from team_invites where invitee_id=$1`, [angela])).status === 'cancelled');
ok('locked team notified', (await one(`select count(*)::int c from notifications where kind='team_locked'`)).c === 3);
await expectErr('no unlock (even superuser)', () => q(`update teams set status='open', locked_at=null where id=$1`, [team]), 'cannot be unlocked');
await expectErr('no member replacement', () => q(`insert into team_members(team_id, profile_id, competition_id) values ($1,$2,$3)`, [team, nadia, stack]), 'Team is locked');
await expectErr('no member removal', () => q(`delete from team_members where team_id=$1 and profile_id=$2`, [team, rizki]), 'Team is locked');
await as(nadia, () => expectErr('request to locked team refused', () => q(`select public.request_join($1)`, [team]), 'locked'));

console.log('Auto-lock + warnings');
const soon = (await one(`insert into competitions(name, organizer, category, level, registration_deadline, team_max, status) values ('Past Lock Comp','Org','business','campus', public.today_wib(), 3, 'approved') returning id`)).id;
const t2 = (await one(`insert into teams(competition_id, leader_id, name, max_members) values ($1,$2,'Late Team',3) returning id`, [soon, samuel])).id;
await q(`insert into team_members(team_id, profile_id, competition_id, is_leader) values ($1,$2,$3,true)`, [t2, samuel, soon]);
await q(`insert into join_requests(team_id, profile_id) values ($1,$2)`, [t2, nadia]);
ok('auto_lock_due_teams locks 1', (await one(`select public.auto_lock_due_teams() n`)).n === 1);
ok('auto lock reason', (await one(`select lock_reason from teams where id=$1`, [t2])).lock_reason === 'auto');
ok('auto-lock rejects pending', (await one(`select status from join_requests where team_id=$1`, [t2])).status === 'auto_rejected');
const h3 = (await one(`insert into competitions(name, organizer, category, level, registration_deadline, team_max, status) values ('H3 Comp','Org2','design','campus', public.today_wib()+3, 3, 'approved') returning id`)).id;
await as(nadia, () => q(`select public.create_team($1,'Nadia Team')`, [h3]));
ok('H-3 warning sent', (await one(`select public.send_lock_warnings() n`)).n === 1);
await q(`select public.send_lock_warnings()`);
ok('warning deduped', (await one(`select count(*)::int c from notifications where kind='lock_warning'`)).c === 1);
console.log('    ', (await one(`select title, body from notifications where kind='lock_warning'`)));
ok('cron jobs registered', (await one(`select count(*)::int c from cron.job`)).c === 3);

console.log('Competition submission + duplicate check');
const draft = await as(josh, async () => (await one(`insert into competitions(name, organizer, category, level, registration_deadline, team_max, submitted_by) values ('Hology 9.0 UI/UX Design Sprint','Universitas Brawijaya','design','national','2026-12-15',3,$1) returning id`, [josh])).id);
await as(rizki, async () => ok('other students cannot see drafts', (await q(`select id from competitions where id=$1`, [draft])).length === 0));
await db.exec(`set role service_role`);
const cands = await q(`select name, name_similarity, rule_score, days_apart from public.find_duplicate_candidates($1)`, [draft]);
await db.exec(`reset role`);
console.log('    candidates:', cands);
ok('Hology 8.0 found as candidate', cands[0]?.name === 'Hology 8.0 UI/UX Design Sprint');
await as(josh, () => expectErr('student cannot call find_duplicate_candidates', () => q(`select * from public.find_duplicate_candidates($1)`, [draft]), 'permission denied'));
await as(josh, () => expectErr('student cannot set duplicate flags', () => q(`update competitions set duplicate_status='clear' where id=$1`, [draft]), 'permission denied'));
await q(`update competitions set duplicate_status='possible_duplicate' where id=$1`, [draft]);
await as(josh, async () => {
  await expectErr('proof required', () => q(`select public.submit_competition($1,'new season')`, [draft]), 'proof');
  await q(`insert into competition_files(competition_id, storage_path, file_name, uploaded_by) values ($1::uuid, $1::text || '/guide.pdf', 'guide.pdf', $2::uuid)`, [draft, josh]);
  await q(`insert into storage.objects(bucket_id, name) values ('competition-proofs', $1 || '/guide.pdf')`, [draft]);
  await expectErr('override reason required for possible duplicate', () => q(`select public.submit_competition($1)`, [draft]), 'reason');
  await q(`select public.submit_competition($1,'This is the 2026 season (9.0)')`, [draft]);
});
ok('pending after submit', (await one(`select status from competitions where id=$1`, [draft])).status === 'pending');
ok('admin notified', (await one(`select count(*)::int c from notifications where profile_id=$1 and kind='competition_submitted'`, [admin])).c === 1);
await as(josh, () => expectErr('student cannot approve', () => q(`select public.admin_review_competition($1,true)`, [draft]), 'Admins only'));
await as(admin, () => q(`select public.admin_review_competition($1,true,'ok')`, [draft]));
ok('approved by admin', (await one(`select status from competitions where id=$1`, [draft])).status === 'approved');
// fallback: never checked -> check_failed
const draft2 = await as(josh, async () => (await one(`insert into competitions(name, organizer, category, level, registration_deadline, team_max, submitted_by, guidebook_url) values ('Totally New Cup','New Org','science','campus','2027-03-01',3,$1,'https://x') returning id`, [josh])).id);
await as(josh, () => q(`select public.submit_competition($1)`, [draft2]));
ok('unchecked -> check_failed (manual review)', (await one(`select duplicate_status from competitions where id=$1`, [draft2])).duplicate_status === 'check_failed');

console.log('Ratings, reports, SEP');
const past = (await one(`select id from competitions where name like 'Hology 8.0%'`)).id;
const t3 = (await one(`insert into teams(competition_id, leader_id, name, max_members) values ($1,$2,'Pitch Perfect',3) returning id`, [past, satria])).id;
await q(`insert into team_members(team_id, profile_id, competition_id, is_leader) values ($1,$2,$4,true),($1,$3,$4,false)`, [t3, satria, rizki, past]);
await q(`select public.lock_team_internal($1,'manual')`, [t3]);
const crit = { communication: 5, time_management: 4, teamwork: 5, responsibility: 4 };
await as(satria, async () => {
  await expectErr('criteria validated', () => q(`select public.submit_rating($1,$2,'[]','{"communication":5}')`, [t3, rizki]), 'stars');
  await q(`select public.submit_rating($1,$2,$3,$4,'great')`, [t3, rizki, JSON.stringify([{ skill_id: await skill('Data Analysis'), tier: 4 }]), JSON.stringify(crit)]);
  ok('rating progress', (await q(`select * from public.my_rating_progress($1)`, [t3]))[0].rated === true);
});
ok('reputation = 4.5', Number((await one(`select reputation from profiles where id=$1`, [rizki])).reputation) === 4.5);
ok('peer level updated', Number((await one(`select peer_level from profile_skills where profile_id=$1 and skill_id=$2`, [rizki, await skill('Data Analysis')])).peer_level) === 4);
await as(rizki, async () => ok('ratee cannot read rating rows', (await q(`select * from peer_ratings`)).length === 0));

const rep = await as(satria, async () => (await one(`select public.file_report($1,$2,'no_show','Did not attend the final rehearsal on 14 Oct.', $3) id`, [t3, rizki, JSON.stringify([{ label: 'Chat excerpt' }])])).id);
await as(satria, async () => ok('SEP blocked by open report', (await one(`select public.sep_claim_blockers($1) b`, [t3])).b.some(x => x.includes('open reports'))));
await as(rizki, async () => {
  ok('reported cannot select reports table', (await q(`select * from reports`)).length === 0);
  const mine = await q(`select * from public.reports_about_me()`);
  ok('reports_about_me hides reporter', mine.length === 1 && !('reporter_id' in mine[0]) && mine[0].evidence.length === 1);
  await q(`select public.submit_appeal($1,'The rehearsal was moved while I had a lab exam.', '[{"label":"Recording"}]')`, [rep]);
});
await as(admin, () => q(`select public.admin_decide_report($1,'upheld','No-show confirmed')`, [rep]));
ok('upheld report lowers reputation to 4.25', Number((await one(`select reputation from profiles where id=$1`, [rizki])).reputation) === 4.25);
await as(satria, async () => {
  ok('no blockers now', (await one(`select public.sep_claim_blockers($1) b`, [t3])).b.length === 0);
  const c = (await one(`select public.submit_sep_claim($1,'winner_1','1st Place','https://x') id`, [t3])).id;
  ok('estimate from rules (national winner = 100)', (await one(`select estimated_points from sep_claims where id=$1`, [c])).estimated_points === 100);
  await as(admin, () => q(`select public.admin_verify_sep_claim($1,true)`, [c]));
});
const stats = await as(admin, async () => (await one(`select public.admin_dashboard_stats() s`)).s);
console.log('    stats:', stats);
ok('stats computed', stats.sep_credited === 200);
await as(rizki, () => expectErr('students cannot read stats', () => q(`select public.admin_dashboard_stats()`), 'Admins only'));
await as(rizki, () => expectErr('internal fn not callable', () => q(`select public.lock_team_internal($1,'manual')`, [team]), 'permission denied'));

console.log('Storage');
await as(rizki, async () => {
  await expectErr('cannot upload to other team chat', () => q(`insert into storage.objects(bucket_id, name) values ('chat-attachments', $1 || '/x.png')`, [t2]), 'row-level security');
  await q(`insert into storage.objects(bucket_id, name) values ('chat-attachments', $1 || '/x.png')`, [team]);
  ok('member can upload to own team chat', true);
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
