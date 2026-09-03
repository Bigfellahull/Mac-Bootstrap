# Commissioning checklist

Run each profile independently on a Mac configured as a new machine.

## Before bootstrap

- Apply available macOS updates.
- Enable FileVault and store its recovery material outside this repository.
- Install the Command Line Tools with `xcode-select --install`.
- Install Homebrew from its official instructions at <https://brew.sh>.
- Sign into the Mac App Store on the Air before installing store applications.

## Bootstrap

```bash
bin/mac plan PROFILE
bin/mac apply PROFILE
bin/mac verify PROFILE
```

Run `apply` and `verify` a second time. The second run must remain clean.

## All Macs

- Sign into 1Password, Tailscale, CleanMyMac and ExpressVPN.
- Approve only the expected privacy and network-extension permissions.
- Confirm Tailscale remains reachable while ExpressVPN is connected.
- Confirm no Docker Desktop, Colima or local development runtime was installed.

## Air

- Activate CleanShot X and grant only its required screen-recording permissions.
- Restart Ghostty after bootstrap and confirm its Catppuccin theme and Starship prompt load.
- Configure Ghostty and Zed against the OpenSSH targets owned by `dev-machine`.
- Confirm `work-dev` and `personal-dev` attach to the default and named tmux sessions.
- Confirm `work-devs` and `personal-devs` list the available tmux sessions.
- Configure DataGrip through SSH tunnels; do not expose mini database ports.
- Confirm FieldKit can communicate with the intended Teenage Engineering devices.
- Sign into Microsoft Teams and grant only its required privacy permissions.
- Choose and record any macOS settings promoted from `docs/settings.md`.

## Minis

- Enable Remote Login for the intended account only.
- Give Tailscale stable names `personal-mini` and `work-mini`.
- Start OrbStack and run its diagnostics.
- Initialize and verify the profile-specific local development CA with `bin/local-dev-tls init PROFILE`.
- Export the TLS handoff, import it into only the matching Ubuntu profile, then remove the exact temporary handoff from both machines.
- Validate HTTPS with representative Caddy, Go, .NET and Next.js servers and a browser before relying on the shared certificate.
- Clone `dev-machine` and follow its commissioning documentation.
- Verify restart, sleep and network behaviour before relying on unattended access.

## Work mini

- Commission the dedicated work VM key and restricted authorization described in the [OrbStack Docker API bridge guide](orbstack-docker-api.md).
- Start the VM's user-level bridge service and confirm its forwarded socket is owned by the VM user with mode `0600`.
- Verify Docker API access, published-port callbacks and cleanup through a real API consumer.
- Activate Parallels separately.
- Create or restore the Windows VM without coupling it to OrbStack bootstrap.

## Personal mini

- Leave the OrbStack Docker API bridge disabled unless a personal VM workload needs direct API access.
- If enabled, commission a new key and socket rather than copying work credentials or runtime state.

## Browser clients

- On any separate Mac used to browse a forwarded VM service, import and trust only the matching profile's public `root-ca.pem` through Keychain Access.
- Never copy a CA private key or reusable leaf private key to a browser-only client.
- If Firefox is not configured to use macOS roots, import the public root through Firefox's certificate settings.
