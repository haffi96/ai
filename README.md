# ai

Agentic AI tooling setup — remote agent services, skills, and helpers.

## Setup

```bash
git clone https://github.com/haffi96/ai ~/code/ai && cd ~/code/ai
./setup.sh --all
```

The unit files hardcode `%h/code/ai`, so the clone must live at `~/code/ai`;
setup aborts with a clear message if it doesn't.

| Flag | Does |
| --- | --- |
| `--all` | `--t3code --opencode --skills` |
| `--t3code` | T3 Code service + `t3-token` helper |
| `--opencode` | opencode web server |
| `--skills` | link `skills/` into `~/.opencode`, `~/.agents`, `~/.claude` |
| `--serve` | publish the opencode port on the tailnet (opt-in) |

`--serve` is deliberately excluded from `--all` — it changes what's exposed on
your tailnet, so it stays a separate decision.

Setup is idempotent and safe to re-run: it skips the `sudo install` when
`/usr/local/bin/t3-token` already matches, and only invokes apt for packages
that are actually missing.

### What it checks

Preflight runs before anything touches systemd:

- **node** — via PATH, then nvm/volta/system, mirroring `run-t3code`
- **opencode** — `~/.opencode/bin/opencode`, then PATH
- **g++, make, python3** — `t3` pulls in `node-pty`, which has no usable
  prebuilt binary and falls back to `node-gyp`. Without a C++ toolchain the
  service crash-loops with *no error in the journal*. Missing packages are
  installed with apt automatically.

Anything apt can't fix (node, opencode) fails preflight with install
instructions rather than proceeding.

### What it verifies

After `enable --now`, each service is polled until it is both `active` **and**
accepting connections on its port. A restart counter above zero means it
crashed, so setup bails immediately rather than waiting out the timeout. On
failure it prints the last 30 journal lines and exits non-zero — setup cannot
report success for a service that isn't up.

## Services

Systemd user units, symlinked into `~/.config/systemd/user/`. Both use `run-*`
wrapper scripts so there are no hardcoded node/nvm paths — wrappers resolve
`node`/`npx` from PATH, then fall back to any nvm install, volta, or system
locations.

- **customt3code.service** — T3 Code server (via `run-t3code`, `npx t3@nightly serve`)
  - Binds to the tailscale IPv4 automatically; override with `T3CODE_HOST`
- **opencode-web.service** — opencode web server on port 4096 (via `run-opencode`)
  - Override with `OPENCODE_PORT` / `OPENCODE_HOSTNAME`

```bash
systemctl --user start customt3code
systemctl --user status opencode-web
```

### Configuration

Both units read `~/.config/ai-services.env` via `EnvironmentFile=-`, seeded by
setup on first run. Shell environment does *not* reach a systemd service, so
this file is the only place overrides persist across reboots.

```bash
$EDITOR ~/.config/ai-services.env
systemctl --user restart customt3code opencode-web
```

> opencode binds `0.0.0.0` and logs `OPENCODE_SERVER_PASSWORD is not set;
> server is unsecured` when that variable is empty. Set it in the env file if
> the port is reachable beyond your tailnet.

## Scripts

- **t3-token** — get the current T3 Code pairing token from journal logs

```bash
t3-token latest   # just the token
t3-token url      # full pairing URL
t3-token restart  # restart the service and print a fresh pairing URL
```

## Skills

Drop skills into `skills/`; `./setup.sh --skills` symlinks them into
`~/.opencode/skills/`, `~/.agents/skills/`, and `~/.claude/skills/`.
