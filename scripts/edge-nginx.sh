#!/bin/bash
set -u
source "$(dirname "$0")/common.sh"
require_macos
begin_log "edge-nginx"

run "macOS version" sw_vers
network_inventory
ping_team_hosts
run "Nginx binary location" which nginx
run "Project Nginx configuration validation" nginx -t -c "$REPO_DIR/nginx/nginx.conf"
run "Backend A direct health check from edge" curl --connect-timeout 4 --max-time 8 -i "http://${BACKEND_A_IP}:${BACKEND_A_PORT}/api/status"
run "Backend B direct health check from edge" curl --connect-timeout 4 --max-time 8 -i "http://${BACKEND_B_IP}:${BACKEND_B_PORT}/api/status"
run "Proxied HTTPS status (certificate verified; system DNS unchanged)" curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" --resolve "$APP_HOST:$EDGE_PORT:$EDGE_PRIMARY_IP" -i "https://${APP_HOST}:${EDGE_PORT}/api/status"

note "Extension D: first ensure the active upstream has max_fails/fail_timeout and proxy_next_upstream settings; run nginx -t and reload. Stop Backend A on its Mac, then on this edge run several requests to the status URL and confirm X-Backend: B each time. Restart A and confirm both IDs return."
note "Extension E: copy the validated edge configuration to the standby Mac, adjust its local certificate paths and upstream addresses, validate with nginx -t, then change the DNS A record to EDGE_STANDBY_IP. Compare fresh lookups and clients with cached old answers."
note "Before reloading, confirm scripts/team.env and nginx/nginx.conf use today's addresses and the certificate paths exist on this Mac."
finish_log
