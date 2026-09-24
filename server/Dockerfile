FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd cmd
COPY internal internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/nafir-api ./cmd/api

FROM alpine:3.21
RUN addgroup -S nafir && adduser -S -G nafir -u 10001 nafir
COPY --from=build /out/nafir-api /usr/local/bin/nafir-api
USER nafir
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/nafir-api"]
