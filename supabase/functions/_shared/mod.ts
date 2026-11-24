// Shared helpers for Bearch Edge Functions (Deno + TypeScript).
// Secrets (GEMINI_API_KEY, SUPABASE_SERVICE_ROLE_KEY) only ever live here, server-side.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function env(name: string, fallback?: string): string {
  const v = Deno.env.get(name) ?? fallback;
  if (v === undefined) throw new Error(`Missing env ${name}`);
  return v;
}

/** Client that acts as the calling user (RLS applies). */
export function userClient(req: Request): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
}

/** Service-role client: bypasses RLS. Only use after authorising the caller. */
export function adminClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
}

export async function requireUser(req: Request) {
  const client = userClient(req);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return { client, user: null };
  return { client, user: data.user };
}

/** Simple global budget so a demo can't burn the Gemini quota. */
export async function aiBudgetLeft(admin: SupabaseClient, fn: string): Promise<boolean> {
  const limit = Number(env("AI_HOURLY_LIMIT", "60"));
  const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("ai_calls")
    .select("id", { count: "exact", head: true })
    .eq("fn", fn)
    .gte("created_at", since);
  return (count ?? 0) < limit;
}

export async function logAiCall(
  admin: SupabaseClient,
  row: { fn: string; competition_id?: string; profile_id?: string; ok: boolean; detail?: string },
) {
  await admin.from("ai_calls").insert({ ...row, detail: row.detail?.slice(0, 500) });
}

// ---------------------------------------------------------------------------
// Gemini (REST, JSON mode)
// ---------------------------------------------------------------------------

export type GeminiSchema = Record<string, unknown>;

export class GeminiError extends Error {
  constructor(message: string, readonly status?: number) {
    super(message);
  }
}

export async function geminiJson<T>(prompt: string, schema: GeminiSchema): Promise<{ data: T; model: string }> {
  const key = env("GEMINI_API_KEY");
  const model = env("GEMINI_MODEL", "gemini-2.5-flash");
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.1,
          responseMimeType: "application/json",
          responseSchema: schema,
        },
      }),
      signal: AbortSignal.timeout(20_000),
    },
  );
  if (!res.ok) {
    throw new GeminiError(`Gemini HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`, res.status);
  }
  const body = await res.json();
  const text: string | undefined = body?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new GeminiError("Gemini returned no content");
  try {
    return { data: JSON.parse(text) as T, model };
  } catch {
    throw new GeminiError("Gemini returned invalid JSON");
  }
}
