#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
  local src=$1 dest=$2
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    echo "refusing to overwrite non-symlink: $dest" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
  echo "linked $dest -> $src"
}

setup_t3code() {
  link "$REPO_DIR/customt3code.service" "$HOME/.config/systemd/user/customt3code.service"
  sudo install -m 0755 "$REPO_DIR/t3-token" /usr/local/bin/t3-token
  systemctl --user daemon-reload
  systemctl --user enable --now customt3code.service
  echo "t3code: enabled and started"
}

setup_opencode() {
  link "$REPO_DIR/opencode-web.service" "$HOME/.config/systemd/user/opencode-web.service"
  systemctl --user daemon-reload
  systemctl --user enable --now opencode-web.service
  echo "opencode: enabled and started"
}

setup_skills() {
  for dir in "$HOME/.opencode/skills" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
    mkdir -p "$dir"
    for f in "$REPO_DIR/skills"/*; do
      [[ -e "$f" ]] || continue
      link "$f" "$dir/$(basename "$f")"
    done
  done
  echo "skills: linked from $REPO_DIR/skills into ~/.opencode, ~/.agents, ~/.claude"
}

if [[ $# -eq 0 ]]; then
  echo "usage: ./setup.sh --t3code | --opencode | --skills" >&2
  exit 1
fi

for arg in "$@"; do
  case "$arg" in
    --t3code) setup_t3code ;;
    --opencode) setup_opencode ;;
    --skills) setup_skills ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done
