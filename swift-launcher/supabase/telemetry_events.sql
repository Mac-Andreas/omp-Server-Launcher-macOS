-- Telemetry schema for the open.mp Server Launcher.
--
-- Events arrive only via the `telemetry` Edge Function, which inserts using the
-- service-role key. Anon/clients have NO direct access — the table is locked
-- and the app never holds a DB key (it only knows the function URL).
--
-- Apply in the Supabase SQL editor or:  psql "$DATABASE_URL" -f telemetry_events.sql

create table if not exists public.telemetry_events (
  id              bigserial primary key,
  anonymous_id    uuid,
  event_name      text not null,
  app_version     text,
  os_name         text,
  os_version      text,
  architecture    text,
  locale          text,
  platform        text,
  extended        boolean default false,
  source          text,
  event_properties jsonb not null default '{}'::jsonb,
  timestamp_utc   timestamptz,          -- client wall clock
  received_at     timestamptz not null default now()  -- server authoritative
);

create index if not exists telemetry_events_name_idx       on public.telemetry_events (event_name);
create index if not exists telemetry_events_received_idx    on public.telemetry_events (received_at);
create index if not exists telemetry_events_anon_idx        on public.telemetry_events (anonymous_id);

-- Lock the table to anon: no direct insert/select/update/delete. The Edge
-- Function uses the service role, which bypasses RLS, so inserts still work.
alter table public.telemetry_events enable row level security;
revoke all on public.telemetry_events from anon;
-- (No anon policy is created, so RLS denies all anon access by default.)

----------------------------------------------------------------------------
-- Aggregate views for a dashboard (mirror the qawno/community/launcher shape
-- on the main site so the launcher's numbers can be surfaced the same way).
----------------------------------------------------------------------------
create or replace view public.launcher_app_dau as
  select count(distinct anonymous_id) as devices
  from public.telemetry_events
  where received_at >= now() - interval '1 day';

create or replace view public.launcher_app_total_devices as
  select count(distinct anonymous_id) as devices,
         min(received_at)            as first_seen,
         max(received_at)            as last_seen
  from public.telemetry_events;

grant select on
  public.launcher_app_dau,
  public.launcher_app_total_devices
to anon;
