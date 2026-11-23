# Team Akku command kit and run order

These scripts run checks and save a timestamped terminal transcript under `Evidence/logs/`. They do not silently change DNS, firewall, or network settings. Those changes need the team to verify the target Mac and retain a rollback path.

## First setup (all four Macs)

1. Make sure the project folder is present on each Mac. In `scripts/`, copy `team.env.example` to `team.env`.
2. Check each current Mac address with `ipconfig getifaddr en0` (or the interface used by your Wi-Fi) and update `scripts/team.env` on all Macs. Match the addresses to the actual role machines. Update the edge port to the port in the active Nginx config (the checked-in config currently says 8443).
3. Confirm that the TLS certificate at `tls/server.crt` is trusted by the client and has `app.team1.test` and `api.team1.test` in its Subject Alternative Names. Set `TLS_CA_FILE` in `team.env` if the trusted certificate is elsewhere.
4. Make the scripts executable: `chmod +x scripts/*.sh`.
5. Do not put passwords, private keys, or machine-specific secrets in `team.env`. Send the same non-secret address config to each member.

Each role script prints command lines, output, and each command's exit status in Terminal while writing the transcript once to the log. A non-zero command count is not automatically a failed project check: some fault-demo commands are expected to fail. Read the scenario heading and explain the observed result.

Current role IPs reported on 2026-11-23: Akhilesh/DNS `10.7.13.217`, Kavya/edge `10.7.26.222`, Dhruv/Backend A and backup DNS `10.7.30.216`, and Lakshya/Backend B and standby-edge candidate `10.7.15.193`. DHCP addresses can change, so recheck before a later session. The client Wi-Fi DNS settings are not changed by these scripts. For read-only DNS checks, use `dig @DNS_PRIMARY_IP ...`; do not run `networksetup -setdnsservers` unless the team deliberately chooses to change that Mac's resolver configuration.

## Suggested responsibility and execution order

Run in this order so prerequisites are ready before the combined checks.

### 0. All four Macs: collect and agree on network details first

Run these commands on **each Mac** before editing `team.env`. First identify which hardware interface and network service are actually in use:

```bash
networksetup -listallhardwareports
networksetup -listallnetworkservices
```

Use the interface mapped to Wi-Fi (often `en0`) and the exact service name (often `Wi-Fi`). Substitute the values you found below:

```bash
IFACE="en0"
SERVICE="Wi-Fi"
echo "Computer: $(scutil --get ComputerName)"
sw_vers
networksetup -getinfo "$SERVICE"
ipconfig getifaddr "$IFACE"
ifconfig "$IFACE" | grep -E 'inet |ether '
route -n get default | grep gateway
networksetup -getdnsservers "$SERVICE"
```

Record each Mac's hostname, active interface, current IPv4 address, subnet mask, default gateway, MAC address, and current DNS servers in one shared table. `networksetup -getinfo` gives the service's IP, subnet mask, router, and Ethernet address; `ifconfig` gives the interface details. If the IPs are DHCP-assigned and change often, reserve them in the router if you can. Decide now which non-primary-DNS Mac will host backup DNS and which non-primary-edge Mac will host standby Nginx. They may be the same Mac for the demo if its ports and services do not conflict.

