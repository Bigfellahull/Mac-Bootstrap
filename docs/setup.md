# Set up the Macs, VMs and development tools

This is the end-to-end installation order. Keep this page open while working;
the linked reference pages explain options and troubleshooting. Complete the
personal mini and its VM first, repeat for work, then connect the Air to both.
Air application installation can happen earlier. Existing machines can resume
at the first unfinished step; do not recreate a working VM.

## Route through this guide

| Steps | Where | Outcome |
|---|---|---|
| 1–3 | Each Mac | Applications, accounts and network ready |
| 4–6 | Each mini, then its VM | Ubuntu bootstrapped, local HTTPS imported |
| 7 | Either mini and its VM, if opted in | Optional Docker API bridge |
| 8 | Each VM | Git, tools, repositories and database setup |
| 9–11 | Air and each mini | Separate SSH keys and working VM access |
| 12–14 | Air | Zed, terminal, Finder, browser and database clients |
| 15 | Applicable machines | Optional Windows, storage and app setup |
| 16 | All machines | Final checks |

Every command block says where it runs. Run commands one block at a time and
read the result before proceeding. `exit` leaves a VM/SSH shell. Profile names
are different in the two repositories:

| Mac | Mac-Bootstrap profile | Dev-Machine profile | Ubuntu name |
|---|---|---|---|
| Air | `air` | — | — |
| Personal mini | `personal-mini` | `personal` | `personal-dev` |
| Work mini | `work-mini` | `work` | `work-dev` |

The examples use `~/Downloads/Mac-Bootstrap` and `~/Downloads/Dev-Machine` on
macOS. Substitute your checkout location if different. The seeded guest copy
is `~/code/dev-machine` (lowercase); a separate Git clone named `Dev-Machine`
is a different directory on Linux. Always know which revision you are using.
Keep hostnames, user identities, keys and tokens in local settings, not Git.

## 1. Prepare each Mac

**On each Mac:** finish macOS setup and updates, enable FileVault and store the
recovery material privately. Install Command Line Tools:

```bash
xcode-select --install
```

