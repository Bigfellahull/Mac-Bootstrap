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

Create the Air's settings file outside the repository:

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

1. Sign into Tailscale on all three Macs and confirm the minis have distinct,
   stable names. Enable macOS Remote Login for only the intended account on
   each mini. Start OrbStack and provision the matching Ubuntu machine through
   `dev-machine`.
2. Create separate passphrase-protected Air keys at
   `~/.ssh/work-mini_ed25519` and `~/.ssh/personal-mini_ed25519`. Never reuse one
   key for both roles, or copy a mini's generated OrbStack private key to the
   Air. Key generation remains manual.

   For new keys, run these commands on the Air and choose a passphrase for each:

   ```bash
   mkdir -p ~/.ssh
   ssh-keygen -t ed25519 -f ~/.ssh/work-mini_ed25519 -C air-work-mini
   ssh-keygen -t ed25519 -f ~/.ssh/personal-mini_ed25519 -C air-personal-mini
   ```

   If either file already exists, inspect it and decide whether to reuse that
   role's key; do not overwrite it as part of routine commissioning.
3. On each mini, authorise only its corresponding Air public key in the intended
   macOS account's `~/.ssh/authorized_keys` and
   `~/.orbstack/ssh/authorized_keys`. Preserve existing entries. Restart OrbStack
   after changing its authorised keys, as its documentation requires. Keep
   these Air access keys separate from the VM's Docker API bridge key.
   Transfer the contents of the matching `.pub` file, never the private key.
4. Apply the Air SSH configuration, then inspect all four effective aliases:

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
5. Verify each host fingerprint through trusted access to the corresponding
   mini before accepting SSH host-key prompts. Test `ssh work-mini`,
   `ssh work-dev`, `ssh personal-mini` and `ssh personal-dev`. Repeat VM access
   on the LAN and from another network.
6. Use `ssh work-dev` or `ssh personal-dev` in Zed. In Ghostty, the `work-dev`
   and `personal-dev` shell helpers attach to tmux; an optional argument selects
   a session. `work-devs` and `personal-devs` list sessions. TablePlus connects
   through the mini aliases as described in [database access](tableplus.md).

Usernames, Tailscale account names, private keys and host trust remain local.
Bootstrap never creates keys, modifies authorised keys or accepts host keys.

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
