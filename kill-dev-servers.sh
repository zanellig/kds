#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: kill-dev-servers.sh [--dry-run|-n]

Stops local development servers that are listening on TCP ports.

Matches common host dev processes such as bun/npm/pnpm/yarn dev, vite,
next dev, turbo dev, wrangler dev, and workerd. Skips Docker/container-owned
processes and actual Electron/Code listener processes.
EOF
}

dry_run=0

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n)
      dry_run=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

have() {
  command -v "$1" >/dev/null 2>&1
}

pid_exists() {
  local pid="$1"
  [[ -d "/proc/$pid" ]]
}

command_for_pid() {
  local pid="$1"
  ps -p "$pid" -o args= 2>/dev/null || true
}

comm_for_pid() {
  local pid="$1"
  ps -p "$pid" -o comm= 2>/dev/null || true
}

ppid_for_pid() {
  local pid="$1"
  ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ' || true
}

pgid_for_pid() {
  local pid="$1"
  ps -p "$pid" -o pgid= 2>/dev/null | tr -d ' ' || true
}

is_container_pid() {
  local pid="$1"

  [[ -r "/proc/$pid/cgroup" ]] || return 1
  grep -Eiq 'docker|containerd|kubepods|libpod|podman' "/proc/$pid/cgroup"
}

has_container_runtime_ancestor() {
  local pid="$1"
  local comm

  while [[ "$pid" =~ ^[0-9]+$ && "$pid" != "1" ]]; do
    comm="$(comm_for_pid "$pid")"
    case "$comm" in
      docker|dockerd|docker-proxy|containerd|containerd-shim*|podman|conmon)
        return 0
        ;;
    esac

    pid="$(ppid_for_pid "$pid")"
  done

  return 1
}

is_editor_process() {
  local pid="$1"
  local comm

  comm="$(comm_for_pid "$pid")"
  case "$comm" in
    electron|code|code-oss|codium)
      return 0
      ;;
  esac

  return 1
}

looks_like_dev_server() {
  local pid="$1"
  local cmd

  cmd="$(command_for_pid "$pid")"

  [[ "$cmd" =~ (^|[[:space:]/])(bun|npm|pnpm|yarn)([[:space:]]|$).*(^|[[:space:]])(run[[:space:]]+)?dev(:[[:alnum:]_-]+)?([[:space:]]|$) ]] ||
    [[ "$cmd" =~ (^|[[:space:]/])vite([[:space:]]|$) ]] ||
    [[ "$cmd" =~ (^|[[:space:]/])next([[:space:]]+dev|$) ]] ||
    [[ "$cmd" =~ (^|[[:space:]/])turbo([[:space:]]|$).*(^|[[:space:]])dev([[:space:]]|$) ]] ||
    [[ "$cmd" =~ (^|[[:space:]/])wrangler([[:space:]]+dev|$) ]] ||
    [[ "$cmd" =~ (^|[[:space:]/])workerd([[:space:]]|$) ]]
}

print_match() {
  local pid="$1"
  local pgid="$2"
  local cmd="$3"
  local mode="${4:-pgid}"

  if (( dry_run )); then
    if [[ "$mode" == "pid" ]]; then
      printf 'would stop: pid=%s pgid=%s mode=pid cmd=%s\n' "$pid" "$pgid" "$cmd"
    else
      printf 'would stop: pid=%s pgid=%s cmd=%s\n' "$pid" "$pgid" "$cmd"
    fi
  else
    if [[ "$mode" == "pid" ]]; then
      printf 'stopping: pid=%s pgid=%s mode=pid cmd=%s\n' "$pid" "$pgid" "$cmd"
    else
      printf 'stopping: pid=%s pgid=%s cmd=%s\n' "$pid" "$pgid" "$cmd"
    fi
  fi
}

discover_listener_pids_with_ss() {
  local line
  local rest

  ss -H -ltnp 2>/dev/null | while IFS= read -r line; do
    rest="$line"
    while [[ "$rest" =~ pid=([0-9]+) ]]; do
      printf '%s\n' "${BASH_REMATCH[1]}"
      rest="${rest#*pid=${BASH_REMATCH[1]}}"
    done
  done || true
}

discover_listener_pids_with_lsof() {
  local line

  lsof -nP -iTCP -sTCP:LISTEN -Fp 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" =~ ^p([0-9]+)$ ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
  done || true
}

discover_listener_pids() {
  if have ss; then
    discover_listener_pids_with_ss
  fi

  if have lsof; then
    discover_listener_pids_with_lsof
  fi
}

process_group_exists() {
  local pgid="$1"

  kill -0 -- "-$pgid" 2>/dev/null
}

if ! have ss && ! have lsof; then
  echo "kds requires ss (iproute2) or lsof to discover TCP listeners; neither was found." >&2
  exit 1
fi

mapfile -t listener_pids < <(discover_listener_pids | sort -u)

if (( ${#listener_pids[@]} == 0 )); then
  echo "No TCP listeners found."
  exit 0
fi

declare -A seen_targets=()
declare -A terminated_pgids=()
declare -A terminated_pids=()
matched=0
current_pgid="$(pgid_for_pid "$$")"

for pid in "${listener_pids[@]}"; do
  pid_exists "$pid" || continue
  is_container_pid "$pid" && continue
  has_container_runtime_ancestor "$pid" && continue
  is_editor_process "$pid" && continue
  looks_like_dev_server "$pid" || continue

  pgid="$(pgid_for_pid "$pid")"
  [[ -n "$pgid" ]] || continue

  kill_mode="pgid"
  target_key="pgid:$pgid"
  if [[ -n "$current_pgid" && "$pgid" == "$current_pgid" ]]; then
    kill_mode="pid"
    target_key="pid:$pid"
  fi

  if [[ -n "${seen_targets[$target_key]:-}" ]]; then
    continue
  fi

  seen_targets[$target_key]=1
  matched=1
  print_match "$pid" "$pgid" "$(command_for_pid "$pid")" "$kill_mode"

  if (( ! dry_run )); then
    if [[ "$kill_mode" == "pgid" ]]; then
      terminated_pgids[$pgid]=1
      kill -TERM -- "-$pgid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    else
      terminated_pids[$pid]=1
      kill -TERM "$pid" 2>/dev/null || true
    fi
  fi
done

if (( ! matched )); then
  echo "No matching host dev servers found."
  exit 0
fi

if (( dry_run )); then
  exit 0
fi

sleep 2

for pgid in "${!terminated_pgids[@]}"; do
  if process_group_exists "$pgid"; then
    printf 'still running after TERM, sending KILL to pgid=%s\n' "$pgid" >&2
    kill -KILL -- "-$pgid" 2>/dev/null || true
  fi
done

for pid in "${!terminated_pids[@]}"; do
  if pid_exists "$pid"; then
    printf 'still running after TERM, sending KILL to pid=%s\n' "$pid" >&2
    kill -KILL "$pid" 2>/dev/null || true
  fi
done
