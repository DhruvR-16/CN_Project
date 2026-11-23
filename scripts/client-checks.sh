#!/bin/bash
set -u
source "$(dirname "$0")/common.sh"
require_macos
SCENARIO="${1:-baseline}"
begin_log "client-${SCENARIO}"

run "macOS version" sw_vers
network_inventory
run "Configured DNS resolvers" scutil --dns
ping_team_hosts
run "Private DNS lookup for app hostname (direct query; no Wi-Fi DNS change)" dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
run "Private DNS lookup for API hostname (direct query; no Wi-Fi DNS change)" dig "@$DNS_PRIMARY_IP" "$API_HOST" A +noall +answer
run "Ping edge" ping -c 3 "$EDGE_PRIMARY_IP"
run "Ping Backend A host" ping -c 3 "$BACKEND_A_IP"
run "Ping Backend B host" ping -c 3 "$BACKEND_B_IP"

case "$SCENARIO" in
  baseline)
    run "HTTPS status with trusted certificate (hostname preserved; system DNS unchanged)" curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_PRIMARY_IP" -i "https://${APP_HOST}:${EDGE_PORT}/api/status"
    for n in 1 2 3 4 5 6; do
      run "Load-balance request $n" curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_PRIMARY_IP" -sS -D - "https://${APP_HOST}:${EDGE_PORT}/api/status"
    done
    run "Cache endpoint headers and body" curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_PRIMARY_IP" -i "https://${APP_HOST}:${EDGE_PORT}/api/cache"
    run "Conditional cache request expecting 304" curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_PRIMARY_IP" -H 'If-None-Match: "team1-cache-v1"' -i "https://${APP_HOST}:${EDGE_PORT}/api/cache"
    ;;
  dns-failover)
    run "Direct query to backup DNS" dig "@$DNS_BACKUP_IP" "$APP_HOST" A +noall +answer
    note "This checks the backup DNS service directly. It does not change Wi-Fi DNS settings or prove automatic system-resolver failover."
    ;;
  backend-a-down)
    for n in 1 2 3 4 5 6; do
      run "Request with Backend A stopped $n" curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_PRIMARY_IP" -sS -D - "https://${APP_HOST}:${EDGE_PORT}/api/status"
    done
    ;;
  edge-cutover)
    run "Fresh primary DNS answer during edge cutover" dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
    run "Request to standby edge (hostname preserved; system DNS unchanged)" curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_STANDBY_IP" -i "https://${APP_HOST}:${EDGE_PORT}/api/status"
    ;;
  wrong-dns)
    run "Public resolver lookup for private hostname (expected failure/NXDOMAIN)" dig @8.8.8.8 "$APP_HOST" A
    run "Private resolver lookup for comparison" dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
    ;;
  wrong-dns-target)
    run "Observe deliberately incorrect DNS record" dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
    run "Request forced to deliberately incorrect test IP (expected connection failure)" curl --connect-timeout 4 --max-time 5 --cacert "$TLS_CA_FILE" --resolve "$APP_HOST:$EDGE_PORT:192.0.2.1" -i "https://${APP_HOST}:${EDGE_PORT}/api/status"
    ;;
  all-backends-down)
    run "HTTPS request with both backends stopped (expect upstream 502/504)" curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_PRIMARY_IP" -i "https://${APP_HOST}:${EDGE_PORT}/api/status"
    ;;
  wrong-port)
    run "TCP check to configured edge port" nc -vz -G 3 "$EDGE_PRIMARY_IP" "$EDGE_PORT"
    run "TCP check to deliberately unused neighboring port (adjust if in use)" nc -vz -G 3 "$EDGE_PRIMARY_IP" "$((EDGE_PORT + 1))"
    ;;
  *)
    echo "Usage: $0 [baseline|dns-failover|backend-a-down|edge-cutover|wrong-dns|wrong-dns-target|all-backends-down|wrong-port]" >&2
    exit 2
    ;;
esac

note "Capture a screenshot of this terminal/log plus the matching Wireshark view. For Wireshark, capture DNS (udp.port==53), TCP/TLS to the edge (tcp.port==${EDGE_PORT}), and show SYN/SYN-ACK/ACK followed by TLS handshake packets. Do not claim a step passed unless the output shows it."
note "For the faculty fault challenge, diagnose in order: dig/name resolution -> nc -vz EDGE_IP EDGE_PORT -> curl with certificate validation -> application status/backend header. Record the injected fault, evidence, layer, fix/isolation, and retest."
finish_log
