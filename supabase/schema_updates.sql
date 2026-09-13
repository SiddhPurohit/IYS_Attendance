-- =========================================================
-- IYS Attendance — schema updates
-- Run this whole file in the Supabase SQL editor (top to bottom).
-- Safe to re-run: every step is guarded or drops-and-recreates.
-- This REPLACES the earlier attendance_views.sql.
--
-- Covers:
--   1. members.joined_on  — explicit joining date per boy
--   2. events             — special programs marked across all locations
--   3. summary views      — join-date aware, events kept separate
-- =========================================================

-- ---------------------------------------------------------
-- 1. Joining date
-- ---------------------------------------------------------
alter table public.members add column if not exists joined_on date;

update public.members
   set joined_on = (created_at at time zone 'Asia/Kolkata')::date
 where joined_on is null;

alter table public.members alter column joined_on set default current_date;
alter table public.members alter column joined_on set not null;

-- ---------------------------------------------------------
-- 2. Events
--
-- An event is one special program (Janmashtami, a youth festival…)
-- that every location attends. Creating an event also creates one
-- session row per location, linked back by sessions.event_id — so
-- attendance marking, RLS and eligibility all work unchanged, and each
-- location admin can only touch their own location's boys.
-- ---------------------------------------------------------
create table if not exists public.events (
  id         uuid primary key default uuid_generate_v4(),
  title      text not null,
  event_date date not null,
  notes      text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.sessions
  add column if not exists event_id uuid references public.events(id) on delete cascade;

create index if not exists sessions_event_idx on public.sessions(event_id);

-- A location still gets at most one REGULAR session per day, but an event
-- session may sit alongside it (e.g. a festival on a normal program day).
alter table public.sessions
  drop constraint if exists sessions_location_id_session_date_key;

create unique index if not exists sessions_regular_unique
  on public.sessions (location_id, session_date)
  where event_id is null;

create unique index if not exists sessions_event_unique
  on public.sessions (location_id, event_id)
  where event_id is not null;

alter table public.events enable row level security;

-- Every admin needs to read events (their session list shows the title).
drop policy if exists "events_read" on public.events;
create policy "events_read" on public.events
  for select using (auth.role() = 'authenticated');

-- Only the super admin can create/edit/delete them.
drop policy if exists "events_superadmin_write" on public.events;
create policy "events_superadmin_write" on public.events
  for all using (public.current_role() = 'super_admin')
  with check (public.current_role() = 'super_admin');

-- ---------------------------------------------------------
-- 3. Summary views
--
-- Sessions before a boy joined are excluded from his percentage and
-- from the location's expected head count. Event sessions are excluded
-- from these regular-programme summaries entirely — a one-off festival
-- should not move the weekly trend — and are reported separately by
-- event_attendance_summary below.
-- ---------------------------------------------------------
drop view if exists public.attendance_summary_by_member;
drop view if exists public.attendance_summary_by_location;
drop view if exists public.event_attendance_summary;

-- Per location, per session date (regular programmes only)
create view public.attendance_summary_by_location
with (security_invoker = true) as
with eligible as (
  select
    s.id as session_id,
    m.id as member_id
  from public.sessions s
  join public.members m
    on  m.location_id = s.location_id
    and m.is_active = true
    and m.joined_on <= s.session_date
  where s.event_id is null
),
counts as (
  select
    s.id                                        as session_id,
    s.location_id,
    s.session_date,
    count(e.member_id)                          as total_members,
    count(a.id) filter (where a.present = true) as present_count
  from public.sessions s
  left join eligible e
    on e.session_id = s.id
  left join public.attendance a
    on  a.session_id = e.session_id
    and a.member_id  = e.member_id
  where s.event_id is null
  group by s.id, s.location_id, s.session_date
)
select
  c.location_id,
  l.name          as location_name,
  c.session_date,
  case
    when c.total_members = 0 then 0
    else round((c.present_count::numeric / c.total_members) * 100, 2)
  end             as avg_attendance_percentage,
  c.present_count,
  c.total_members
from counts c
join public.locations l on l.id = c.location_id;

-- Per member (regular programmes only)
create view public.attendance_summary_by_member
with (security_invoker = true) as
with eligible as (
  select
    m.id as member_id,
    s.id as session_id
  from public.members m
  join public.sessions s
    on  s.location_id = m.location_id
    and s.session_date >= m.joined_on
  where m.is_active = true
    and s.event_id is null
),
totals as (
  select
    m.id                                        as member_id,
    m.full_name,
    m.location_id,
    count(e.session_id)                         as total_sessions,
    count(a.id) filter (where a.present = true) as attended_sessions
  from public.members m
  -- LEFT JOIN so a newly added boy still appears, with 0 sessions
  left join eligible e
    on e.member_id = m.id
  left join public.attendance a
    on  a.session_id = e.session_id
    and a.member_id  = m.id
  where m.is_active = true
  group by m.id, m.full_name, m.location_id
)
select
  t.member_id,
  t.full_name,
  t.location_id,
  l.name as location_name,
  t.total_sessions,
  t.attended_sessions,
  case
    when t.total_sessions = 0 then 0
    else round((t.attended_sessions::numeric / t.total_sessions) * 100, 2)
  end as attendance_percentage
from totals t
join public.locations l on l.id = t.location_id;

-- Per event, per location — the super admin's bird's-eye view.
-- security_invoker means a location admin only sees their own row.
create view public.event_attendance_summary
with (security_invoker = true) as
select
  e.id                                        as event_id,
  e.title,
  e.event_date,
  s.id                                        as session_id,
  s.location_id,
  l.name                                      as location_name,
  count(a.id) filter (where a.present = true) as present_count,
  count(a.id)                                 as total_marked
from public.events e
join public.sessions  s on s.event_id = e.id
join public.locations l on l.id = s.location_id
left join public.attendance a on a.session_id = s.id
group by e.id, e.title, e.event_date, s.id, s.location_id, l.name;

-- =========================================================
-- OPTIONAL cleanup (not run by the statements above).
--
-- If you move a boy's joining date forward, rows may be left behind for
-- sessions that now predate him. The views ignore them, but the "Boy
-- Details" screen counts raw attendance rows, so it can disagree.
--
-- Step 1 — preview:
--   select m.full_name, s.session_date, a.present
--   from public.attendance a
--   join public.members  m on m.id = a.member_id
--   join public.sessions s on s.id = a.session_id
--   where s.session_date < m.joined_on
--   order by m.full_name, s.session_date;
--
-- Step 2 — only if that list looks right (NOT reversible):
--   delete from public.attendance a
--   using public.members m, public.sessions s
--   where m.id = a.member_id
--     and s.id = a.session_id
--     and s.session_date < m.joined_on;
-- =========================================================
