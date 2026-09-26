# mac-bootstrap

`mac-bootstrap` installs and verifies the durable macOS layer used by the
MacBook Air, personal Mac mini and work Mac mini. It is designed for Macs set
up as new machines rather than restored from a Time Machine system image.

Project repositories, SDKs, databases and AI coding CLIs do not live here.
General development belongs in the disposable Ubuntu machines managed by
`dev-machine`. Windows-specific builds and applications use the work mini's
separately commissioned Parallels VM; see [Windows development](docs/windows-development.md).

## Start here

Follow the [commissioning guide](docs/commissioning.md) for the complete order
of work, including the manual steps before and after installation. Start with
the minis before commissioning the Air connections; Air application installation
can run independently.

| Stage | Required action |
|---|---|
| Before scripts | macOS setup, FileVault, Command Line Tools, Homebrew and the Air App Store sign-in |
| Installation | Run the selected profile as the normal macOS user |
| After scripts, all Macs | App sign-ins, licences, privacy/network permissions and Tailscale connectivity checks |
| After scripts, minis | Remote Login, OrbStack, local TLS CA, Ubuntu provisioning and the work Docker API bridge |
| After scripts, Air | Local SSH settings, separate keys, host trust, browser CA trust and client connections |
| Final checks | Run the profile verifier, resolve commissioning warnings and test real connections |

`apply` finishing successfully does not mean commissioning is complete.

## Profiles

### Air

The Air receives the common applications plus:

- Alcove
- Backdrop
- ChatGPT
- CleanShot X
- Discord
- Dropover
- Fastmail
- Ghostty
- Google Drive
- Keynote, Numbers and Pages
- Linear
- Microsoft Teams
- Rectangle
- SideNotes
- [Mountain Duck](docs/mountain-duck.md) for VM files in Finder
- TablePlus
- Windows App
- Zed

### Personal mini

The personal mini receives the common applications plus 1Password CLI,
CleanMyMac CLI and OrbStack. Support for an SSH-forwarded OrbStack Docker API
bridge is available but disabled until a personal workload needs it. It also
receives `mkcert` for commissioning a
profile-specific local development CA and reusable VM server certificate.

### Work mini

The work mini receives the common applications, 1Password CLI, CleanMyMac CLI,
OneDrive, OrbStack and Parallels Desktop.
Its profile expects a commissioned SSH-forwarded OrbStack Docker API bridge for
development processes that need direct API access from the Ubuntu VM. It also
receives `mkcert` for its own local development TLS authority.

OneDrive sign-in, sync selection and macOS File Sharing remain manual. See
[OneDrive access from the Air](docs/onedrive.md) for setup and verification.

### Common applications

Every Mac receives:

- 1Password
- CleanMyMac
- Tailscale
- Starship, bat, fd, fzf, ripgrep and zoxide
- zsh-autosuggestions and zsh-syntax-highlighting

Authentication, subscription activation, privacy permissions and network
extension approval remain interactive.

## First use

Install Apple's Command Line Tools before cloning this repository:

```bash
xcode-select --install
```

Install Homebrew from its official instructions at <https://brew.sh>. Both are
explicit prerequisites; bootstrap checks for them rather than installing them.
Run bootstrap as the normal macOS user, not with `sudo`. Homebrew cask package
installers may still request administrator approval during installation.

Then run the appropriate profile:

```bash
bin/mac plan air
bin/mac apply air
```

Complete the applicable manual steps in the [commissioning guide](docs/commissioning.md), then run:

```bash
bin/mac verify air
```

Use `personal-mini` or `work-mini` on the minis. If the App Store is not ready,
apply the Homebrew applications first and return to the App Store applications
later:

```bash
bin/mac apply air --skip-app-store
bin/mac verify air --skip-app-store
```

`apply` shows Homebrew command output as installation runs, followed by shell and profile
configuration messages and Mac App Store installation output where applicable.
There is no overall progress percentage; individual installers may pause or
request administrator approval.

`plan` is read-only. `apply` installs missing applications and updates managed
shell and profile configuration. It does not uninstall applications or request bundle cleanup;
Homebrew can still perform its normal dependency and cache maintenance.
`verify` reports missing state without changing it. None of these commands copies user data. Before
commissioning, missing Air SSH settings, mini TLS state and the work bridge can
cause verification to fail. `--skip-app-store` skips only App Store checks; rerun
without it after completing those installations.

## Boundaries

- Air: graphical client applications, SSH, Tailscale, Zed, Ghostty, Starship and
  focused command-line shell tools.
- Minis: Tailscale, Remote Login, OrbStack, 1Password CLI, CleanMyMac CLI and the shared shell tools.
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

## Air SSH routing

The Air uses the same `work-dev` and `personal-dev` SSH aliases on the LAN and
away. This repository manages routing through each mini over Tailscale to its
Ubuntu machine. Ghostty, Zed and the shell helpers use those aliases.

Supply the minis' full Tailscale DNS names and macOS/Linux usernames in
`~/.config/mac-bootstrap/ssh-air.tsv`, using `config/ssh/air.tsv.example` as a
template. Bootstrap installs the SSH routes when these local settings exist;
verification reports missing setup. Keys, authorisation and host trust remain
explicit commissioning steps. See [Air SSH access](docs/remote-access.md).

The Air's `work-image` and `personal-image` helpers transfer a clipboard image
to the selected VM and copy an inspection prompt for pasting into Codex. Images remain until explicitly cleaned. See
[remote image transfer and cleanup](docs/remote-access.md#images-in-remote-codex-sessions).

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
terminfo integration. All profiles manage a shared Starship prompt, zsh
completion, autosuggestions, syntax highlighting, fzf and zoxide for local
and SSH zsh sessions. Development VM helpers belong to the Air profile.
Ubuntu Bash and tmux prompt configuration belongs to `dev-machine`. Dock,
Finder, keyboard, trackpad, screenshot, power and Remote Login settings remain
operator-controlled as
described in [`docs/settings.md`](docs/settings.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Commissioning](docs/commissioning.md)
- [Windows development in Parallels](docs/windows-development.md)
- [Air SSH access](docs/remote-access.md)
- [TablePlus database access](docs/tableplus.md)
- [OneDrive access from the Air](docs/onedrive.md)
- [Local development TLS](docs/local-dev-tls.md)
- [OrbStack Docker API bridge](docs/orbstack-docker-api.md)
- [macOS settings policy](docs/settings.md)
