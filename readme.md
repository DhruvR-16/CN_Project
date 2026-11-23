# Computer Networks Project — Team Akku

This project sets up a small private network with local DNS, an HTTPS reverse proxy, two backend servers, and a basic load-balancing and caching demonstration.

## Overview

The setup uses four Macs on the same private LAN.

| Machine | Role | Private IP | Interface |
|---|---|---|---|
| Mac 1 (Akhilesh Kumar) | DNS server (`dnsmasq`) | `10.7.13.217` | `en0` |
| Mac 2 (Kavya Jain) | Nginx reverse proxy, HTTPS and load balancer | `10.7.26.222` | `en0` |
| Mac 3 (Dhruv Ramani) | Backend A | `10.7.30.216` | `en0` |
| Mac 4 (Lakshya Agrawal) | Backend B | `10.7.15.193` | `en0` |

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
listen-address=127.0.0.1,10.7.13.217
bind-interfaces

address=/app.team1.test/10.7.26.222
address=/api.team1.test/10.7.26.222
```

Restart `dnsmasq` after saving the configuration. The exact configuration path depends on the Homebrew installation.

Test the DNS records from a client machine:

```bash
dig @10.7.13.217 app.team1.test
dig @10.7.13.217 api.team1.test
```

Both names should resolve to `10.7.26.222`.

These direct queries leave each Mac's Wi-Fi DNS setting unchanged. A plain `dig app.team1.test` tests the Mac's existing resolver configuration, which may not use the project DNS server.

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

On Mac 2, configure Nginx to listen on HTTPS port `8443` and forward requests to both backends.

The upstream section should use the current backend addresses:

```nginx
upstream team1_backends {
    server 10.7.30.216:3001 max_fails=1 fail_timeout=10s;
    server 10.7.15.193:3002 max_fails=1 fail_timeout=10s;
}
```

The HTTPS server should use the names and certificate files below. Replace the certificate paths with the actual absolute paths on Mac 2.

```nginx
server {
    listen 8443 ssl;
    server_name app.team1.test api.team1.test;

    ssl_certificate /absolute/path/to/tls/server.crt;
    ssl_certificate_key /absolute/path/to/tls/server.key;

    location / {
        proxy_pass http://team1_backends;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
    }
}
```

Keep the `events` and `http` blocks required by the complete Nginx configuration file. Before restarting Nginx, validate the configuration:

```bash
nginx -t -c "$PWD/nginx/nginx.conf"
```

If the test succeeds, reload or restart Nginx using the method used for your installation.

**Note:** The `nginx/nginx.conf` currently in the repository must be checked and updated to match this topology. Its checked-in upstream IPs and listening port do not match the current setup.

## 5. TLS certificate

The server certificate must include both DNS names:

- `app.team1.test`
- `api.team1.test`

Because the project uses a self-signed certificate, provide the certificate to `curl` as a trusted CA certificate when testing:

```bash
curl --resolve app.team1.test:8443:10.7.26.222 --cacert /absolute/path/to/tls/server.crt \
  https://app.team1.test:8443/api/status
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
curl --resolve app.team1.test:8443:10.7.26.222 --cacert /absolute/path/to/tls/server.crt \
  -H 'If-None-Match: "team1-cache-v1"' \
  -i https://app.team1.test:8443/api/cache
```

When the resource matches that ETag, the backend implementation returns `304 Not Modified`.

## 7. Testing

Run the ordered evaluation runbook below. The runbook uses direct DNS queries and `curl --resolve` so it does not change a Mac's Wi-Fi DNS settings. Scripts save their output under `Evidence/logs/`.

**DNS resolution**

```bash
source scripts/team.env
dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
dig "@$DNS_PRIMARY_IP" "$API_HOST" A +noall +answer
dig @8.8.8.8 "$APP_HOST" A
```

The private DNS server should resolve the project names. The public resolver is expected to return `NXDOMAIN` when reachable and when the name is not publicly registered.

**HTTPS and reverse proxy**

```bash
source scripts/team.env
curl --cacert "$PWD/tls/server.crt" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_PRIMARY_IP" \
  -i "https://$APP_HOST:$EDGE_PORT/api/status"
