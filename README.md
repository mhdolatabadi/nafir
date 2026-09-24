# Nafir

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

The API needs PostgreSQL, MinIO and a token secret. It applies its database
migrations on startup.

```bash
docker run -d --name nafir-db -p 5432:5432 \
  -e POSTGRES_USER=nafir -e POSTGRES_PASSWORD=nafir -e POSTGRES_DB=nafir postgres:16-alpine
docker run -d --name nafir-minio -p 9000:9000 minio/minio server /data
cd server
export DATABASE_URL='postgres://nafir:nafir@localhost:5432/nafir?sslmode=disable'
export AUTH_TOKEN_SECRET="$(openssl rand -hex 32)"
export STORAGE_ENDPOINT=localhost:9000 STORAGE_PUBLIC_URL=http://localhost:9000
export STORAGE_BUCKET=nafir-music STORAGE_ACCESS_KEY=minioadmin STORAGE_SECRET_KEY=minioadmin
TEST_DATABASE_URL="$DATABASE_URL" go test ./...
go run ./cmd/api
```

Then open `http://localhost:8080/api/v1/health`. `AUTH_TOKEN_TTL` (default
`720h`) sets how long a login lasts. The store tests drop and recreate tables in
`TEST_DATABASE_URL`, so point it at a disposable database.

| Endpoint | Purpose |
| --- | --- |
| `POST /api/v1/auth/register` | Create an account from `{"email", "password"}` and return a session |
| `POST /api/v1/auth/login` | Return a session for valid credentials |
| `GET /api/v1/me` | Return the user for `Authorization: Bearer <token>` |
| `GET /api/v1/tracks` | List the caller's tracks, newest first |
| `GET /api/v1/tracks/{id}` | One of the caller's tracks; another user's track is `404` |
| `GET /api/v1/tracks/{id}/stream` | A short-lived presigned URL for the caller's track |

Passwords must be 8–72 characters and are stored only as bcrypt hashes.

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
server is unavailable. It then restores the saved session, or asks the user to
sign in or register. The access token is kept in the platform's secure storage
(Keychain, Keystore, or encrypted browser storage on the web).

## Deploy

See [deploy/README.md](deploy/README.md). Do not commit deployment secrets or `.env`.
