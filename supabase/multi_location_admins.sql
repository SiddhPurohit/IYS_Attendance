-- =========================================================
-- IYS Attendance — multi-location admins
-- Run this whole file in the Supabase SQL editor (top to bottom).
-- Safe to re-run: every step is guarded or drops-and-recreates.
--
-- Before: an admin had exactly one location (profiles.location_id) and
-- every policy compared against current_location().
-- After:  an admin has any number of locations (admin_locations) and every
-- policy checks membership via accessible_locations().
--
-- Sessions stay single-location. An admin marking two locations at once
-- produces one session row per location, so all per-location reporting
-- (attendance_summary_by_location, the dashboard trend, the bar chart)
-- keeps working exactly as before.
-- =========================================================

-- ---------------------------------------------------------
-- 1. The grant table
-- ---------------------------------------------------------
create table if not exists public.admin_locations (
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (profile_id, location_id)
);

create index if not exists admin_locations_profile_idx
  on public.admin_locations(profile_id);

-- Carry every existing admin's single location across, so nobody loses
-- access the moment this runs.
insert into public.admin_locations (profile_id, location_id)
select id, location_id
  from public.profiles
 where location_id is not null
on conflict do nothing;

-- ---------------------------------------------------------
-- 2. The replacement for current_location()
--
-- SECURITY DEFINER for the same reason current_location() was: it runs as
-- the owner, so it can read admin_locations from inside a policy without
-- recursing through that table's own RLS.
-- ---------------------------------------------------------
create or replace function public.accessible_locations()
returns setof uuid
language sql
stable
security definer
as $$
  select location_id
    from public.admin_locations
   where profile_id = auth.uid();
$$;

-- ---------------------------------------------------------
-- 3. RLS on the grant table itself
--
-- An admin may read their own grants (the app needs this to know which
-- locations to show). Only a super admin can hand out or revoke access.
-- ---------------------------------------------------------
alter table public.admin_locations enable row level security;

drop policy if exists "admin_locations_read_own" on public.admin_locations;
create policy "admin_locations_read_own" on public.admin_locations
  for select using (
    profile_id = auth.uid() or public.current_role() = 'super_admin'
  );

drop policy if exists "admin_locations_superadmin_write" on public.admin_locations;
create policy "admin_locations_superadmin_write" on public.admin_locations
  for all using (public.current_role() = 'super_admin')
  with check (public.current_role() = 'super_admin');

-- ---------------------------------------------------------
-- 4. Re-scope the three data policies
--
-- Identical in shape to before; only the location test changed from
-- "= current_location()" to "in (select accessible_locations())".
-- ---------------------------------------------------------
drop policy if exists "members_scoped" on public.members;
create policy "members_scoped" on public.members
  for all using (
    public.current_role() = 'super_admin'
    or location_id in (select public.accessible_locations())
  )
  with check (
    public.current_role() = 'super_admin'
    or location_id in (select public.accessible_locations())
  );

drop policy if exists "sessions_scoped" on public.sessions;
create policy "sessions_scoped" on public.sessions
  for all using (
    public.current_role() = 'super_admin'
    or location_id in (select public.accessible_locations())
  )
  with check (
    public.current_role() = 'super_admin'
    or location_id in (select public.accessible_locations())
  );

drop policy if exists "attendance_scoped" on public.attendance;
create policy "attendance_scoped" on public.attendance
  for all using (
    public.current_role() = 'super_admin'
    or exists (
      select 1 from public.sessions s
       where s.id = attendance.session_id
         and s.location_id in (select public.accessible_locations())
    )
  )
  with check (
    public.current_role() = 'super_admin'
    or exists (
      select 1 from public.sessions s
       where s.id = attendance.session_id
         and s.location_id in (select public.accessible_locations())
    )
  );

-- =========================================================
-- GRANTING ACCESS — this is how you make someone a multi-location admin.
--
-- Give an existing admin a second location:
--   insert into public.admin_locations (profile_id, location_id)
--   select p.id, l.id
--     from public.profiles p, public.locations l
--    where p.full_name = 'Their Name'
--      and l.name      = 'Malad'
--   on conflict do nothing;
--
-- Revoke one:
--   delete from public.admin_locations
--    where profile_id = (select id from public.profiles where full_name = 'Their Name')
--      and location_id = (select id from public.locations where name = 'Malad');
--
-- See who has what:
--   select p.full_name, p.role, l.name as location
--     from public.admin_locations al
--     join public.profiles  p on p.id = al.profile_id
--     join public.locations l on l.id = al.location_id
--    order by p.full_name, l.name;
--
-- Super admins need no rows here — their policies short-circuit on role.
-- =========================================================

-- =========================================================
-- LEGACY, left in place deliberately (NOT run above).
--
-- profiles.location_id and current_location() are no longer consulted by
-- any policy or by the app. They are kept so this migration is reversible
-- and so nothing referencing them breaks mid-deploy. Once you have
-- confirmed multi-location access works, they can go:
--
--   alter table public.profiles drop column location_id;
--   drop function if exists public.current_location();
--
-- Until then, be aware that editing profiles.location_id has NO effect on
-- what an admin can see — admin_locations is the only thing that matters.
-- =========================================================
