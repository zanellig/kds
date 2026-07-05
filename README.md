# kill-dev-servers

Small Linux shell script to stop local JavaScript dev servers without touching Docker containers or editor processes.

It scans TCP listeners and stops process groups that look like host development servers:

- `bun`, `npm`, `pnpm`, or `yarn` running `dev`
- `vite`
- `next dev`
- `turbo ... dev`
- `wrangler dev`
- `workerd`

It skips Docker/container-owned processes and actual Electron/Code listener processes.

## Usage

Preview what would be stopped:

```sh
./kill-dev-servers.sh --dry-run
```

Stop matching dev servers:

```sh
./kill-dev-servers.sh
```

## Shell Alias

Add this to your shell rc file, such as `~/.zshrc` or `~/.bashrc`:

```sh
alias kds="$HOME/playground/kill-dev-servers/kill-dev-servers.sh"
```

Then reload your shell:

```sh
source ~/.zshrc
```

Use:

```sh
kds --dry-run
kds
```
