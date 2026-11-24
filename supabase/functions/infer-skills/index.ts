// infer-skills: infer the skills a competition needs, ONCE per competition (cached).
//
// Called by the app when a team leader opens "Recommended teammates".
//   POST { "team_id": uuid }
//
// - If the leader already set required skills -> AI is NOT used.
// - Else, if the competition has cached inferred skills -> return the cache.
// - Else ask Gemini (competition details only; no student data ever leaves
//   Bearch), keep only skills from our catalog, cache them on the competition.
// - On any AI failure / quota -> { fallback: true } and the app shows
//   "Skill yang dibutuhkan belum diatur" with a "Set required skills" button.
//
// Ranking itself happens in Postgres: rpc('recommend_candidates', { p_team }).

import {
  adminClient,
  aiBudgetLeft,
  corsHeaders,
  geminiJson,
  json,
  logAiCall,
  requireUser,
} from "../_shared/mod.ts";

const FALLBACK_MESSAGE = "Skill yang dibutuhkan belum diatur";

interface Skill {
  id: string;
  name: string;
  kind: "hard" | "soft";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const { client, user } = await requireUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);

  let teamId: string | undefined;
  try {
    teamId = (await req.json())?.team_id;
  } catch { /* handled below */ }
  if (!teamId) return json({ error: "team_id is required" }, 400);

  // Authorise through RLS: caller must be a member of the team.
  const { data: membership } = await client
    .from("team_members")
    .select("team_id, competition_id")
    .eq("team_id", teamId)
    .eq("profile_id", user.id)
    .maybeSingle();
  if (!membership) return json({ error: "Only team members can request recommendations" }, 403);

  const { data: leaderSkills } = await client
    .from("team_required_skills")
    .select("skill_id, role_label, skills(name)")
    .eq("team_id", teamId);
  if (leaderSkills && leaderSkills.length > 0) {
    return json({
      source: "leader",
      cached: false,
      // deno-lint-ignore no-explicit-any
      skills: leaderSkills.map((s: any) => ({ id: s.skill_id, name: s.skills?.name, role_label: s.role_label })),
    });
  }

  const admin = adminClient();
  const { data: comp, error: compErr } = await admin
    .from("competitions")
    .select("id, name, organizer, category, level, description, status, inferred_skill_ids, inferred_skills_at")
    .eq("id", membership.competition_id)
    .single();
  if (compErr || !comp) return json({ error: "Competition not found" }, 404);

  const { data: catalog } = await admin.from("skills").select("id, name, kind").order("name");
  const skills = (catalog ?? []) as Skill[];
  const byId = new Map(skills.map((s) => [s.id, s]));

  if (comp.inferred_skill_ids && comp.inferred_skill_ids.length > 0) {
    return json({
      source: "ai",
      cached: true,
      inferred_at: comp.inferred_skills_at,
      skills: (comp.inferred_skill_ids as string[]).map((id) => byId.get(id)).filter(Boolean),
    });
  }

  if (!(await aiBudgetLeft(admin, "infer-skills"))) {
    await logAiCall(admin, { fn: "infer-skills", competition_id: comp.id, profile_id: user.id, ok: false, detail: "quota" });
    return json({ source: "none", fallback: true, reason: "quota", message: FALLBACK_MESSAGE });
  }

  const prompt = [
    "You help university students form competition teams.",
    "Pick the 3 to 6 skills a team most needs for the competition below.",
    "Choose ONLY from the skill catalog, copying names exactly. Prefer hard skills; include at most 1 soft skill.",
    "",
    "Competition:",
    `- Name: ${comp.name}`,
    `- Organizer: ${comp.organizer}`,
    `- Category: ${comp.category}`,
    `- Level: ${comp.level}`,
    `- Description: ${(comp.description ?? "").slice(0, 2000)}`,
    "",
    "Skill catalog:",
    skills.map((s) => `- ${s.name} (${s.kind})`).join("\n"),
  ].join("\n");

  try {
    const { data, model } = await geminiJson<{ skills: string[] }>(prompt, {
      type: "OBJECT",
      properties: { skills: { type: "ARRAY", items: { type: "STRING" } } },
      required: ["skills"],
    });

    const byName = new Map(skills.map((s) => [s.name.toLowerCase(), s]));
    const picked = [...new Set((data.skills ?? []).map((n) => byName.get(String(n).trim().toLowerCase())))]
      .filter((s): s is Skill => !!s)
      .slice(0, 6);

    if (picked.length === 0) {
      await logAiCall(admin, { fn: "infer-skills", competition_id: comp.id, profile_id: user.id, ok: false, detail: "no catalog match" });
      return json({ source: "none", fallback: true, reason: "no_match", message: FALLBACK_MESSAGE });
    }

    // Race-safe cache: only the first writer wins; everyone else re-reads.
    await admin
      .from("competitions")
      .update({
        inferred_skill_ids: picked.map((s) => s.id),
        inferred_skills_at: new Date().toISOString(),
        inferred_skills_model: model,
      })
      .eq("id", comp.id)
      .is("inferred_skill_ids", null);

    const { data: fresh } = await admin
      .from("competitions")
      .select("inferred_skill_ids, inferred_skills_at")
      .eq("id", comp.id)
      .single();

    await logAiCall(admin, { fn: "infer-skills", competition_id: comp.id, profile_id: user.id, ok: true });
    return json({
      source: "ai",
      cached: false,
      inferred_at: fresh?.inferred_skills_at,
      skills: ((fresh?.inferred_skill_ids ?? picked.map((s) => s.id)) as string[])
        .map((id) => byId.get(id))
        .filter(Boolean),
    });
  } catch (e) {
    await logAiCall(admin, { fn: "infer-skills", competition_id: comp.id, profile_id: user.id, ok: false, detail: String(e) });
    return json({ source: "none", fallback: true, reason: "ai_error", message: FALLBACK_MESSAGE });
  }
});
