#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${KDS_REPO_URL:-https://github.com/zanellig/kds.git}"
CLONE_DIR="${KDS_CLONE_DIR:-$HOME/.local/share/kds/repo}"
INSTALL_DIR="${KDS_INSTALL_DIR:-$HOME/.local/bin}"
BIN_PATH="${KDS_BIN_PATH:-$INSTALL_DIR/kds}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
REINSTALL="${KDS_REINSTALL:-}"
SKIP_AGENT_INSTRUCTIONS="${KDS_SKIP_AGENT_INSTRUCTIONS:-}"

BLOCK_START="<!-- kds:agent-instructions -->"
BLOCK_END="<!-- /kds:agent-instructions -->"
RC_BLOCK_START="# kds:alias"
RC_BLOCK_END="# /kds:alias"

say() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

installed_kds_path() {
  if [[ -e "$BIN_PATH" ]]; then
    printf '%s\n' "$BIN_PATH"
    return
  fi

  command -v kds 2>/dev/null || true
}

confirm_reinstall_if_needed() {
  local existing_path
  local answer

  existing_path="$(installed_kds_path)"
  [[ -n "$existing_path" ]] || return 0

  case "$REINSTALL" in
    1|true|TRUE|yes|YES|y|Y)
      say "Reinstalling existing kds at $existing_path"
      return
      ;;
    0|false|FALSE|no|NO|n|N)
      say "kds is already installed at $existing_path; leaving it unchanged."
      exit 0
      ;;
  esac

  if [[ -t 0 ]]; then
    printf 'kds is already installed at %s. Reinstall it? [y/N] ' "$existing_path"
    IFS= read -r answer || answer=""
  elif { : </dev/tty; } 2>/dev/null; then
    printf 'kds is already installed at %s. Reinstall it? [y/N] ' "$existing_path" >/dev/tty
    IFS= read -r answer </dev/tty || answer=""
  else
    say "kds is already installed at $existing_path."
    say "Re-run with KDS_REINSTALL=1 to reinstall or KDS_REINSTALL=0 to keep the existing install."
    exit 1
  fi

  case "$answer" in
    y|Y|yes|YES)
      say "Reinstalling existing kds at $existing_path"
      ;;
    *)
      say "Keeping existing kds at $existing_path"
      exit 0
      ;;
  esac
}

clone_or_update_repo() {
  if [[ -d "$CLONE_DIR/.git" ]]; then
    say "Updating $CLONE_DIR"
    git -C "$CLONE_DIR" fetch --quiet origin
    git -C "$CLONE_DIR" checkout --quiet main
    git -C "$CLONE_DIR" pull --quiet --ff-only origin main
    return
  fi

  rm -rf "$CLONE_DIR"
  mkdir -p "$(dirname "$CLONE_DIR")"
  say "Cloning $REPO_URL into $CLONE_DIR"
  git clone --quiet "$REPO_URL" "$CLONE_DIR"
}

install_binary() {
  mkdir -p "$INSTALL_DIR" "$(dirname "$BIN_PATH")"
  cp "$CLONE_DIR/kill-dev-servers.sh" "$BIN_PATH"
  chmod +x "$BIN_PATH"
  say "Installed $BIN_PATH"
}

replace_or_append_block() {
  local file="$1"
  local start="$2"
  local end="$3"
  local block="$4"
  local tmp

  mkdir -p "$(dirname "$file")"
  touch "$file"

  tmp="$(mktemp)"
  awk -v start="$start" -v end="$end" -v block="$block" '
    BEGIN {
      in_block = 0
      wrote_block = 0
    }
    $0 == start {
      if (!wrote_block) {
        print block
        wrote_block = 1
      }
      in_block = 1
      next
    }
    $0 == end {
      in_block = 0
      next
    }
    !in_block {
      print
    }
    END {
      if (!wrote_block) {
        if (NR > 0) {
          print ""
        }
        print block
      }
    }
  ' "$file" >"$tmp"

  mv "$tmp" "$file"
}

install_aliases() {
  local shell_block
  local fish_block
  local rc_file
  local updated=0

  shell_block="$(printf '%s\nalias kds="%s"\n%s' "$RC_BLOCK_START" "$BIN_PATH" "$RC_BLOCK_END")"
  fish_block="$(printf '%s\nalias kds "%s"\n%s' "$RC_BLOCK_START" "$BIN_PATH" "$RC_BLOCK_END")"

  for rc_file in \
    "$HOME/.zshrc" \
    "$HOME/.zprofile" \
    "$HOME/.bashrc" \
    "$HOME/.bash_profile" \
    "$HOME/.profile"
  do
    if [[ -f "$rc_file" ]]; then
      replace_or_append_block "$rc_file" "$RC_BLOCK_START" "$RC_BLOCK_END" "$shell_block"
      say "Updated alias in $rc_file"
      updated=1
    fi
  done

  rc_file="$HOME/.config/fish/config.fish"
  if [[ -f "$rc_file" ]]; then
    replace_or_append_block "$rc_file" "$RC_BLOCK_START" "$RC_BLOCK_END" "$fish_block"
    say "Updated alias in $rc_file"
    updated=1
  fi

  if (( ! updated )); then
    say "No existing shell rc files found; add this alias manually if needed:"
    say "alias kds=\"$BIN_PATH\""
  fi
}

agent_instruction_block() {
  awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
    $0 == start {
      in_block = 1
    }
    in_block {
      print
    }
    $0 == end {
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$CLONE_DIR/AGENTS.md"
}

unique_agent_targets() {
  local codex_dir
  local codex_home
  local claude_dir
  local opencode_dir

  codex_home="${CODEX_HOME:-$HOME/.codex}"
  printf '%s\n' "$codex_home/AGENTS.md"

  shopt -s nullglob
  for codex_dir in "$HOME"/.codex*; do
    if [[ -d "$codex_dir" ]]; then
      printf '%s\n' "$codex_dir/AGENTS.md"
    fi
  done
  shopt -u nullglob

  claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  printf '%s\n' "$claude_dir/CLAUDE.md"

  opencode_dir="${OPENCODE_HOME:-$CONFIG_HOME/opencode}"
  printf '%s\n' "$opencode_dir/AGENTS.md"

  printf '%s\n' "$CONFIG_HOME/agents/AGENTS.md"
  printf '%s\n' "$HOME/.agents/AGENTS.md"
  printf '%s\n' "$HOME/.gemini/GEMINI.md"
}

install_agent_instructions() {
  local block
  local target

  block="$(agent_instruction_block)"

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    replace_or_append_block "$target" "$BLOCK_START" "$BLOCK_END" "$block"
    say "Updated agent instructions in $target"
  done < <(unique_agent_targets | awk '!seen[$0]++')
}

main() {
  if ! have git; then
    echo "install.sh requires git." >&2
    exit 1
  fi

  confirm_reinstall_if_needed
  clone_or_update_repo
  install_binary
  install_aliases

  case "$SKIP_AGENT_INSTRUCTIONS" in
    1|true|TRUE|yes|YES|y|Y)
      say "Skipping agent instruction updates."
      ;;
    *)
      install_agent_instructions
      ;;
  esac

  say ""
  say "Done. Try: kds --dry-run"
}

main "$@"
