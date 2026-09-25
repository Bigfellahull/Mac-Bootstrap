# Commissioning guide

Use this as the entry point for a new Mac. Complete each mini independently,
then commission the Air connections to both. The Air applications can be
installed before the minis are ready.

Commands below run as the normal macOS user from the `Mac-Bootstrap` checkout
unless another location is stated. Replace `PROFILE` with `air`, `work-mini` or
`personal-mini`. `dev-machine` uses `work` and `personal` instead.

## 1. Before running scripts

- Complete macOS setup as a new machine and apply available updates.
- Enable FileVault and store its recovery material outside the repositories.
- Install Apple's Command Line Tools with `xcode-select --install`; full Xcode
  is not required.
- Install Homebrew using the [official instructions](https://brew.sh), then
  follow its shell setup instructions. Do not run bootstrap with `sudo`.
- Clone or transfer this repository and open a terminal in its root directory.
- On the Air, sign into the Mac App Store, or use `--skip-app-store` initially.
- Keep work and personal accounts, credentials and runtime state separate.

No host language SDK, Docker Desktop, Colima or Podman is needed. Application
package installers may request administrator approval while Homebrew runs.

## 2. Install the macOS profile

```bash
bin/mac plan PROFILE
bin/mac apply PROFILE
```

On the Air, App Store installation can be deferred:

```bash
bin/mac apply air --skip-app-store
```

After signing into the store, rerun `bin/mac apply air` without that flag.

`apply` installs the declared applications, shared macOS shell configuration
and profile-specific configuration. It does not
sign into services, activate licences, grant permissions, enable Remote Login,
create SSH keys, accept host keys, initialise TLS or create Ubuntu machines.
Missing Air SSH settings produce a warning and leave SSH configuration alone;
complete them in step 5. A full `verify` can fail until commissioning is done.

## 3. Complete application setup on every Mac

- Open 1Password, Tailscale and CleanMyMac. Sign in or activate each
  application as required.
- Approve the applications' required privacy and network-extension permissions.
- Enable Tailscale MagicDNS and give the minis stable, distinct names:
  `work-mini` and `personal-mini`. Record their full Tailscale DNS names locally.
- Choose Finder, Dock, keyboard, screenshot and other preferences using the
  [settings policy](settings.md). These are not restored by bootstrap.

## 4. Commission each mini and its Ubuntu machine

1. Enable Remote Login for only the intended macOS account. Keep its username
   locally for the Air settings.
2. Open OrbStack, complete any licence/setup prompts and confirm its CLI works:

   ```bash
   orbctl version
   orbctl doctor
   docker context show
   docker compose version
   ```

3. Initialise and verify the matching local development CA:

   ```bash
   bin/local-dev-tls init PROFILE
   bin/local-dev-tls verify PROFILE
   ```

   These commands are for mini profiles only. CA creation and macOS trust are
   explicit actions; trust installation may prompt for administrator access.
4. Clone or transfer `Dev-Machine` to this mini. Follow its
   [README setup walkthrough](https://github.com/Bigfellahull/Dev-Machine/blob/main/README.md#start-here)
   to review local resource settings, create the matching Ubuntu machine and
   complete its Git, provider authentication and database setup. Run host
   lifecycle commands from that checkout and Ubuntu commands inside the VM.
5. After the VM exists, export and import the profile-matched TLS handoff using
   [local development TLS](local-dev-tls.md). Remove the exact temporary
   handoff from both ends after verification. The CA private key stays on its
   issuing mini.
6. On **work only**, commission the dedicated VM-to-Mac key and restricted
   authorisation in the [Docker API bridge guide](orbstack-docker-api.md).
   Follow the linked guest guide to initialise, start and verify its service.
   This key is separate from the Air's interactive SSH keys.
7. On **work only**, activate Parallels and create or restore its Windows VM
   separately from OrbStack provisioning. Install Git for Windows, rustup and
   Visual Studio 2026 Build Tools with the x64 C++ workload. Share the required
   transfer directory through a mapped Windows drive and make it accessible
   from the OrbStack guest. Keep its location in local settings. Then follow
   [Dev-Machine's Windows native build commissioning](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/windows-builds.md):
   run `orbstack-windows-build provision` and `orbstack-windows-build verify`
   inside work Ubuntu to install and verify the pinned Rust x64 target.
   Native project helpers invoke `mac prlctl` through OrbStack; the restricted
   Docker API SSH key remains for socket forwarding only and needs no new grant.
   Follow [Windows development in Parallels](windows-development.md) for
   additional .NET, web and native application prerequisites. Keep project
   dependencies, package access and runtime settings in private documentation.
   Use the configured Parallels UNC share for tools that support it; mapped
   drive letters can change between sessions.
8. On **work only**, sign into OneDrive and select the folders to sync. Follow
   [OneDrive access from the Air](onedrive.md) to download files locally and
   commission macOS File Sharing.
9. Configure power and network behaviour for unattended use using the
   [settings policy](settings.md). Test sleep, wake, restart and remote access;
   bootstrap does not configure them or bypass FileVault unlock requirements.

The personal Docker API bridge remains disabled. `dev-machine` currently
installs its guest helper and service only on work, so changing the host policy
alone cannot enable a personal bridge.

## 5. Commission the Air

- Google Drive needs a user-owned `~/Library/Application Support/Google`
  directory. Bootstrap prepares it before installation and checks it again
  afterwards. If the directory is owned by root, bootstrap changes only that
  directory's owner and group to the current user, requesting administrator
  approval when needed. It preserves existing contents and leaves the
  system-wide `/Library/Application Support/Google` directory unchanged.
  To repeat this step, run `bootstrap/google-drive.sh apply air`.
  Verification checks ownership and access without changing them. See
  [Google's configuration-folder guidance](https://support.google.com/drive/answer/2565956?hl=en-GB).
- Restart Ghostty and confirm its theme, Starship prompt and shell helpers load.
- Activate CleanShot X and grant its required screen-recording permissions.
- Complete licences and permissions for other Air apps as required. Sign into
  Google Drive, Teams and other services you use; select sync folders
  locally. App installation does not restore their settings or data.
- Follow [Air SSH access](remote-access.md) to fill in
  `~/.config/mac-bootstrap/ssh-air.tsv`, create separate work/personal Air keys,
  authorise their public keys on the matching minis and verify host fingerprints.
- Apply and verify the routes with `bootstrap/ssh.sh apply air` and
  `bootstrap/ssh.sh verify air`. Both mini destinations must be present in the
  local settings, even if one is temporarily offline.
- Follow the [Keychain setup](remote-access.md#4-apply-the-air-routes-and-remember-passphrases)
  on the Air to load both keys and avoid repeated passphrase prompts.
- Configure Zed and Ghostty to use `work-dev` and `personal-dev`. Test the
  [tmux helpers](remote-access.md#tmux-helpers-on-the-air) with default and named
  sessions, plus `work-devs` and `personal-devs` session listings.
- Configure [TablePlus database tunnels](tableplus.md) through the mini aliases.
- Connect to the work mini's [OneDrive share](onedrive.md#connect-from-the-air)
  in Finder and test file access and cloud synchronisation.
- Import and trust each required **public** `root-ca.pem` through Keychain
  Access. Never copy a CA private key or reusable leaf key to the Air. If a
  browser does not use macOS roots, configure its public-root trust separately.
- Use the explicit [browser port forward](remote-access.md#browser-access-to-vm-services)
  when opening a VM development server on the Air. Certificate trust alone
  does not provide a network connection.

## 6. Final verification

On each Mac, from `Mac-Bootstrap`:

```bash
bin/mac verify PROFILE
```

Resolve failures, and review warnings even when the command exits successfully.
Remote Login may need a manual check if administrator access was unavailable.
SSH verification checks managed configuration, not authentication or network
reachability. Application sign-ins, licences and privacy permissions also need
manual checks. Finish Air verification without `--skip-app-store`.

Inside each Ubuntu VM, from `~/code/dev-machine`, run `bootstrap/verify.sh` as
described in its commissioning guide. Resolve required commissioning warnings
there too; a successful exit code alone is not proof of completion.

Test real SSH and database connections over Tailscale on the LAN and from
another network. Validate HTTPS from the browser clients and, on work, test a
real Docker API consumer with cleanup enabled.

Rerun the Mac profile's `apply` and `verify`; they should need no configuration
repair. Test representative development workflows, backups and restores using
the `dev-machine` checklist. Do not rebuild a primary VM merely to check the
documentation: its destructive recovery test requires important state to be
saved elsewhere first.
