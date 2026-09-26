# Architecture

## Machine roles

```text
MacBook Air
  apps / TablePlus / Zed / Ghostty / shell tools / Tailscale
                   |
                   | SSH and database tunnels
                   v
work-mini or personal-mini
  macOS / Tailscale / Remote Login / OrbStack
                   |
                   v
work-dev or personal-dev
  source / SDKs / CLIs / development processes
```

The macOS machines are durable and the Ubuntu machines are disposable. Host
bootstrap therefore installs and verifies expected state but does not delete
unexpected applications. Profile changes must not be used as an uninstaller.

The work mini also hosts a separate Parallels Windows VM for .NET Framework,
ASP.NET and native Windows C++ projects. Its compilers, targeting packs and
application dependencies belong inside Windows. Mac bootstrap installs
Parallels; Windows commissioning remains manual. SQL Server containers belong
to the work mini's OrbStack runtime, with project-specific data and credentials.
See [Windows development](windows-development.md) for generic guest prerequisites.
Application-specific requirements and machine inventories belong in private
documentation.

## Air SSH routing

This repository owns the Air's SSH aliases, jump-host routing and macOS access
commissioning. Both local and remote access use the minis' full Tailscale DNS
names. The Air connects through each mini's Remote Login service to its local
OrbStack SSH endpoint. Work and personal use distinct Air keys and VM host-key
aliases. Local settings supply usernames and Tailscale names; they are never
committed. See [Air SSH access](remote-access.md).

`dev-machine` owns the corresponding Ubuntu machine names, Linux users and
development environment. Its remote-access guide consumes the aliases defined
here.

## OrbStack Docker API bridge

An opted-in work or personal VM uses SSH Unix-socket forwarding when a development process needs
direct access to the Docker API:

```text
Ubuntu process
  -> user-owned runtime socket in Ubuntu
  -> encrypted SSH forwarding
  -> ~/.orbstack/run/docker.sock on the matching mini
  -> OrbStack container

Container callback
  -> docker.orb.internal:<published port>
  -> OrbStack container
```

No Docker daemon or container runs in the Ubuntu VM, and no Docker TCP port or
guest `/var/run/docker.sock` link is created. The host owns OrbStack and SSH
authorization, `dev-machine` owns the user-level tunnel service, and each
project owns any consumer-specific environment variables.

The bridge implementation is generic rather than Testcontainers-specific.
Testcontainers is one consumer; Docker SDKs and IDE integrations may use the
same API path. Both profiles leave the bridge disabled until a workload requires it.
Each side records its opt-in in a private local flag; commissioning keeps the
work and personal keys separate.

## Local development TLS

Each mini is the sole issuer for its matching VM's local development
certificate. The mini stores a profile-specific CA private key, trusts the
public root in macOS and exports only the public root plus a reusable leaf
certificate and key. `dev-machine` installs those files into stable VM paths and
creates the password-protected PFX used by .NET.

Browser clients trust only the public root. A browser on the issuing mini uses
the system trust installed during commissioning; a browser on the Air needs an
explicit public-root import for each profile it accesses. Projects select PEM
or PFX files through command-scoped wrappers and never manage the CA.

## Installation managers

Homebrew Bundle owns formulae and casks declared in `config/Brewfile.*`. The
Mac App Store CLI installs the small set of Air applications available only
through the store.

Homebrew and the Mac App Store are the only application managers. Vendor
updaters may update their applications after installation, but the bootstrap
does not introduce additional package-manager stacks.

## Application configuration

All profiles install Starship, fzf, zoxide, fd, ripgrep, bat, zsh
autosuggestions and zsh syntax highlighting. A shared zsh fragment enables
Homebrew paths, tab completion, fzf key bindings and completion, zoxide
navigation, bat previews and the two zsh enhancements. These settings apply
to local and SSH zsh sessions on macOS. The Air also installs development VM
SSH and tmux helpers. Both minis install 1Password CLI; authentication remains
interactive and separate for work and personal accounts. Managed Air
Ghostty preferences come from a dedicated fragment referenced by
`~/.config/ghostty/config`; it selects Catppuccin light/dark themes and SSH
environment and terminfo integration. Existing configuration outside managed
fragments is preserved. Other application authentication, licences and
permissions stay interactive.

## Security boundary

The repository contains application names, public App Store IDs, settings
policy and non-secret authorization policy only. It never contains Apple,
Tailscale, VPN, 1Password, JetBrains, Parallels, SSH private keys or database
credentials. Work and personal bridge credentials and runtime sockets must
remain separate. Their local development CA keys, leaf keys and VM TLS state
must also remain separate.
