# Acceptance checklist

Use the [end-to-end setup guide](setup.md) for installation commands in order.
This page checks the result; it is not a second installation route. Record
machine-specific results and deliberately deferred work privately, outside Git.

## Every Mac

- [ ] macOS updates and FileVault are complete; recovery material is stored privately.
- [ ] The matching profile was applied as the normal user.
- [ ] Application sign-ins, licences and required permissions are complete.
- [ ] Tailscale is connected; the minis have distinct full MagicDNS names.
- [ ] A new terminal loads the managed Starship/shell configuration.
- [ ] `bin/mac verify PROFILE` passes from the Mac-Bootstrap checkout (`air`, `personal-mini` or `work-mini`).

A verifier checks installed/configured state. It does not prove provider login,
application permissions or every live connection. Review its warnings too.

## Each mini and VM

- [ ] Remote Login permits the intended macOS account.
- [ ] OrbStack is running; `orbctl doctor` and `docker compose version` pass.
- [ ] `personal-dev` or `work-dev` has the matching Linux profile and expected resources.
- [ ] The correct mini's TLS handoff was imported and `local-dev-tls verify` passes in Ubuntu.
- [ ] Temporary TLS handoffs were removed after verification; each CA private key remains on its issuing mini.
- [ ] Each opted-in bridge passes `orbstack-docker-api verify`; disabled profiles have no bridge state or marked host authorisation.
- [ ] The guest verifier was run from the intended revision of Dev-Machine, with `--skip-ai` only if setup deliberately skipped AI tools.
- [ ] VM Git identity/authentication, needed provider logins and project configuration are complete or explicitly deferred.
- [ ] At least one real project's restore/build/test, database and HTTPS workflow has passed.
- [ ] Unattended sleep/wake and restart behaviour is understood, including FileVault's possible local unlock requirement.

The [Dev-Machine acceptance checklist](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/commissioning.md)
adds tool-specific, storage and recovery checks. Windows/Parallels remains a
separate work capability; commission it before relying on Windows builds.

## Air access

- [ ] The App Store applications are installed; final verification ran without `--skip-app-store`.
- [ ] `ssh-air.tsv` records both minis and their actual macOS/Linux users.
- [ ] Work and personal use different passphrase-protected Air keys.
- [ ] Each Air public key is authorised in both SSH files on its matching mini; OrbStack was restarted after changes.
- [ ] Host fingerprints were verified, and all four SSH aliases reach the expected account.
- [ ] Keychain/agent setup avoids repeated passphrase prompts.
- [ ] Zed opens a remote project on each VM; its terminal reports the correct host and project path.
- [ ] Ghostty/tmux sessions survive disconnect and reattach.
- [ ] Mountain Duck shows separate work/personal Finder locations, with a verified file transfer through each.
- [ ] Public roots are trusted by the intended browser; an HTTPS service works through an explicit Air SSH forward.
- [ ] TablePlus connections use the matching mini and actual database port when needed.
- [ ] Work OneDrive sharing and Air application sync selections are complete where used.
- [ ] Remote connections were tested both on the LAN and from another network.

## Maintenance and troubleshooting

Rerunning the profile apply should preserve private state and unrelated settings.
Quit Mountain Duck/Cyberduck before applying changed bookmarks. Do not rebuild
a primary VM just to test a document; that is a separate destructive recovery
exercise after backups and source changes are recoverable elsewhere.

If Google Drive cannot create its configuration, run
`bootstrap/google-drive.sh apply air` from Mac-Bootstrap. It prepares the
user-owned `~/Library/Application Support/Google` directory, repairing only
that directory's ownership with administrator approval if needed. It preserves
contents and does not change `/Library/Application Support/Google`.

Use the relevant reference for failures:

- [Air SSH and host trust](remote-access.md)
- [Mountain Duck](mountain-duck.md)
- [TLS and renewal](local-dev-tls.md)
- [Optional Docker API bridge](orbstack-docker-api.md)
- [TablePlus](tableplus.md)
- [OneDrive](onedrive.md)
- [Windows development](windows-development.md)
- [Settings policy](settings.md)
