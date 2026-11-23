#!/bin/bash
# Shared helpers for the Team Akku role scripts. Compatible with macOS Bash 3.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/team.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing $CONFIG_FILE. Copy team.env.example to team.env and edit the addresses." >&2
  exit 2
fi
# team.env is a trusted, team-maintained shell config file.
# shellcheck disable=SC1090
source "$CONFIG_FILE"

DNS_TTL="${DNS_TTL:-30}"
NETWORK_SERVICE="${NETWORK_SERVICE:-Wi-Fi}"
TLS_CA_FILE="${TLS_CA_FILE:-}"
[[ -n "$TLS_CA_FILE" ]] || TLS_CA_FILE="$REPO_DIR/tls/server.crt"
LOG_DIR="$REPO_DIR/Evidence/logs"
mkdir -p "$LOG_DIR"
COMMAND_FAILURES=0

begin_log() {
  local role="$1" host stamp
  host="$(scutil --get ComputerName 2>/dev/null || hostname)"
  stamp="$(date '+%Y%m%d-%H%M%S')"
  LOG_FILE="$LOG_DIR/${role}-${host}-${stamp}.log"
  touch "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  echo "Team Akku evidence run"
  echo "Role: $role"
  echo "Machine: $host ($(hostname))"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Config: $CONFIG_FILE"
  echo "Log: $LOG_FILE"
  echo "NOTE: exit code 0 means command succeeded; non-zero means inspect output and fix before claiming success."
}

run() {
  local label="$1" rc
  shift
  echo
  echo "===== $label ====="
  printf 'COMMAND:'
  printf ' %q' "$@"
  printf '\n'
  # begin_log already tees this process's stdout/stderr to the evidence log.
  # Run directly so command output appears once and the real status is retained.
  "$@" 2>&1
  rc=$?
  echo "EXIT STATUS: $rc"
  if [[ "$rc" -ne 0 ]]; then
    COMMAND_FAILURES=$((COMMAND_FAILURES + 1))
  fi
  return 0
}

note() { echo; echo "===== ACTION REQUIRED: $* ====="; }

finish_log() {
  echo
  echo "===== SUMMARY ====="
  echo "Commands with non-zero exit status: $COMMAND_FAILURES"
  echo "Review each EXIT STATUS above. In deliberate failure scenarios, a failing check may be the expected observation."
  echo "Saved transcript: $LOG_FILE"
  [[ "$COMMAND_FAILURES" -eq 0 ]]
}

network_inventory() {
  run "IPv4/interface details" ifconfig "$NETWORK_INTERFACE"
  run "Default gateway/route" route -n get default
  run "Network service DNS servers ($NETWORK_SERVICE)" networksetup -getdnsservers "$NETWORK_SERVICE"
  run "Network interface MAC address ($NETWORK_INTERFACE)" ifconfig "$NETWORK_INTERFACE"
}

ping_team_hosts() {
  local label ip
  for label in primary-DNS backup-DNS primary-edge standby-edge backend-A backend-B; do
    case "$label" in
      primary-DNS) ip="$DNS_PRIMARY_IP" ;;
      backup-DNS) ip="$DNS_BACKUP_IP" ;;
      primary-edge) ip="$EDGE_PRIMARY_IP" ;;
      standby-edge) ip="$EDGE_STANDBY_IP" ;;
      backend-A) ip="$BACKEND_A_IP" ;;
      backend-B) ip="$BACKEND_B_IP" ;;
    esac
    run "Ping $label ($ip)" ping -c 3 "$ip"
  done
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "These role scripts are intended for macOS." >&2
    exit 2
  fi
}

curl_domain() {
  local host="$1" path="$2"
  curl --connect-timeout 4 --max-time 12 --cacert "$TLS_CA_FILE" \
    -i "https://${host}:${EDGE_PORT}${path}"
}
