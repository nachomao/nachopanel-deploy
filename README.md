# NachoPanel cloud service

NachoPanel cloud releases target Ubuntu 22.04/24.04 and Debian 12 on x86_64 or arm64. A fresh installation can provision the operating-system packages, Node.js 22, PostgreSQL 16, NachoPanel, and an optional Caddy HTTPS proxy without manual database setup.

## Guided installation

Run the versioned installer from a terminal. It uses `/dev/tty`, so the wizard remains interactive when the script itself is piped through `bash`.

```bash
curl -fsSL "https://github.com/nachomao/nachopanel-deploy/releases/download/v3.0.1/install.sh" |
  sudo bash -s -- install --version 3.0.1
```

The wizard configures the public URL, Windows installer gateway, agent authentication, database, and HTTPS proxy. The recommended database choice creates:

- PostgreSQL 16 from the signed PostgreSQL package repository;
- a `nachopanel` role and database;
- a unique random password for this server;
- a root-owned `/etc/nachopanel/nachopanel.env` file with mode `0600`;
- all required schemas and an administrator API Key.

The password is never printed or passed in a process argument. Select advanced database settings in the wizard to choose a different role, database, port, or password.

## Unattended installation

Without a terminal, the installer uses secure defaults. Supply at least the public URL; Caddy, PostgreSQL 16, agent authentication, and the Windows installer gateway are enabled by default.

```bash
curl -fsSL "https://github.com/nachomao/nachopanel-deploy/releases/download/v3.0.1/install.sh" |
  sudo env NACHO_PUBLIC_URL=https://panel.example.com \
    bash -s -- install --version 3.0.1 --non-interactive
```

For a custom managed password, create a root-only password file:

```bash
sudo install -m 0600 /dev/null /root/nachopanel-db-password
sudo sh -c 'printf %s "replace-with-a-strong-password" > /root/nachopanel-db-password'
sudo env NACHO_PUBLIC_URL=https://panel.example.com \
  bash install.sh install --non-interactive \
  --db-mode managed --db-user nachopanel --db-name nachopanel \
  --db-password-file /root/nachopanel-db-password
```

To use an existing PostgreSQL 16+ service, put its URL in a root-only file. Local PostgreSQL is not installed or modified in external mode.

```bash
sudo install -m 0600 /dev/null /root/nachopanel-database-url
sudo sh -c 'printf %s "postgresql://user:password@database.example.com:5432/nachopanel?sslmode=require" > /root/nachopanel-database-url'
sudo env NACHO_PUBLIC_URL=https://panel.example.com \
  bash install.sh install --non-interactive \
  --db-mode external --database-url-file /root/nachopanel-database-url
```

## HTTPS and gateway

Managed Caddy mode requires the public domain to resolve to the server and inbound access to ports 80 and 443. When the Windows installer gateway is enabled, port 8090 must also be reachable. The application and gateway bind only to loopback in this mode:

- `https://panel.example.com` forwards to `127.0.0.1:3000`;
- `https://panel.example.com:8090` forwards to `127.0.0.1:8091`.

Choose `--proxy-mode external` when another reverse proxy terminates TLS. Choose `--proxy-mode none --allow-http` only for private HTTP testing. The installer never changes UFW rules or cloud security groups.

Agent authentication defaults to `required`. Deployment tokens can be reused across a batch, while each registered client receives an independent credential. Disabling authentication requires the wizard confirmation or the explicit `--disable-agent-auth` flag.

## Operation

```bash
sudo systemctl status nachopanel
sudo journalctl -u nachopanel -f
sudo nachopanelctl status
sudo nachopanelctl upgrade --version 3.0.1
sudo nachopanelctl repair
sudo nachopanelctl uninstall
sudo /opt/nachopanel/runtime/node/bin/node /opt/nachopanel/current/server/admin-cli.mjs key create --name recovery --scope admin
```

`upgrade` and `repair` reuse the saved database configuration without prompting or rotating its password. `uninstall` preserves `/etc/nachopanel`, `/var/lib/nachopanel`, PostgreSQL data, and the Caddy installation. Add `--purge` to remove NachoPanel configuration and local artifacts; PostgreSQL databases are never dropped automatically.

For multiple API nodes, select external PostgreSQL and configure S3-compatible artifact storage. The management API contract is in `cloud-api.openapi.yaml`.
