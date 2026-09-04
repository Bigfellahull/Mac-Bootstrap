# mac-bootstrap

`mac-bootstrap` installs and verifies the durable macOS layer used by the
MacBook Air, personal Mac mini and work Mac mini. It is designed for Macs set
up as new machines rather than restored from a Time Machine system image.

Project repositories, SDKs, databases and AI coding CLIs do not live here.
They belong in the disposable Ubuntu machines managed by `dev-machine`.

## Profiles

### Air

The Air receives the common applications plus:

- Alcove
- Backdrop
- Bartender 6
- CleanShot X
- DataGrip
- Discord
- Dropover
- FieldKit
- Ghostty
- Google Drive
- Keynote, Numbers and Pages
- Linear
- Microsoft Teams
- Notion
- Rectangle
- SideNotes
- Starship
- bat
- fd
- fzf
- ripgrep
- zoxide
- zsh-autosuggestions
- zsh-syntax-highlighting
- Windows App
- Zed

### Personal mini

The personal mini receives the common applications plus OrbStack. Support for
an SSH-forwarded OrbStack Docker API bridge is available but disabled until a
personal workload needs it. It also receives `mkcert` for commissioning a
profile-specific local development CA and reusable VM server certificate.

### Work mini

The work mini receives the common applications, OrbStack and Parallels Desktop.
Its profile expects a commissioned SSH-forwarded OrbStack Docker API bridge for
development processes that need direct API access from the Ubuntu VM. It also
receives `mkcert` for its own local development TLS authority.

### Common applications

Every Mac receives:

- 1Password
- CleanMyMac
- ExpressVPN
- Tailscale

Authentication, subscription activation, privacy permissions and network
extension approval remain interactive.

## First use

Install Apple's Command Line Tools before cloning this repository:

```bash
xcode-select --install
```

Install Homebrew from its official instructions at <https://brew.sh>. Both are
explicit prerequisites so bootstrap never initiates an interactive toolchain or
administrator-authentication flow.

Then run the appropriate profile:

```bash
bin/mac plan air
bin/mac apply air
bin/mac verify air
```

Use `personal-mini` or `work-mini` on the minis. If the App Store is not ready,
apply the Homebrew applications first and return to the App Store applications
later:

```bash
bin/mac apply air --skip-app-store
bin/mac verify air --skip-app-store
```

`plan` is read-only. `apply` installs missing applications but never runs
Homebrew cleanup and never uninstalls an application. `verify` reports missing
state without changing it. None of these commands copies user data.

## Boundaries

- Air: graphical client applications, SSH, Tailscale, Zed, Ghostty, Starship and
  focused command-line shell tools.
- Minis: Tailscale, Remote Login and OrbStack.
- Work mini: an SSH-forwarded OrbStack Docker API bridge, commissioned with a
  dedicated VM key.
- Work mini: Parallels is independent of OrbStack provisioning.
- Minis: separate local development CAs; CA private keys never leave their
  issuing hosts.
- Ubuntu: source code, runtimes, developer CLIs and database clients.
- OrbStack Docker: profile- and project-scoped database containers.
- Credentials: entered interactively and never committed.

Homebrew development formulae, Docker Desktop, Colima, local PostgreSQL and
Redis services, full Xcode and host language runtimes are outside every profile.

## OrbStack Docker API bridge

The work VM can reach the Mac's user-owned OrbStack socket through an encrypted
SSH Unix-socket forward. This does not install a Docker daemon in Ubuntu or
expose a Docker TCP port. Ordinary linked `docker` and `docker compose` commands
do not need the bridge; it is for processes that consume the Docker API
directly.

The host bootstrap verifies the OrbStack socket and a restricted SSH
authorization. Key creation, host-key verification and authorization remain
commissioning steps, while the tunnel service belongs to `dev-machine`. See
[`docs/orbstack-docker-api.md`](docs/orbstack-docker-api.md).

## Local development TLS

Each mini can create and trust a profile-specific `mkcert` CA, issue a reusable
certificate for `localhost` and `*.dev.localhost`, and export only the material
needed by its matching Ubuntu VM. CA creation and trust remain explicit
commissioning actions. Projects consume the VM's stable PEM or PFX paths from
command-scoped wrappers; they do not establish trust themselves. See
[`docs/local-dev-tls.md`](docs/local-dev-tls.md).

## macOS settings

The bootstrap manages only explicitly declared macOS settings. The Air profile
manages Ghostty's Catppuccin light/dark preferences, SSH environment and
terminfo integration, plus a shared Starship prompt, focused zsh enhancements
and development VM helpers for local sessions. Remote Bash and tmux prompt
configuration belongs to `dev-machine`. Dock, Finder, keyboard, trackpad,
screenshot, power and Remote Login settings remain operator-controlled as
described in [`docs/settings.md`](docs/settings.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Commissioning](docs/commissioning.md)
- [DataGrip database access](docs/datagrip.md)
- [Local development TLS](docs/local-dev-tls.md)
- [OrbStack Docker API bridge](docs/orbstack-docker-api.md)
- [macOS settings policy](docs/settings.md)
