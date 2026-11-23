#!/bin/bash
set -u
source "$(dirname "$0")/common.sh"
require_macos
begin_log "backend-b"

run "macOS version" sw_vers
network_inventory
ping_team_hosts
run "Python version" python3 --version
run "Backend B source syntax" python3 -m py_compile "$REPO_DIR/backend-b/server.py"
if [[ "${1:-}" != "start" ]]; then
  run "Backend B listener" lsof -nP -iTCP:"$BACKEND_B_PORT" -sTCP:LISTEN
  run "Backend B local status" curl --connect-timeout 3 --max-time 8 -i "http://127.0.0.1:${BACKEND_B_PORT}/api/status"
fi

if [[ "${1:-}" == "start" ]]; then
  echo
  echo "Starting Backend B in foreground. Press Ctrl-C to stop it."
  cd "$REPO_DIR/backend-b" || exit 2
  run "Start Backend B" python3 server.py
  finish_log
else
  note "To start Backend B in the foreground, run: scripts/backend-b.sh start. Keep Backend B running while Backend A is stopped in the failover demo."
  note "Extension C: apply the approved PF rule template on this backend so only EDGE_PRIMARY_IP can reach TCP ${BACKEND_B_PORT}; preserve the current PF rules and use the documented rollback after the demo. Do not enable or replace the system PF rules without checking with the team/admin."
  note "Extension E: this Mac may host standby Nginx if selected. Test it on EDGE_STANDBY_IP and an agreed alternate port before changing DNS."
  finish_log
fi
