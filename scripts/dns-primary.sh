#!/bin/bash
set -u
source "$(dirname "$0")/common.sh"
require_macos
begin_log "dns-primary"

run "macOS version" sw_vers
network_inventory
ping_team_hosts
run "Resolver configuration" scutil --dns
run "dnsmasq Homebrew service status" brew services info dnsmasq
run "Primary DNS app hostname answer" dig "@$DNS_PRIMARY_IP" "$APP_HOST" A +noall +answer
run "Primary DNS API hostname answer" dig "@$DNS_PRIMARY_IP" "$API_HOST" A +noall +answer

note "Extension A: on the selected backup Mac, configure dnsmasq with the same A records and verify using dig @BACKUP_IP app.team1.test. Then set two DNS resolver addresses on two clients and stop the primary DNS service. Re-run scripts/client-checks.sh dns-failover."
note "Extension B: set local-ttl=${DNS_TTL} in the active dnsmasq config; change the app record to the standby edge address, restart dnsmasq, and record client lookup results before/after TTL expiry and after cache flush. Restore the original A record afterwards."
note "Do not assume resolver-list order guarantees primary-then-backup behavior on macOS. Record which resolver answered (dig output) and demonstrate resolution while the primary service is stopped."
finish_log
