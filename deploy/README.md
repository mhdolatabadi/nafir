# SOT server deployment

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

## Updates

On the server, `deploy/deploy.sh` pulls `main`, rebuilds the stack and waits for the health check.

To deploy from GitHub instead, open **Actions → Deploy → Run workflow**. It needs these secrets in the `production` environment:

| Secret | Value |
| --- | --- |
| `DEPLOY_HOST` | Server IP or hostname |
| `DEPLOY_USER` | SSH user that can run `docker` |
| `DEPLOY_PATH` | Absolute path of the repository clone, for example `/opt/sot` |
| `DEPLOY_SSH_KEY` | Private key of a dedicated deploy key pair; add the public key to the user's `~/.ssh/authorized_keys` |
| `DEPLOY_KNOWN_HOSTS` | Output of `ssh-keyscan <host>`, verified against the server's fingerprint |

## Security rules

- Never commit `.env`.
- Keep MinIO and PostgreSQL on the internal Docker network; do not expose their ports.
- Back up the named Docker volumes before upgrades.
- The API will create private music objects and issue short-lived playback links in the next feature.
