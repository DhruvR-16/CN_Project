# Computer Networks Course Project Report

**Project:** Private Network Service Platform (Team Akku)
**Report date:** 23 November 2026
**Environment:** Four macOS laptops on one private Wi-Fi/LAN
**Evidence status:** This report distinguishes repository configuration from results shared during the team's test session. It does not treat an unrun test as a pass.

## 1. Aim and outcome

The project builds a small local service so a client can look up a private name, connect securely to an edge server, and receive a response from either of two application servers. Phase 1 builds and observes the request path. Phase 2 tests how the path behaves when components fail or the destination changes.

The **core service and backend failover were demonstrated**: private DNS returned the edge address, certificate-checked HTTPS returned `200 OK`, and requests reached both backends. When Backend A stopped, Backend B continued serving requests. Several other mandatory Phase 2 extensions still need live results and evidence (Section 7).

## 2. Architecture and responsibilities

| Member | Current IP | Primary work | Service |
|---|---|---|---|
| Akhilesh | `10.7.13.217` | Primary private DNS, DNS record changes and DNS troubleshooting | `dnsmasq`, UDP/TCP 53 |
| Kavya | `10.7.26.222` | HTTPS entry point, TLS certificate, reverse proxy and load balancing | Nginx, TCP 8443 |
| Dhruv | `10.7.30.216` | Backend A, client validation, packet analysis; proposed backup DNS | Python API on TCP 3001; backup `dnsmasq` requires proof |
| Lakshya | `10.7.15.193` | Backend B, client validation; proposed standby edge | Python API on TCP 3002; standby Nginx requires proof |

These are DHCP addresses observed on 23 November 2026. Recheck them before another demonstration.

```text
Client
  | 1. DNS query: app.team1.test -> 10.7.26.222
  v
Akhilesh: primary DNS (10.7.13.217:53)

Client
  | 2. TCP + TLS + HTTPS to app.team1.test:8443
  v
Kavya: Nginx edge (10.7.26.222:8443)
  | 3. HTTP reverse proxy, round-robin selection
  +--> Dhruv: Backend A (10.7.30.216:3001)
  +--> Lakshya: Backend B (10.7.15.193:3002)
  | 4. JSON response and X-Backend header
  v
Client
```

The private records `app.team1.test` and `api.team1.test` point to Kavya's edge address. Nginx is the single client-facing application endpoint. The application servers listen on their LAN interfaces and identify themselves through `X-Backend: A` or `X-Backend: B`.

## 3. What Phase 1 built

1. **Private LAN:** The laptops joined the same LAN and recorded their addresses. Ping and direct service checks established reachability. The assignment also calls for a complete per-machine subnet, gateway, interface, and MAC inventory and all-pairs ping record; retain that with the architecture evidence.
2. **Private DNS:** Akhilesh's `dnsmasq` answers both project names with the edge address. The observed answer had a 30-second TTL. Direct queries with `dig @10.7.13.217` prove this DNS service works. They do not prove that macOS clients are configured to use it as their system resolver.
3. **Two REST backends:** The Python servers expose `/`, `/api/status`, and `/api/cache`. A uses port 3001 and B uses port 3002. Status responses contain JSON and an `X-Backend` header.
4. **Reverse proxy and load balancing:** Nginx accepts application traffic on 8443 and proxies it to the two backend IPs. With both available, repeated requests showed both A and B. The upstream uses round-robin selection by default and `max_fails=1 fail_timeout=10s` for temporary backend unavailability.
5. **HTTPS/TLS:** Nginx terminates TLS using a certificate with both project names in its Subject Alternative Names. The team used `curl --cacert tls/server.crt` so the demonstrated curl connection validated the certificate; it did not use `-k`. The connection from Nginx to the backends is HTTP on the private LAN.
6. **HTTP caching behavior:** `/api/cache` returned `Cache-Control: public, max-age=60` and `ETag: "team1-cache-v1"`. A matching `If-None-Match` request returned `304 Not Modified`. This demonstrates conditional validation; it does not by itself prove a browser made a fresh cache hit.
7. **Protocol observation:** The shared capture output showed a project DNS query and answer, TCP's SYN/SYN-ACK/ACK handshake, a TLS handshake, encrypted client-edge application data, and edge-backend HTTP. Preserve the original capture and labelled screenshots so these observations can be independently shown.

### Phase 1 deliberate failure checks

