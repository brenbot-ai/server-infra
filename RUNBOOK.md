# Multi-Site Migration Runbook
## equityrange.com VPS — Shared Reverse Proxy Setup

**Goal:** Lift nginx out of the poker-tracker stack into a shared proxy that can serve any number of sites. Zero downtime for the poker tracker during migration.

**New layout on the server:**
```
/opt/proxy/           ← shared nginx + certbot (this replaces poker-tracker's nginx)
/opt/poker-tracker/   ← app + db only (nginx removed)
/opt/equityrange/     ← root site static files
```

---

## Step 0 — Copy files to the server

From your local machine (or just `git pull` if you track this repo):

```bash
# From your local machine
scp -r server-infra/proxy         ubuntu@<VPS-IP>:/opt/proxy
scp -r server-infra/poker-tracker ubuntu@<VPS-IP>:/opt/poker-tracker-new
scp -r server-infra/equityrange   ubuntu@<VPS-IP>:/opt/equityrange

ssh ubuntu@<VPS-IP>
```

> From here on, all commands run on the VPS.

---

## Step 1 — Set up the proxy auth directory

The poker tracker uses basic auth. Move the `.htpasswd` file to the shared proxy.

```bash
mkdir -p /opt/proxy/auth

# Copy existing .htpasswd from the old poker-tracker nginx setup
cp /opt/poker-tracker/nginx/auth/.htpasswd /opt/proxy/auth/.htpasswd

# Verify it looks right (should show username:hashed-password)
cat /opt/proxy/auth/.htpasswd
```

---

## Step 2 — Move SSL certs to the proxy

The existing `poker.equityrange.com` cert lives in the poker-tracker stack. Point the proxy at the same location.

```bash
mkdir -p /opt/proxy/certbot

# Symlink or copy the existing certbot directory
# Option A (preferred — symlink so renewals still work):
ln -s /opt/poker-tracker/nginx/certbot/conf /opt/proxy/certbot/conf
ln -s /opt/poker-tracker/nginx/certbot/www  /opt/proxy/certbot/www

# Option B (copy — if symlinks cause issues):
# cp -r /opt/poker-tracker/nginx/certbot/conf /opt/proxy/certbot/conf
# cp -r /opt/poker-tracker/nginx/certbot/www  /opt/proxy/certbot/www
```

---

## Step 3 — Stop the old poker-tracker nginx

Bring down the current stack (this takes port 80/443 offline briefly — ~30 seconds):

```bash
cd /opt/poker-tracker
docker compose -f docker-compose.yml -f docker-compose.prod.yml down
```

> ⚠️  The poker tracker is offline from here until Step 5 completes.

---

## Step 4 — Start the shared proxy

```bash
cd /opt/proxy
chmod +x init-ssl.sh

# Create the proxy-net network (if it doesn't exist yet)
docker network create proxy-net 2>/dev/null || true

# Start nginx + certbot
docker compose up -d

# Verify nginx is running and config is valid
docker compose exec nginx nginx -t
docker compose logs nginx
```

At this point nginx is up but the poker tracker backend is not yet connected — requests to `poker.equityrange.com` will get a 502. That's expected.

---

## Step 5 — Replace the poker-tracker compose file and restart

```bash
# Back up the old compose files
cp /opt/poker-tracker/docker-compose.yml     /opt/poker-tracker/docker-compose.yml.bak
cp /opt/poker-tracker/docker-compose.prod.yml /opt/poker-tracker/docker-compose.prod.yml.bak

# Drop in the new compose (app + db only, no nginx, joins proxy-net)
cp /opt/poker-tracker-new/docker-compose.yml /opt/poker-tracker/docker-compose.yml

# Start the app (single compose file now — no prod overlay needed)
cd /opt/poker-tracker
docker compose up -d

# Watch startup logs
docker compose logs -f app
```

Once the app is healthy, test immediately:
```bash
curl -I https://poker.equityrange.com
# Expect: HTTP/2 200 (or 401 if basic auth prompt is working correctly)
```

