# ai

Agentic AI tooling setup — remote agent services, skills, and helpers.

## Services

Systemd user units, symlinked into `~/.config/systemd/user/`:

- **customt3code.service** — T3 Code server (via `npx t3@nightly serve`)
- **opencode-web.service** — opencode web server on port 4096

Commands:

```bash
systemctl --user start customt3code
systemctl --user status opencode-web
sudo tailscale serve -bg 4096
```

## Scripts

- **t3-token** — get the current T3 Code pairing token from journal logs

```bash
t3-token latest   # just the token
t3-token url      # full pairing URL
t3-token restart  # restart the service and print a fresh pairing URL
```

## Setup

```bash
git clone https://github.com/haffi96/ai && cd ai
./setup.sh --t3code   # T3 Code service + t3-token helper
./setup.sh --opencode # opencode web server (port 4096)
./setup.sh --skills   # link skills into ~/.opencode, ~/.agents, ~/.claude
```

Flags can be combined: `./setup.sh --t3code --skills`.

## Services

Systemd user units, symlinked into `~/.config/systemd/user/`. Both use
`run-*` wrapper scripts so there are no hardcoded node/nvm paths — wrappers
resolve `node`/`npx` from PATH, then fall back to any nvm install, volta, or
system locations.

- **customt3code.service** — T3 Code server (via `run-t3code`, `npx t3@nightly serve`)
  - Binds to the tailscale IPv4 automatically; override with `T3CODE_HOST`
- **opencode-web.service** — opencode web server on port 4096 (via `run-opencode`)
  - Override with `OPENCODE_PORT` / `OPENCODE_HOSTNAME`

## Skills

Drop skills into `skills/`; `./setup.sh --skills` symlinks them into
`~/.opencode/skills/`, `~/.agents/skills/`, and `~/.claude/skills/`.
