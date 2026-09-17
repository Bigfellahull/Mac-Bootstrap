# TablePlus database access

TablePlus runs on the Air. Local development databases run in OrbStack's macOS
Docker engine on the corresponding mini and publish ports only on that mini's
loopback interface.

Use TablePlus's SSH tunnel support rather than exposing a database port over the
LAN or Tailscale:

```text
TablePlus on Air
  -> SSH to work-mini or personal-mini over Tailscale
  -> 127.0.0.1:PUBLISHED_PORT on that mini
  -> OrbStack database container
```

Complete [Air SSH commissioning](remote-access.md) first and obtain the
project's published port from its `db` configuration inside Ubuntu.

Create a connection with the appropriate database driver. For each connection:

1. Set the database host to `127.0.0.1` and use the project-specific published
   port.
2. Enable **Over SSH** and set the SSH host to `work-mini` or `personal-mini`.
3. Select **Use SSH key** and leave the private key empty to use `~/.ssh/config`.
   Alternatively, supply that mini's Tailscale hostname, macOS username and
   matching private key explicitly. Keep work and personal keys separate.
4. Enter database credentials privately; do not add them to this repository.
5. Test the connection over Tailscale on the LAN and from another network.

Azure databases use their managed endpoint and required TLS or identity flow.
Those connection definitions and credentials remain private TablePlus state.

See [TablePlus's connection and SSH tunnel documentation](https://docs.tableplus.com/gui-tools/manage-connections).
