# IYS Attendance

Weekly attendance tracking for ISKCON Youth Services programs, across multiple
locations.

Built with Flutter + Riverpod on the client, and Supabase (Postgres + Auth +
Row-Level Security) as the backend.

## Features

- **Location admins** mark weekly attendance for their own boys, view past
  sessions, and manage their location's member roster (with editable joining
  dates so attendance before a boy joined never counts against him).
- **Super admins** get a cross-location dashboard — attendance trends, a
  location comparison chart, and the ability to mark or edit attendance for
  any location.
- **Special events** (e.g. Janmashtami) can be created by a super admin and
  are automatically added to every location's session list; each admin marks
  only their own boys, and the super admin gets a bird's-eye view of who
  attended, broken down by location.
- Session history with a detail view, editable past attendance, and deletion
  for super admins.

## Architecture

- `lib/core` — models, theme, router, and Supabase client setup.
- `lib/features/*` — one folder per feature (attendance, members, sessions,
  events, dashboard, admin), each with its own `providers/` and `screens/`.
- `supabase/schema_updates.sql` — incremental schema changes (joining dates,
  the events feature, and the summary views), meant to be run in the Supabase
  SQL editor.

Access control is enforced with Postgres Row-Level Security, not in the
client: every table's policies scope reads/writes to the caller's own
location unless they're a super admin. The Supabase URL and anon key are
safe to keep in source — Supabase's anon key is designed to be public, and
security comes entirely from RLS.

## Getting started

```bash
flutter pub get
flutter run
```

The Supabase project URL and anon key are set in
`lib/core/supabase/supabase_client.dart`.

### Regenerating the launcher icon

```bash
python3 tool/generate_icon.py
dart run flutter_launcher_icons
```
