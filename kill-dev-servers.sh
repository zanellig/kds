#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: kill-dev-servers.sh [--dry-run|-n] [--pretty]
       kill-dev-servers.sh [--pid PID|-p PID]

Stops local development servers that are listening on TCP ports.

With no arguments, stops every matching server. --dry-run lists numbered
candidates and the command to stop each one. --pretty adds a human-readable
process table to --dry-run. --pid stops only the current matching candidate
with that PID.

Matches common host dev processes such as bun/npm/pnpm/yarn dev, vite,
next dev, turbo dev, wrangler dev, and workerd. Skips Docker/container-owned
processes and actual Electron/Code listener processes.
EOF
}

dry_run=0
pretty=0
target_pid=""

while (( $# )); do
  case "$1" in
    --dry-run|-n)
      dry_run=1
      shift
      ;;
    --pretty)
      pretty=1
      shift
      ;;
    --pid|-p)
      if [[ -n "$target_pid" ]]; then
        echo "PID may only be specified once." >&2
        exit 2
      fi
      if (( $# < 2 )) || [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "$1 requires a positive numeric PID." >&2
        usage >&2
        exit 2
      fi
      target_pid="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if (( pretty )) && (( ! dry_run )); then
  echo "--pretty requires --dry-run." >&2
  exit 2
fi

if (( dry_run )) && [[ -n "$target_pid" ]]; then
  echo "--dry-run cannot be combined with --pid." >&2
  exit 2
fi

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

  if [[ "$mode" == "pid" ]]; then
    printf 'stopping: pid=%s pgid=%s mode=pid cmd=%s\n' "$pid" "$pgid" "$cmd"
  else
    printf 'stopping: pid=%s pgid=%s cmd=%s\n' "$pid" "$pgid" "$cmd"
  fi
}

print_candidate() {
  local number="$1"
  local pid="$2"
  local pgid="$3"
  local cmd="$4"
  local mode="${5:-pgid}"

  if [[ "$mode" == "pid" ]]; then
    printf 'candidate %s: pid=%s pgid=%s mode=pid cmd=%s | stop with: kds --pid %s\n' "$number" "$pid" "$pgid" "$cmd" "$pid"
  else
    printf 'candidate %s: pid=%s pgid=%s cmd=%s | stop with: kds --pid %s\n' "$number" "$pid" "$pgid" "$cmd" "$pid"
  fi
}

print_pretty_candidates() {
  local index
  local pid
  local metadata
  local type
  local elapsed
  local rss
  local cpu
  local bindings
  local cwd
  local stop
  local width_type=4
  local width_elapsed=7
  local width_rss=3
  local width_cpu=3
  local width_bind=4
  local width_cwd=3
  local -a types=()
  local -a elapsed_times=()
  local -a rss_values=()
  local -a cpu_values=()
  local -a binding_values=()
  local -a cwd_values=()
  local -a stop_values=()

  for index in "${!candidate_pids[@]}"; do
    pid="${candidate_pids[$index]}"
    metadata="$(ps -p "$pid" -o comm= -o etime= -o rss= -o %cpu= 2>/dev/null || true)"
    type=""
    elapsed=""
    rss=""
    cpu=""
    read -r type elapsed rss cpu <<<"$metadata"

    type="${type:--}"
    elapsed="${elapsed:--}"
    if [[ "$rss" =~ ^[0-9]+$ ]]; then
      if (( rss < 1024 )); then
        rss="${rss} KiB"
      else
        rss="$(((rss + 512) / 1024)) MiB"
      fi
    else
      rss="-"
    fi
    if [[ -n "$cpu" ]]; then
      cpu="${cpu}%"
    else
      cpu="-"
    fi

    bindings="${candidate_bindings[$index]:--}"
    bindings="${bindings//$'\n'/, }"
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
    cwd="${cwd:--}"
    stop="kds --pid $pid"

    types+=("$type")
    elapsed_times+=("$elapsed")
    rss_values+=("$rss")
    cpu_values+=("$cpu")
    binding_values+=("$bindings")
    cwd_values+=("$cwd")
    stop_values+=("$stop")

    (( ${#type} > width_type )) && width_type=${#type}
    (( ${#elapsed} > width_elapsed )) && width_elapsed=${#elapsed}
    (( ${#rss} > width_rss )) && width_rss=${#rss}
    (( ${#cpu} > width_cpu )) && width_cpu=${#cpu}
    (( ${#bindings} > width_bind )) && width_bind=${#bindings}
    (( ${#cwd} > width_cwd )) && width_cwd=${#cwd}
  done

  printf '%-*s  %-*s  %*s  %*s  %-*s  %-*s  %s\n' \
    "$width_type" TYPE "$width_elapsed" ELAPSED "$width_rss" RSS \
    "$width_cpu" CPU "$width_bind" BIND "$width_cwd" CWD STOP
  for index in "${!candidate_pids[@]}"; do
    printf '%-*s  %-*s  %*s  %*s  %-*s  %-*s  %s\n' \
      "$width_type" "${types[$index]}" "$width_elapsed" "${elapsed_times[$index]}" \
      "$width_rss" "${rss_values[$index]}" "$width_cpu" "${cpu_values[$index]}" \
      "$width_bind" "${binding_values[$index]}" "$width_cwd" "${cwd_values[$index]}" \
      "${stop_values[$index]}"
  done
}

discover_listeners_with_ss() {
  local line
  local endpoint
  local rest

  ss -H -ltnp 2>/dev/null | while IFS= read -r line; do
    read -r _ _ _ endpoint _ _ <<<"$line"
    [[ -n "$endpoint" ]] || continue
    rest="$line"
    while [[ "$rest" =~ pid=([0-9]+) ]]; do
      printf '%s\t%s\n' "${BASH_REMATCH[1]}" "$endpoint"
      rest="${rest#*pid=${BASH_REMATCH[1]}}"
    done
  done || true
}

discover_listeners_with_lsof() {
  local line
  local pid=""

  lsof -nP -iTCP -sTCP:LISTEN -Fpn 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" =~ ^p([0-9]+)$ ]]; then
      pid="${BASH_REMATCH[1]}"
    elif [[ -n "$pid" && "$line" == n* && -n "${line:1}" ]]; then
      printf '%s\t%s\n' "$pid" "${line:1}"
    fi
  done || true
}

discover_listeners() {
  if have ss; then
    discover_listeners_with_ss
  fi

  if have lsof; then
    discover_listeners_with_lsof
  fi
}

process_group_exists() {
  local pgid="$1"

  kill -0 -- "-$pgid" 2>/dev/null
}

collect_candidates() {
  local pid
  local pgid
  local kill_mode
  local target_key
  local current_pgid
  local candidate_index
  local binding
  declare -A target_indices=()
  declare -A seen_bindings=()

  candidate_pids=()
  candidate_pgids=()
  candidate_commands=()
  candidate_modes=()
  candidate_bindings=()
  current_pgid="$(pgid_for_pid "$$")"

  for pid in "${listener_pids[@]}"; do
    pid_exists "$pid" || continue
    is_container_pid "$pid" && continue
    has_container_runtime_ancestor "$pid" && continue
    is_editor_process "$pid" && continue
    looks_like_dev_server "$pid" || continue

    pgid="$(pgid_for_pid "$pid")"
    [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || continue

    kill_mode="pgid"
    target_key="pgid:$pgid"
    if [[ -n "$current_pgid" && "$pgid" == "$current_pgid" ]]; then
      kill_mode="pid"
      target_key="pid:$pid"
    fi

    if [[ -n "${target_indices[$target_key]:-}" ]]; then
      candidate_index="$((target_indices[$target_key] - 1))"
    else
      candidate_index="${#candidate_pids[@]}"
      target_indices[$target_key]="$((candidate_index + 1))"
      candidate_pids+=("$pid")
      candidate_pgids+=("$pgid")
      candidate_commands+=("$(command_for_pid "$pid")")
      candidate_modes+=("$kill_mode")
      candidate_bindings+=("")
    fi

    while IFS= read -r binding; do
      [[ -n "$binding" ]] || continue
      [[ -z "${seen_bindings["$target_key|$binding"]:-}" ]] || continue
      seen_bindings["$target_key|$binding"]=1
      if [[ -n "${candidate_bindings[$candidate_index]}" ]]; then
        candidate_bindings[$candidate_index]+=$'\n'
      fi
      candidate_bindings[$candidate_index]+="$binding"
    done <<<"${listener_bindings_by_pid[$pid]:-}"
  done
}

if ! have ss && ! have lsof; then
  echo "kds requires ss (iproute2) or lsof to discover TCP listeners; neither was found." >&2
  exit 1
fi

declare -a listener_pids=()
declare -A listener_bindings_by_pid=()
while IFS=$'\t' read -r pid binding; do
  [[ -n "$pid" && -n "$binding" ]] || continue
  if [[ -z "${listener_bindings_by_pid[$pid]:-}" ]]; then
    listener_pids+=("$pid")
    listener_bindings_by_pid[$pid]="$binding"
  else
    listener_bindings_by_pid[$pid]+=$'\n'
    listener_bindings_by_pid[$pid]+="$binding"
  fi
done < <(discover_listeners | sort -k1,1n -k2,2 -u)

declare -a candidate_pids=()
declare -a candidate_pgids=()
declare -a candidate_commands=()
declare -a candidate_modes=()
declare -a candidate_bindings=()
collect_candidates

if (( dry_run )); then
  if (( ${#listener_pids[@]} == 0 )); then
    echo "No TCP listeners found."
    exit 0
  fi
  if (( ${#candidate_pids[@]} == 0 )); then
    echo "No matching host dev servers found."
    exit 0
  fi

  if (( pretty )); then
    print_pretty_candidates
  else
    for index in "${!candidate_pids[@]}"; do
      print_candidate "$((index + 1))" "${candidate_pids[$index]}" "${candidate_pgids[$index]}" "${candidate_commands[$index]}" "${candidate_modes[$index]}"
    done
  fi
  exit 0
fi

if [[ -n "$target_pid" ]]; then
  selected_index=""
  for index in "${!candidate_pids[@]}"; do
    if [[ "${candidate_pids[$index]}" == "$target_pid" ]]; then
      selected_index="$index"
      break
    fi
  done

  if [[ -z "$selected_index" ]]; then
    printf 'Refusing --pid %s: it is not a current KDS candidate. Run kds --dry-run again.\n' "$target_pid" >&2
    exit 1
  fi
  target_indices=("$selected_index")
else
  if (( ${#listener_pids[@]} == 0 )); then
    echo "No TCP listeners found."
    exit 0
  fi
  if (( ${#candidate_pids[@]} == 0 )); then
    echo "No matching host dev servers found."
    exit 0
  fi
  target_indices=("${!candidate_pids[@]}")
fi

declare -A terminated_pgids=()
declare -A terminated_pids=()

for index in "${target_indices[@]}"; do
  pid="${candidate_pids[$index]}"
  pgid="${candidate_pgids[$index]}"
  kill_mode="${candidate_modes[$index]}"
  print_match "$pid" "$pgid" "${candidate_commands[$index]}" "$kill_mode"

  if [[ "$kill_mode" == "pgid" ]]; then
    terminated_pgids[$pgid]=1
    kill -TERM -- "-$pgid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  else
    terminated_pids[$pid]=1
    kill -TERM "$pid" 2>/dev/null || true
  fi
done

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
