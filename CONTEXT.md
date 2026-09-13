# IYS Attendance — Project Context

A complete technical reference for this codebase: what it does, how the
database is shaped, how the client is organized, and the non-obvious design
decisions behind it. Written to bring a new session (human or AI) up to
speed without re-deriving any of this from scratch.

Last verified against the live database: 2026 (see the schema-dump query at
the bottom to refresh this).

## What the app does

Weekly attendance tracking for ISKCON Youth Services (IYS) programs across
four physical locations (Vasai, Borivali, Mira Road, Malad). Two roles:

- **Location admin** — scoped to one location. Marks weekly attendance for
  their own boys (devotees), manages their location's roster, views their
  location's session history.
- **Super admin** — no location of their own (`location_id` is `NULL`).
  Sees every location: a cross-location dashboard with attendance trends,
  can mark or edit attendance anywhere, can create **special events**
  (e.g. Janmashtami) that every location marks independently, and gets a
  bird's-eye view of event attendance broken down by location.

There is no public sign-up and no in-app account creation — see
[Account provisioning](#account-provisioning).

## Tech stack

- **Flutter** (SDK `^3.9.2`), Material 3.
- **Riverpod** (`flutter_riverpod`) for state — every provider is a plain
  (non-`autoDispose`) `FutureProvider`/`FutureProvider.family`. This is a
  deliberate choice (simplicity over memory-optimal caching) but it has a
  real consequence: see [Cache invalidation](#cache-invalidation--the-logout-leak).
- **go_router** for navigation, with a `redirect` that branches on
  `profiles.role` and a global `refreshListenable` tied to Supabase auth
  state (see [Routing](#routing)).
- **Supabase** — Postgres + Auth + Row-Level Security. No custom backend;
  the Flutter client talks to Supabase directly using the anon/publishable
  key. All access control is enforced by RLS, not by the client.
- **fl_chart** for the dashboard's trend line and location bar chart.
- **google_fonts** (Inter + Outfit) for typography.

The Supabase URL and anon/publishable key are hardcoded in
[`lib/core/supabase/supabase_client.dart`](lib/core/supabase/supabase_client.dart)
and are safe to have in source — see
[Why the anon key is safe to publish](#why-the-anon-key-is-safe-to-publish).

## Project structure

```
lib/
  core/
    models/          Location, Member, Session, Profile, Event — thin
                      classes with fromJson()/toInsertJson(), one field per
                      DB column actually used by the client.
    providers/        auth_provider.dart (session, profile, sign in/out,
                       AuthChangeNotifier for go_router).
    router/           app_router.dart — the entire route table + redirect.
    supabase/          supabase_client.dart — client init, hardcoded creds.
    theme/             app_theme.dart — AppColors, AppGradients, ThemeData.
    widgets/           motifs.dart — hand-drawn LotusIcon / PeacockFeather /
                       SacredHeader, used in place of emoji throughout.
  features/
    admin/            Location-admin home screen.
    attendance/       Mark Attendance screen + its provider (the one place
                      that writes to `sessions` and `attendance`).
    auth/             Login screen.
    dashboard/        Super-admin dashboard, member detail ("Devotee
                       Details"), and the providers backing both.
    events/           Special-events feature: create/list/detail screens
                       and events_provider.dart.
    members/          Add/edit member, manage-members (roster) screens.
    sessions/         Sessions list + session detail (view/edit/delete).
```

Each feature folder is `providers/` + `screens/`. There's no repository or
service layer between screens and Supabase — providers call
`Supabase.instance.client` directly.

## Database schema

Six tables in `public`, all owned by the app. `auth.users` (managed by
Supabase Auth) is the seventh, implicit table — `profiles.id` is a 1:1
mirror of it.

### `locations`

| column       | type          | nullable | default             |
|--------------|---------------|----------|---------------------|
| id           | uuid          | no       | `uuid_generate_v4()`|
| name         | text          | no       |                     |
| created_at   | timestamptz   | no       | `now()`             |

The four rows are Vasai, Borivali, Mira Road, Malad. **No app code creates
locations** — the `locations_read` RLS policy (below) only grants `SELECT`,
so even a super admin cannot insert/update/delete a location through the
client. New locations must be added directly in the Supabase SQL editor.

### `profiles`

1:1 with `auth.users` (`profiles.id` = `auth.users.id`, not enforced by an
explicit FK in `public` since `auth` is a separate schema).

| column       | type          | nullable | default              |
|--------------|---------------|----------|----------------------|
| id           | uuid          | no       |                      |
| full_name    | text          | no       |                      |
| role         | `user_role`   | no       | `'admin'`            |
| location_id  | uuid → locations.id | yes | (null = super admin) |
| created_at   | timestamptz   | no       | `now()`              |

`user_role` is a Postgres enum: `'admin' | 'super_admin'`.

No `INSERT`, `UPDATE`, or `DELETE` policy exists on this table (see RLS
below) — profile rows can only be written via the SQL editor / service
role, never through the app. This is intentional; see
[Account provisioning](#account-provisioning).

### `members`

The devotee roster.

| column       | type          | nullable | default              |
|--------------|---------------|----------|----------------------|
| id           | uuid          | no       | `uuid_generate_v4()` |
| full_name    | text          | no       |                      |
| dob          | date          | yes      |                      |
| phone        | text          | yes      |                      |
| email        | text          | yes      |                      |
| location_id  | uuid → locations.id | no |                      |
| is_active    | boolean       | no       | `true`               |
| created_by   | uuid → profiles.id | yes |                      |
| created_at   | timestamptz   | no       | `now()`              |
| joined_on    | date          | no       | `CURRENT_DATE`       |

`is_active` is a soft-delete flag — [`softDeleteMember()`](lib/features/members/providers/members_provider.dart)
sets it `false` rather than deleting the row, so attendance history is
preserved. `joined_on` is the field the eligibility logic hinges on — see
[Joining-date eligibility](#joining-date-eligibility).

### `sessions`

One row per (location, date) for a regular programme, or per
(location, event) for an event.

| column       | type          | nullable | default              |
|--------------|---------------|----------|----------------------|
| id           | uuid          | no       | `uuid_generate_v4()` |
| location_id  | uuid → locations.id | no |                      |
| session_date | date          | no       | `CURRENT_DATE`        |
| notes        | text          | yes      |                      |
| created_by   | uuid → profiles.id | yes |                      |
| created_at   | timestamptz   | no       | `now()`              |
| event_id     | uuid → events.id, **ON DELETE CASCADE** | yes | |

Two partial unique indexes (from `schema_updates.sql`) let a location have
at most one regular session per day *and* one session per event, without
the two conflicting:

```sql
create unique index sessions_regular_unique
  on sessions (location_id, session_date) where event_id is null;
create unique index sessions_event_unique
  on sessions (location_id, event_id) where event_id is not null;
```

**Sessions are created lazily, only on save** — see
[Sessions are created on save, not on view](#sessions-are-created-on-save-not-on-view).

### `attendance`

| column       | type          | nullable | default              |
|--------------|---------------|----------|----------------------|
| id           | uuid          | no       | `uuid_generate_v4()` |
| session_id   | uuid → sessions.id, **ON DELETE CASCADE** | no | |
| member_id    | uuid → members.id, **ON DELETE CASCADE** | no | |
| present      | boolean       | no       | `true`               |
| marked_by    | uuid → profiles.id | yes |                      |
| marked_at    | timestamptz   | no       | `now()`              |

There's an implied unique constraint on `(session_id, member_id)` — the app
upserts with `onConflict: 'session_id,member_id'`
([`saveAttendanceForSession`](lib/features/attendance/providers/attendance_provider.dart)),
which requires one to exist. It predates `schema_updates.sql` so its exact
name isn't in this repo; confirm with
`\d attendance` / `pg_indexes` if you need it.

Because `session_id`/`member_id` cascade, deleting a session or a member
also deletes their attendance rows automatically. The app additionally
deletes attendance explicitly before deleting a session or event
([`deleteSession`](lib/features/sessions/providers/sessions_provider.dart),
[`deleteEvent`](lib/features/events/providers/events_provider.dart)) — this
predates the cascade being confirmed and is now redundant but harmless.

### `events`

| column       | type          | nullable | default              |
|--------------|---------------|----------|----------------------|
| id           | uuid          | no       | `uuid_generate_v4()` |
| title        | text          | no       |                      |
| event_date   | date          | no       |                      |
| notes        | text          | yes      |                      |
| created_by   | uuid → profiles.id | yes |                      |
| created_at   | timestamptz   | no       | `now()`              |

An event is a wrapper: creating one inserts the event row **and** one
`sessions` row per location (linked by `sessions.event_id`), so every
location gets it in their session list on creation. See
[Events architecture](#events-architecture).

## Row-Level Security

RLS is enabled on all six tables (confirmed via `pg_tables.rowsecurity`).
Two helper functions back almost every policy:

```sql
CREATE FUNCTION public.current_role() RETURNS user_role
  LANGUAGE sql STABLE SECURITY DEFINER AS $$
  select role from public.profiles where id = auth.uid();
$$;

CREATE FUNCTION public.current_location() RETURNS uuid
  LANGUAGE sql STABLE SECURITY DEFINER AS $$
  select location_id from public.profiles where id = auth.uid();
$$;
```

Both are `SECURITY DEFINER` — they run as the function owner, not the
caller, which is what lets them read `profiles` inside a policy that's
*attached to* `profiles` without recursing into RLS. Every scoped policy
below ultimately trusts these two functions, which means it ultimately
trusts `profiles.role` and `profiles.location_id` being un-forgeable — see
[the self-update fix](#security-history) for why that matters.

Current policies, table by table:

| table | policy | command | rule |
|---|---|---|---|
| `attendance` | `attendance_scoped` | ALL | `current_role() = 'super_admin'` OR the row's session belongs to `current_location()` |
| `members` | `members_scoped` | ALL | `current_role() = 'super_admin'` OR `location_id = current_location()` |
| `sessions` | `sessions_scoped` | ALL | `current_role() = 'super_admin'` OR `location_id = current_location()` |
| `events` | `events_read` | SELECT | `auth.role() = 'authenticated'` (any signed-in user) |
| `events` | `events_superadmin_write` | ALL | `current_role() = 'super_admin'` |
| `locations` | `locations_read` | SELECT | `auth.role() = 'authenticated'` (no write policy at all) |
| `profiles` | `profiles_self_or_superadmin_read` | SELECT | `id = auth.uid()` OR `current_role() = 'super_admin'` |

`events_read`/`locations_read` being open to any authenticated user is
intentional and low-risk — event titles/dates and location names aren't
sensitive, and there's no public sign-up, so "any authenticated user" means
"one of the ~5 manually-created admin accounts."

### Security history

**`profiles_self_update` (UPDATE, `id = auth.uid()`, no `with_check`) was
removed.** It let any authenticated user update their own profile row with
no column restriction — and since `current_role()`/`current_location()`
read `role`/`location_id` straight from that row, any admin could run
`update profiles set role = 'super_admin' where id = auth.uid()` via a
plain REST call and instantly escalate, which would also have defeated
`members_scoped`/`sessions_scoped`/`attendance_scoped` in one shot. No
client code ever called `.update()` on `profiles`, so dropping it cost no
functionality:

```sql
drop policy if exists "profiles_self_update" on public.profiles;
```

If self-service profile editing (e.g. changing your own display name) is
ever wanted, don't restore a row-level policy alone — pair it with a
column-level grant so `role`/`location_id` stay out of reach even if the
row check passes:

```sql
revoke update on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;
```

### Why the anon key is safe to publish

Supabase's anon/publishable key is *designed* to be public — every
Supabase client app ships it. It is not a secret; `current_role()` /
`current_location()` plus the policies above are what actually gate
access. This repo only ever embeds the publishable key, never a
service-role key. Verified before making the repo public:

- RLS enabled on all 6 tables.
- The privilege-escalation policy above, removed.
- Public sign-up disabled in the dashboard (Authentication → Settings) —
  accounts are provisioned manually (~5 admins).

## Views

Defined in [`supabase/schema_updates.sql`](supabase/schema_updates.sql),
all `security_invoker = true` (so a location admin querying a view only
gets their own rows, per the base table policies — the view doesn't widen
access).

- **`attendance_summary_by_location`** — per location, per session date:
  present count, total eligible members, percentage. Regular sessions only
  (`event_id is null`).
- **`attendance_summary_by_member`** — per member: total eligible sessions,
  attended count, percentage. Regular sessions only. Uses a `LEFT JOIN` so
  a brand-new member with zero sessions still appears (at 0%), rather than
  being omitted.
- **`event_attendance_summary`** — per event, per location: present count
  and total marked. This is what the super admin's event bird's-eye view
  reads (via `eventSummaryProvider`, though that provider actually queries
  `sessions`/`attendance` directly with member names rather than this view
  — the view is left in place as a lighter-weight alternative if the
  per-member breakdown is ever not needed).

All three summary views join against `members.joined_on` to exclude
sessions that predate a member — see below.

## Core design decisions

### Joining-date eligibility

`members.joined_on` (default: today, editable) is the anchor for every
attendance percentage in the app. A member is only "eligible" for a
session if `session.session_date >= member.joined_on`. This is applied in
three independent places that all need to agree:

1. `activeMembersProvider` — filters who shows up to be marked
   (`.lte('joined_on', date)`), so a session can't even be marked against
   someone who hadn't joined yet.
2. `attendance_summary_by_location` / `attendance_summary_by_member` views
   — the `eligible` CTE in each excludes pre-joining sessions from the
   denominator.
3. The Devotee Details page (`member_detail_screen.dart`) — reads
   `memberAttendanceHistoryProvider`, which is raw `attendance` rows, not
   the view; if a member's `joined_on` is moved *forward* after sessions
   were already marked, old rows can remain that the view now ignores but
   this page's raw count would not. `schema_updates.sql` has a commented-out
   cleanup query for exactly this case — it's manual/optional because
   deleting attendance rows is not reversible.

### Sessions are created on save, not on view

Early in development, simply *opening* Mark Attendance for a date created
a `sessions` row (0% attendance) even if nothing was ever marked. Fixed by
splitting the read and write paths:

- `existingSessionProvider` — read-only lookup, returns `null` if nothing
  exists yet. Used while a date is just being viewed.
- `_getOrCreateSession()` (private, in `attendance_provider.dart`) — only
  called from `saveAttendance()`, i.e. only when the admin actually taps
  Save.

This is also why `existingSessionProvider`/`_getOrCreateSession` both
filter `.isFilter('event_id', null)` — without it, looking up "the session
for this location on this date" could return an *event* session that
happens to share a date with the regular programme.

### Events architecture

An event is one row in `events` plus **one `sessions` row per location**
(`createEvent()` in `events_provider.dart` inserts the event, reads all
locations, then bulk-inserts one session per location with `event_id` set).
This is the key design choice: it means attendance marking, RLS, and
joining-date eligibility all work completely unchanged for event sessions
— a location admin marking an event is marking a `sessions` row scoped to
their `location_id`, exactly like a regular Wednesday. No new permission
logic was needed anywhere.

Consequences of this choice:

- Deleting an event cascades to its sessions (`sessions.event_id ON DELETE
  CASCADE`) and from there to attendance — `deleteEvent()` also does this
  explicitly, which is redundant now but was written before the cascade
  was confirmed.
- The sessions list ([`sessions_list_screen.dart`](lib/features/sessions/screens/sessions_list_screen.dart))
  distinguishes an event session from a regular one purely by
  `event_id != null` (joined in via `sessions(*, events(title))`), styling
  it with a saffron card and an "EVENT" badge.
- A session with nothing marked yet (`total_marked == 0`) is tapped
  straight into Mark Attendance instead of the detail page, since the
  detail page would just be empty. This was aimed at events (which start
  with 0 marked at every location) but is written as "unmarked", not
  "is an event", since a never-opened regular session behaves the same way.
- Regular summaries (`attendance_summary_by_*`) explicitly exclude event
  sessions (`where event_id is null`) so a one-off festival never moves the
  weekly attendance trend; events get their own separate reporting instead.

### Cache invalidation — the logout leak

Every provider is a plain `FutureProvider` (not `autoDispose`), which means
Riverpod caches results indefinitely by default. Two consequences this
codebase specifically had to handle:

1. **Stale data after a write.** Saving attendance, adding a member, etc.
   doesn't automatically invalidate the providers that list/summarize that
   data. `invalidateAttendanceCaches(ref)` in `attendance_provider.dart` is
   the single place that knows the full fan-out (sessions list, session
   detail, dashboard summaries, member history, event roll-ups) and is
   called after every write that could affect any of them. When adding a
   new provider that derives from `attendance`/`sessions`/`members`/
   `events`, it needs to be added to this list.
2. **Stale data across accounts (the actual security-relevant bug).**
   Without action, a signed-out admin's cached members/sessions/dashboard
   data survives in memory and gets shown to whoever logs in next on the
   same device. Fixed in [`main.dart`](lib/main.dart) by keying the
   `ProviderScope` on the signed-in user's id:
   ```dart
   ProviderScope(
     key: ValueKey(_userId ?? 'signed-out'),
     child: const IYSApp(),
   )
   ```
   Changing the key destroys and rebuilds the entire provider container,
   which is the only way to guarantee every cached provider is gone —
   invalidating them one by one is guaranteed to miss one eventually.

### Routing

Two parallel route trees hang off `/admin` (location admin) and
`/dashboard` (super admin) — see [`app_router.dart`](lib/core/router/app_router.dart).
They're structurally identical (`attendance`, `attendance/edit/:locationId/:date`,
`attendance/session/:sessionId`, `members`, `members/add`,
`members/edit/:id`, `sessions`, `sessions/:id`), with `/dashboard` adding
`member/:id` (Devotee Details) and `events*` since only a super admin uses
those. `MarkAttendanceScreen` is shared by both trees and branches on
whether `locationId`/`sessionId` was passed explicitly (super admin) or
should come from the caller's own profile (location admin).

The `redirect` callback is the single source of truth for
"logged out → `/login`" and "logged in on `/login` → route by role"; it
calls Supabase directly (`_fetchProfile()`) rather than going through a
Riverpod provider, since it can run before the `ProviderScope` exists.
`authChangeNotifier` (a plain `ChangeNotifier` wrapping
`onAuthStateChange`) is `go_router`'s `refreshListenable`, so a sign-out
triggers `redirect` to re-run without any provider being involved.

Screens navigate with `push()`, not `go()`, for anything that should
return to where it was opened from (add/edit member, mark attendance,
session/event detail) — `go()` replaces the whole stack, so back would land
somewhere unrelated to where the user actually came from. Back buttons
generally implement "pop if possible, else go() to a sane default" rather
than assuming a pop always has somewhere to land (needed for the case
where a route was opened directly, e.g. via a deep link).

## Account provisioning

There is no sign-up flow and no admin-creation screen in the app. Based on
the schema (no `INSERT` policy on `profiles`, sign-up disabled in Auth
settings), new admins are provisioned manually:

1. Supabase Dashboard → Authentication → Users → **Add user** (sets email
   + password, creates the `auth.users` row).
2. In the SQL editor (running as `postgres`, which bypasses RLS — this is
   the only way to write to `profiles` at all), insert the matching row:
   ```sql
   insert into public.profiles (id, full_name, role, location_id)
   values ('<auth-user-uuid>', 'Full Name', 'admin', '<location-uuid>');
   -- role 'super_admin' and location_id null for a super admin
   ```

## Setup

```bash
flutter pub get
flutter run
```

Supabase URL/key: [`lib/core/supabase/supabase_client.dart`](lib/core/supabase/supabase_client.dart).
Schema changes beyond the base tables: [`supabase/schema_updates.sql`](supabase/schema_updates.sql)
(idempotent — safe to re-run).

Regenerate the launcher icon after changing `tool/generate_icon.py`:

```bash
python3 tool/generate_icon.py
dart run flutter_launcher_icons
```

## Refreshing this document

The base table DDL and the two RLS helper functions live only in the
database, not in this repo (the original `CREATE TABLE`/`CREATE POLICY`
statements were run directly in the SQL editor before this repo existed).
To re-verify anything in the [Database schema](#database-schema) or
[Row-Level Security](#row-level-security) sections against the live
database, run in the Supabase SQL editor:

```sql
select json_build_object(
  'columns', (
    select json_agg(row_to_json(c) order by c.table_name, c.ordinal_position)
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name in ('profiles','locations','members','sessions','attendance','events')
  ),
  'policies', (
    select json_agg(row_to_json(p))
    from pg_policies p
    where p.schemaname = 'public'
  ),
  'functions', (
    select json_agg(json_build_object('name', p.proname, 'definition', pg_get_functiondef(p.oid)))
    from pg_proc p
    where p.proname in ('current_role','current_location')
  ),
  'foreign_keys', (
    select json_agg(json_build_object(
      'table', tc.table_name, 'column', kcu.column_name,
      'references_table', ccu.table_name, 'references_column', ccu.column_name,
      'on_delete', rc.delete_rule
    ))
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on tc.constraint_name = ccu.constraint_name and tc.table_schema = ccu.table_schema
    join information_schema.referential_constraints rc
      on tc.constraint_name = rc.constraint_name and tc.table_schema = rc.constraint_schema
    where tc.constraint_type = 'FOREIGN KEY' and tc.table_schema = 'public'
  )
) as schema_dump;
```
