# SOT

Cross-platform personal cloud music player. Music is stored on the user's self-hosted server and streamed to Android/iOS with a bounded, disposable device cache.

## Stack

- Flutter mobile client
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

## Deploy

See [deploy/README.md](deploy/README.md). Do not commit deployment secrets or `.env`.
