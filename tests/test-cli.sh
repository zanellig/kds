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
printf 'LISTEN 0 128 [::1]:3001 [::]:* users:(("node",pid=%s,fd=2))\n' "$TEST_PID_ONE"
printf 'LISTEN 0 128 127.0.0.1:3002 0.0.0.0:* users:(("node",pid=%s,fd=1))\n' "$TEST_PID_TWO"
EOF

cat >"$tmp_dir/bin/lsof" <<'EOF'
#!/usr/bin/env bash
printf 'p%s\nn127.0.0.1:3000\n' "$TEST_PID_ONE"
printf 'p%s\nn*:3002\n' "$TEST_PID_TWO"
EOF

cat >"$tmp_dir/bin/ps" <<'EOF'
#!/usr/bin/env bash
pid="$2"
field="$4"
if [[ "$*" == *'-o comm= -o etime= -o rss= -o %cpu='* ]]; then
  [[ -z "${MISSING_PRETTY_METADATA:-}" ]] || exit 0
  case "$pid" in
    "$TEST_PID_ONE") printf 'node 01:23 65536 1.5\n' ;;
    "$TEST_PID_TWO") printf 'bun 2-03:04:05 512 0.0\n' ;;
  esac
  exit 0
fi
case "$field:$pid" in
  args=:"$TEST_PID_ONE") printf 'node /work/one/node_modules/.bin/vite\n' ;;
  args=:"$TEST_PID_TWO") printf 'next dev --turbopack\n' ;;
  args=*) printf 'bash\n' ;;
  comm=*) printf 'node\n' ;;
  ppid=*) printf '1\n' ;;
  pgid=:"$TEST_PID_ONE") printf '81001\n' ;;
  pgid=:"$TEST_PID_TWO") printf '81002\n' ;;
  pgid=*) printf '81999\n' ;;
  comm=:"$TEST_PID_ONE") printf 'node\n' ;;
  comm=:"$TEST_PID_TWO") printf 'bun\n' ;;
  etime=:"$TEST_PID_ONE") printf '01:23\n' ;;
  etime=:"$TEST_PID_TWO") printf '2-03:04:05\n' ;;
  rss=:"$TEST_PID_ONE") printf '65536\n' ;;
  rss=:"$TEST_PID_TWO") printf '512\n' ;;
  %cpu=:"$TEST_PID_ONE") printf '1.5\n' ;;
  %cpu=:"$TEST_PID_TWO") printf '0.0\n' ;;
esac
EOF

cat >"$tmp_dir/bin/readlink" <<'EOF'
#!/usr/bin/env bash
[[ -z "${MISSING_PRETTY_METADATA:-}" ]] || exit 0
case "$1" in
  */"$TEST_PID_ONE"/cwd) printf '/work/one\n' ;;
  */"$TEST_PID_TWO"/cwd) printf '/work/two with spaces\n' ;;
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

pretty_preview="$($repo_dir/kill-dev-servers.sh --dry-run --pretty)"
grep -Eq '^TYPE +ELAPSED +RSS +CPU +BIND +CWD +STOP$' <<<"$pretty_preview" || fail 'pretty preview has no header'
grep -Fq "node  01:23        64 MiB  1.5%  127.0.0.1:3000, [::1]:3001" <<<"$pretty_preview" || fail 'first pretty row lacks process metadata or bindings'
grep -Fq "/work/one" <<<"$pretty_preview" || fail 'first pretty row lacks cwd'
grep -Fq "kds --pid $pid_one" <<<"$pretty_preview" || fail 'first pretty row is not actionable'
grep -Fq "bun   2-03:04:05  512 KiB  0.0%  127.0.0.1:3002, *:3002" <<<"$pretty_preview" || fail 'second pretty row lacks process metadata or bindings'
grep -Fq "/work/two with spaces" <<<"$pretty_preview" || fail 'second pretty row lacks cwd'
[[ "$(grep -Fo '127.0.0.1:3000' <<<"$pretty_preview" | wc -l)" -eq 1 ]] || fail 'duplicate bindings were not removed'
[[ ! -e "$KILL_LOG" ]] || fail 'pretty dry-run signaled a process'

missing_preview="$(MISSING_PRETTY_METADATA=1 $repo_dir/kill-dev-servers.sh --dry-run --pretty)"
grep -Eq '^- +- +- +- +' <<<"$missing_preview" || fail 'missing pretty metadata has no fallbacks'
grep -Fq "kds --pid $pid_one" <<<"$missing_preview" || fail 'missing metadata removed actionable stop command'

if "$repo_dir/kill-dev-servers.sh" --pretty >/dev/null 2>&1; then
  fail 'pretty was accepted without dry-run'
fi
if "$repo_dir/kill-dev-servers.sh" --dry-run --pretty --pid "$pid_one" >/dev/null 2>&1; then
  fail 'pretty dry-run and PID were accepted together'
fi

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
