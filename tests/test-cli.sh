#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

pid_one="$$"
pid_two="$PPID"
export TEST_PID_ONE="$pid_one" TEST_PID_TWO="$pid_two"
export KILL_LOG="$tmp_dir/kill.log"

mkdir -p "$tmp_dir/bin"

cat >"$tmp_dir/bin/ss" <<'EOF'
#!/usr/bin/env bash
printf 'LISTEN 0 128 127.0.0.1:3000 0.0.0.0:* users:(("node",pid=%s,fd=1))\n' "$TEST_PID_ONE"
printf 'LISTEN 0 128 127.0.0.1:3001 0.0.0.0:* users:(("node",pid=%s,fd=1))\n' "$TEST_PID_TWO"
EOF

cat >"$tmp_dir/bin/lsof" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$tmp_dir/bin/ps" <<'EOF'
#!/usr/bin/env bash
pid="$2"
field="$4"
case "$field:$pid" in
  args=:"$TEST_PID_ONE") printf 'node /work/one/node_modules/.bin/vite\n' ;;
  args=:"$TEST_PID_TWO") printf 'next dev --turbopack\n' ;;
  args=*) printf 'bash\n' ;;
  comm=*) printf 'node\n' ;;
  ppid=*) printf '1\n' ;;
  pgid=:"$TEST_PID_ONE") printf '81001\n' ;;
  pgid=:"$TEST_PID_TWO") printf '81002\n' ;;
  pgid=*) printf '81999\n' ;;
esac
EOF

cat >"$tmp_dir/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$tmp_dir/bin/"*
export PATH="$tmp_dir/bin:$PATH"

kill() {
  if [[ "$1" == "-0" ]]; then
    return 1
  fi
  printf '%s\n' "$*" >>"$KILL_LOG"
}
export -f kill

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

preview="$($repo_dir/kill-dev-servers.sh --dry-run)"
short_preview="$($repo_dir/kill-dev-servers.sh -n)"
[[ "$preview" == "$short_preview" ]] || fail '-n differs from --dry-run'
grep -Eq "candidate [0-9]+: pid=$pid_one pgid=81001 cmd=node /work/one/node_modules/.bin/vite \| stop with: kds --pid $pid_one" <<<"$preview" || fail 'first server is not actionable'
grep -Eq "candidate [0-9]+: pid=$pid_two pgid=81002 cmd=next dev --turbopack \| stop with: kds --pid $pid_two" <<<"$preview" || fail 'second server is not actionable'
[[ ! -e "$KILL_LOG" ]] || fail 'dry-run signaled a process'

"$repo_dir/kill-dev-servers.sh" --pid "$pid_one" >/dev/null
grep -Fxq -- '-TERM -- -81001' "$KILL_LOG" || fail 'targeted mode did not stop selected group'
if grep -Fq -- '-81002' "$KILL_LOG"; then
  fail 'targeted mode widened to another candidate'
fi

: >"$KILL_LOG"
"$repo_dir/kill-dev-servers.sh" >/dev/null
grep -Fxq -- '-TERM -- -81001' "$KILL_LOG" || fail 'bare mode missed first group'
grep -Fxq -- '-TERM -- -81002' "$KILL_LOG" || fail 'bare mode missed second group'

if "$repo_dir/kill-dev-servers.sh" --pid 999999 >/dev/null 2>&1; then
  fail 'noncandidate PID was accepted'
fi
if "$repo_dir/kill-dev-servers.sh" --dry-run --pid "$pid_one" >/dev/null 2>&1; then
  fail 'dry-run and PID were accepted together'
fi
if "$repo_dir/kill-dev-servers.sh" --pid nope >/dev/null 2>&1; then
  fail 'invalid PID was accepted'
fi

printf 'ok\n'
