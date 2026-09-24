# initialize-certs: Let's Encrypt Certificate Bootstrap

**ONLY USE ON THE HOST**

This folder contains configuration for bootstrapping Let's Encrypt SSL certificates using a minimal nginx container and ACME HTTP-01 challenge.

See also: [../docs/Troubleshooting/SERVER.InstallFirstRunTroubles.md](../docs/Troubleshooting/SERVER.InstallFirstRunTroubles.md) for first-run diagnostics, common failure signatures, and copy-paste recovery commands.

## Usage

1. **Start Minimal Nginx for ACME Challenge**

   ```sh
   task certs:acme-nginx-up
   ```

   This starts the temporary nginx on port 80 using `initialize-certs/nginx/letsencrypt_acme.conf`.

2. **Verify Nginx is Running**

   ```sh
   curl http://kforkode.dk/
   # Expected: "ACME bootstrap nginx is running"
   ```

3. **Run Staging Dry-Run First (Recommended)**

   ```sh
   task certs:certbot-dry-run:all
   ```

   Or run a single site:

   ```sh
   task certs:certbot-dry-run:kfk
   task certs:certbot-dry-run:hvt
   task certs:certbot-dry-run:cvp
   ```

4. **Obtain Certificates**

   ```sh
   task certs:certbot:all
   ```

   Or run a single site:

   ```sh
   task certs:certbot:kfk
   task certs:certbot:hvt
   task certs:certbot:cvp
   ```

   Certificates are written to `/etc/letsencrypt`.

5. **Stop ACME Nginx**

   ```sh
   task certs:acme-nginx-down
   ```

6. **Switch to Main App Stack**
   Start your main stack with your regular compose file. Nginx will now use the issued certs.

## Configured Domains

Certificates are currently hardcoded per site in `Taskfile.Certs.yml`:

- `kforkode.dk`, `www.kforkode.dk`, `squidex.kforkode.dk`
- `habibi-vip-taxi.com`, `www.habibi-vip-taxi.com`
- `carstens-vinduespolering.dk`, `www.carstens-vinduespolering.dk`

## Available Tasks

| Task                             | Description                                          |
| -------------------------------- | ---------------------------------------------------- |
| `task certs:acme-nginx-up`       | Start ACME nginx (port 80)                           |
| `task certs:acme-nginx-test`     | Test ACME challenge path for `kforkode.dk`           |
| `task certs:acme-nginx-down`     | Stop ACME nginx                                      |
| `task certs:certbot-dry-run:kfk` | Dry run for `kforkode.dk` (+ www + squidex)          |
| `task certs:certbot-dry-run:hvt` | Dry run for `habibi-vip-taxi.com` (+ www)            |
| `task certs:certbot-dry-run:cvp` | Dry run for `carstens-vinduespolering.dk` (+ www)    |
| `task certs:certbot-dry-run:all` | Dry run for all configured sites                     |
| `task certs:certbot:kfk`         | Issue cert for `kforkode.dk` (+ www + squidex)       |
| `task certs:certbot:hvt`         | Issue cert for `habibi-vip-taxi.com` (+ www)         |
| `task certs:certbot:cvp`         | Issue cert for `carstens-vinduespolering.dk` (+ www) |
| `task certs:certbot:all`         | Issue certs for all configured sites                 |

## Files

- `nginx/letsencrypt_acme.conf` — Nginx config used by the ACME bootstrap container
- `nginx/docker-compose.letsencrypt.yml` — Minimal compose file for ACME

## Tips

- `certbot` tasks use `sudo`, so you may be prompted for your account password.
- Run `sudo -v` once before `task certs:certbot:all` to avoid repeated prompts.
- For renewals, use `certbot renew` (or your host's `certbot.timer` setup).

## Troubleshooting

### Testing ACME Challenge Locally

After starting ACME nginx, test the challenge path:

```sh
task certs:acme-nginx-test
```

Or test manually with the correct `Host` header:

```sh
curl -i -H "Host: kforkode.dk" http://127.0.0.1/.well-known/acme-challenge/test.txt
```

You can also test through the public domain (if DNS is already pointing at this server):

```sh
curl -i http://kforkode.dk/.well-known/acme-challenge/test.txt
```

#### Issue: `curl http://127.0.0.1/.well-known/acme-challenge/test.txt` returns 404

**Root cause:** Nginx receives `Host: 127.0.0.1` but your config specifies your actual domain in `server_name`. Nginx only routes to configs whose `server_name` matches the HTTP `Host` header.

**Solution 1: Test with the correct Host header**

```sh
curl -i -H "Host: kforkode.dk" http://127.0.0.1/.well-known/acme-challenge/test.txt
```

**Solution 2: Test via the actual domain (if DNS already points to this server)**

```sh
curl -i http://kforkode.dk/.well-known/acme-challenge/test.txt
```

Expected result: **HTTP 200** with file contents.

#### Pre-flight checklist

Before running certbot, verify:

```sh
# 1. Container is running
docker ps | grep nginx

# 2. Config file is loaded correctly
docker exec <container-name> cat /etc/nginx/conf.d/letsencrypt_acme.conf

# 3. Challenge directory exists with correct structure
sudo ls -la /var/www/letsencrypt_challenges/.well-known/acme-challenge/

# 4. Test with correct Host header
curl -i -H "Host: kforkode.dk" http://127.0.0.1/.well-known/acme-challenge/test.txt
```

### Issue: Let's Encrypt returns 521 or "Invalid response" from ACME challenge

**Symptom:** Certbot reports:

```
Invalid response from https://your.domain.com/.well-known/acme-challenge/{token}: 521
```

**Root cause:** Your domain is proxied through Cloudflare (or another reverse proxy/CDN). Cloudflare blocks the ACME challenge requests.

**Solution:**

1. Log into Cloudflare DNS settings
2. Find the DNS record for your domain
3. Toggle the record from **Proxied** (orange cloud) to **DNS only** (grey cloud)
4. Wait 1–2 minutes for DNS propagation
5. Re-run certbot:

   ```sh
   task certs:certbot:all
   ```

6. Once the certificate is successfully issued, toggle the DNS record back to **Proxied**

**Why this works:** With "DNS only", Let's Encrypt fetches the challenge token directly from your server, bypassing Cloudflare. After you have the certificate, Cloudflare can resume proxying traffic normally.

For broader first-run troubleshooting (Compose V1/V2 mismatch, bind-mount path mistakes, restart loops), see [../docs/Troubleshooting/SERVER.InstallFirstRunTroubles.md](../docs/Troubleshooting/SERVER.InstallFirstRunTroubles.md).

---

**This process is only needed for the initial certificate issuance.**