| Fault introduced | Observation | What it shows |
|---|---|---|
| Ask a public DNS server for the private name | `NXDOMAIN` was observed; team DNS still returned the edge IP | DNS failure can occur while IP connectivity remains available |
| Set the project DNS target to `192.0.2.1` | DNS returned that address, but the app connection timed out; the correct record was restored | A valid DNS answer does not mean the destination service works |
| Stop Backend A | Six requests succeeded from B | Nginx can continue through the surviving backend |
| Stop both backends | DNS still answered and Nginx returned `502 Bad Gateway` | The failure is behind the edge, at the application upstream |
| Connect to unused port 8444 | Connection refused while port 8443 worked | Reaching a host does not imply a service is listening on every port |

## 4. What Phase 2 changed

Phase 2 extends the same topology rather than replacing it. The repository's Nginx upstream now has failure thresholds and retry directives (`proxy_next_upstream` and `proxy_next_upstream_tries 2`), allowing a request to be tried on the other backend after selected upstream errors. DNS answers use a short 30-second TTL in the running primary configuration. The runbook also defines a backup DNS host, backend firewall isolation procedure, and standby-edge cutover procedure. **A procedure in the repository is a plan, not evidence that its live test passed.**

| Extension required by the project document | Current result | Remaining demonstration |
|---|---|---|
| A. Backup DNS | Dhruv is assigned as backup host. An initial backup query timed out; no successful primary-outage client result was shared. | Start the second resolver, show matching records, stop primary DNS, and show clients continue resolving via backup. The assignment requires clients to list both DNS addresses. |
| B. TTL and controlled record change | Primary DNS answers showed TTL 30 seconds. | Change the record, show an actual client's old cached answer, expiry and new answer, then a manual cache flush and immediate change. Direct `dig @server` alone does not show client caching. |
| C. Backend service isolation | No completed firewall-rule test was shared. | Apply reviewed rules with rollback on both backends; show Kavya can connect while another client cannot; restore original rules afterward. |
| D. Backend failover | **Demonstrated.** Six requests succeeded from B with A stopped; after A restarted, requests reached both A and B. | Keep screenshots/logs of shutdown, surviving responses and recovery. Nginx itself remains a single point of failure. |
| E. Standby edge and DNS cutover | Lakshya is the proposed standby host; live standby and cutover were not demonstrated in shared results. | Start a standby Nginx, verify it directly, update both DNS records, observe new and cached clients, then restore the primary edge address. |
| F. Faculty troubleshooting challenge | This is performed during evaluation. | Diagnose the injected fault in order: DNS, TCP port, TLS certificate, then backend/application. |

The current runbook intentionally uses `dig @DNS_IP` and `curl --resolve` for many checks. They preserve each Mac's existing Wi-Fi DNS settings and still validate the project's DNS server and HTTPS route. They **do not** prove automatic client DNS failover or a system-resolver cache transition. Those assignment requirements need a separate, observed demonstration.

## 5. Test results and troubleshooting findings

| Check | Result shared by the team | Interpretation |
|---|---|---|
| Primary DNS | Both project names resolved to `10.7.26.222`, TTL 30 | Name-to-edge mapping worked on the primary resolver |
| Nginx syntax/start | `nginx -t` succeeded; a listener on 8443 was later shown | Syntax validation alone does not start Nginx |
| HTTPS through edge | Certificate-checked curl returned `HTTP/1.1 200 OK` and `X-Backend` | The client-edge-backend path worked |
| Round robin | Repeated requests showed A and B, including alternating responses after A restarted | Both backends were available through the edge |
| Cache validation | Cache headers and `304 Not Modified` were observed | Conditional HTTP caching behavior worked |
| Backend A outage | Six requests returned `200 OK` from B | Backend failover worked for that test |
| Both backends unavailable | Nginx returned `502 Bad Gateway` | Edge was reachable but had no working upstream |

Early setup errors were diagnosed by layer. `dnsmasq` was initially not running, so DNS queries timed out even though the DNS Mac answered ping. Later, Nginx config syntax was valid but port 8443 had no listener; starting Nginx fixed the connection refusal. An attempted `nginx -s reload` failed with an invalid PID because there was no running process to reload. A `502` response indicated that Nginx was reachable but could not complete the upstream request; checking each backend directly identified the application side of the path. These were setup/troubleshooting observations, separate from deliberate fault demonstrations.

