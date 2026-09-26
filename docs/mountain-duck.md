# VM files in Finder

The Air profile installs Mountain Duck and manages two SFTP bookmarks,
`work-dev` and `personal-dev`. Each opens `/home/<linux-user>` using its own Air
SSH key and existing mini jump host. No Mountain Duck installation or additional
file server is needed on the minis or Linux guests. The native Linux filesystem
remains the source of truth; use the mounted folders for file transfers and keep
builds, Git commands and development tools in the VM.

## Provisioning

Complete [Air SSH routing](remote-access.md) first, including the private local
`~/.config/mac-bootstrap/ssh-air.tsv` file. Confirm both `sftp work-dev` and
`sftp personal-dev` work. Host identities must be verified before accepting them.

Quit Mountain Duck and Cyberduck before applying changed bookmarks (they share
the same bookmark store). Run `bin/mac apply air`, or for this component only:

```sh
brew install --cask mountain-duck
bootstrap/mountain-duck.sh apply air
bootstrap/mountain-duck.sh verify air
```

The component manages two fixed UUID `.duck` files in
`~/Library/Group Containers/G69SCX94XU.duck/Library/Application Support/duck/Bookmarks`.
It preserves other bookmarks and app-specific fields in its own bookmarks.
Connection fields are managed: edit the local SSH settings and reapply instead
of changing the server, username, key or initial path in the app. Verification
checks configuration offline; it does not establish a Finder mount or validate
licensing, permissions or connectivity. Missing SSH settings defer creation at
apply time and fail verification. Mini profiles leave this component alone.

## First connection

Open Mountain Duck from Applications and complete its trial/licence prompts.
Connect both bookmarks from its menu-bar icon and confirm the home directories
appear in Finder. The default **Integrated** mode provides native Finder locations
and downloads files on demand. Alternatively, choose **Online** in the bookmark
for a network-volume workflow without persistent offline synchronization. Enable
the Finder extension if macOS requests it; licences and privacy prompts are manual.

The server fields intentionally contain the SSH aliases, not their resolved
addresses. Mountain Duck supports `HostName`, `IdentityFile`, `User` and
`ProxyJump` from SSH configuration. If prompted for a host fingerprint, verify
it against the correct mini or guest; do not accept an unfamiliar fingerprint.
If prompted for a private-key passphrase, unlock that key yourself.

Create a small disposable file in each mount and check it from the corresponding
SSH session, then copy a file back to the Air. Confirm work and personal content
appear in their respective mounts. In Mountain Duck preferences, enable its
login item and Save Workspace if you want connected volumes restored after
login. These application preferences are selected interactively.

Tailscale, the destination mini and its VM must be running for live file access.
Finder integration handles files; it does not forward browser links launched
inside an SSH session to the Air.

References: [SFTP and SSH config](https://docs.cyberduck.io/protocols/sftp/),
[bookmark location](https://docs.cyberduck.io/mountainduck/interface/),
[Online mode](https://docs.cyberduck.io/mountainduck/connect/online/).
