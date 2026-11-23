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
run "Private DNS lookup for app hostname" dig "$APP_HOST" A
run "Private DNS lookup for API hostname" dig "$API_HOST" A
run "Ping edge" ping -c 3 "$EDGE_PRIMARY_IP"
run "Ping Backend A host" ping -c 3 "$BACKEND_A_IP"
run "Ping Backend B host" ping -c 3 "$BACKEND_B_IP"

case "$SCENARIO" in
  baseline)
    run "HTTPS status with trusted certificate" bash -c 'curl --connect-timeout 4 --max-time 12 --cacert "$1" -i "https://${2}:${3}/api/status"' _ "$TLS_CA_FILE" "$APP_HOST" "$EDGE_PORT"
    for n in 1 2 3 4 5 6; do
      run "Load-balance request $n" bash -c 'curl --connect-timeout 4 --max-time 12 --cacert "$1" -sS -D - "https://${2}:${3}/api/status"' _ "$TLS_CA_FILE" "$APP_HOST" "$EDGE_PORT"
    done
    run "Cache endpoint headers and body" bash -c 'curl --connect-timeout 4 --max-time 12 --cacert "$1" -i "https://${2}:${3}/api/cache"' _ "$TLS_CA_FILE" "$APP_HOST" "$EDGE_PORT"
    run "Conditional cache request expecting 304" bash -c 'curl --connect-timeout 4 --max-time 12 --cacert "$1" -H '\''If-None-Match: "team1-cache-v1"'\'' -i "https://${2}:${3}/api/cache"' _ "$TLS_CA_FILE" "$APP_HOST" "$EDGE_PORT"
    ;;
  dns-failover)
    run "Direct query to backup DNS" dig "@$DNS_BACKUP_IP" "$APP_HOST" A +noall +answer
    run "System resolver lookup with primary stopped" dscacheutil -q host -a name "$APP_HOST"
    ;;
  backend-a-down)
    for n in 1 2 3 4 5 6; do
      run "Request with Backend A stopped $n" bash -c 'curl --connect-timeout 4 --max-time 12 --cacert "$1" -sS -D - "https://${2}:${3}/api/status"' _ "$TLS_CA_FILE" "$APP_HOST" "$EDGE_PORT"
    done
    ;;
  edge-cutover)
    run "Fresh DNS answer during edge cutover" dig "$APP_HOST" A
    run "Request to current DNS-selected edge" bash -c 'curl --connect-timeout 4 --max-time 12 --cacert "$1" -i "https://${2}:${3}/api/status"' _ "$TLS_CA_FILE" "$APP_HOST" "$EDGE_PORT"
    ;;
  wrong-dns)
    run "Public resolver lookup for private hostname (expected failure/NXDOMAIN)" dig @8.8.8.8 "$APP_HOST" A
    run "Private resolver lookup for comparison" dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
    ;;
  wrong-dns-target)
    run "Observe deliberately incorrect DNS record" dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
    run "Request after deliberately incorrect DNS answer (expect connect/TLS failure or wrong destination)" bash -c 'curl --connect-timeout 4 --max-time 12 --cacert "$1" -i "https://${2}:${3}/api/status"' _ "$TLS_CA_FILE" "$APP_HOST" "$EDGE_PORT"
    ;;
  all-backends-down)
    run "HTTPS request with both backends stopped (expect upstream 502/504)" bash -c 'curl --connect-timeout 4 --max-time 12 --cacert "$1" -i "https://${2}:${3}/api/status"' _ "$TLS_CA_FILE" "$APP_HOST" "$EDGE_PORT"
    ;;
  wrong-port)
    run "TCP check to configured edge port" nc -vz -G 3 "$EDGE_PRIMARY_IP" "$EDGE_PORT"
    run "TCP check to deliberately unused neighboring port (adjust if in use)" nc -vz -G 3 "$EDGE_PRIMARY_IP" "$((EDGE_PORT + 1))"
    ;;
  *)
    echo "Usage: $0 [baseline|dns-failover|backend-a-down|edge-cutover|wrong-dns|all-backends-down|wrong-port]" >&2
    exit 2
    ;;
esac

note "Capture a screenshot of this terminal/log plus the matching Wireshark view. For Wireshark, capture DNS (udp.port==53), TCP/TLS to the edge (tcp.port==${EDGE_PORT}), and show SYN/SYN-ACK/ACK followed by TLS handshake packets. Do not claim a step passed unless the output shows it."
note "For the faculty fault challenge, diagnose in order: dig/name resolution -> nc -vz EDGE_IP EDGE_PORT -> curl with certificate validation -> application status/backend header. Record the injected fault, evidence, layer, fix/isolation, and retest."
finish_log