## 6. Security measures and boundaries

- **TLS on the client-to-edge hop:** The edge presents a certificate for the project names, and the demonstrated curl commands validate it with `--cacert`. This protects that hop against passive reading and checks the server identity against the supplied certificate.
- **Private service naming:** The `.test` names are answered by the team DNS service. A private LAN and private DNS are deployment choices; they are not substitutes for access control.
- **Backend exposure:** The two backend services currently listen on `0.0.0.0`, so other LAN clients can potentially connect directly until firewall isolation is actually applied and tested. The Nginx-to-backend hop uses unencrypted HTTP.
- **Certificate key handling:** `tls/server.key` is currently tracked in the Git repository. For a real deployment, a published private key must be treated as compromised, replaced, and kept out of version control. The current certificate should be described as a classroom demonstration certificate, not a production security control.

## 7. Key concepts learned

| Concept | Meaning in this project |
|---|---|
| DNS and TTL | DNS maps a human-readable project name to the edge IP; TTL tells a caching resolver how long an answer may remain fresh. |
| IP and TCP ports | The IP identifies a host; the port identifies a listening service on that host. TCP establishes a connection before HTTPS data flows. |
| TLS and certificate validation | TLS negotiates an encrypted client-edge session. Certificate validation checks that the presented identity matches the requested name and trusted certificate. |
| Reverse proxy | Nginx receives client requests and forwards them to internal backend services, returning the backend response to the client. |
| Load balancing | Nginx normally distributes successive requests across A and B using round robin. |
| HTTP caching | `Cache-Control` describes freshness; an ETag lets the client ask whether its stored version is still current and receive `304` if so. |
| Failover and single points of failure | A backend outage can be tolerated while another backend works; one edge or one DNS server remains a risk until a tested standby or backup is in service. |
| Layered diagnosis | A successful ping does not prove DNS, TCP service availability, TLS validity, or backend health. Check each layer in that order. |

### Phase 2 learning summary by extension

- **A — Backup DNS:** A second resolver is intended to preserve name lookup during a primary DNS outage. A direct answer from backup is only the first check; actual client continuation must be observed.
- **B — TTL:** Short TTLs can shorten an edge migration, but a live client's cached answer may remain until expiry. Record both resolver and client observations.
- **C — Isolation:** Limiting backend ports to the edge narrows direct LAN access. A rule is effective only when the edge still succeeds and an ordinary client is blocked; a rollback is needed.
- **D — Failover:** Nginx sent traffic to B while A was unavailable and resumed distributing traffic when A returned. This does not make the edge itself highly available.
- **E — Edge migration:** A standby edge and DNS change could move new lookups to another Mac. Cached clients can still use the previous address until their cached answer expires.
- **F — Troubleshooting:** DNS, TCP, TLS, and application failures produce different symptoms. Testing one layer at a time identifies the fault without guessing.

## 8. Evidence, remaining work, and evaluation order

Save the current `10.7.x` screenshots and timestamped logs from `Evidence/logs/`, plus the original Wireshark capture. Some existing images in `Evidence/` show an older `10.3.x` network and should be labelled historical rather than used as proof of today's IPs. The repository does not currently contain the team's latest live logs from each Mac.

Before evaluation, complete and capture **backup DNS**, **client TTL/cache behavior**, **backend firewall isolation with rollback**, and **standby edge cutover**. Retain the run output for the instructor's fault challenge. Confirm the two-client system DNS requirement and browser/certificate trust requirement separately from direct `dig` and `curl --resolve` checks. Also retain a complete current IP/subnet/gateway/MAC inventory and all-pairs ping evidence.

For the live demo, follow the assignment's 11-step sequence: topology; LAN; private DNS; HTTPS by name; load balancing; packet capture; caching; one-backend outage; Phase 2 DNS/resilience; faculty fault; individual viva. The ordered commands and member responsibilities are in [readme.md](readme.md#9-one-pass-evaluation-runbook) and [scripts/README.md](scripts/README.md). Stop and restore each deliberate fault before the next test.

## 9. Source and scope

This report follows the supplied `CN_Project_Doc (1).pdf` (Sections 6–9), the checked-in application and Nginx configuration, and terminal results shared by the team on 23 November 2026. Results described as *demonstrated* were observed in those shared outputs; outstanding items are explicitly marked. It is a project report and readiness record, not a claim that every Phase 2 requirement has already passed.
