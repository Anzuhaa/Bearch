// Creates demo accounts (1 Student Affairs admin + 4 students) on a Supabase
// project, with filled-in skill profiles, availability and one demo lobby.
// Idempotent: safe to run again (it updates instead of duplicating).
//
// Usage (needs the service-role key, never commit it):
//   SUPABASE_URL=https://<ref>.supabase.co \
//   SUPABASE_SERVICE_ROLE_KEY=... \
//   DEMO_PASSWORD=... \
//   node supabase/scripts/demo_accounts.mjs
//
// Demo emails use the reserved `.test` TLD, so they can never be real inboxes.
// They sign in with email + password (the app shows "Demo login" only when
// DEMO_LOGIN=true in app/env.json). Real users keep using UPH email OTP.

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.DEMO_PASSWORD;
if (!url || !key || !password) {
  console.error('Set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and DEMO_PASSWORD');
  process.exit(1);
}

const headers = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };

async function call(method, path, body, extraHeaders = {}) {
  const res = await fetch(`${url}${path}`, {
    method,
    headers: { ...headers, ...extraHeaders },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const err = new Error(`${method} ${path} -> ${res.status}: ${text.slice(0, 300)}`);
    err.status = res.status;
    throw err;
  }
  return data;
}
const rest = (method, path, body, prefer) =>
  call(method, `/rest/v1/${path}`, body, prefer ? { Prefer: prefer } : {});

const ACCOUNTS = [
  {
    email: 'admin@bearch.test',
    name: 'Student Affairs (Demo)',
    role: 'admin',
  },
  {
    email: 'satria@bearch.test',
    name: 'Satria (Demo)',
    major: 'Informatics',
    batch: 2023,
    skills: [['Python', 3], ['Backend Development', 3], ['Leadership', 3]],
    slots: [[2, '19:00', '22:00'], [4, '19:00', '22:00'], [6, '10:00', '13:00']],
  },
  {
    email: 'rizki@bearch.test',
    name: 'Rizki (Demo)',
    major: 'Mathematics (Data Science)',
    batch: 2023,
    skills: [['Data Analysis', 3], ['Python', 3], ['SQL', 2], ['Communication', 3]],
    slots: [[2, '19:00', '22:00'], [4, '19:00', '22:00']],
  },
  {
    email: 'samuel@bearch.test',
    name: 'Samuel (Demo)',
    major: 'Visual Communication Design',
    batch: 2022,
    skills: [['UI/UX Design', 3], ['Figma', 3], ['Pitching', 2], ['Creativity', 3]],
    slots: [[1, '10:00', '15:00'], [3, '10:00', '15:00'], [6, '09:00', '17:00']],
  },
  {
    email: 'angela@bearch.test',
    name: 'Angela (Demo)',
    major: 'Statistics',
    batch: 2024,
    skills: [['Data Analysis', 3], ['R', 3], ['Data Visualization', 3]],
    slots: [[6, '09:00', '12:00'], [7, '09:00', '12:00']],
  },
];

// 1. Let these emails in (the DB trigger rejects non-UPH addresses otherwise).
await rest(
  'POST',
  'email_allowlist?on_conflict=email',
  ACCOUNTS.map((a) => ({ email: a.email, role: a.role ?? 'student', note: 'demo account' })),
  'resolution=merge-duplicates',
);

const majors = Object.fromEntries((await rest('GET', 'majors?select=id,name')).map((m) => [m.name, m.id]));
const skills = Object.fromEntries((await rest('GET', 'skills?select=id,name')).map((s) => [s.name, s.id]));

const ids = {};
for (const a of ACCOUNTS) {
  // 2. Auth user (confirmed, password login).
  try {
    const user = await call('POST', '/auth/v1/admin/users', {
      email: a.email,
      password,
      email_confirm: true,
      user_metadata: { full_name: a.name },
    });
    ids[a.email] = user.id;
  } catch (e) {
    if (e.status !== 422) throw e; // already exists
    const [p] = await rest('GET', `profiles?select=id&email=eq.${encodeURIComponent(a.email)}`);
    ids[a.email] = p.id;
    await call('PUT', `/auth/v1/admin/users/${p.id}`, { password });
  }
  const id = ids[a.email];

  // 3. Profile, skills, availability.
  await rest('PATCH', `profiles?id=eq.${id}`, {
    full_name: a.name,
    major_id: a.major ? majors[a.major] : null,
    batch: a.batch ?? null,
    onboarded: true,
  });
  if (a.skills) {
    await rest('DELETE', `profile_skills?profile_id=eq.${id}`);
    await rest('POST', 'profile_skills', a.skills.map(([name, level]) => {
      if (!skills[name]) throw new Error(`Unknown skill ${name}`);
      return { profile_id: id, skill_id: skills[name], level };
    }));
  }
  if (a.slots) {
    await rest('DELETE', `availability_slots?profile_id=eq.${id}`);
    await rest('POST', 'availability_slots', a.slots.map(([weekday, start_time, end_time]) => ({
      profile_id: id, weekday, start_time, end_time,
    })));
  }
  console.log(`✓ ${a.email} (${a.role ?? 'student'})`);
}

// 4. A demo lobby on UPH STACK 2026: Satria leads, no required skills set,
//    so "Recommended teammates" exercises the AI inference path.
const [stack] = await rest('GET', `competitions?select=id,team_max&name=eq.${encodeURIComponent('UPH STACK Hackathon 2026')}`);
if (stack) {
  const satria = ids['satria@bearch.test'];
  const [existing] = await rest('GET', `team_members?select=team_id&competition_id=eq.${stack.id}&profile_id=eq.${satria}`);
  if (!existing) {
    const [team] = await rest('POST', 'teams', {
      competition_id: stack.id,
      leader_id: satria,
      name: 'Bear Invasion (Demo)',
      pitch: 'Building a teammate-matchmaking app for Case 1. Need a data person and a UI/UX designer.',
      max_members: 4,
    }, 'return=representation');
    await rest('POST', 'team_members', {
      team_id: team.id, profile_id: satria, competition_id: stack.id, is_leader: true, role_label: 'Leader',
    });
    console.log('✓ demo lobby "Bear Invasion (Demo)" on UPH STACK 2026');
  } else {
    console.log('• demo lobby already exists');
  }
}

console.log('\nDone. Sign in with any demo email above + DEMO_PASSWORD.');
