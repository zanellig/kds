<!-- kds:agent-instructions -->
# KDS (Kill Dev Servers)

Use `kds` when the user asks to stop, clear, or kill local development servers.

Preview matching servers first:

```sh
kds --dry-run
```

The preview prints a `kds --pid PID` command for each candidate. You may run
that targeted command without asking only when you started the server in this
session. Ask the user before stopping any other candidate.

Run bare `kds` only when the user explicitly wants every listed dev server
stopped:

```sh
kds
```

`kds` targets host dev-server listeners such as `bun`, `npm`, `pnpm`, `yarn`,
`vite`, `next dev`, `turbo dev`, `wrangler dev`, and `workerd`. It is designed
to skip Docker/container-owned processes and actual Electron/Code listener
processes.

Do not use broad process killers such as `pkill node`, `killall bun`, or
`pkill -f vite` for this task unless the user explicitly asks for that riskier
behavior.
<!-- /kds:agent-instructions -->