```

**Load balancing**

```bash
scripts/client-checks.sh baseline
```

Check the response body and `X-Backend` header to identify the responding backend. The actual sequence depends on the Nginx upstream configuration and backend availability.

**LAN connectivity**

From each machine, ping the other machines using their private IP addresses:

```bash
ping -c 4 10.7.26.222
ping -c 4 10.7.30.216
ping -c 4 10.7.15.193
```

Use the appropriate destination addresses for each source machine and record the actual results.

## 8. Evidence

The `Evidence` directory contains screenshots collected during project testing. Use them alongside the corresponding configuration and command output when documenting DNS resolution, HTTPS responses, backend selection, and caching behavior.

## 9. One-pass evaluation runbook

Run in order. Current IPs reported on 2026-11-23: Akhilesh/DNS `10.7.13.217`, Kavya/edge `10.7.26.222`, Dhruv/Backend A and backup DNS `10.7.30.216`, Lakshya/Backend B and standby-edge candidate `10.7.15.193`. Confirm these before testing because DHCP can change.

**No Wi-Fi DNS changes:** these steps do not set or replace any Mac's DNS servers. Do not run `networksetup -setdnsservers`. `networksetup -getdnsservers` only reads the current setting. Akhilesh, Dhruv, and Lakshya reported no DNS servers listed for Wi-Fi; Kavya reported public resolvers `8.8.8.8` and `8.8.4.4`. These settings stay unchanged. Project DNS checks use `dig @DNS_IP`; HTTPS uses `curl --resolve`, preserving the hostname and certificate check. This does not prove automatic macOS resolver failover or client DNS-cache behavior.

### Step 0: all Macs, prepare and confirm IPs

```bash
cd /path/to/CN_Project
cp scripts/team.env.example scripts/team.env
chmod +x scripts/*.sh
echo "Computer: $(scutil --get ComputerName)"
ipconfig getifaddr en0
networksetup -getdnsservers "Wi-Fi"
MY_IP="$(ipconfig getifaddr en0)"
for PEER_IP in 10.7.13.217 10.7.26.222 10.7.30.216 10.7.15.193; do
  if [ "$PEER_IP" != "$MY_IP" ]; then ping -c 3 "$PEER_IP"; fi
done
```

If an address changed, update `scripts/team.env.example`, `nginx/nginx.conf`, and both dnsmasq records, then copy the updated example to each local `scripts/team.env`. Stop if any IP is stale.

### Step 1: Akhilesh, primary DNS

Back up and edit the active Homebrew dnsmasq file. Keep unrelated settings; replace old project records so these occur once:

```bash
DNS_CONF="$(brew --prefix)/etc/dnsmasq.conf"
sudo cp "$DNS_CONF" "$DNS_CONF.team1-backup"
sudo nano "$DNS_CONF"
```

```ini
interface=en0
listen-address=127.0.0.1,10.7.13.217
bind-interfaces
local-ttl=30
address=/app.team1.test/10.7.26.222
address=/api.team1.test/10.7.26.222
```

```bash
sudo brew services restart dnsmasq
sudo lsof -nP -iUDP:53 -iTCP:53
dig @10.7.13.217 app.team1.test A +noall +answer
dig @10.7.13.217 api.team1.test A +noall +answer
scripts/dns-primary.sh
```

Both DNS answers should be `10.7.26.222`.

### Step 2: Dhruv, backup DNS and Backend A

Check port 53 first. Start the backup only if that port is free; keep this Terminal open:

```bash
cd /path/to/CN_Project
sudo lsof -nP -iUDP:53 -iTCP:53
cat > "$HOME/team1-dnsmasq-backup.conf" <<EOF
port=53
interface=en0
listen-address=127.0.0.1,10.7.30.216
bind-interfaces
local-ttl=30
address=/app.team1.test/10.7.26.222
address=/api.team1.test/10.7.26.222
EOF
sudo dnsmasq --no-daemon --log-queries --conf-file="$HOME/team1-dnsmasq-backup.conf"
```

In a second Terminal on Dhruv's Mac:

```bash
cd /path/to/CN_Project
dig @10.7.30.216 app.team1.test A +noall +answer
dig @10.7.30.216 api.team1.test A +noall +answer
scripts/backend-a.sh start
```

### Step 3: Lakshya, Backend B

```bash
cd /path/to/CN_Project
scripts/backend-b.sh start
```

Leave the backend terminals open.

### Step 4: Kavya, Nginx edge

Confirm the config has upstreams `10.7.30.216:3001` and `10.7.15.193:3002`; confirm the certificate paths exist on Kavya's Mac. Test and check whether Nginx is already running:

```bash
cd /path/to/CN_Project
nginx -t -c "$PWD/nginx/nginx.conf"
lsof -nP -iTCP:8443 -sTCP:LISTEN
```

If already running, reload; otherwise, start. Run only one:

```bash
nginx -s reload -c "$PWD/nginx/nginx.conf"
```

```bash
nginx -c "$PWD/nginx/nginx.conf"
```

Then:

```bash
lsof -nP -iTCP:8443 -sTCP:LISTEN
scripts/edge-nginx.sh
```

### Step 5: client, Phase 1 baseline and packet capture

```bash
cd /path/to/CN_Project
scripts/client-checks.sh baseline
```

Pass criteria: DNS answers point to the edge; HTTPS returns `200 OK` with trusted certificate; repeated requests show both `X-Backend: A` and `X-Backend: B`; cache headers include `Cache-Control` and `ETag`; conditional request returns `304 Not Modified`. Scripts save logs to `Evidence/logs/`. Stop and fix a required failing layer before moving on.

Capture Wireshark on Wi-Fi (`en0`) while running the baseline and save the `.pcapng` under `Evidence/`. Display filters: `dns`, `tcp.port == 8443`, `tls.handshake`. Show DNS query/answer, TCP SYN/SYN-ACK/ACK, TLS handshake, encrypted data.

### Step 6: Phase 1 five fault demos

Restore each fault before the next test. Expected failures during injected faults are evidence.

1. Wrong DNS server: `dig @8.8.8.8 app.team1.test A`, then `dig @10.7.13.217 app.team1.test A +noall +answer`; run `scripts/client-checks.sh wrong-dns`. This does not change Wi-Fi DNS.
2. Wrong DNS target: on Akhilesh's Mac, temporarily change only the app dnsmasq record to `192.0.2.1`, restart dnsmasq, run `scripts/client-checks.sh wrong-dns-target`, then restore app record `10.7.26.222` and restart DNS. Verify using `dig @10.7.13.217 app.team1.test A +noall +answer`.
3. Backend A stopped: Ctrl-C Dhruv's Backend A terminal; run `scripts/client-checks.sh backend-a-down`; restart with `scripts/backend-a.sh start`.
4. Both backends stopped: Ctrl-C both backend terminals; run `scripts/client-checks.sh all-backends-down`; restart with `scripts/backend-a.sh start` and `scripts/backend-b.sh start`.
5. Wrong port: run `scripts/client-checks.sh wrong-port`.

### Step 7: Phase 2 A, backup DNS

With both DNS services running, query each. Stop primary dnsmasq on Akhilesh, query backup directly again, then restore primary immediately:

```bash
dig @10.7.13.217 app.team1.test A +noall +answer
dig @10.7.30.216 app.team1.test A +noall +answer
sudo brew services stop dnsmasq
dig @10.7.30.216 app.team1.test A +noall +answer
sudo brew services start dnsmasq
```

This proves the backup resolver answers while primary is down. It does not prove automatic client failover; the assignment requires clients listing both private DNS servers. This runbook intentionally leaves Wi-Fi DNS unchanged, so report that limitation honestly.

### Step 8: Phase 2 B, TTL and record change

Both dnsmasq configs use `local-ttl=30`. Record the current answer. On Akhilesh's Mac, edit the primary config and set only the app record to `10.7.15.193`; restart primary. On Dhruv's Mac, edit the backup config to the same app record, stop the foreground backup with Ctrl-C in its running Terminal, then restart it:

```bash
sudo nano "$(brew --prefix)/etc/dnsmasq.conf"
sudo brew services restart dnsmasq
```

```bash
nano "$HOME/team1-dnsmasq-backup.conf"
sudo dnsmasq --no-daemon --log-queries --conf-file="$HOME/team1-dnsmasq-backup.conf"
```

Then query both:

```bash
dig @10.7.13.217 app.team1.test A +noall +answer
dig @10.7.30.216 app.team1.test A +noall +answer
```

Wait 35 seconds and capture the answer again. Restore both records to `10.7.26.222` by editing the same two files, then restart both DNS services using the commands above. Direct `dig @DNS_IP` bypasses client cache, so it cannot prove stale cached answers. Only on a client already using team DNS, inspect/flush the cache:

```bash
dscacheutil -q host -a name app.team1.test
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
dscacheutil -q host -a name app.team1.test
```

### Step 9: Phase 2 C, backend firewall isolation

The repo has no approved PF rules template. Obtain the exact faculty/admin-approved allow-edge/block-client rules and rollback commands before changing firewalls; do not replace macOS PF rules with an improvised ruleset. After the approved rules are applied on both backends, test from Kavya's edge:

```bash
source scripts/team.env
curl --connect-timeout 4 --max-time 8 -i "http://$BACKEND_A_IP:$BACKEND_A_PORT/api/status"
curl --connect-timeout 4 --max-time 8 -i "http://$BACKEND_B_IP:$BACKEND_B_PORT/api/status"
```

From another client, direct backend connections should fail:

```bash
source scripts/team.env
nc -vz -G 3 "$BACKEND_A_IP" "$BACKEND_A_PORT"
nc -vz -G 3 "$BACKEND_B_IP" "$BACKEND_B_PORT"
```

Run the approved rollback and repeat the edge checks. Do not report C complete until isolation and rollback both pass.

### Step 10: Phase 2 D, backend failover

Stop Backend A with Ctrl-C, run `scripts/client-checks.sh backend-a-down`, and confirm all successful responses show B. Restart A with `scripts/backend-a.sh start`, then run `scripts/client-checks.sh baseline` and confirm both IDs return. Explain Nginx is still a single point of failure.

### Step 11: Phase 2 E, standby edge/cutover

On Lakshya's Mac, make a standby config with local cert paths, validate, and start Nginx on port 8443 (Backend B uses 3002):

```bash
cd /path/to/CN_Project
sed -e "s#/Users/kavyajain/CN-Project-Team1/tls/server.crt#$PWD/tls/server.crt#" \
    -e "s#/Users/kavyajain/CN-Project-Team1/tls/server.key#$PWD/tls/server.key#" \
    nginx/nginx.conf > "$HOME/team1-standby-nginx.conf"
nginx -t -c "$HOME/team1-standby-nginx.conf"
nginx -c "$HOME/team1-standby-nginx.conf"
lsof -nP -iTCP:8443 -sTCP:LISTEN
```

From a client, verify standby TLS with the hostname retained:

```bash
source scripts/team.env
curl --cacert "$PWD/tls/server.crt" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_STANDBY_IP" \
  -i "https://$APP_HOST:$EDGE_PORT/api/status"
```

Only continue after `200 OK`. Change the app record on both DNS servers to `10.7.15.193` using the edit/restart commands in Step 8, then run `scripts/client-checks.sh edge-cutover` and check direct answers with `dig @10.7.13.217 app.team1.test A +noall +answer` and `dig @10.7.30.216 app.team1.test A +noall +answer`. Restore both records to `10.7.26.222` using Step 8. Client cached cutover is only proven if that client uses team DNS.

### Step 12: Phase 2 F and final presentation

The instructor injects this fault during evaluation. Diagnose in order, without changing Wi-Fi DNS:

```bash
source scripts/team.env
dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
nc -vz -G 3 "$EDGE_PRIMARY_IP" "$EDGE_PORT"
curl --cacert "$PWD/tls/server.crt" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_PRIMARY_IP" -v \
  "https://$APP_HOST:$EDGE_PORT/api/status"
curl --connect-timeout 4 --max-time 8 "http://$BACKEND_A_IP:$BACKEND_A_PORT/api/status"
curl --connect-timeout 4 --max-time 8 "http://$BACKEND_B_IP:$BACKEND_B_PORT/api/status"
```

The final demo has 11 presentation steps, not 11 separate Phase 2 tests: (1) topology/roles, (2) IPs and LAN, (3) DNS, (4) trusted HTTPS, (5) load balancing, (6) Wireshark DNS/TCP/TLS, (7) cache/304, (8) Backend A outage, (9) Phase 2 DNS/TTL/edge resilience, (10) instructor fault diagnosis, and (11) individual viva. Extensions A-E require actual evidence; F is the live instructor challenge.

After testing, restore both DNS A records to `10.7.26.222`, restart primary and backup DNS, run the approved PF rollback, and leave both backends and primary Nginx running. These steps do not change client Wi-Fi DNS settings.

## Security notes

- Do not expose the backend ports directly to untrusted networks.
- Keep the TLS private key (`server.key`) out of a public repository. If it has already been committed, remove it from version control and replace the key as appropriate.
- A self-signed certificate is suitable for a controlled demonstration, but clients must explicitly trust it.
- Report test results from actual command output rather than assumed results.
