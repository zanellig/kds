---
name: verify
summary: Verify KDS CLI changes with isolated listener process groups
---

# Verify KDS

For runtime CLI changes, start disposable matching listeners in separate process groups:

```bash
setsid bash -c 'exec -a vite python -m http.server 0 --bind 127.0.0.1' >fixture.log 2>&1 & pid=$!
```

Use a trap that sends `KILL` to each captured negative PGID. Drive `./kill-dev-servers.sh --dry-run` and only `./kill-dev-servers.sh --pid "$pid"`; never run bare KDS while unrelated servers are listed. Confirm another disposable fixture survives and a stale PID is refused.
