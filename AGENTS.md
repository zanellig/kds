<!-- kds:agent-instructions -->
# KDS (Kill Dev Servers)

Use `kds` when the user asks to stop, clear, or kill local development servers.

Run a preview first when the request is exploratory or safety-sensitive:

```sh
kds --dry-run
```

Run the command directly when the user clearly wants matching dev servers stopped:

```sh
kds
```

Only run `kds` when the sole dev server up is the one you (the agent) started
in this session. If a preview (`kds --dry-run`) shows other dev servers that
you did not start, stop and ask the user before killing anything.

`kds` targets host dev-server listeners such as `bun`, `npm`, `pnpm`, `yarn`,
`vite`, `next dev`, `turbo dev`, `wrangler dev`, and `workerd`. It is designed
to skip Docker/container-owned processes and actual Electron/Code listener
processes.

Do not use broad process killers such as `pkill node`, `killall bun`, or
`pkill -f vite` for this task unless the user explicitly asks for that riskier
behavior.
<!-- /kds:agent-instructions -->
