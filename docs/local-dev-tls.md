# Local development TLS

Each mini owns a separate local development certificate authority and a reusable
leaf certificate for services running in its Ubuntu VM. The work and personal
profiles never copy CA keys, leaf keys or generated runtime state between one
another.

The host uses `mkcert` only as a machine provisioning utility. Project SDKs and
development servers remain in Ubuntu.

## Trust model

```text
work-mini or personal-mini
  profile-specific mkcert CA
    root private key: remains on that mini
    public root: trusted by macOS and copied to its matching Ubuntu VM
    reusable leaf key and certificate: copied to its matching Ubuntu VM
                                      |
                                      v
                     Caddy / Go / .NET / Next.js development server
                                      |
                                      v
                  browser trusts the profile-specific public root
```

The leaf covers:

- `localhost`
- `127.0.0.1`
- `::1`
- `dev.localhost`
- `*.dev.localhost`

Names below `.localhost` are defined as loopback names. They are useful for
local virtual hosts but do not make a service remotely reachable.

## Host commissioning

Apply the mini profile before initializing TLS so `mkcert` is present:

```bash
bin/mac apply work-mini
bin/local-dev-tls init work-mini
bin/local-dev-tls verify work-mini
```

Use `personal-mini` on the personal host. `init` creates the CA only when it is
absent, installs its public root in the macOS system trust store and issues the
leaf certificate. Trust installation may ask for an administrator password.
The operation is deliberately separate from `bin/mac apply` because it creates
private material and changes system trust.

State is stored under:

```text
~/Library/Application Support/mac-bootstrap/local-dev-tls/PROFILE/
├── ca/
│   ├── rootCA.pem
│   └── rootCA-key.pem
└── bundle/
    ├── root-ca.pem
    ├── localhost.pem
    ├── localhost-key.pem
    └── profile
```

The state directories use mode `0700`, the CA private key uses `0400`, and the
leaf private key uses `0600`. The CA private key must remain on its issuing mini
and must never be copied to Ubuntu, another Mac or this repository. Verification
rejects granting ACLs, symlinked state paths, CA-capable leaf certificates and
leaf keys that match the CA key.

## VM handoff

Export a new, exact handoff directory:

```bash
bin/local-dev-tls export work-mini /private/tmp/work-local-dev-tls
```

Transfer that directory only to the matching VM through an authenticated local
channel, then run the `dev-machine` importer inside Ubuntu. The export contains
the public root and the leaf private key, but never the CA private key. Remove
the exact handoff directory from both ends after a successful import.

Do not reuse a work export for personal or copy an installed
`~/.config/local-dev-tls` directory between VMs. A profile marker in the export
causes the Ubuntu importer to reject a cross-profile handoff.

## Browser clients

Safari and Chromium browsers on the issuing mini use the macOS system trust
store. A browser on another Mac, such as the Air connecting through an SSH port
forward, also needs that profile's **public** `root-ca.pem` imported and trusted
explicitly. Use Keychain Access during commissioning; do not copy the CA
private key or leaf private key to a browser-only client.

Firefox can use its own certificate database depending on its configuration.
If it does not use macOS system roots, import only `root-ca.pem` through
Firefox's certificate settings.

## Renewal

The verifier warns by failing when the leaf has fewer than 30 days remaining or
the CA has fewer than one year remaining. Reissue the leaf explicitly:

```bash
bin/local-dev-tls renew work-mini
bin/local-dev-tls export work-mini /private/tmp/work-local-dev-tls-renewed
```

Import the renewed handoff into the matching VM and retest representative
servers and browsers. `renew` does not silently rotate the CA. A CA rotation is
a deliberate recommissioning event because every client trust store must be
updated.

## Container boundary

The stable certificate paths live inside Ubuntu. A container created by the
Mac-hosted OrbStack Docker engine cannot bind-mount those VM paths directly.
Projects that terminate TLS inside a container must explicitly copy the leaf
material to profile-scoped host state or a Docker volume and validate its
permissions. Do not expose the CA private key to a container.

## References

- [mkcert](https://github.com/FiloSottile/mkcert#readme)
- [Special-use `localhost` names](https://www.rfc-editor.org/rfc/rfc6761.html#section-6.3)
