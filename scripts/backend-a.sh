#!/bin/bash
set -u
source "$(dirname "$0")/common.sh"
require_macos
begin_log "backend-a"

run "macOS version" sw_vers
network_inventory
ping_team_hosts
run "Python version" python3 --version
run "Backend A source syntax" python3 -m py_compile "$REPO_DIR/backend-a/server.py"
if [[ "${1:-}" != "start" ]]; then
  run "Backend A listener" lsof -nP -iTCP:"$BACKEND_A_PORT" -sTCP:LISTEN
  run "Backend A local status" curl --connect-timeout 3 --max-time 8 -i "http://127.0.0.1:${BACKEND_A_PORT}/api/status"
fi

if [[ "${1:-}" == "start" ]]; then
  echo
  echo "Starting Backend A in foreground. Press Ctrl-C to stop it for the outage demo."
  cd "$REPO_DIR/backend-a" || exit 2
  run "Start Backend A" python3 server.py
  finish_log
else
  note "To start Backend A in the foreground, run: scripts/backend-a.sh start. Ctrl-C stops it for Extension D; restart it with the same command after capturing the failover evidence."
  note "Extension C: apply the approved PF rule template on this backend so only EDGE_PRIMARY_IP can reach TCP ${BACKEND_A_PORT}; preserve the current PF rules and use the documented rollback after the demo. Do not enable or replace the system PF rules without checking with the team/admin."
  finish_log
fi
