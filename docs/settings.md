# macOS settings policy

The bootstrap does not copy or restore macOS preference databases. A setting is
managed only when its value and profile scope are explicitly declared and a
read-only verification check exists.

## Managed settings

Air:

- OpenSSH uses managed `work-mini`, `work-dev`, `personal-mini` and `personal-dev` aliases, with Tailscale jump-host routing configured from local settings. See [Air SSH access](remote-access.md).
- Ghostty loads a managed fragment selecting Catppuccin Frappe in dark mode, Catppuccin Latte in light mode, and the declared window, cursor and background preferences.
- Ghostty enables `ssh-env` and `ssh-terminfo` so clean remote machines receive compatible terminal metadata. Apply preserves configuration outside the managed fragment; verify is read-only.
- Starship uses the shared prompt configuration for local zsh sessions. It is not installed on the minis.

## Unmanaged settings

The bootstrap does not change the following operator-controlled settings.

Common settings:

- Finder filename extensions, path bar and status bar
- Dock size, auto-hide, recent applications and layout
- Screenshot folder and format
- Keyboard repeat and automatic correction
- Menu-bar contents
- Firewall and FileVault configuration

Air settings:

- Tap-to-click and dragging
- Battery and display behaviour
- Default browser

Mini settings:

- Stable hostname
- Remote Login
- Sleep prevention while connected to power
- Wake for network access
- Restart after power failure

FileVault recovery keys, Remote Login authorization and privacy permissions are
security-sensitive commissioning steps. They must never be written to the
repository.
