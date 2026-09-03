# DataGrip database access

DataGrip runs on the Air. Local development databases run in OrbStack's macOS
Docker engine on the corresponding mini and publish ports only on that mini's
loopback interface.

Use DataGrip's SSH tunnel support rather than exposing a database port over the
LAN or Tailscale:

```text
DataGrip on Air
  -> SSH to work-mini or personal-mini over Tailscale
  -> 127.0.0.1:PUBLISHED_PORT on that mini
  -> OrbStack database container
```

For each data source:

1. Set the database host to `127.0.0.1` and use the project-specific published
   port.
2. Enable an SSH tunnel to `work-mini` or `personal-mini`.
3. Select OpenSSH configuration and authentication-agent support.
4. Enter database credentials privately; do not add them to this repository.
5. Test the connection with ExpressVPN both connected and disconnected.

Azure databases use their managed endpoint and required TLS or identity flow.
Those connection definitions and credentials remain private DataGrip state.

DataGrip documents both built-in SSH tunnels and OpenSSH-agent authentication:
<https://www.jetbrains.com/help/datagrip/configuring-ssh-and-ssl.html>.