> ✅ Poker tracker is back online at this point.

---

## Step 6 — Set up equityrange.com DNS + SSL

1. **Add DNS A record:** Point `equityrange.com` and `www.equityrange.com` to your VPS IP in your DNS registrar (same IP as `poker.equityrange.com`).

2. **Wait for DNS propagation** (usually minutes, up to an hour). Check with:
   ```bash
   dig +short equityrange.com
   # Should return your VPS IP
   ```

3. **Issue the SSL certificate:**
   ```bash
   cd /opt/proxy
   docker run --rm \
     -v /opt/proxy/certbot/conf:/etc/letsencrypt \
     -v /opt/proxy/certbot/www:/var/www/certbot \
     certbot/certbot certonly --webroot \
     -w /var/www/certbot \
     -d equityrange.com \
     -d www.equityrange.com \
     --email your@email.com \
     --agree-tos \
     --no-eff-email
   docker exec proxy-nginx nginx -s reload
   ```

4. **Test:**
   ```bash
   curl -I https://equityrange.com
   # Expect: HTTP/2 200
   ```

---

## Step 7 — Clean up

Once everything is confirmed working:

```bash
# Remove the old prod overlay (no longer needed)
# Keep the .bak files around for a week, then remove
rm /opt/poker-tracker/docker-compose.prod.yml

# Remove old nginx directory from poker-tracker (certs are now under /opt/proxy)
# ONLY do this if you used Option A (symlinks) in Step 2
# If you copied the certs, leave the originals until you're confident in renewals
# rm -rf /opt/poker-tracker/nginx

# Remove staging directory
rm -rf /opt/poker-tracker-new
```

---

## Adding a New Site Later

1. **DNS:** Add A record for `newproject.equityrange.com` → VPS IP
   > ⚠️ If using Cloudflare: set the record to **DNS only (grey cloud)** during cert issuance. You can re-enable proxying after.
2. **Nginx conf:** Copy `_template.conf.example` → `conf.d/newproject.conf`, replace `NEWPROJECT`
3. **SSL:** Run certbot directly:
   ```bash
   docker run --rm \
     -v /opt/proxy/certbot/conf:/etc/letsencrypt \
     -v /opt/proxy/certbot/www:/var/www/certbot \
     certbot/certbot certonly --webroot \
     -w /var/www/certbot \
     -d newproject.equityrange.com \
     --email your@email.com \
     --agree-tos \
     --no-eff-email
   docker exec proxy-nginx nginx -s reload
   ```
4. **Static files** (if static site): copy to `/opt/<newproject>/html/`, add volume mount to proxy compose
5. **App** (if backend): create `/opt/<newproject>/`, write a `docker-compose.yml` that joins `proxy-net`
6. **Start app:** `docker compose up -d` in the app directory
7. **Done**

---

## Ongoing Operations

| Task | Command |
|------|---------|
| Restart proxy | `cd /opt/proxy && docker compose restart nginx` |
| Reload nginx config | `cd /opt/proxy && docker compose exec nginx nginx -s reload` |
| View proxy logs | `cd /opt/proxy && docker compose logs -f nginx` |
| Update poker tracker | `cd /opt/poker-tracker && git pull && docker compose up -d --build` |
| Renew certs (auto) | Handled by certbot container every 12h |
| Force cert renewal | `cd /opt/proxy && docker compose exec certbot certbot renew --force-renewal` |

---

## Rollback

If something goes wrong before Step 5:

```bash
# Restore old docker-compose files
cp /opt/poker-tracker/docker-compose.yml.bak     /opt/poker-tracker/docker-compose.yml
cp /opt/poker-tracker/docker-compose.prod.yml.bak /opt/poker-tracker/docker-compose.prod.yml

# Stop the new proxy
cd /opt/proxy && docker compose down

# Restart the old stack
cd /opt/poker-tracker
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

