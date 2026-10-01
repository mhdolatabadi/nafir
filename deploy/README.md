# Nafir server deployment

## One-time setup

1. Point an A/AAAA DNS record for your chosen subdomain (for example, `music.example.com`) to the Ubuntu server.
2. Open inbound TCP ports 80 and 443 in the server firewall/provider firewall.
3. Clone this repository on the server.
4. Copy the environment template and replace every placeholder with a long random value:

   ```bash
   cd deploy
   cp .env.example .env
   chmod 600 .env
   ```

5. Start the stack:

   ```bash
   docker compose up -d --build
   ```

Caddy automatically obtains and renews the TLS certificate after DNS resolves to the server. Verify with:

```bash
curl https://music.example.com/api/v1/health
```

Expected response: `{"status":"ok"}`.

Caddy splits the domain between three services:

| Path | Served by |
|---|---|
| `/`, `/p/{token}`, `/sitemap.xml`, `/robots.txt` | the API's public pages: popular public playlists, readable by anyone and by search engines |
| `/app/` | the Flutter web app (also installable as a PWA); it calls the API on its own origin |
| `/api/*` | the Go API |

`/app` redirects to `/app/`, and share links from before the move
(`/?shared=…`) redirect to `/app/?shared=…`. Both the API and the public pages
receive the visitor's IP in `X-Nafir-Client-IP` for rate limiting.

Audio objects under `/nafir-music/*` deliberately bypass Caddy response
compression and are served with `Cache-Control: private, no-transform`. This
keeps byte ranges and cached media identical to the object stored in MinIO.

## Images

The **Images** workflow builds the `api` and `web` images on every push to `main`
and publishes them to GitHub Container Registry as
`ghcr.io/mhdolatabadi/nafir/{api,web}`, tagged with the commit SHA and `latest`.
The server only pulls them, so it never needs the multi-gigabyte Flutter SDK.

If `docker compose pull` returns `unauthorized`, open each package under the
repository's **Packages** and set its visibility to public, or run
`docker login ghcr.io` on the server with a token that has `read:packages`.

To build locally instead, run `docker compose up -d --build`.

## Updates

On the server, `deploy/deploy.sh` pulls `main`, pulls the images built for that
exact commit, restarts the stack and waits for the health check. Run it after
the **Images** workflow for that commit has finished; otherwise the pull fails
and nothing is restarted.

To deploy from GitHub instead, open **Actions → Deploy → Run workflow**. It needs these secrets in the `production` environment:

| Secret | Value |
| --- | --- |
| `DEPLOY_HOST` | Server IP or hostname |
| `DEPLOY_USER` | SSH user that can run `docker` |
| `DEPLOY_PATH` | Absolute path of the repository clone, for example `/opt/nafir` |
| `DEPLOY_SSH_KEY` | Private key of a dedicated deploy key pair; add the public key to the user's `~/.ssh/authorized_keys` |
| `DEPLOY_KNOWN_HOSTS` | Output of `ssh-keyscan <host>`, verified against the server's fingerprint |

## Adding authentication to an existing server

The API now refuses to start without `AUTH_TOKEN_SECRET`. Add it to `deploy/.env` before deploying:

```bash
echo "AUTH_TOKEN_SECRET=$(openssl rand -hex 32)" >> deploy/.env
```

Changing it later signs every user out.

## Upgrading from SOT

The project was renamed from SOT to Nafir. On a server deployed before the rename:

