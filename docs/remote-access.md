# Air SSH access

`mac-bootstrap` owns the Air's OpenSSH aliases and routing, shell helpers and
macOS access commissioning. `dev-machine` owns the Ubuntu machine names, Linux
users and development environment. Ghostty, Zed and SSH clients use the same
aliases.

## Routing

Use Tailscale on the Air and both minis, with MagicDNS enabled. Connect through
each mini's full Tailscale DNS name both on the LAN and away:

```text
work-dev     -> work-mini over Tailscale     -> 127.0.0.1:32222 -> work-dev VM
personal-dev -> personal-mini over Tailscale -> 127.0.0.1:32222 -> personal-dev VM
```

The loopback endpoint is on the destination mini. OpenSSH `ProxyJump` reaches
it through macOS Remote Login. No public port forwarding or Tailscale client
inside Ubuntu is required. The Air does not need OrbStack or its local `orb`
SSH alias.

Tailscale attempts direct peer connections, including over the LAN, and falls
back to relays when necessary. Direct connectivity is not guaranteed; check
`tailscale status` or `tailscale ping` when diagnosing performance. See
[Tailscale connection types](https://tailscale.com/docs/reference/device-connectivity)
and [OrbStack SSH access](https://docs.orbstack.dev/machines/ssh).

## Local settings

On the Air, run these commands from the `Mac-Bootstrap` checkout to create the
settings file outside the repository:

```bash
mkdir -p ~/.config/mac-bootstrap
cp config/ssh/air.tsv.example ~/.config/mac-bootstrap/ssh-air.tsv
chmod 600 ~/.config/mac-bootstrap/ssh-air.tsv
```

Edit the file before applying it. Keep four tab-separated fields on each row:

1. Profile: `work` or `personal`.
2. The corresponding mini's full MagicDNS name, such as `work-mini.TAILNET.ts.net`.
3. The macOS account used for Remote Login on that mini.
4. The Linux account inside its primary Ubuntu machine.

Replace all uppercase placeholders. Use the full DNS names shown by Tailscale;
short names and `.local` names are not accepted. Both rows are required, with
distinct mini addresses. The supported username format is lowercase letters,
digits, underscores and hyphens, starting with a letter or underscore. The
file is parsed as data and is never sourced as shell code.

`bin/mac apply air` installs the routes when this file exists. If it is absent,
application installation continues with a commissioning warning; `verify`
reports the missing SSH setup. Invalid settings stop SSH installation before
any SSH configuration is changed.

To apply or verify only SSH configuration:

```bash
bootstrap/ssh.sh apply air
bootstrap/ssh.sh verify air
```

The managed fragment is `~/.ssh/mac-bootstrap/air.conf`. Bootstrap prepends a
marked include to `~/.ssh/config` and preserves configuration outside that
block. The four aliases are owned by bootstrap. The fragment uses separate
work/personal identity paths and VM host-key aliases, disables agent forwarding
and connection sharing for these aliases, and sets keepalive options.

Offline verification checks the local settings, generated fragment and include
placement. It does not evaluate other SSH configuration, execute `Match exec`
commands, contact machines, check credentials or establish host trust. Existing
SSH configuration can add options such as extra `IdentityFile` entries or port
forwards; review the effective configuration during commissioning.

## Authentication and commissioning

Run Air commands in a local terminal on the Air. Run mini commands in macOS
Terminal on the matching mini, signed in as the account used for Remote Login
and OrbStack. These steps do not run inside Ubuntu.

### 1. Prepare the Macs

Sign into Tailscale on all three Macs and confirm the minis have distinct,
stable names. On each mini, open System Settings > General > Sharing > Remote
Login and allow only the intended macOS account. Start OrbStack and provision
the matching Ubuntu machine through `dev-machine`.

### 2. Create the Air keys

On the Air, create separate passphrase-protected keys for work and personal:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/work-mini_ed25519 -C air-work-mini
ssh-keygen -t ed25519 -f ~/.ssh/personal-mini_ed25519 -C air-personal-mini
```

Run each `ssh-keygen` command separately and choose a passphrase when prompted.
If either key already exists, inspect it and decide whether to reuse that
role's key; do not overwrite it as part of routine commissioning. Never reuse
one key for both roles or copy a mini's generated OrbStack private key to the
Air. The passphrase protects the private key on disk; Keychain setup below
avoids typing it for every connection.

### 3. Authorise each public key on its mini

On the Air, display the personal public key:

```bash
cat ~/.ssh/personal-mini_ed25519.pub
```

Copy the entire line beginning `ssh-ed25519`, including the final comment.
Transfer only the `.pub` contents. The private key stays on the Air.

On the personal mini, in the intended macOS account, prepare both files:

```bash
mkdir -p ~/.ssh ~/.orbstack/ssh
chmod 700 ~/.ssh ~/.orbstack/ssh
touch ~/.ssh/authorized_keys ~/.orbstack/ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys ~/.orbstack/ssh/authorized_keys
```

These commands preserve existing entries. Open the macOS authorisation file:

```bash
nano ~/.ssh/authorized_keys
```

Paste the public key on a new line, leaving existing entries intact. Each key
must occupy one line, even if the editor visually wraps it. If the key is
already present, do not add it again. Save with **Ctrl+O**, then **Enter**;
exit with **Ctrl+X**.

Open the OrbStack authorisation file and add the same public key:

```bash
nano ~/.orbstack/ssh/authorized_keys
```

Save and exit in the same way. The first file permits the macOS jump-host
connection; the second permits the connection to OrbStack's SSH service.
Restart OrbStack on the mini after editing its authorised keys, as required
by the [OrbStack SSH documentation](https://docs.orbstack.dev/machines/ssh#authentication).

For the work mini, display the work public key on the Air:

```bash
cat ~/.ssh/work-mini_ed25519.pub
```

Repeat the mini commands and editing steps on the work mini using that key.
The destination paths are the same on both minis. Authorise only the matching
Air key on each mini, and keep these access keys separate from the VM's Docker
API bridge key.

### 4. Apply the Air routes and remember passphrases

On the Air, complete the [local settings](#local-settings), then run these
commands from the `Mac-Bootstrap` checkout:

```bash
bootstrap/ssh.sh apply air
bootstrap/ssh.sh verify air
```

To remember the key passphrases, open the Air's SSH configuration:

```bash
nano ~/.ssh/config
```

Add the following block immediately after
`# mac-bootstrap: end managed Air SSH routing`, before any other host settings.
Keep it outside the managed block; do not edit `~/.ssh/mac-bootstrap/air.conf`.

```sshconfig
Host work-mini work-dev personal-mini personal-dev
  AddKeysToAgent yes
  UseKeychain yes

Host *
```

The final `Host *` ends the scope of these settings so subsequent configuration
keeps its original scope. Save with **Ctrl+O**, **Enter**, then **Ctrl+X**.
Bootstrap preserves this block when routes are reapplied.

On the Air, run each command and enter the corresponding key's passphrase:

```bash
/usr/bin/ssh-add --apple-use-keychain ~/.ssh/personal-mini_ed25519
/usr/bin/ssh-add --apple-use-keychain ~/.ssh/work-mini_ed25519
```

These commands load the keys into the Air's SSH agent and store their
passphrases in its login Keychain. With Keychain unlocked, later connections
can load the keys without repeated passphrase prompts. The private keys remain
passphrase-protected on disk. See
[Apple's SSH Keychain and agent guidance](https://developer.apple.com/library/archive/technotes/tn2449/_index.html).

A VM connection authenticates twice: first to the mini's macOS account, then
to OrbStack. Without a loaded key or Keychain access, both connections may ask
for the same passphrase. Both SSH clients run on the Air; agent forwarding to
the mini is not needed. The tmux helpers use these same SSH settings.

To check which keys are loaded on the Air:

```bash
/usr/bin/ssh-add -l
```

### 5. Verify the connections

On the Air, inspect all four effective aliases:

```bash
ssh -G work-mini
ssh -G work-dev
ssh -G personal-mini
ssh -G personal-dev
```

Check the mini's full Tailscale name, users, jump host, identity file and VM
host-key alias. Each role must use only its own identity. If existing global
SSH settings add other identities or forwards, exclude the managed aliases
from those settings manually. These commands evaluate the user's full SSH
configuration, including any user-defined `Match exec` commands.

Verify each host fingerprint through trusted access to the corresponding mini
before accepting SSH host-key prompts. Then test these commands from the Air,
one at a time. Run `exit` in each remote shell to return to the Air before
testing the next connection:

```bash
ssh personal-mini
ssh personal-dev
ssh work-mini
ssh work-dev
```

Repeat VM access on the LAN and from another network. Use `ssh work-dev` or
`ssh personal-dev` in Zed. TablePlus connects through the mini aliases as
described in [database access](tableplus.md).

Usernames, Tailscale account names, private keys and host trust remain local.
Bootstrap never creates keys, modifies authorised keys or accepts host keys.

## tmux helpers on the Air

The Air profile installs the helpers. From the `Mac-Bootstrap` checkout on the
Air, apply the profile if needed:

```bash
bin/mac apply air
```

Open a new Ghostty tab with a local zsh session on the Air. Choose the command
for the destination and session you want:

| Action | Personal VM | Work VM |
|---|---|---|
| Create or attach to the default `dev` session | `personal-dev` | `work-dev` |
| Create or attach to a named session | `personal-dev my-session` | `work-dev my-session` |
| List existing sessions | `personal-devs` | `work-devs` |

For example, connect to the personal VM's default session:

```bash
personal-dev
```

With the default tmux key bindings, press **Ctrl+B**, release both keys, then
press **D** to detach and return to the Air. The session keeps running in the
VM. Run `personal-dev` again to reattach. VM restarts end its tmux sessions.

The helpers use the SSH aliases and the Air's Keychain settings above, so they
do not require separate keys or passphrase setup. If a helper is not recognised
after applying the profile, open a new local terminal tab on the Air. Session
listing may report no server running until the first session has been created.

## Shell experience on the minis

Use `ssh work-mini` or `ssh personal-mini` for the macOS host shell. Apply the
matching mini profile as the macOS account used for SSH, then reconnect with
an interactive zsh session. Both minis receive the same Starship prompt,
autosuggestions, syntax highlighting, tab completion, fzf bindings, bat
previews and zoxide navigation as the Air. Suggestions and navigation use
each machine's own history; bootstrap does not copy history or credentials.

Ghostty runs on the Air, so its Catppuccin theme, font and window preferences
continue to apply to the terminal displaying the SSH session. Its managed
[SSH integration](https://ghostty.org/docs/features/ssh) provides terminal
environment and terminfo support. Ghostty itself is not installed on the minis.
The Ubuntu shells reached through `work-dev` and `personal-dev` are configured
by `dev-machine`.

Both mini profiles install [1Password CLI](https://formulae.brew.sh/cask/1password-cli),
available as `op`. Check installation with `op --version`. Sign-in and any
1Password integration setup remain interactive on each mini, using only that
mini's work or personal account.

Both mini profiles also install
[CleanMyMac CLI](https://formulae.brew.sh/cask/cleanmymac-cli), available as
`cleanmymac` or `cmm`. Check installation with `cleanmymac --version`.
Cleanup remains an operator action; bootstrap only installs the tool.

## Images in remote Codex sessions

Run `work-image` or `personal-image` on the Mac holding the clipboard, in a
local terminal tab. The Air profile installs
[pngpaste](https://formulae.brew.sh/formula/pngpaste) and both shell commands:

```bash
bin/mac apply air
```

Open a new zsh session after applying the profile. No separate dependency
installation is needed.

Copy an image, then choose its destination explicitly:

```bash
work-image
personal-image
```

With no arguments, each command captures the current image as a PNG and
transfers it through the matching SSH alias. Run only the command for the intended VM. Ubuntu must have
Python 3.8 or later, as provided by `dev-machine`. No clipboard service or X11
server is needed in Ubuntu.

Images live in `~/.local/share/dev-machine/images/` inside the selected VM,
with unique `dev-image-<identifier>.png` names. The directory has mode `700`
and image files have mode `600`. The helper refuses symlinked directory
components and directories writable by other users.

After a successful upload, the helper prints the remote path and replaces the
Mac clipboard with `Inspect this image: <remote path>`. Paste that text into
Codex in the selected VM, including an existing tmux session. This asks Codex
to open the transferred file; it does not invoke Codex's image-paste shortcut.
Copy the original image again before sending it to another VM.

Capture or transfer failures leave the clipboard unchanged. If the upload
succeeds but the clipboard update fails, use the printed path. Temporary
local captures are removed when the helper exits normally or reports an error.

Images do not expire automatically, so resumed sessions can still use them.
Clean one VM explicitly, optionally selecting images older than 30 days:

```bash
work-image clean
personal-image clean --older-than 30d
```

Cleanup shows the VM alias, full directory, selected file count and total size.
Type that exact VM alias to confirm. Age uses the image file's modification
time; `Nd` accepts a positive whole number of days. Only regular files with
the helper's naming pattern are selected. Unrelated files, symlinks,
subdirectories and images uploaded after the preview are retained. Cleanup
stops if a selected file changes before confirmation. Removing an image can
prevent a resumed session from opening it again.

Both zsh functions call the shared executable at
`~/.config/mac-bootstrap/dev-image`. A macOS shortcut can invoke it with
`send work-dev` or `send personal-dev`. Ensure Homebrew's `bin` directory is
on the shortcut's `PATH`. Bootstrap does not assign a global keyboard shortcut.

## Browser access to VM services

After commissioning SSH and browser CA trust, forward a specific development
port from the Air. For a work VM HTTPS server listening on `127.0.0.1:3000`:

```bash
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:3000:127.0.0.1:3000 work-dev
```

Keep that terminal open and browse to `https://localhost:3000` on the Air. The
service must already be running in Ubuntu and use the commissioned certificate.
Stop the forward with Ctrl-C when finished. If the local port is occupied,
choose another local port and use it in the browser URL.

To reach a personal VM server concurrently, use a separate local port:

```bash
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:3001:127.0.0.1:3000 personal-dev
```

Browse to `https://localhost:3001` with the personal public root trusted.
Project-specific ports and virtual-host names remain project configuration;
bootstrap does not create persistent application forwards.

## Configuration failures

The installer rejects symlinked paths, writable-by-others files/directories and
ACLs on the inspected SSH/settings paths. Inspect the reported path before
retrying; bootstrap does not repair permissions or replace symlink targets.
Keep the settings and managed files owned by the intended Air user. Incomplete
or duplicate managed blocks in `~/.ssh/config` also require manual correction.

## Finder access to VM files

The Air profile installs Mountain Duck and creates work/personal SFTP bookmarks
from the same local SSH settings. Follow [Mountain Duck commissioning](mountain-duck.md)
for first connection, connection modes and Finder checks. The minis need no additional
SMB share for this route.
