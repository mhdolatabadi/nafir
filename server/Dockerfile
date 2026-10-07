FROM golang:1.26.8-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd cmd
COPY internal internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/nafir-api ./cmd/api

FROM alpine:3.21
# yt-dlp (pinned by hash in ytdlp-requirements.txt) with Python, ffmpeg to copy
# audio out of videos without re-encoding, and Node.js for YouTube's
# JavaScript challenges. Alpine's packages follow the pinned 3.21 branch.
RUN apk add --no-cache ca-certificates python3 ffmpeg nodejs
COPY ytdlp-requirements.txt /tmp/ytdlp-requirements.txt
RUN python3 -m venv /opt/yt-dlp \
    && /opt/yt-dlp/bin/pip install --no-cache-dir --no-deps --require-hashes -r /tmp/ytdlp-requirements.txt \
    && ln -s /opt/yt-dlp/bin/yt-dlp /usr/local/bin/yt-dlp \
    && rm /tmp/ytdlp-requirements.txt \
    && yt-dlp --version
RUN addgroup -S nafir && adduser -S -G nafir -u 10001 nafir
COPY --from=build /out/nafir-api /usr/local/bin/nafir-api
USER nafir
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/nafir-api"]
