# Architecture

Nafir is self-hosted on an Ubuntu server.

## Components

- **Flutter** renders the mobile UI and plays audio.
- **Go API** authenticates users, manages metadata and authorizes uploads/playback.
- **PostgreSQL** stores users, tracks, albums and playlists.
- **MinIO** stores private audio and artwork objects.
- **Caddy** terminates HTTPS and serves the web app, the API under `/api/`, and presigned audio requests under `/nafir-music/`.
- **Docker Compose** runs the server stack.

## Storage and streaming

Objects use an owner-scoped path such as `users/{userId}/tracks/{trackId}/{filename}`. MinIO and PostgreSQL are reachable only on Docker's internal network. The client never receives MinIO administration credentials.

For playback, the authenticated client calls `GET /api/v1/tracks/{id}/stream` and receives a presigned URL (one hour by default, `STORAGE_URL_TTL`). The URL is signed for the public domain; Caddy forwards `/nafir-music/*` to MinIO, which verifies the signature, so the bucket itself stays private. Audio is streamed with byte-range support. The phone keeps only a bounded, evictable cache; cloud storage remains the source of truth.

## Access control

PostgreSQL has no row-level policies; the Go API is the boundary. Every track query takes the authenticated user's ID from the access token and filters on `owner_id`, and the store has no method that reads a track without an owner. Another user's track answers `404 not_found`, the same as a track that does not exist, so IDs cannot be probed.

## Delivery phases

| Phase | Outcome |
| --- | --- |
| 1 | Go API, container stack and HTTPS health check |
| 2 | Accounts, JWT authentication and database migrations |
| 3 | Private upload, track library and signed streaming |
| 4 | Queue, background playback and cache controls |
