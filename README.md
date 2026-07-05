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

## Install

Clone the repo and install the script somewhere on your `PATH`:

```sh
git clone https://github.com/zanellig/kill-dev-servers.git
mkdir -p "$HOME/.local/bin"
cp kill-dev-servers/kill-dev-servers.sh "$HOME/.local/bin/kds"
chmod +x "$HOME/.local/bin/kds"
```

Make sure `~/.local/bin` is on your `PATH`. For zsh:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

For bash:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

If you do not want to add `~/.local/bin` to your `PATH`, use an alias instead:

```sh
alias kds="/path/to/kill-dev-servers.sh"
```

## Usage

Preview what would be stopped:

```sh
kds --dry-run
```

Stop matching dev servers:

```sh
kds
```

## Shell Alias

If you prefer to edit your shell rc file manually, add this to `~/.zshrc`,
`~/.bashrc`, or the equivalent file for your shell:

```sh
alias kds="/path/to/kill-dev-servers.sh"
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
