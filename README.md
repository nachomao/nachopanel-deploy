# NachoPanel cloud service

NachoPanel cloud releases target Ubuntu 22.04/24.04 and Debian 12 on x86_64 or arm64. PostgreSQL 16+ and an HTTPS reverse proxy are supplied by the deployer.

## Install

Create a PostgreSQL database and user, then run the versioned installer. The database URL is requested securely from `/dev/tty` when it is not supplied through `DATABASE_URL` or `--database-url-file`.

```bash
curl -fsSL "https://github.com/nachomao/nachopanel-deploy/releases/download/v3.0.0/install.sh" |
  sudo env NACHO_PUBLIC_URL=https://panel.example.com \
    bash -s -- install --version 3.0.0
```

The installer downloads and verifies the pinned Node.js runtime and NachoPanel release, runs migrations, installs the systemd unit, performs a real health check, and prints the administrator API Key once.

Agent authentication defaults to `required`. Deployment tokens may be reused across a batch, while each registered client receives its own credential. To deliberately allow unauthenticated agents and enable a tokenless installer URL, pass `--disable-agent-auth`; the installer prints a security warning and persists the choice. Use `--require-agent-auth` to turn protection back on.

## Operate

```bash
sudo systemctl status nachopanel
sudo journalctl -u nachopanel -f
sudo nachopanelctl status
sudo nachopanelctl upgrade --version 3.1.0
sudo nachopanelctl repair
sudo nachopanelctl uninstall
sudo /opt/nachopanel/runtime/node/bin/node /opt/nachopanel/current/server/admin-cli.mjs key create --name recovery --scope admin
```

`uninstall` preserves `/etc/nachopanel` and `/var/lib/nachopanel`. Add `--purge` to remove configuration and local artifacts; the PostgreSQL database is never dropped automatically.

Expose port 3000 through an HTTPS reverse proxy. Port 8090 is the optional short Windows installer gateway and can be disabled with `INSTALLER_GATEWAY_DISABLED=1`.

The gateway itself speaks HTTP. To publish `https://panel.example.com:8090`, terminate TLS in the reverse proxy and forward it to `INSTALLER_PORT` (use a different internal port when both processes share a host). Set `NACHO_INSTALLER_PUBLIC_URL=https://panel.example.com:8090` so generated IRM commands use the external endpoint. For private HTTP testing only, pass `--allow-http`.

For multiple API nodes, configure S3-compatible artifact storage and a shared PostgreSQL database.

The API contract for the management frontend is in `deploy/cloud-api.openapi.yaml`.
