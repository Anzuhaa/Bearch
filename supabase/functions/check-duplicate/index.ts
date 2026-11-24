// check-duplicate: AI duplicate check for a student-submitted competition.
//
//   POST { "competition_id": uuid }   (caller = submitter or admin; status draft/pending)
//
// 1. Postgres finds candidates by organizer + category + timeline + fuzzy name
//    (find_duplicate_candidates, pg_trgm).
// 2. Gemini judges whether the submission is the same competition as one of them.
// 3. Result is stored on the competition:
//      clear              -> nothing similar
//      possible_duplicate -> app shows the "Possible duplicate found" card; the
//                            student can still submit with a reason, and the
//                            admin queue shows the flag
//      check_failed       -> AI unavailable; admin reviews manually (fallback)

import {
  adminClient,
  aiBudgetLeft,
  corsHeaders,
  geminiJson,
  json,
  logAiCall,
  requireUser,
} from "../_shared/mod.ts";

interface Candidate {
  competition_id: string;
  name: string;
  organizer: string;
  category: string;
  registration_deadline: string;
  status: string;
  name_similarity: number;
  organizer_similarity: number;
  same_category: boolean;
  days_apart: number;
  rule_score: number;
}

interface Verdict {
  verdict: "duplicate" | "possible_duplicate" | "distinct";
  duplicate_of_id: string | null;
  confidence: number;
  summary: string;
}

/** Human-readable, deterministic reason chips (shown in app + admin queue). */
function reasonChips(c: Candidate) {
  const pct = (x: number) => `${Math.round(Number(x) * 100)}% similar`;
  return [
    { label: "Name", value: pct(c.name_similarity) },
    {
      label: "Organizer",
      value: Number(c.organizer_similarity) >= 0.9 ? "Same" : pct(c.organizer_similarity),
    },
    { label: "Category", value: c.same_category ? "Same" : "Different" },
    {
      label: "Timeline",
      value: c.days_apart <= 45 ? "Same window" : c.days_apart <= 120 ? "Close dates" : "Different season",
    },
  ];
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const { client, user } = await requireUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);

  let competitionId: string | undefined;
  try {
    competitionId = (await req.json())?.competition_id;
  } catch { /* handled below */ }
  if (!competitionId) return json({ error: "competition_id is required" }, 400);

  // RLS lets the caller see only their own submissions (or everything if admin).
  const { data: comp } = await client
    .from("competitions")
    .select("id, name, organizer, category, level, description, official_url, registration_deadline, status, submitted_by")
    .eq("id", competitionId)
    .maybeSingle();
  if (!comp) return json({ error: "Competition not found" }, 404);
  if (!["draft", "pending"].includes(comp.status)) {
    return json({ error: "Only drafts or pending submissions can be checked" }, 409);
  }

  const admin = adminClient();
  const { data: profile } = await admin.from("profiles").select("role").eq("id", user.id).single();
  if (comp.submitted_by !== user.id && profile?.role !== "admin") {
    return json({ error: "Forbidden" }, 403);
  }

  const save = async (fields: Record<string, unknown>) => {
    await admin
      .from("competitions")
      .update({ ...fields, duplicate_checked_at: new Date().toISOString() })
      .eq("id", comp.id);
  };

  const { data: rows, error: rpcErr } = await admin.rpc("find_duplicate_candidates", {
    p_competition: comp.id,
    p_limit: 5,
  });
  if (rpcErr) {
    await save({ duplicate_status: "check_failed", duplicate_reasons: [{ label: "Check", value: "Search failed" }] });
    return json({ status: "check_failed", message: "Duplicate check unavailable; Student Affairs will review manually." });
  }
  const candidates = (rows ?? []) as Candidate[];

  if (candidates.length === 0) {
    await save({ duplicate_status: "clear", duplicate_of: null, duplicate_score: 0, duplicate_reasons: [] });
    return json({ status: "clear" });
  }

  const top = candidates[0];
  const failOpen = async (detail: string) => {
    // Fallback = manual admin review. Keep the strongest rule-based hint for the admin.
    await logAiCall(admin, { fn: "check-duplicate", competition_id: comp.id, profile_id: user.id, ok: false, detail });
    await save({
      duplicate_status: "check_failed",
      duplicate_of: top.competition_id,
      duplicate_score: Number(top.rule_score),
      duplicate_reasons: [{ label: "AI check", value: "Unavailable, manual review" }, ...reasonChips(top)],
    });
    return json({
      status: "check_failed",
      message: "AI check unavailable; Student Affairs will review this submission manually.",
    });
  };

  if (!(await aiBudgetLeft(admin, "check-duplicate"))) return await failOpen("quota");

  const prompt = [
    "You check whether a newly submitted student competition is a duplicate of an existing listing.",
    "Compare organizer, category, timeline (registration deadline) and name.",
    "- 'duplicate': clearly the same competition AND the same edition/season (same event listed twice).",
    "- 'possible_duplicate': same competition series/organizer but it is unclear whether it is a new edition,",
    "   or details overlap strongly. A new yearly edition with a different timeline is still 'possible_duplicate'",
    "   so the submitter confirms it.",
    "- 'distinct': a different competition.",
    "Answer with the candidate id you matched (or null), confidence 0..1, and a one-sentence summary in English.",
    "",
    "New submission:",
    JSON.stringify({
      name: comp.name,
      organizer: comp.organizer,
      category: comp.category,
      level: comp.level,
      registration_deadline: comp.registration_deadline,
      official_url: comp.official_url,
      description: (comp.description ?? "").slice(0, 1500),
    }),
    "",
    "Existing candidates:",
    JSON.stringify(candidates.map((c) => ({
      id: c.competition_id,
      name: c.name,
      organizer: c.organizer,
      category: c.category,
      registration_deadline: c.registration_deadline,
      days_apart: c.days_apart,
    }))),
  ].join("\n");

  try {
    const { data } = await geminiJson<Verdict>(prompt, {
      type: "OBJECT",
      properties: {
        verdict: { type: "STRING", enum: ["duplicate", "possible_duplicate", "distinct"] },
        duplicate_of_id: { type: "STRING", nullable: true },
        confidence: { type: "NUMBER" },
        summary: { type: "STRING" },
      },
      required: ["verdict", "confidence", "summary"],
    });

    await logAiCall(admin, { fn: "check-duplicate", competition_id: comp.id, profile_id: user.id, ok: true });

    if (data.verdict === "distinct") {
      await save({
        duplicate_status: "clear",
        duplicate_of: null,
        duplicate_score: Number(top.rule_score),
        duplicate_reasons: [{ label: "AI", value: data.summary }],
      });
      return json({ status: "clear", summary: data.summary });
    }

    const match = candidates.find((c) => c.competition_id === data.duplicate_of_id) ?? top;
    const reasons = [...reasonChips(match), { label: "AI", value: data.summary }];
    await save({
      duplicate_status: "possible_duplicate",
      duplicate_of: match.competition_id,
      duplicate_score: Math.max(0, Math.min(1, Number(data.confidence) || Number(match.rule_score))),
      duplicate_reasons: reasons,
    });
    return json({
      status: "possible_duplicate",
      duplicate_of: {
        id: match.competition_id,
        name: match.name,
        organizer: match.organizer,
        category: match.category,
        registration_deadline: match.registration_deadline,
      },
      reasons,
      summary: data.summary,
    });
  } catch (e) {
    return await failOpen(String(e));
  }
});
