// Supabase Edge Function: telemetry proxy.
//
// The macOS app posts anonymous events here. This function holds the Supabase
// service-role key (from the function's own env, never shipped to clients) and
// performs the INSERT into `telemetry_events`. The app embeds only this
// function's public URL — no DB key in the binary.
//
// Deploy:
//   supabase functions deploy telemetry --no-verify-jwt
//   supabase secrets set PROJECT_URL=... SECRET_KEY=sb_secret_...
//
// Uses a 2025-style `sb_secret_...` key (replaces the legacy service_role JWT);
// it bypasses RLS for the insert. SUPABASE_URL / SUPABASE_* names are reserved
// by the platform, so the secrets are named PROJECT_URL / SECRET_KEY.
//
// --no-verify-jwt: the app is anonymous and sends no auth token. Abuse is
// bounded by the validation + a coarse payload allow-list below; the table is
// insert-only via this function (RLS denies anon writes directly).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("PROJECT_URL") ?? Deno.env.get("SUPABASE_URL")!;
const SECRET_KEY = Deno.env.get("SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

// Only these top-level keys are persisted; anything else is dropped so a
// malicious client can't stuff arbitrary columns.
const ALLOWED = [
  "anonymous_id",
  "event_name",
  "app_version",
  "os_name",
  "os_version",
  "architecture",
  "locale",
  "platform",
  "extended",
  "timestamp_utc",
  "source",
  "event_properties",
];

const MAX_BODY = 8 * 1024; // 8 KB is plenty for one event.

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  const raw = await req.text();
  if (raw.length > MAX_BODY) {
    return json({ error: "payload too large" }, 413);
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "invalid json" }, 400);
  }

  // Required minimal fields.
  if (typeof body.event_name !== "string" || !body.event_name) {
    return json({ error: "event_name required" }, 400);
  }
  if (typeof body.anonymous_id !== "string" || !body.anonymous_id) {
    return json({ error: "anonymous_id required" }, 400);
  }

  // Whitelist + cap source to our app so the table only collects our events.
  const row: Record<string, unknown> = {};
  for (const k of ALLOWED) if (k in body) row[k] = body[k];
  row.source = "openmp_server_launcher";
  row.received_at = new Date().toISOString();

  const sb = createClient(SUPABASE_URL, SECRET_KEY, {
    auth: { persistSession: false },
  });
  const { error } = await sb.from("telemetry_events").insert(row);
  if (error) {
    console.error("insert failed:", error.message);
    return json({ error: "insert failed" }, 500);
  }
  return json({ ok: true }, 200);
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
