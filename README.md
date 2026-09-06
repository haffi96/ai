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
./setup.sh --skills   # link skills into ~/.opencode/skills/
```

Flags can be combined: `./setup.sh --t3code --skills`.

## Services

Systemd user units, symlinked into `~/.config/systemd/user/`:

- **customt3code.service** — T3 Code server (via `npx t3@nightly serve`)
- **opencode-web.service** — opencode web server on port 4096

## Skills

Drop skills into `skills/`; `./setup.sh --skills` symlinks them into `~/.opencode/skills/`.
