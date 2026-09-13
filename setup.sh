#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_DIR="$HOME/code/ai"

T3_UNIT=customt3code.service
OC_UNIT=opencode-web.service
T3_PORT=${T3CODE_PORT:-3773}
OC_PORT=${OPENCODE_PORT:-4096}

APT_PKGS=()
FATAL=()

# ---------------------------------------------------------------- output ----

say()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------- preflight ----

# Mirrors run-t3code: PATH first, then any nvm/volta/system install.
resolve_node() {
  local n
  n=$(command -v node || true)
  if [[ -z $n ]]; then
    for c in "$HOME"/.nvm/versions/node/*/bin/node "$HOME"/.volta/bin/node \
             /usr/local/bin/node /usr/bin/node; do
      [[ -x $c ]] && n=$c && break
    done
  fi
  printf '%s' "${n:-}"
}

# Mirrors run-opencode.
resolve_opencode() {
  local b="$HOME/.opencode/bin/opencode"
  [[ -x $b ]] || b=$(command -v opencode || true)
  printf '%s' "${b:-}"
}

report() { printf 'preflight: %-12s %s\n' "$1" "$2"; }

# need_cmd <command> [apt-package] [hint]
# With an apt package, a miss is queued for auto-install. Without one, it's fatal.
need_cmd() {
  local cmd=$1 pkg=${2:-} hint=${3:-} path
  path=$(command -v "$cmd" || true)
  if [[ -n $path ]]; then
    report "$cmd" "ok"
  elif [[ -n $pkg ]]; then
    report "$cmd" "MISSING (apt: $pkg)"
    APT_PKGS+=("$pkg")
  else
    report "$cmd" "MISSING"
    FATAL+=("$cmd${hint:+ — $hint}")
  fi
}

preflight_node() {
  local n
  n=$(resolve_node)
  if [[ -n $n ]]; then
    report node "ok ($("$n" -v 2>/dev/null))"
  else
    report node "MISSING"
    FATAL+=("node — install via nvm: https://github.com/nvm-sh/nvm")
  fi
}

preflight_opencode() {
  local b
  b=$(resolve_opencode)
  if [[ -n $b ]]; then
    report opencode "ok ($b)"
  else
    report opencode "MISSING"
    FATAL+=("opencode — install: curl -fsSL https://opencode.ai/install | bash")
  fi
}

# node-pty (a t3 dependency) has no usable prebuilt binary here and falls back
# to node-gyp, which needs a C++ toolchain. Without it the service crash-loops
# with no output in the journal.
preflight_buildtools() {
  need_cmd g++ g++
  need_cmd make make
  need_cmd python3 python3
}

apt_install() {
  command -v apt-get >/dev/null 2>&1 ||
    die "missing packages (${APT_PKGS[*]}) and no apt-get on this system — install them manually"
  note "installing build deps: ${APT_PKGS[*]}"
  if ! sudo apt-get install -y "${APT_PKGS[@]}"; then
    note "install failed, refreshing package lists and retrying"
    sudo apt-get update
    sudo apt-get install -y "${APT_PKGS[@]}"
  fi
  local cmd
  for cmd in "${APT_PKGS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd still not on PATH after install"
  done
  note "build deps installed"
}

finish_preflight() {
  if ((${#FATAL[@]})); then
    say ""
    say "preflight failed — install these first:"
    local f
    for f in "${FATAL[@]}"; do say "  - $f"; done
    exit 1
  fi
  ((${#APT_PKGS[@]})) && apt_install
  APT_PKGS=()
  return 0
}

# The unit files hardcode %h/code/ai, so a clone anywhere else silently
# produces units pointing at a path that does not exist.
check_repo_location() {
  [[ $REPO_DIR == "$EXPECTED_DIR" ]] && return 0
  die "repo is at $REPO_DIR but the .service files hardcode $EXPECTED_DIR
       move the clone there, or edit ExecStart in customt3code.service / opencode-web.service"
}

# ------------------------------------------------------------ verification ---

port_open() { timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

unit_failed() {
  local unit=$1 why=$2
  say ""
  say "error: $unit $why"
  say "--- last 30 journal lines ---"
  journalctl --user -u "$unit" --no-pager -n 30 2>&1 | sed 's/^/  /'
  exit 1
}

# wait_for_unit <unit> <host> <port> [timeout]
# Polls until the unit is active AND the port accepts a connection. Any restart
# means it crashed, so bail immediately rather than waiting out the timeout.
wait_for_unit() {
  local unit=$1 host=$2 port=$3 timeout=${4:-60}
  local start=$SECONDS state restarts
  note "waiting for $unit on $host:$port (up to ${timeout}s)"
  while (( SECONDS - start < timeout )); do
    state=$(systemctl --user is-active "$unit" 2>/dev/null || true)
    restarts=$(systemctl --user show -p NRestarts --value "$unit" 2>/dev/null || echo 0)
    if [[ $state == failed ]] || (( restarts > 0 )); then
      unit_failed "$unit" "crashed after starting (restarts: $restarts)"
    fi
    if [[ $state == active ]] && port_open "$host" "$port"; then
      note "$unit is active and listening on $host:$port"
      return 0
    fi
    sleep 2
  done
  unit_failed "$unit" "did not come up within ${timeout}s"
}

# ------------------------------------------------------------------ links ---

link() {
  local src=$1 dest=$2
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    die "refusing to overwrite non-symlink: $dest"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
  note "linked $dest -> $src"
}

# Only shells out to sudo when the installed copy actually differs, so a
# re-run of an already-provisioned box never prompts for a password.
install_helper() {
  local src=$1 dest=$2
  if cmp -s "$src" "$dest" 2>/dev/null; then
    note "$dest already up to date"
    return 0
  fi
  sudo install -m 0755 "$src" "$dest"
  note "installed $dest"
}

ENV_FILE="$HOME/.config/ai-services.env"

# Both units read this via EnvironmentFile=-, so overrides survive a reboot
# instead of only applying to the shell that ran setup.
seed_env_file() {
  [[ -e $ENV_FILE ]] && return 0
  mkdir -p "$(dirname "$ENV_FILE")"
  cat > "$ENV_FILE" <<'ENVEOF'
# Overrides for customt3code.service and opencode-web.service.
# Uncomment and edit, then: systemctl --user restart customt3code opencode-web

#T3CODE_HOST=100.64.0.1
#OPENCODE_PORT=4096
#OPENCODE_HOSTNAME=0.0.0.0
# opencode binds 0.0.0.0 and is unauthenticated without this:
#OPENCODE_SERVER_PASSWORD=
ENVEOF
  note "created $ENV_FILE"
}

start_unit() {
  local unit=$1
  seed_env_file
  systemctl --user daemon-reload
  systemctl --user reset-failed "$unit" 2>/dev/null || true
  systemctl --user enable --now "$unit"
}

# ------------------------------------------------------------------ setup ---

# Same host resolution as run-t3code, so verification checks the address the
# server actually binds to.
t3_host() {
  local h=${T3CODE_HOST:-}
  if [[ -z $h ]] && command -v tailscale >/dev/null 2>&1; then
    h=$(tailscale ip -4 2>/dev/null | head -1 || true)
  fi
  printf '%s' "${h:-127.0.0.1}"
}

setup_t3code() {
  step "t3code"
  preflight_node
  preflight_buildtools
  finish_preflight

  link "$REPO_DIR/customt3code.service" "$HOME/.config/systemd/user/$T3_UNIT"
  install_helper "$REPO_DIR/t3-token" /usr/local/bin/t3-token
  start_unit "$T3_UNIT"

  # First run downloads t3@nightly and builds node-pty, so allow extra time.
  wait_for_unit "$T3_UNIT" "$(t3_host)" "$T3_PORT" 180

  local url
  url=$(journalctl --user -u "$T3_UNIT" --no-pager 2>/dev/null |
        grep 'Pairing URL:' | tail -1 | sed -E 's/.*(http[^ ]*)/\1/' || true)
  [[ -n $url ]] && note "pairing URL: $url"
  say "t3code: ready"
}

setup_opencode() {
  step "opencode"
  preflight_opencode
  finish_preflight

  link "$REPO_DIR/opencode-web.service" "$HOME/.config/systemd/user/$OC_UNIT"
  start_unit "$OC_UNIT"
  wait_for_unit "$OC_UNIT" 127.0.0.1 "$OC_PORT" 60
  say "opencode: ready on port $OC_PORT"
}

setup_skills() {
  step "skills"
  local found=0 dir f
  for dir in "$HOME/.opencode/skills" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
    mkdir -p "$dir"
    for f in "$REPO_DIR/skills"/*; do
      [[ -e "$f" ]] || continue
      [[ $(basename "$f") == .gitkeep ]] && continue
      link "$f" "$dir/$(basename "$f")"
      found=1
    done
  done
  if (( found )); then
    say "skills: linked into ~/.opencode, ~/.agents, ~/.claude"
  else
    say "skills: nothing to link — $REPO_DIR/skills is empty (dirs created)"
  fi
}

setup_serve() {
  step "tailscale serve"
  command -v tailscale >/dev/null 2>&1 || die "tailscale not installed"
  sudo tailscale serve -bg "$OC_PORT"
  tailscale serve status 2>&1 | sed 's/^/    /'
  say "serve: opencode published on the tailnet"
}

usage() {
  local code=${1:-1} out=2
  (( code == 0 )) && out=1
  cat >&"$out" <<'USAGE'
usage: ./setup.sh [--all] [--t3code] [--opencode] [--skills] [--serve]

  --all       t3code + opencode + skills (not --serve)
  --t3code    T3 Code service + t3-token helper
  --opencode  opencode web server
  --skills    link skills/ into ~/.opencode, ~/.agents, ~/.claude
  --serve     publish the opencode port on the tailnet (opt-in; changes what
              is exposed, so it is never part of --all)

Each service is verified after start: setup fails with journal output if the
unit crashes or its port never opens.

env: T3CODE_HOST, T3CODE_PORT (3773), OPENCODE_PORT (4096)
USAGE
  exit "$code"
}

[[ $# -eq 0 ]] && usage

do_t3code=0 do_opencode=0 do_skills=0 do_serve=0
for arg in "$@"; do
  case "$arg" in
    --all)      do_t3code=1; do_opencode=1; do_skills=1 ;;
    --t3code)   do_t3code=1 ;;
    --opencode) do_opencode=1 ;;
    --skills)   do_skills=1 ;;
    --serve)    do_serve=1 ;;
    -h|--help)  usage 0 ;;
    *) printf 'unknown option: %s\n' "$arg" >&2; usage ;;
  esac
done

check_repo_location
sudo -n true 2>/dev/null || say "note: some steps need sudo; you may be prompted"

(( do_t3code ))   && setup_t3code
(( do_opencode )) && setup_opencode
(( do_skills ))   && setup_skills
(( do_serve ))    && setup_serve

say ""
say "setup complete"
