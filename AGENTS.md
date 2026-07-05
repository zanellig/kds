# kill-dev-servers Agent Instructions

<!-- headroom:kds-instructions -->
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

`kds` targets host dev-server listeners such as `bun`, `npm`, `pnpm`, `yarn`,
`vite`, `next dev`, `turbo dev`, `wrangler dev`, and `workerd`. It is designed
to skip Docker/container-owned processes and actual Electron/Code listener
processes.

Do not use broad process killers such as `pkill node`, `killall bun`, or
`pkill -f vite` for this task unless the user explicitly asks for that riskier
behavior.
<!-- /headroom:kds-instructions -->