1. In `deploy/.env`, rename `SOT_DOMAIN` to `NAFIR_DOMAIN` and add `NAFIR_IMAGE_REPO` from `.env.example`.
2. PostgreSQL only reads `POSTGRES_DB` and `POSTGRES_USER` when its volume is first created, so the
   existing `sot` database and role stay as they are. Pick one:
   - The volume holds no data yet: `docker compose down && docker volume rm deploy_postgres-data`,
     then deploy again and a fresh `nafir` database is created.
   - Keep the data: add a `nafir` superuser and rename the database. The old `sot` role created the
     cluster, so PostgreSQL keeps it; it simply stops being used.

     ```bash
     docker compose exec postgres psql -U sot -d postgres \
       -c "CREATE ROLE nafir WITH SUPERUSER LOGIN PASSWORD '<POSTGRES_PASSWORD from .env>';"
     docker compose exec postgres psql -U nafir -d postgres \
       -c 'ALTER DATABASE sot RENAME TO nafir;' \
       -c 'ALTER DATABASE nafir OWNER TO nafir;'
     ```

## Bale and Telegram bots

People can send audio to Nafir's Bale or Telegram bot and it lands in their
library. To link a chat to their account, they open **Settings → اتصال به بات**
in the Nafir app (web or Android), get a one-time 8-digit code, and send it to
the bot. Proving who they are happens in the app they are already signed in to,
so the bots need no email and never ask for a password.

Each bot is optional and stays off while its token is empty.

1. Create the bot with **@BotFather** in Bale and/or Telegram. Copy its token
   and username.
2. In `deploy/.env`, set:
   - `BOT_WEBHOOK_SECRET` to `openssl rand -hex 32`. It is part of each
     webhook URL, so only the messenger knows where to post updates; Telegram
     also sends it back in a header, which the API checks.
   - `BALE_BOT_TOKEN` and `BALE_BOT_USERNAME` for Bale.
   - `TELEGRAM_BOT_TOKEN` and `TELEGRAM_BOT_USERNAME` for Telegram.
   - The usernames let the app name each bot and offer a link that opens it
     with the code filled in.
3. **Telegram from a server in Iran:** `api.telegram.org` is filtered there, so
   set `TELEGRAM_PROXY_URL` to a proxy outside Iran (`socks5://…` or
   `http://…`). Telegram must also be able to reach
   `https://<NAFIR_DOMAIN>` to deliver updates. Bale has a matching
   `BALE_PROXY_URL`, which it normally does not need.
4. Deploy. On start the API registers
   `https://<NAFIR_DOMAIN>/api/v1/bots/<bale|telegram>/webhook/<secret>` with
   each messenger, and logs `bot webhook registered provider=<name>`. If a
   messenger is unreachable it keeps retrying and logs each failure.

Link codes last ten minutes and work once. A chat that sends five wrong codes
in an hour is locked out for the rest of that hour, and each account can
request ten codes an hour (`BOT_LINK_RATE_REQUESTS`, `BOT_LINK_RATE_WINDOW`).
One code links a chat in whichever bot it is sent to.

Bot imports follow the same rules as uploads from the app: the file size
limit, the storage quota, the pending-upload limit and `UPLOADS_ENABLED`.
Both Bot APIs serve bots files up to 20 MB by default
(`BALE_MAX_DOWNLOAD_BYTES`, `TELEGRAM_MAX_DOWNLOAD_BYTES`); larger files get a
message explaining the limit.

Once a chat is linked, each track's menu in the app offers «ارسال به بله» or
«ارسال به تلگرام»: the bot posts that audio into the chat, where it can be
played or forwarded. Bots upload files up to 50 MB by default
(`BALE_MAX_UPLOAD_BYTES`, `TELEGRAM_MAX_UPLOAD_BYTES`), each account can send
thirty tracks an hour (`BOT_SEND_RATE_REQUESTS`, `BOT_SEND_RATE_WINDOW`), and
a track sent once is sent again instantly without another upload.

To turn a bot off, clear its token and deploy. A chat can be unlinked from
the bot with `/logout`.

## Operating the bots

### Secrets
Bot tokens, `BOT_WEBHOOK_SECRET` and `OPS_TOKEN` live only in `deploy/.env` on
the server. The GitHub deploy workflow never sees them: it runs `deploy.sh`
over SSH, and the API reads them at start. They are not baked into images,
and the API never logs them. Errors are stripped of bot tokens, and the
webhook secret is never printed.

