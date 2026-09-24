# SOT

Cross-platform personal cloud music player. Music is stored on the user's self-hosted server and streamed to Android, iOS, and the web with a bounded, disposable device cache.

## Stack

- Flutter client for Android, iOS, and Web/PWA
- Go HTTP API
- PostgreSQL for accounts and track metadata
- MinIO for private audio object storage
- Caddy for automatic HTTPS
- Docker Compose for Ubuntu deployment

## Product principles

- Private by default: users can access only their own tracks.
- Stream first: no automatic permanent download to the phone.
- Familiar playback: queue, seek, shuffle, repeat, background playback and media controls.
- Cache is bounded and can be cleared without deleting cloud files.

## Run the API locally

```bash
cd server
go test ./...
go run ./cmd/api
```

Then open `http://localhost:8080/api/v1/health`.

## Run the Flutter app

Start the Go API, then run Flutter with its public base URL:

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` points to the host machine from the Android emulator. For a real
device or production build, use the HTTPS domain served by Caddy:

```bash
flutter run --dart-define=API_BASE_URL=https://music.example.com
```

The app checks `/api/v1/health` on startup and offers a retry action when the
server is unavailable. Authentication will be added against the Go API; the
old Supabase client integration has been removed.

## Deploy

See [deploy/README.md](deploy/README.md). Do not commit deployment secrets or `.env`.
