# OrbStack Docker API bridge

The bridge gives selected Ubuntu VM processes direct access to OrbStack's
Docker API without installing a Docker daemon in the VM or exposing a Docker
TCP port. Ordinary linked `docker` and `docker compose` commands continue to
work without it.

The work-mini profile enables the host prerequisites. The personal-mini profile
supports the same mechanism but leaves it disabled until a personal workload
needs direct API access.

The supplied `dev-machine` guest helper and service support work only. Personal
use would require guest support as well as a reviewed host-profile change; leave
it disabled with the supplied profiles.

## Ownership

`mac-bootstrap` owns and verifies:

- OrbStack's host socket at `~/.orbstack/run/docker.sock`.
- The policy for the dedicated forwarding key in `~/.ssh/authorized_keys`.
- Separation between work and personal credentials.

`dev-machine` owns:

- A unique private key inside each VM.
- The verified Mac SSH host key in the VM's `known_hosts`.
- The user-level tunnel service and its runtime socket.
- Reconnection and stale-socket handling.

Each API consumer owns its command-scoped environment. No bootstrap should
globally export `DOCKER_HOST`.

## Host commissioning

Start OrbStack and confirm the current Mac user owns its socket:

```bash
test -S "$HOME/.orbstack/run/docker.sock"
stat -f 'owner=%Su mode=%Lp path=%N' "$HOME/.orbstack/run/docker.sock"
```

Generate the dedicated key in the VM, not on the Mac. Use a distinct key for
every VM-to-Mac pairing. Follow the `dev-machine`
[guest commissioning commands](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/docker-api.md#commissioning)
to initialise the key and, after host authorisation, start and verify the
service. Transfer only its public key and append it manually to
the matching Mac user's `~/.ssh/authorized_keys` with this shape:

```text
restrict,port-forwarding,command="/usr/bin/false" ssh-ed25519 PUBLIC_KEY_MATERIAL orbstack-docker-api-work-mini
```

For a personal bridge, use a newly generated key and the marker
`orbstack-docker-api-personal-mini`. Do not copy the work key.

Keep the SSH files owned by the Mac user and not writable by group or others:

```bash
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/authorized_keys"
```

Before the VM accepts the Mac host key, compare its fingerprint through a
separate trusted path. Do not trust an unverified `ssh-keyscan` result by
itself.

Run the profile verifier after commissioning:

```bash
bin/mac verify work-mini
```

The verifier requires a real, non-symlinked OrbStack socket owned by the Mac
user and not writable by group or others. It also requires the matching
authorization marker with `restrict`, `port-forwarding`, and a forced
`/usr/bin/false` command, without re-enabling PTY, agent, X11 or user-rc access.
Exactly one entry may carry the profile's marker, and that key must not appear
elsewhere in `authorized_keys`. The supplied policy therefore commissions one
VM bridge per mini. A work clone needs a deliberate authorisation handover;
concurrent VM bridge keys require a separate host-policy change. A disabled mini
profile requires its authorization marker to be absent. Either profile rejects
an authorization marker belonging to the other mini.

## Guest tunnel contract

The VM service should use OpenSSH Unix-socket forwarding with these controls:

```text
ExitOnForwardFailure=yes
StreamLocalBindUnlink=yes
StreamLocalBindMask=0177
```

The generic guest socket contract is
`${XDG_RUNTIME_DIR}/orbstack-docker.sock`. Consumers may use a different
user-owned runtime path when explicitly configured, provided it is a real
socket with mode `0600`. The host-side policy does not depend on the guest
socket name.

A generic Docker API consumer needs only a command-scoped host selection:

```bash
DOCKER_HOST="unix://${forwarded_socket}" command-that-uses-the-docker-api
```

Consumer-specific variables remain with the consumer. For example,
Testcontainers also needs its Docker socket mount override and the OrbStack
published-port hostname; those do not belong in the tunnel service or the Mac
profile.

## Security boundary

Docker API access is effectively full control of the OrbStack engine. The
forwarded socket must remain accessible only to the VM user, and Ryuk or an
equivalent consumer cleanup mechanism should remain enabled.

The forwarding key blocks shell commands and PTY access, but macOS OpenSSH
cannot constrain `permitopen` to a Unix-socket destination. Re-enabling port
forwarding therefore allows that key to request other forwards reachable by
the Mac account. Protect it as a privileged credential, and remove its
authorization when the bridge is no longer needed.
