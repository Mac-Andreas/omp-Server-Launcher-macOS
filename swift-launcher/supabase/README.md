# Telemetry backend (Supabase)

The app sends **no Supabase key**. It posts events to the `telemetry` Edge
Function, which holds the service-role key server-side and inserts into
`telemetry_events`.

```
macOS app ──POST event──▶ Edge Function (service key) ──insert──▶ telemetry_events
   knows only the public function URL          key never leaves Supabase
```

## One-time setup

1. **Create the table + views**

   Run `telemetry_events.sql` in the Supabase SQL editor (or `psql -f`).

2. **Deploy the function**

   ```sh
   supabase functions deploy telemetry --no-verify-jwt
   ```

   `--no-verify-jwt` because the app is anonymous (no auth token). Abuse is
   bounded by the function's payload allow-list + size cap; the table itself is
   anon-locked, so the function is the only write path.

3. **Set the function's secrets** (server-side only — never in the app)

   Use a 2025-style `sb_secret_…` key (Project Settings → API Keys → Secret
   keys). It replaces the legacy `service_role` JWT and bypasses RLS for the
   insert. Names are PROJECT_URL / SECRET_KEY because the platform reserves
   `SUPABASE_*`.

   ```sh
   supabase secrets set \
     PROJECT_URL=https://<project-ref>.supabase.co \
     SECRET_KEY=sb_secret_xxx
   ```

   Supabase auto-revokes `sb_secret_…` keys it finds in public GitHub repos, so
   keep this out of git (it lives only in the function's secrets + a gitignored
   local .env).

4. **Point the app at the function**

   The default URL is in `Sources/ServerLauncher/Core/AppInfo.swift`
   (`telemetryEndpoint`). Override per build with the `TELEMETRY_ENDPOINT`
   env var. Confirm the `<project-ref>` matches your project.

## Why this is safe

- No DB credential ships in the `.app` (would otherwise be `strings`-able).
- The table is RLS-locked to anon; only the function's service role inserts.
- The function whitelists columns and caps body size, so clients can't write
  arbitrary data.

## Verify

```sh
curl -X POST https://<project-ref>.supabase.co/functions/v1/telemetry \
  -H 'content-type: application/json' \
  -d '{"event_name":"test","anonymous_id":"00000000-0000-0000-0000-000000000000"}'
# -> {"ok":true}
```
