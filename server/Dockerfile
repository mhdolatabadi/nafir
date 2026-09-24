FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd cmd
COPY internal internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/sot-api ./cmd/api

FROM alpine:3.21
RUN addgroup -S sot && adduser -S -G sot -u 10001 sot
COPY --from=build /out/sot-api /usr/local/bin/sot-api
USER sot
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/sot-api"]
