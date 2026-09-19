# Repository guidance for coding agents

This repository provisions durable macOS machines. Preserve these invariants:

- Never add secrets, tokens, private keys, account identities or recovery keys.
- Never install Docker Desktop, Colima, Podman or a host development toolchain.
- OrbStack belongs only on the mini profiles.
- Work and personal minis must never share credentials or runtime state.
- Host changes are additive and conservative; never prune applications automatically.
- Keep interactive authentication, licences and privacy permissions outside bootstrap.
- Use documented Homebrew casks or Mac App Store IDs instead of remote installer scripts where possible.
- Treat undocumented macOS defaults as opt-in changes requiring explicit review.
- Public documentation describes durable behavior and policy, not project
  status, implementation history, personal plans or acceptance progress.
- Use generic workload examples in public documentation. Keep private project
  names, internal endpoints and machine inventories in private documentation.
- Run `make test` and `make lint` after changes.
