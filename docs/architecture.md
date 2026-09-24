# Architecture

Nafir is self-hosted on an Ubuntu server.

## Components

- **Flutter** renders the mobile UI and plays audio.
- **Go API** authenticates users, manages metadata and authorizes uploads/playback.
- **PostgreSQL** stores users, tracks, albums and playlists.
- **MinIO** stores private audio and artwork objects.
- **Caddy** exposes only the API over HTTPS.
- **Docker Compose** runs the server stack.

## Storage and streaming

Objects use an owner-scoped path such as `users/{userId}/tracks/{trackId}/{filename}`. MinIO and PostgreSQL are reachable only on Docker's internal network. The client never receives MinIO administration credentials.

For playback, the authenticated client asks the Go API for a short-lived signed URL. Audio is streamed with byte-range support. The phone keeps only a bounded, evictable cache; cloud storage remains the source of truth.

## Delivery phases

| Phase | Outcome |
| --- | --- |
| 1 | Go API, container stack and HTTPS health check |
| 2 | Accounts, JWT authentication and database migrations |
| 3 | Private upload, track library and signed streaming |
| 4 | Queue, background playback and cache controls |