Finish the installer. Install Homebrew using [brew.sh](https://brew.sh) and its
printed shell setup instructions. Then confirm:

```bash
xcode-select -p
brew --version
```

Obtain Mac-Bootstrap, using an existing checkout if you already have one:

```bash
mkdir -p ~/Downloads
cd ~/Downloads
git clone https://github.com/Bigfellahull/Mac-Bootstrap.git
cd Mac-Bootstrap
```

A downloaded archive also works, but is not a Git checkout and cannot be
committed or updated with `git pull`. No host language SDK is required.

## 2. Install the matching Mac profile

**On each Mac, in Mac-Bootstrap:** choose exactly the matching pair.

```bash
# Personal mini
bin/mac plan personal-mini
bin/mac apply personal-mini
```

```bash
# Work mini
bin/mac plan work-mini
bin/mac apply work-mini
```

```bash
# Air
bin/mac plan air
bin/mac apply air
```

Use the normal macOS account, not `sudo`. Individual installers may ask for
administrator approval. On the Air, sign into the App Store first; if deferring
it, use `bin/mac apply air --skip-app-store` and rerun without the flag later.
Quit Mountain Duck/Cyberduck before an Air apply that changes their bookmarks.

**Expected:** installation finishes. Missing Air SSH settings are expected at
this point. Full verification can also report uncommissioned TLS or an opted-in
Docker API bridge; those are handled below. Apply does not sign into apps,
create VMs or establish certificate trust.

## 3. Finish the shared Mac setup

**On each Mac:** open 1Password, Tailscale and CleanMyMac. Complete sign-ins,
licences and required permissions. Restart the terminal to load the managed
shell settings. Enable Tailscale MagicDNS and choose distinct stable names for
the minis. Record each mini's full Tailscale DNS name privately.

**On each mini:** enable System Settings → General → Sharing → Remote Login
for the intended macOS account. Record `whoami` from a macOS terminal. Open
OrbStack and finish its setup/licence prompts, then check:

```bash
orbctl version
orbctl doctor
docker context show
docker compose version
```

**Expected:** OrbStack and Compose work on the mini. The Air does not need
OrbStack. Choose sleep/power behaviour for unattended access in System Settings;
see [settings policy](settings.md). FileVault can require local unlock after a
restart, so test that operationally.

## 4. Create and bootstrap one Ubuntu VM

**On the personal mini:** obtain Dev-Machine and prepare its local settings.
Use an existing checkout instead of cloning over it.

```bash
cd ~/Downloads
git clone https://github.com/Bigfellahull/Dev-Machine.git
cd Dev-Machine
mkdir -p config/local
if [ ! -e config/local/host.env ]; then
  cp config/host.env.example config/local/host.env
fi
nano config/local/host.env
```

Choose memory/disk limits for this mini before continuing. Defaults are 24 GB
RAM and a 300 GB disk ceiling; the external-drive setting is only for exports.
If using private work MCP servers, add their ignored local configuration before
creation as described in [Dev-Machine's AI reference](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/bootstrap.md#mcp-servers-and-authentication).

**On the personal mini, in Dev-Machine:**

```bash
bin/dev create personal --dry-run
bin/dev create personal
orb -m personal-dev
```

**On the work mini:** repeat the clone/settings steps there, then use:

```bash
bin/dev create work --dry-run
bin/dev create work
orb -m work-dev
```

`create` also runs bootstrap, handles required Ubuntu reboots and seeds
`~/code/dev-machine`. Do not run a second bootstrap just because creation has
finished. If the VM exists but provisioning failed, inspect the error and use
`bin/dev provision personal` or `bin/dev provision work` on its mini to resume.
Add `--skip-ai` only if you intentionally want to omit AI setup.

**Inside the newly opened Ubuntu shell:**

```bash
whoami
hostname
cat ~/.config/dev-machine/profile
cd ~/code/dev-machine
bootstrap/verify.sh
```

Record the Linux username for Air SSH settings. The profile must match its mini.
Use `--skip-ai` on verification if creation used it. Resolve tool-installation
failures before proceeding; authentication, TLS and opted-in bridge commissioning
warnings are expected until the later steps. Use `exit` to return to macOS.

## 5. Issue and transfer the matching HTTPS certificate

**In a macOS terminal on the matching mini:** select its role. These variables
belong to this terminal only; repeat them if you open a new one.

```bash
role=personal  # use work on the work mini
vm="$role-dev"
mac_profile="$role-mini"
handoff="/private/tmp/$role-local-dev-tls"
guest_handoff="/tmp/$role-local-dev-tls"
cd ~/Downloads/Mac-Bootstrap
bin/local-dev-tls init "$mac_profile"
bin/local-dev-tls verify "$mac_profile"
bin/local-dev-tls export "$mac_profile" "$handoff"
```

Approve the trust prompt locally. Use a fresh handoff path; if the named folder
already exists, inspect it and choose a new matching pair of paths rather than
overwriting it. The export includes the public root and leaf key, never the CA
private key.

**In the same mini terminal:** transfer into a new private directory in its VM.

```bash
orb -m "$vm" sh -c 'umask 077; mkdir "$1"' sh "$guest_handoff" &&
  COPYFILE_DISABLE=1 tar --no-xattrs -C "$handoff" -cf - . | orb -m "$vm" tar -xf - -C "$guest_handoff"
orb -m "$vm"
```

## 6. Import and verify HTTPS inside Ubuntu

**Inside personal Ubuntu:**

```bash
local-dev-tls import /tmp/personal-local-dev-tls
local-dev-tls verify
local-dev-tls paths
```

**Inside work Ubuntu:** use `/tmp/work-local-dev-tls` instead. If you chose
another temporary path in step 5, use that exact path here. Import may request
sudo for the public root trust. It creates the stable PEM/PFX files for projects.

After verification succeeds, remove only the temporary handoff inside this VM:

```bash
# Personal example; use the exact work handoff on work.
rm -r -- /tmp/personal-local-dev-tls
exit
```

**Back in the same mini terminal from step 5:**

```bash
rm -r -- "$handoff"
```

Keep the issuing mini's CA state. Renewal and framework wrappers are documented
in [TLS reference](local-dev-tls.md) and [guest TLS paths](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/local-dev-tls.md#project-wrappers).

## 7. Opt into the Docker API bridge if needed

Skip this section on either profile unless a workload needs direct Docker API
access, for example Testcontainers or Aspire. Both profiles default to disabled;
ordinary PostgreSQL access and database commands do not need it.

**On the matching mini:** set its flag (use `personal-mini` on personal):

```bash
mkdir -p ~/.config/mac-bootstrap
(umask 077; printf 'enabled\n' > ~/.config/mac-bootstrap/docker-api-bridge.work-mini)
chmod 600 ~/.config/mac-bootstrap/docker-api-bridge.work-mini
```

**Inside its Ubuntu VM, from an up-to-date Dev-Machine checkout:**

```bash
mkdir -p ~/.config/dev-machine
(umask 077; printf 'enabled\n' > ~/.config/dev-machine/docker-api-bridge)
chmod 600 ~/.config/dev-machine/docker-api-bridge
orb/docker-api.sh
```

For an already commissioned work bridge, create both flags before applying the
module, then run `orbstack-docker-api verify`; keep its existing key. For a new
bridge continue below. The commands show work; on personal substitute
`personal-dev` and the marker `orbstack-docker-api-personal-mini` throughout.

**On the work mini:** confirm the socket and display its host-key fingerprint.

```bash
test -S "$HOME/.orbstack/run/docker.sock"
stat -f 'owner=%Su mode=%Lp path=%N' "$HOME/.orbstack/run/docker.sock"
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
whoami
```

Record the Mac username and absolute socket path. Transfer the public host key
through this already trusted local OrbStack connection:

```bash
awk '{print "host.orb.internal " $1 " " $2}' /etc/ssh/ssh_host_ed25519_key.pub \
  | orb -m work-dev sh -c 'umask 077; cat > "$HOME/work-mini-known-hosts"'
orb -m work-dev
```

**Inside work Ubuntu:** compare the fingerprint with the one just displayed
on the mini, then initialise. Replace `MAC_USER` and `MAC_SOCKET` with the values
recorded above, retaining quotes around the socket path.

```bash
ssh-keygen -lf ~/work-mini-known-hosts
orbstack-docker-api init host.orb.internal MAC_USER "MAC_SOCKET" ~/work-mini-known-hosts
orbstack-docker-api public-key
```

Copy only the printed public key. **On the work mini**, preserve existing SSH
entries and add it to `~/.ssh/authorized_keys` with this exact restriction prefix
and comment, substituting its public key material:

```text
restrict,port-forwarding,command="/usr/bin/false" ssh-ed25519 PUBLIC_KEY_MATERIAL orbstack-docker-api-work-mini
```

```bash
mkdir -p ~/.ssh
touch ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
nano ~/.ssh/authorized_keys
```

Do not add a duplicate marker or reuse an Air key. **Inside work Ubuntu:**

```bash
orbstack-docker-api start
orbstack-docker-api verify
```

**Expected:** the API probe passes. This dedicated key grants Docker-engine
control through forwarding; keep its private key in its matching VM. See the
[bridge reference](orbstack-docker-api.md) for restrictions and recovery.

## 8. Set up the VM tools and first project

**Inside each Ubuntu VM, independently:** configure Git and GitHub access.
Replace the identity placeholders before running.

```bash
git config --global user.name "Your Name"
git config --global user.email "private-address-for-this-profile"
gh auth login
gh auth status
mkdir -p ~/code
```

Select the intended Git transport during login. For SSH repository URLs, first
install or create this profile's Git-host key and authorise its public key with
the Git provider. Air-to-VM keys do not grant VM-to-GitHub access. Test a clone
and fetch of a repository you are entitled to access, under `~/code`.

Open `codex`, `claude` and `grok` one at a time and complete each sign-in if using
them. Exit each before opening the next. If a login link opens on the mini,
copy the displayed link into the Air browser when the provider supports that
flow; SSH does not automatically open the Air browser. A callback to localhost
may need the provider's documented remote/device flow or an SSH forward.

**Personal Ubuntu:** run `railway login`, then `railway whoami`. Configure the
intended project context and authenticate Linear/MCP integrations where used.
**Work Ubuntu:** run `az login`, choose the intended account/subscription and
check `az account show`; use `dotnet restore --interactive` for private feeds.
Private work SSH keys and provider logins may be deferred until needed.

For each project, restore local secrets from its private source, inspect its
runtime pins and follow its dependency/restore instructions. In particular,
.NET `global.json` may require an SDK beyond the global default. Use the shared
TLS files from step 6 in its development wrapper.

To use the supplied database helpers, **inside Ubuntu**:

```bash
mkdir -p ~/.config/dev-machine
if [ ! -e ~/.config/dev-machine/db.env ]; then
  cp ~/code/dev-machine/docker/db.env.example ~/.config/dev-machine/db.env
fi
chmod 600 ~/.config/dev-machine/db.env
nano ~/.config/dev-machine/db.env
```

Replace the enabled engines' placeholder credentials before starting anything.
Give concurrently running projects distinct published ports/private env files.
**From the project's directory in Ubuntu**, start only what it needs:

```bash
db --help
db start postgres
db status
db connection postgres
```

Personal supports PostgreSQL; work also supports SQL Server and Redis. If a
project already supplies its own Compose setup, follow that instead of starting
a duplicate database. Test the actual app-to-database connection. Refer to the
[VM setup guide](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/setup.md)
for the full profile-specific tool checklist and database networking checks.

## 9. Create the two Air access keys

**On the Air:** create keys only if they do not already exist. Reuse the correct
existing role's key rather than overwriting it. Choose a passphrase for each.

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/personal-mini_ed25519 -C air-personal-mini
ssh-keygen -t ed25519 -f ~/.ssh/work-mini_ed25519 -C air-work-mini
```

Display each `.pub` file and copy its single public-key line to its matching
mini. Never copy the private key.

```bash
cat ~/.ssh/personal-mini_ed25519.pub
cat ~/.ssh/work-mini_ed25519.pub
```

## 10. Authorise the matching Air key on each mini

**In a macOS terminal on each mini:**

```bash
mkdir -p ~/.ssh ~/.orbstack/ssh
chmod 700 ~/.ssh ~/.orbstack/ssh
touch ~/.ssh/authorized_keys ~/.orbstack/ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys ~/.orbstack/ssh/authorized_keys
nano ~/.ssh/authorized_keys
nano ~/.orbstack/ssh/authorized_keys
```

In each editor, add that mini's matching Air public key on one new line,
preserving other entries. Do not duplicate an existing key. Save with Ctrl+O,
Enter, then exit with Ctrl+X. Both files need the key: the first authenticates
the mini jump, the second the VM connection. Any opted-in Docker bridge entry from
step 7 remains separate. The existing uncommented OrbStack key also stays in
place. An opted-in mini has an extra restricted macOS entry; a disabled one does
not need it; see [which keys belong where](remote-access.md#which-authorised-key-entries-belong-where).
Fully quit and reopen OrbStack when it is safe to
interrupt its VMs so it reloads the authorised keys.

## 11. Configure and test the Air SSH routes

**On the Air, in Mac-Bootstrap:**

```bash
cd ~/Downloads/Mac-Bootstrap
mkdir -p ~/.config/mac-bootstrap
if [ ! -e ~/.config/mac-bootstrap/ssh-air.tsv ]; then
  cp config/ssh/air.tsv.example ~/.config/mac-bootstrap/ssh-air.tsv
fi
chmod 600 ~/.config/mac-bootstrap/ssh-air.tsv
nano ~/.config/mac-bootstrap/ssh-air.tsv
```

Supply both tab-separated rows: role, mini's full Tailscale DNS name, mini's
macOS username, VM's Linux username. Use the values recorded in steps 3–4.
Then apply:

```bash
bootstrap/ssh.sh apply air
bootstrap/ssh.sh verify air
nano ~/.ssh/config
```

Immediately after `# mac-bootstrap: end managed Air SSH routing`, outside that
managed block and before other host settings, add this once:

```sshconfig
Host work-mini work-dev personal-mini personal-dev
  AddKeysToAgent yes
  UseKeychain yes

Host *
```

**On the Air:** load each key and save its passphrase in the login Keychain.

```bash
/usr/bin/ssh-add --apple-use-keychain ~/.ssh/personal-mini_ed25519
/usr/bin/ssh-add --apple-use-keychain ~/.ssh/work-mini_ed25519
```

Before accepting first-connect prompts, compare host fingerprints through
trusted access to the mini. For macOS, display
`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on that mini. The second prompt
is for OrbStack's SSH service. In a trusted local terminal on that same mini,
read its loopback service key and compare it with the Air prompt:

```bash
ssh-keyscan -t ed25519 -p 32222 127.0.0.1 | ssh-keygen -lf -
```

This check runs locally on the intended mini, not against an unverified remote
network address. See [Air SSH access](remote-access.md) for route diagnostics.
Do not accept a different or unknown key just to make the connection succeed.

**On the Air:** run each separately, exiting back to the Air between commands.

```bash
ssh personal-mini
ssh personal-dev
ssh work-mini
ssh work-dev
```

**Expected:** all four reach the intended account. If mini access works but VM
access fails, check OrbStack is running, its authorised-key file contains the
matching Air key, it was restarted, and the TSV has the correct Linux user.

## 12. Connect Zed and the terminal

**On the Air, in Zed:** press **Ctrl+Cmd+Shift+O**, choose **Connect New Server**,
and enter `ssh personal-dev`. Wait for its remote server, then choose a specific
folder such as `/home/LINUX_USER/code/project-a`. Repeat with `ssh work-dev` and
its project folder. Use `~/code` temporarily if a VM has no project yet.

Open a Zed terminal in each remote project and run:

```bash
hostname
pwd
command -v mise
```

**Expected:** the correct VM, project path and managed tools. Source, terminals
and language servers run in Ubuntu. Use this remote workflow for development;
opening the Finder-mounted folder as a local project would use the Air's tools.
See [Zed remote development](https://zed.dev/docs/remote-development).

**In a fresh Ghostty terminal on the Air:** run `personal-dev` or `work-dev` to
open the managed tmux helper. Detach with Ctrl+B, then D; rerun the helper and
confirm the session survives. Use `personal-devs` or `work-devs` to list sessions.
Use plain `ssh personal-dev`/`ssh work-dev` when you want a shell without tmux.

## 13. Connect Finder with Mountain Duck

**On the Air, with Mountain Duck and Cyberduck quit, in Mac-Bootstrap:**

```bash
bootstrap/mountain-duck.sh apply air
bootstrap/mountain-duck.sh verify air
```

Open Mountain Duck and complete its licence/trial step. Connect both bookmarks
from its menu-bar icon. Integrated mode gives native Finder locations and
on-demand files; Online mode is an alternative network-volume workflow.
Confirm the matching VM homes appear, copy a disposable file into each, and
verify it through SSH. Enable Login Item and Save Workspace in the app if you
want automatic reconnection. No SMB share of the OrbStack mount is needed.
See [Mountain Duck reference](mountain-duck.md).

## 14. Connect browsers and TablePlus

**On each mini:** obtain only its public root from
`~/Library/Application Support/mac-bootstrap/local-dev-tls/PROFILE/bundle/root-ca.pem`.
Transfer the two public roots to the Air under distinct filenames. Never copy
`rootCA-key.pem` or `localhost-key.pem` to the Air for browser access.

**On the Air:** import each public root into Keychain Access and explicitly
trust it for SSL. Configure a browser's own certificate store if it does not
use macOS trust. Start the project's HTTPS server inside its VM, then keep a
separate Air terminal running a forward, for example:

```bash
ssh -N -L 127.0.0.1:3000:127.0.0.1:3000 personal-dev
```

Open `https://localhost:3000` on the Air. For work, use `work-dev`; choose a
different local port if both forwards run concurrently. Match the remote port
to the actual service. Certificate trust and network forwarding are both needed.

**In TablePlus on the Air:** create the database connection with host
`127.0.0.1`, its actual published database port and private database credentials.
Enable the SSH tunnel to the matching **mini** alias, with that mini's macOS
account and matching Air key (or SSH-config support). Test it. The database is
hosted by OrbStack on the mini, so this tunnel targets the mini, not the VM.
See [TablePlus reference](tableplus.md).

## 15. Complete optional or workload-specific setup

These do not block the basic Ubuntu/Zed/Finder workflow. Record deferred work
privately and complete it before relying on the relevant capability.

| Capability | When needed | Procedure |
|---|---|---|
| Windows/Parallels | Work builds require Windows | Create/activate the VM, then follow [Windows development](windows-development.md) and [guest build commissioning](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/windows-builds.md) |
| Work OneDrive share | Files must be available from the Air | Sign in, download chosen folders and follow [OneDrive access](onedrive.md) |
| TablePlus | GUI database administration | Step 14 and [connection settings](tableplus.md) |
| External storage/export | Backup and recovery | [Storage guide](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/storage.md) |
| Work Testcontainers/Aspire, SQL Server, OCR/media | A project uses them | [VM tool checklist](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/setup.md#6-complete-the-profile-specific-setup) |
| Air cloud apps and capture tools | You use those applications | Finish sign-ins, licences and permissions; select sync folders locally |

## 16. Finish verification

**On each Mac, in Mac-Bootstrap:** run the corresponding command.

```bash
bin/mac verify personal-mini
```

Use `work-mini` on work and `air` on the Air. Finish Air checks without
`--skip-app-store` once its App Store apps are installed.

**Inside each VM:**

```bash
cd ~/code/dev-machine
bootstrap/verify.sh
```

Require zero failures and account for every warning, including intentionally
deferred Windows or provider authentication. Complete one real project's
restore/build/test workflow, HTTPS and database access. Check SSH/Zed from
another network, tmux reconnection, and a file transfer for each Finder mount.
The [acceptance checklist](commissioning.md) records what the automated checks
do not prove. Back up private configuration and important database/source state;
a destructive rebuild rehearsal is a separate recovery exercise.