After sharing the IP table, test reachability. Each Mac should ping the other three Macs using their recorded addresses (do not use the example addresses in `team.env.example` unless they match today's inventory):

```bash
ping -c 4 PEER_IP
```

From the DNS Mac, verify the current project records and from a client verify its system resolver:

```bash
dig @DNS_PRIMARY_IP app.team1.test A +noall +answer
dig @DNS_PRIMARY_IP api.team1.test A +noall +answer
dig app.team1.test A +noall +answer
```

Replace `DNS_PRIMARY_IP` in those examples with the literal address. Both project records should point to the active edge. On the assigned machines, confirm required programs exist before the team session:

```bash
command -v dnsmasq  # DNS host and backup-DNS host
command -v python3  # both backend hosts
command -v nginx    # primary and standby edge hosts
command -v dig
command -v curl
command -v nc
```

Once agreed, update the same non-secret values in `scripts/team.env` on every Mac: `DNS_PRIMARY_IP`, `DNS_BACKUP_IP`, `EDGE_PRIMARY_IP`, `EDGE_STANDBY_IP`, `BACKEND_A_IP`, `BACKEND_B_IP`, `NETWORK_INTERFACE`, `NETWORK_SERVICE`, and `EDGE_PORT`. The checked-in config uses port 8443, but use the port the active Nginx service actually listens on. Verify the active Nginx upstream IPs and certificate paths match the table before proceeding.

### 1. Everyone: LAN inventory (Phase 1 Task A)

Each member runs their role script once; the scripts include `sw_vers` and `ifconfig`. Record all four current IPv4 addresses, prefix/subnet, gateway, interface, and MAC address in the architecture document. Ping every other Mac from each machine and record the actual results. Do not infer that all pairs work from one successful ping.

### 2. Akhilesh: primary DNS (Phase 1 Task B)

Run `scripts/dns-primary.sh`. Check the primary dnsmasq service and both records. The answers for `app.team1.test` and `api.team1.test` must be the current edge address. Configure at least two clients to use the team DNS server and verify with `dig` from those clients.

### 3. Dhruv and Lakshya: backends (Phase 1 Task C)

On the corresponding Macs run `scripts/backend-a.sh start` and `scripts/backend-b.sh start` in separate Terminal windows. Keep both running. Each listens on its LAN interface and should return its own `X-Backend` identity on ports 3001 and 3002.

### 4. Kavya: edge proxy, TLS, and load balancing (Phase 1 Tasks D/E)

Update the active `nginx/nginx.conf` with the verified backend addresses, current certificate paths, and chosen edge port. The checked-in config uses 8443, which is allowed by the assignment. Run `scripts/edge-nginx.sh` on the edge Mac. On success, reload Nginx using the method used by that installation. Confirm the client URL uses the DNS hostname and certificate validation succeeds; do not use `curl -k`.

### 5. Everyone: Phase 1 client validation (Tasks F/G)

From at least two configured client Macs, run `scripts/client-checks.sh baseline`. Confirm both backend IDs appear across repeated requests, `/api/cache` returns `Cache-Control` and `ETag`, and the conditional request returns 304. Capture a Wireshark trace of a new request showing DNS, TCP handshake, TLS handshake, and encrypted application data. Save screenshots or the `.pcapng` with a short note naming the commands and time. Also rehearse the five Phase 1 failure cases listed in the project PDF (wrong resolver, wrong DNS target, one/both backends stopped, wrong port) and save actual observations.

Do not start Phase 2 demonstrations until the team can show the Phase 1 gate: client name lookup, HTTPS with certificate validation, and responses from both backends through the edge.

For the Phase 1 failure demonstrations, use the matching client scenarios where available: `scripts/client-checks.sh wrong-dns`, `scripts/client-checks.sh wrong-dns-target`, `scripts/client-checks.sh backend-a-down`, `scripts/client-checks.sh all-backends-down`, and `scripts/client-checks.sh wrong-port`. The DNS-target case requires Akhilesh to temporarily point the record at a wrong test IP first; restore the correct record immediately afterward. For backend outage cases, stop the service with Ctrl-C in its owning terminal, capture the client result, and restart it.

### 6. Akhilesh + second host: backup DNS (Phase 2 Extension A)

Choose a backup host other than the primary DNS Mac. Make sure port 53 is free on it before starting the demo resolver. The following runs dnsmasq in the foreground with a separate project config, so Ctrl-C stops only this demo process. On the backup host:

```bash
cd /path/to/CN_Project
source scripts/team.env
command -v dnsmasq
sudo lsof -nP -iUDP:53 -iTCP:53
cat > "$HOME/team1-dnsmasq-backup.conf" <<EOF
port=53
interface=$NETWORK_INTERFACE
listen-address=127.0.0.1,$DNS_BACKUP_IP
bind-interfaces
local-ttl=$DNS_TTL
address=/$APP_HOST/$EDGE_PRIMARY_IP
address=/$API_HOST/$EDGE_PRIMARY_IP
EOF
sudo dnsmasq --no-daemon --conf-file="$HOME/team1-dnsmasq-backup.conf"
```

Leave that terminal running. In another terminal, test and save evidence:

```bash
dig "@$DNS_BACKUP_IP" "$APP_HOST" A +noall +answer
dig "@$DNS_BACKUP_IP" "$API_HOST" A +noall +answer
```

**This next command changes the Mac's Wi-Fi DNS settings. Do not run it for the current read-only test session.** It is included only because the assignment's full backup-resolver demonstration requires clients to list both DNS servers. The scripts themselves never run this command. If the team later explicitly decides to perform that configuration step, use the exact service name from `networksetup -listallnetworkservices`:

```bash
cd /path/to/CN_Project
source scripts/team.env
sudo networksetup -setdnsservers "$NETWORK_SERVICE" "$DNS_PRIMARY_IP" "$DNS_BACKUP_IP"
networksetup -getdnsservers "$NETWORK_SERVICE"
```

Stop the primary dnsmasq service using the method Akhilesh normally uses. From each client run:

```bash
scripts/client-checks.sh dns-failover
```

Capture the lookup and resolver details. Also run `dig "@$DNS_BACKUP_IP" "$APP_HOST" A` to prove the backup responds directly. macOS resolver selection may not strictly follow the listed order, so record the actual resolver. Restart primary DNS, stop the foreground backup with Ctrl-C, and restore clients to the intended DNS settings after the demo.

### 7. Akhilesh + client owners: TTL and record change (Extension B)

Do this on both DNS resolvers. For an existing Homebrew dnsmasq service, inspect the active config path first; the common path below is not guaranteed if the service was installed/configured differently:

```bash
brew --prefix
DNS_CONF="$(brew --prefix)/etc/dnsmasq.conf"
grep -nE '^(address|local-ttl|interface|listen-address|bind-interfaces)' "$DNS_CONF"
nano "$DNS_CONF"
```

Set `local-ttl=30` and verify both project `address=` lines are present. Restart dnsmasq using the same service manager used to start it (for a Homebrew service, usually `brew services restart dnsmasq`). On a client, with `team.env` loaded:

```bash
cd /path/to/CN_Project
source scripts/team.env
dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
dscacheutil -q host -a name "$APP_HOST"
```

Save the initial answer. Now change the app record on **both** resolvers to `$EDGE_STANDBY_IP`, restart both resolvers, and immediately compare the direct resolver answer and the system-resolver answer:

```bash
dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
dscacheutil -q host -a name "$APP_HOST"
```

The direct `dig @resolver` query asks that resolver and does not prove the Mac's local DNS cache retained an old answer. Record both outputs and wait longer than the configured TTL, then query the system resolver again. To show manual cache flush:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
dscacheutil -q host -a name "$APP_HOST"
```

Restore the app record to `$EDGE_PRIMARY_IP` on both resolvers, restart them, verify with `dig`, and flush client caches after the demo. Capture actual TTL values and observed answers; do not report a cache effect unless you observed it.

### 8. Dhruv + Lakshya + Kavya: backend isolation (Extension C)

This step changes the host firewall. Use the faculty-provided macOS PF rule template or get the exact rules and rollback procedure reviewed by the administrator. Don't load a project-only ruleset over the Mac's system PF rules. Before applying, each backend owner saves current state:

```bash
sudo pfctl -s info
sudo pfctl -sr > "$HOME/pf-rules-before-team1.txt"
sudo pfctl -sa > "$HOME/pf-state-before-team1.txt"
```

Apply the approved template on each backend so inbound TCP to its backend port is allowed from `EDGE_PRIMARY_IP` and blocked from other client IPs. Use the template's exact load and rollback commands. Verify from Kavya's edge Mac:

```bash
cd /path/to/CN_Project
source scripts/team.env
curl --connect-timeout 4 --max-time 8 -i "http://$BACKEND_A_IP:$BACKEND_A_PORT/api/status"
curl --connect-timeout 4 --max-time 8 -i "http://$BACKEND_B_IP:$BACKEND_B_PORT/api/status"
```

Then, from a separate client Mac, verify direct connections are blocked:

```bash
nc -vz -G 3 "$BACKEND_A_IP" "$BACKEND_A_PORT"
nc -vz -G 3 "$BACKEND_B_IP" "$BACKEND_B_PORT"
```

Capture both sides, apply the template's rollback immediately after the demo, and re-run the edge checks. Record the rollback result.

### 9. Kavya + Dhruv/Lakshya: backend failover (Extension D)

In the active Nginx `upstream` block, set passive failure handling for both servers. The addresses/ports below must match `team.env`:

```nginx
upstream team1_backends {
    server BACKEND_A_IP:3001 max_fails=1 fail_timeout=10s;
    server BACKEND_B_IP:3002 max_fails=1 fail_timeout=10s;
}
```

Replace the two placeholders with literal IPs; Nginx does not expand `team.env`. Inside `location /`, make sure the proxy retry directives are present:

```nginx
proxy_pass http://team1_backends;
proxy_next_upstream error timeout http_502 http_503 http_504;
proxy_next_upstream_tries 2;
```

Validate the actual config path, then reload Nginx using the same service method used to start it:

```bash
nginx -t -c /absolute/path/to/nginx.conf
nginx -s reload -c /absolute/path/to/nginx.conf
```

If Nginx is managed by Homebrew, make sure it is loading this config before using `brew services restart nginx`. Stop Backend A with Ctrl-C on Dhruv's terminal. From a client run:

```bash
scripts/client-checks.sh backend-a-down
```

Successful responses should identify Backend B. Restart Backend A and run `scripts/client-checks.sh baseline`; confirm both backend IDs return. These are passive checks: Nginx learns a backend failed from request errors, and the edge Mac remains a single point of failure.

### 10. Kavya + standby host + Akhilesh: edge migration (Extension E)

On the chosen standby Mac, copy the Nginx config and TLS certificate/key through your team's approved private method. Update the backend IPs and the standby's local certificate paths. Run `nginx -t -c /absolute/path/to/standby-nginx.conf`, then start the standby using the same Nginx service method and an agreed edge port. Keep both edges running.

Before changing DNS, test the standby while preserving the hostname for TLS validation (run on a client):

```bash
cd /path/to/CN_Project
source scripts/team.env
curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" \
  --resolve "$APP_HOST:$EDGE_PORT:$EDGE_STANDBY_IP" \
  -i "https://$APP_HOST:$EDGE_PORT/api/status"
```

Only continue if the response is healthy and certificate validation succeeds. Change the `app` A record on both DNS resolvers to the standby edge and restart them. On clients run:

```bash
scripts/client-checks.sh edge-cutover
dscacheutil -q host -a name "$APP_HOST"
```

Show an already-cached client still using the old edge while a fresh lookup uses the standby, if observed. Restore the original A record on both resolvers and flush caches after capturing evidence.

### 11. Everyone: troubleshooting challenge and final rehearsal (Extension F)

The instructor injects one fault during evaluation; don't pre-script a guessed fix. Use this sequence from a client, with `team.env` loaded:

```bash
cd /path/to/CN_Project
source scripts/team.env
dig "$APP_HOST" A
nc -vz -G 3 "$EDGE_PRIMARY_IP" "$EDGE_PORT"
curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" -v \
  "https://$APP_HOST:$EDGE_PORT/api/status"
curl --connect-timeout 4 --max-time 8 \
  "http://$BACKEND_A_IP:$BACKEND_A_PORT/api/status"
curl --connect-timeout 4 --max-time 8 \
  "http://$BACKEND_B_IP:$BACKEND_B_PORT/api/status"
```

Explain what each result proves: DNS answer, TCP reachability/port, TLS validation and HTTP response, then backend/application response. Identify the affected layer, fix or isolate the fault, and repeat the relevant checks. Rehearse the PDF's full 11-step final demo and individual viva.

## Evidence checklist

Keep each run's log in `Evidence/logs/` and add concise matching evidence in `Evidence/`:

- Topology, IP/service inventory, and pairwise ping results.
- DNS queries from clients and backup DNS; TTL before/after record change and cache flush.
- Trusted HTTPS result; load balancing with both `X-Backend` values; cache headers and 304.
- Wireshark capture and annotated screenshots for DNS, TCP SYN/SYN-ACK/ACK, TLS handshake, and encrypted data.
- Backend-A outage/recovery, firewall isolation and rollback, standby edge cutover, and faculty fault diagnosis.
- Phase 2 report: what changed, actual results for each extension, troubleshooting notes, and one learning summary per extension.

A saved log records what a script observed on that Mac; it does not prove a different machine's state or replace the live demo. Redact public/private keys and any unrelated personal information before sharing evidence.

## Rough time estimate

For a team whose Phase 1 setup is already stable and whose four Macs are available together, budget roughly **6–10 elapsed hours** for Phase 2 setup, demonstrations, evidence capture, and a first rehearsal. Allow **another 2–6 hours** if Phase 1 addresses/configuration need repair, firewall rules need instructor/admin help, or certificate trust and standby Nginx need debugging. The actual TTL wait is about a minute per observation; most time is in verifying the right configs, coordinating machine changes, and collecting clean evidence. The report and viva practice can be done in parallel and may take another **2–3 team hours**.
