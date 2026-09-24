# SOT

Cross-platform personal music player. Each user owns a private music library: audio files live in cloud storage and are streamed with a bounded, disposable cache rather than permanently downloaded to the device.

## Product principles

- Private by default: a user can only list and play their own tracks.
- Stream first: no automatic offline downloads.
- Familiar playback: queue, seek, shuffle, repeat, background playback and media controls.
- Cache is a performance feature, not a library: it has a configurable size limit and can be cleared at any time.

## Stack

- Flutter for Android and iOS
- Supabase Auth, Postgres and Storage
- `just_audio` + `audio_service` for playback and background controls
- Riverpod for app state

## Local setup

```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=your-project-url --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Do not commit secrets. Database and Storage Row Level Security are the access boundary.