### Health
- `deploy.sh` checks the bots after every deploy when `OPS_TOKEN` is set. It
  prints the report and warns if a bot needs attention. The site is up either
  way, so a warning does not fail the deploy.
- Any time:

  ```bash
  curl -s -H "Authorization: Bearer $OPS_TOKEN" https://<NAFIR_DOMAIN>/api/v1/ops/bots
  ```

  For each bot this shows:
  - whether its webhook is registered at the right URL
  - how many updates the messenger is still holding, and its last delivery
    error
  - the import queue (queued, downloading, done and failed in the last hour,
    oldest waiting)
  - counters since the API started: updates, duplicates, links, imports and
    sends, and their failures

  `problems` lists anything that needs attention, and `healthy` is false when
  any bot has a problem.
- Every five minutes the API logs a `bot health` line per bot, at warning
  level when there is a problem:

  ```bash
  docker compose logs api | grep "bot health"
  ```

  Warnings mean one of these:
  - the messenger's API is unreachable
  - the webhook is not registered, or points elsewhere
  - more than 100 updates are waiting
  - a delivery error in the last 15 minutes
  - an import waiting over 15 minutes
  - more than 10 failed imports in an hour

### Smoke test after changing bot settings
1. The deploy output shows `Bot health: {"healthy":true,...}`.
2. In the app: **Settings → اتصال به بات → دریافت کد اتصال**. Send the code to
   the bot; it replies that the chat is linked.
3. Send an mp3 to the bot. It replies «… به کتابخانهٔ نفیر اضافه شد.», and the
   track appears in the app with «از بله» or «از تلگرام».
4. From the track's menu choose «ارسال به …»; the audio arrives in the chat.
5. `/logout` in the bot, then send another file: the bot asks to link again.

### Rotating a bot token
1. In @BotFather, revoke the token and copy the new one.
2. Replace `BALE_BOT_TOKEN` or `TELEGRAM_BOT_TOKEN` in `deploy/.env` and run
   `deploy/deploy.sh`. On start, the API registers the webhook again with the
   new token.

Linked chats, imports and sent-file IDs all survive the rotation.

### Rotating the webhook secret
Set a new `BOT_WEBHOOK_SECRET` (`openssl rand -hex 32`) and deploy. Each bot's
webhook is re-registered with the new URL (and, for Telegram, the new header
secret). Updates still addressed to the old URL get 404, and the messenger
retries them at the new one.

### When a messenger or the network is down
- **Updates:** Telegram and Bale keep undelivered updates and retry them.
  Nafir ignores updates it has already handled, so retries are safe. When all
  16 update workers are busy, the webhook answers 503 so the messenger retries
  later.
- **Imports:** a failed download is retried three times with growing delays.
  Imports interrupted by a restart resume when the API starts, and a failed
  import removes its half-stored track and object.
- **Webhook registration:** if the messenger is unreachable at start, the API
  keeps retrying with growing delays up to five minutes.
- **Telegram from Iran:** if Telegram becomes unreachable, check
  `TELEGRAM_PROXY_URL` first.

### Turning a bot off or rolling back
- **Turn a bot off:** clear its token and deploy. Its webhook stays registered
  with the messenger, which then gets 404s. To stop that too:

  ```bash
  curl -s "https://tapi.bale.ai/bot<token>/deleteWebhook"      # Bale
  curl -s "https://api.telegram.org/bot<token>/deleteWebhook"  # Telegram
  ```
- **Roll back:** run `deploy/deploy.sh <previous-commit>`. Bot tables only gain
  columns and tables, so an older API keeps working with them.

## Security rules

- Never commit `.env`.
- Keep MinIO and PostgreSQL on the internal Docker network; do not expose their ports.
- Back up the named Docker volumes before upgrades.
- The API will create private music objects and issue short-lived playback links in the next feature.
