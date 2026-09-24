# Architecture

## Storage and streaming

Each upload is stored at `users/{userId}/tracks/{trackId}/{originalFileName}` in a private Supabase Storage bucket. Track metadata lives in Postgres. The client requests a short-lived signed URL only for its own track, then passes that URL to the player.

The player uses an on-device cache capped at 500 MB. Cached bytes are evicted oldest-first and are never treated as a source of truth. Uploading does not duplicate the file in the user's music library on device.

## Data model

```sql
create table public.tracks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  artist text,
  album text,
  duration_ms integer,
  storage_path text not null unique,
  artwork_path text,
  created_at timestamptz not null default now()
);

alter table public.tracks enable row level security;
create policy "Users manage own tracks" on public.tracks
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
```

Storage policies must restrict objects to the authenticated user path. Signed URLs expire quickly, for example after one hour.

## Delivery phases

| Phase | Outcome |
| --- | --- |
| 1 | Auth, private upload, library, stream playback |
| 2 | Queue, shuffle/repeat, search, album art and playlists |
| 3 | Background playback, lock-screen controls, cache settings |
| 4 | Offline downloads as a deliberate, opt-in feature |
