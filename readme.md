# Computer Networks Project — Team Akku

This project sets up a small private network with local DNS, an HTTPS reverse proxy, two backend servers, and a basic load-balancing and caching demonstration.

## Overview

The setup uses four Macs on the same private LAN.

| Machine | Role | Private IP | Interface |
|---|---|---|---|
| Mac 1 | DNS server (`dnsmasq`) | `10.3.3.183` | `en0` |
| Mac 2 | Nginx reverse proxy, HTTPS and load balancer | `10.3.3.179` | `en0` |
| Mac 3 | Backend A | `10.3.3.173` | `en0` |
| Mac 4 | Backend B | `10.3.3.169` | `en0` |

The local names `app.team1.test` and `api.team1.test` resolve to the Nginx machine. Nginx forwards incoming requests to either backend over HTTP, while clients connect to Nginx over HTTPS.

## Repository structure

```text
CN_Project-main/
├── backend-a/
│   └── server.py
├── backend-b/
│   └── server.py
├── nginx/
│   └── nginx.conf
├── tls/
│   ├── server.crt
│   └── server.key
└── Evidence/
    └── Project screenshots
```

## 1. Configure private DNS

Install `dnsmasq` on Mac 1 if it is not already installed:

```bash
brew install dnsmasq
```

Add the following project entries to the `dnsmasq.conf` file:

```ini
interface=en0
listen-address=127.0.0.1,10.3.3.183
bind-interfaces

address=/app.team1.test/10.3.3.179
address=/api.team1.test/10.3.3.179
```

Restart `dnsmasq` after saving the configuration. The exact configuration path depends on the Homebrew installation.

Test the DNS records from a client machine:

```bash
dig @10.3.3.183 app.team1.test
dig @10.3.3.183 api.team1.test
```

Both names should resolve to `10.3.3.179`.

For the client to use Mac 1 automatically, configure its DNS resolver to use `10.3.3.183`. Then verify the default resolver:

```bash
dig app.team1.test
```

The `SERVER` line should identify the private DNS server.

## 2. Start Backend A

On Mac 3, open the `backend-a` directory and run:

```bash
python3 server.py
```

Backend A listens on port `3001`.

## 3. Start Backend B

On Mac 4, open the `backend-b` directory and run:

```bash
python3 server.py
```

Backend B listens on port `3002`.

Both servers provide JSON responses. The `X-Backend` response header identifies which backend handled the request.

## 4. Configure Nginx

On Mac 2, configure Nginx to listen on HTTPS port `443` and forward requests to both backends.

The upstream section should use the current backend addresses:

```nginx
upstream team1_backends {
    server 10.3.3.173:3001 max_fails=1 fail_timeout=10s;
    server 10.3.3.169:3002 max_fails=1 fail_timeout=10s;
}
```

The HTTPS server should use the names and certificate files below. Replace the certificate paths with the actual absolute paths on Mac 2.

```nginx
server {
    listen 443 ssl;
    server_name app.team1.test api.team1.test;

    ssl_certificate /absolute/path/to/tls/server.crt;
    ssl_certificate_key /absolute/path/to/tls/server.key;

    location / {
        proxy_pass http://team1_backends;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }
}
```

Keep the `events` and `http` blocks required by the complete Nginx configuration file. Before restarting Nginx, validate the configuration:

```bash
nginx -t
```

If the test succeeds, reload or restart Nginx using the method used for your installation.

**Note:** The `nginx/nginx.conf` currently in the repository must be checked and updated to match this topology. Its checked-in upstream IPs and listening port do not match the current setup.

## 5. TLS certificate

The server certificate must include both DNS names:

- `app.team1.test`
- `api.team1.test`

Because the project uses a self-signed certificate, provide the certificate to `curl` as a trusted CA certificate when testing:

```bash
curl --cacert /absolute/path/to/tls/server.crt \
  https://app.team1.test/api/status
```

This verifies the HTTPS connection without disabling certificate verification.

## 6. API endpoints

### Status endpoint

```text
GET /api/status
```

Returns a JSON status response identifying the backend that handled the request.

Example response:

```json
{
  "backend": "A",
  "status": "ok"
}
```

The backend value can be `A` or `B`.

### Cache endpoint

```text
GET /api/cache
```

Returns a JSON response with caching headers:

```text
Cache-Control: public, max-age=60
ETag: "team1-cache-v1"
```

The `Cache-Control` header specifies a 60-second freshness period. The ETag identifies the resource version.

To test conditional requests, send the matching ETag:

```bash
curl --cacert /absolute/path/to/tls/server.crt \
  -H 'If-None-Match: "team1-cache-v1"' \
  -i https://app.team1.test/api/cache
```

When the resource matches that ETag, the backend implementation returns `304 Not Modified`.

## 7. Testing

Run these checks after starting the relevant services.

**DNS resolution**

```bash
dig app.team1.test
dig api.team1.test
dig @8.8.8.8 app.team1.test
```

The private DNS server should resolve the project names. The public resolver is expected to return `NXDOMAIN` when reachable and when the name is not publicly registered.

**HTTPS and reverse proxy**

```bash
curl --cacert /absolute/path/to/tls/server.crt \
  -i https://app.team1.test/api/status
```

**Load balancing**

```bash
for i in {1..6}; do
  curl -sS --cacert /absolute/path/to/tls/server.crt \
    -i https://app.team1.test/api/status
  echo
done
```

Check the response body and `X-Backend` header to identify the responding backend. The actual sequence depends on the Nginx upstream configuration and backend availability.

**LAN connectivity**

From each machine, ping the other machines using their private IP addresses:

```bash
ping -c 4 10.3.3.179
ping -c 4 10.3.3.173
ping -c 4 10.3.3.169
```

Use the appropriate destination addresses for each source machine and record the actual results.

## 8. Evidence

The `Evidence` directory contains screenshots collected during project testing. Use them alongside the corresponding configuration and command output when documenting DNS resolution, HTTPS responses, backend selection, and caching behavior.

## Security notes

- Do not expose the backend ports directly to untrusted networks.
- Keep the TLS private key (`server.key`) out of a public repository. If it has already been committed, remove it from version control and replace the key as appropriate.
- A self-signed certificate is suitable for a controlled demonstration, but clients must explicitly trust it.
- Report test results from actual command output rather than assumed results.
