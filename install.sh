#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="nachopanel"
INSTALL_ROOT="/opt/nachopanel"
DATA_DIR="/var/lib/nachopanel"
CONFIG_DIR="/etc/nachopanel"
ENV_FILE="$CONFIG_DIR/nachopanel.env"
UNIT_FILE="/etc/systemd/system/$SERVICE_NAME.service"
CADDY_FILE="/etc/caddy/Caddyfile"
CADDY_SNIPPET="/etc/caddy/conf.d/nachopanel.caddy"
OS_RELEASE_FILE="${NACHO_OS_RELEASE_FILE:-/etc/os-release}"
NODE_VERSION="${NACHO_NODE_VERSION:-22.17.0}"
POSTGRESQL_VERSION="${NACHO_POSTGRESQL_VERSION:-16}"
VERSION="${NACHO_VERSION:-3.0.2}"
REPOSITORY="${NACHO_GITHUB_REPOSITORY:-nachomao/nachopanel-deploy}"
RELEASE_BASE_URL="${NACHO_RELEASE_BASE_URL:-}"
NODE_BASE_URL="${NACHO_NODE_BASE_URL:-}"
RELEASE_BASE_URL_SET=$([[ -n "${NACHO_RELEASE_BASE_URL:-}" ]] && printf 1 || printf 0)
NODE_BASE_URL_SET=$([[ -n "${NACHO_NODE_BASE_URL:-}" ]] && printf 1 || printf 0)

NODE_VERSION_SET=$([[ -n "${NACHO_NODE_VERSION:-}" ]] && printf 1 || printf 0)
VERSION_SET=$([[ -n "${NACHO_VERSION:-}" ]] && printf 1 || printf 0)
REPOSITORY_SET=$([[ -n "${NACHO_GITHUB_REPOSITORY:-}" ]] && printf 1 || printf 0)
PUBLIC_URL="${NACHO_PUBLIC_URL:-}"
PUBLIC_URL_SET=$([[ -n "${NACHO_PUBLIC_URL:-}" ]] && printf 1 || printf 0)
INSTALLER_PUBLIC_URL="${NACHO_INSTALLER_PUBLIC_URL:-}"
INSTALLER_PUBLIC_URL_SET=$([[ -n "${NACHO_INSTALLER_PUBLIC_URL:-}" ]] && printf 1 || printf 0)
AGENT_AUTH_MODE="${NACHO_AGENT_AUTH_MODE:-required}"
AGENT_AUTH_MODE_SET=$([[ -n "${NACHO_AGENT_AUTH_MODE:-}" ]] && printf 1 || printf 0)
AGENT_AUTH_CONFIRMED=$([[ "${NACHO_CONFIRM_UNAUTHENTICATED_AGENTS:-}" == "1" ]] && printf 1 || printf 0)

DATABASE_VALUE="${DATABASE_URL:-}"
DATABASE_VALUE_SET=$([[ -n "${DATABASE_URL:-}" ]] && printf 1 || printf 0)
DATABASE_MODE="${NACHO_DATABASE_MODE:-}"
DATABASE_MODE_SET=$([[ -n "${NACHO_DATABASE_MODE:-}" ]] && printf 1 || printf 0)
DATABASE_USER="${NACHO_DB_USER:-}"
DATABASE_USER_SET=$([[ -n "${NACHO_DB_USER:-}" ]] && printf 1 || printf 0)
DATABASE_NAME="${NACHO_DB_NAME:-}"
DATABASE_NAME_SET=$([[ -n "${NACHO_DB_NAME:-}" ]] && printf 1 || printf 0)
DATABASE_HOST="${NACHO_DB_HOST:-}"
DATABASE_HOST_SET=$([[ -n "${NACHO_DB_HOST:-}" ]] && printf 1 || printf 0)
DATABASE_PORT="${NACHO_DB_PORT:-}"
DATABASE_PORT_SET=$([[ -n "${NACHO_DB_PORT:-}" ]] && printf 1 || printf 0)
DATABASE_SSLMODE="${NACHO_DB_SSLMODE:-}"
DATABASE_SSLMODE_SET=$([[ -n "${NACHO_DB_SSLMODE:-}" ]] && printf 1 || printf 0)
DATABASE_FILE=""
DATABASE_PASSWORD_FILE="${NACHO_DB_PASSWORD_FILE:-}"
DATABASE_PASSWORD=""
DATABASE_PASSWORD_SOURCE="generated"

PROXY_MODE="${NACHO_PROXY_MODE:-}"
PROXY_MODE_SET=$([[ -n "${NACHO_PROXY_MODE:-}" ]] && printf 1 || printf 0)
APP_HOST="${NACHO_APP_HOST:-}"
APP_HOST_SET=$([[ -n "${NACHO_APP_HOST:-}" ]] && printf 1 || printf 0)
APP_PORT="${PORT:-}"
APP_PORT_SET=$([[ -n "${PORT:-}" ]] && printf 1 || printf 0)
API_ONLY="${NACHO_API_ONLY:-1}"
INTERNAL_HOST="${NACHO_INTERNAL_HOST:-127.0.0.1}"
INTERNAL_PORT="${NACHO_INTERNAL_PORT:-39001}"
INSTALLER_HOST="${NACHO_INSTALLER_HOST:-}"
INSTALLER_HOST_SET=$([[ -n "${NACHO_INSTALLER_HOST:-}" ]] && printf 1 || printf 0)
INSTALLER_PORT_VALUE="${INSTALLER_PORT:-}"
INSTALLER_PORT_SET=$([[ -n "${INSTALLER_PORT:-}" ]] && printf 1 || printf 0)
INSTALLER_PUBLIC_PORT="${NACHO_INSTALLER_PUBLIC_PORT:-}"
INSTALLER_PUBLIC_PORT_SET=$([[ -n "${NACHO_INSTALLER_PUBLIC_PORT:-}" ]] && printf 1 || printf 0)
INSTALLER_GATEWAY_ENABLED=$([[ "${INSTALLER_GATEWAY_DISABLED:-}" == "1" ]] && printf 0 || printf 1)
INSTALLER_GATEWAY_SET=$([[ -n "${INSTALLER_GATEWAY_DISABLED+x}" ]] && printf 1 || printf 0)

INTERACTION_MODE="${NACHO_INTERACTION_MODE:-auto}"
ALLOW_HTTP=0
PURGE=0
ACTION="install"
PREVIOUS_RELEASE=""
NEW_RELEASE=""
SWITCHED=0
BOOTSTRAP_SECRET=""
CONFIG_LOADED=0
WIZARD_RAN=0
CADDY_DOMAIN=""
TTY_DEVICE="${NACHO_TTY_DEVICE:-/dev/tty}"
PROMPT_VALUE=""
ROLLBACK_ENABLED=0
CONFIG_CHANGED=0
CONFIG_EXISTED=0
CONFIG_BACKUP=""
CADDY_CHANGED=0
CADDY_HAD_SNIPPET=0
CADDY_CONFIG_BACKUP=""
CADDY_SNIPPET_BACKUP=""

log() { printf '[NachoPanel] %s\n' "$*"; }
fail() {
  printf '[NachoPanel] ERROR: %s\n' "$*" >&2
  if [[ $ROLLBACK_ENABLED -eq 1 ]]; then rollback 1; fi
  exit 1
}
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Run this command as root"; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }

usage() {
  cat <<'EOF'
Usage: install.sh <install|upgrade|repair|status|uninstall> [options]

Options:
  --version VERSION             Release version (default: 3.0.2)
  --repository OWNER/REPO       Override the GitHub repository containing release assets
  --release-base-url URL        HTTPS, HTTP, or file URL containing release assets
  --node-base-url URL           HTTPS, HTTP, or file URL containing Node.js assets
  --interactive                 Force the guided deployment wizard
  --non-interactive             Never prompt; require values through flags or environment
  --public-url URL              Public HTTPS origin for NachoPanel
  --installer-public-url URL    Public HTTPS origin for the Windows installer gateway
  --enable-installer-gateway    Enable the Windows installer gateway
  --disable-installer-gateway   Disable the Windows installer gateway
  --disable-agent-auth          Allow clients without credentials (security risk)
  --require-agent-auth          Require enrollment and per-client credentials
  --db-mode MODE                managed or external (default: managed)
  --db-user USER                Managed/external PostgreSQL user
  --db-name NAME                Managed/external PostgreSQL database name
  --db-host HOST                External PostgreSQL host
  --db-port PORT                PostgreSQL port (default: 5432)
  --db-sslmode MODE             External PostgreSQL SSL mode: require, prefer, or disable
  --db-password-file PATH       Root-only file containing the PostgreSQL password
  --database-url-file PATH      Root-only file containing an external DATABASE_URL
  --proxy-mode MODE             caddy, external, or none (default: caddy on fresh installs)
  --allow-http                  Permit HTTP only with proxy mode none for private testing
  --purge                       Remove NachoPanel config and local artifacts on uninstall
EOF
}

parse_args() {
  ACTION="${1:-install}"
  if [[ $# -gt 0 ]]; then shift; fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) VERSION="${2:?missing version}"; VERSION_SET=1; shift 2 ;;
      --repository) REPOSITORY="${2:?missing repository}"; REPOSITORY_SET=1; shift 2 ;;
      --release-base-url) RELEASE_BASE_URL="${2:?missing release base URL}"; RELEASE_BASE_URL_SET=1; shift 2 ;;
      --node-base-url) NODE_BASE_URL="${2:?missing Node.js base URL}"; NODE_BASE_URL_SET=1; shift 2 ;;
      --interactive) INTERACTION_MODE="always"; shift ;;
      --non-interactive) INTERACTION_MODE="never"; shift ;;
      --public-url) PUBLIC_URL="${2:?missing public URL}"; PUBLIC_URL_SET=1; shift 2 ;;
      --installer-public-url) INSTALLER_PUBLIC_URL="${2:?missing installer public URL}"; INSTALLER_PUBLIC_URL_SET=1; shift 2 ;;
      --enable-installer-gateway) INSTALLER_GATEWAY_ENABLED=1; INSTALLER_GATEWAY_SET=1; shift ;;
      --disable-installer-gateway) INSTALLER_GATEWAY_ENABLED=0; INSTALLER_GATEWAY_SET=1; shift ;;
      --disable-agent-auth) AGENT_AUTH_MODE="disabled"; AGENT_AUTH_MODE_SET=1; AGENT_AUTH_CONFIRMED=1; shift ;;
      --require-agent-auth) AGENT_AUTH_MODE="required"; AGENT_AUTH_MODE_SET=1; shift ;;
      --db-mode) DATABASE_MODE="${2:?missing database mode}"; DATABASE_MODE_SET=1; shift 2 ;;
      --db-user) DATABASE_USER="${2:?missing database user}"; DATABASE_USER_SET=1; shift 2 ;;
      --db-name) DATABASE_NAME="${2:?missing database name}"; DATABASE_NAME_SET=1; shift 2 ;;
      --db-host) DATABASE_HOST="${2:?missing database host}"; DATABASE_HOST_SET=1; shift 2 ;;
      --db-port) DATABASE_PORT="${2:?missing database port}"; DATABASE_PORT_SET=1; shift 2 ;;
      --db-sslmode) DATABASE_SSLMODE="${2:?missing database SSL mode}"; DATABASE_SSLMODE_SET=1; shift 2 ;;
      --db-password-file) DATABASE_PASSWORD_FILE="${2:?missing database password file}"; shift 2 ;;
      --database-url-file) DATABASE_FILE="${2:?missing database URL file}"; DATABASE_MODE="external"; DATABASE_MODE_SET=1; shift 2 ;;
      --proxy-mode) PROXY_MODE="${2:?missing proxy mode}"; PROXY_MODE_SET=1; shift 2 ;;
      --allow-http) ALLOW_HTTP=1; shift ;;
      --purge) PURGE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done
}

load_existing_config() {
  [[ -f "$ENV_FILE" ]] || return 0
  CONFIG_LOADED=1
  set -a
  # This file is created root-owned with mode 0600 by write_config.
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  if [[ $DATABASE_VALUE_SET -eq 0 ]]; then DATABASE_VALUE="${DATABASE_URL:-}"; fi
  if [[ $DATABASE_MODE_SET -eq 0 ]]; then DATABASE_MODE="${NACHO_DATABASE_MODE:-}"; fi
  if [[ $DATABASE_USER_SET -eq 0 ]]; then DATABASE_USER="${NACHO_DB_USER:-}"; fi
  if [[ $DATABASE_NAME_SET -eq 0 ]]; then DATABASE_NAME="${NACHO_DB_NAME:-}"; fi
  if [[ $DATABASE_HOST_SET -eq 0 ]]; then DATABASE_HOST="${NACHO_DB_HOST:-}"; fi
  if [[ $DATABASE_PORT_SET -eq 0 ]]; then DATABASE_PORT="${NACHO_DB_PORT:-}"; fi
  if [[ $DATABASE_SSLMODE_SET -eq 0 ]]; then DATABASE_SSLMODE="${NACHO_DB_SSLMODE:-}"; fi
  if [[ $PUBLIC_URL_SET -eq 0 ]]; then PUBLIC_URL="${NACHO_PUBLIC_URL:-}"; fi
  if [[ $INSTALLER_PUBLIC_URL_SET -eq 0 ]]; then INSTALLER_PUBLIC_URL="${NACHO_INSTALLER_PUBLIC_URL:-}"; fi
  if [[ $AGENT_AUTH_MODE_SET -eq 0 ]]; then AGENT_AUTH_MODE="${NACHO_AGENT_AUTH_MODE:-required}"; fi
  if [[ $PROXY_MODE_SET -eq 0 ]]; then PROXY_MODE="${NACHO_PROXY_MODE:-external}"; fi
  if [[ $APP_HOST_SET -eq 0 ]]; then APP_HOST="${NACHO_APP_HOST:-}"; fi
  if [[ $APP_PORT_SET -eq 0 ]]; then APP_PORT="${PORT:-}"; fi
  if [[ $INSTALLER_HOST_SET -eq 0 ]]; then INSTALLER_HOST="${NACHO_INSTALLER_HOST:-}"; fi
  if [[ $INSTALLER_PORT_SET -eq 0 ]]; then INSTALLER_PORT_VALUE="${INSTALLER_PORT:-}"; fi
  if [[ $INSTALLER_PUBLIC_PORT_SET -eq 0 ]]; then INSTALLER_PUBLIC_PORT="${NACHO_INSTALLER_PUBLIC_PORT:-}"; fi
  if [[ $INSTALLER_GATEWAY_SET -eq 0 ]]; then INSTALLER_GATEWAY_ENABLED=$([[ "${INSTALLER_GATEWAY_DISABLED:-}" == "1" ]] && printf 0 || printf 1); fi
  if [[ $REPOSITORY_SET -eq 0 ]]; then REPOSITORY="${NACHO_GITHUB_REPOSITORY:-$REPOSITORY}"; fi
  if [[ $VERSION_SET -eq 0 ]]; then VERSION="${NACHO_VERSION:-$VERSION}"; fi
  if [[ $NODE_VERSION_SET -eq 0 ]]; then NODE_VERSION="${NACHO_NODE_VERSION:-$NODE_VERSION}"; fi
  if [[ $RELEASE_BASE_URL_SET -eq 0 ]]; then RELEASE_BASE_URL="${NACHO_RELEASE_BASE_URL:-}"; fi
  if [[ $NODE_BASE_URL_SET -eq 0 ]]; then NODE_BASE_URL="${NACHO_NODE_BASE_URL:-}"; fi

  [[ "$DATABASE_MODE" == "local" ]] && DATABASE_MODE="managed"
  if [[ -z "$DATABASE_MODE" && -n "$DATABASE_VALUE" ]]; then DATABASE_MODE="external"; fi
}

has_tty() { [[ -r "$TTY_DEVICE" && -w "$TTY_DEVICE" ]]; }

should_run_wizard() {
  if [[ "$ACTION" != "install" || $CONFIG_LOADED -eq 1 ]]; then return 1; fi
  case "$INTERACTION_MODE" in
    always) has_tty || fail "--interactive requires an attached terminal"; return 0 ;;
    never) return 1 ;;
    auto) has_tty ;;
    *) fail "NACHO_INTERACTION_MODE must be auto, always, or never" ;;
  esac
}

prompt_line() {
  local label="$1" default="${2:-}" value
  while true; do
    if [[ -n "$default" ]]; then
      printf '%s [%s]: ' "$label" "$default" >"$TTY_DEVICE"
    else
      printf '%s: ' "$label" >"$TTY_DEVICE"
    fi
    IFS= read -r value <"$TTY_DEVICE" || fail "Interactive input ended unexpectedly"
    value="${value:-$default}"
    if [[ -n "$value" ]]; then PROMPT_VALUE="$value"; return; fi
    printf 'A value is required.\n' >"$TTY_DEVICE"
  done
}

prompt_choice() {
  local label="$1" default="$2" maximum="$3" value
  while true; do
    printf '%s [%s]: ' "$label" "$default" >"$TTY_DEVICE"
    IFS= read -r value <"$TTY_DEVICE" || fail "Interactive input ended unexpectedly"
    value="${value:-$default}"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= maximum )); then PROMPT_VALUE="$value"; return; fi
    printf 'Choose a number from 1 to %s.\n' "$maximum" >"$TTY_DEVICE"
  done
}

prompt_yes_no() {
  local label="$1" default="${2:-yes}" value suffix
  [[ "$default" == "yes" ]] && suffix="Y/n" || suffix="y/N"
  while true; do
    printf '%s [%s]: ' "$label" "$suffix" >"$TTY_DEVICE"
    IFS= read -r value <"$TTY_DEVICE" || fail "Interactive input ended unexpectedly"
    value="${value,,}"
    if [[ -z "$value" ]]; then [[ "$default" == "yes" ]] && PROMPT_VALUE=1 || PROMPT_VALUE=0; return; fi
    case "$value" in
      y|yes) PROMPT_VALUE=1; return ;;
      n|no) PROMPT_VALUE=0; return ;;
      *) printf 'Enter y or n.\n' >"$TTY_DEVICE" ;;
    esac
  done
}

prompt_password() {
  local first second
  while true; do
    printf 'PostgreSQL password (12-256 characters): ' >"$TTY_DEVICE"
    IFS= read -r -s first <"$TTY_DEVICE" || fail "Interactive input ended unexpectedly"
    printf '\nConfirm PostgreSQL password: ' >"$TTY_DEVICE"
    IFS= read -r -s second <"$TTY_DEVICE" || fail "Interactive input ended unexpectedly"
    printf '\n' >"$TTY_DEVICE"
    if [[ "$first" == "$second" && ${#first} -ge 12 && ${#first} -le 256 && "$first" != *$'\n'* && "$first" != *$'\r'* ]]; then
      DATABASE_PASSWORD="$first"
      DATABASE_PASSWORD_SOURCE="custom"
      return
    fi
    printf 'Passwords must match and contain 12-256 characters.\n' >"$TTY_DEVICE"
  done
}

apply_defaults() {
  DATABASE_USER="${DATABASE_USER:-nachopanel}"
  DATABASE_NAME="${DATABASE_NAME:-nachopanel}"
  DATABASE_PORT="${DATABASE_PORT:-5432}"
  DATABASE_SSLMODE="${DATABASE_SSLMODE:-require}"
  APP_PORT="${APP_PORT:-3000}"
  INSTALLER_PUBLIC_PORT="${INSTALLER_PUBLIC_PORT:-8090}"
  if [[ -z "$DATABASE_MODE" ]]; then
    [[ -n "$DATABASE_VALUE" ]] && DATABASE_MODE="external" || DATABASE_MODE="managed"
  fi
  [[ "$DATABASE_MODE" == "local" ]] && DATABASE_MODE="managed"
  if [[ -z "$PROXY_MODE" ]]; then
    if [[ $CONFIG_LOADED -eq 1 ]]; then
      PROXY_MODE="external"
    elif [[ "$PUBLIC_URL" == http://* ]]; then
      PROXY_MODE="none"
    else
      PROXY_MODE="caddy"
    fi
  fi
}

run_wizard() {
  local choice use_defaults use_supplied confirmation
  WIZARD_RAN=1
  apply_defaults
  printf '\nNachoPanel 3.0.2 guided deployment\n\n' >"$TTY_DEVICE"

  prompt_line "Public NachoPanel URL" "$PUBLIC_URL"
  PUBLIC_URL="$PROMPT_VALUE"

  prompt_yes_no "Enable the Windows installer gateway" "$([[ $INSTALLER_GATEWAY_ENABLED -eq 1 ]] && printf yes || printf no)"
  INSTALLER_GATEWAY_ENABLED="$PROMPT_VALUE"

  printf '\nAgent authentication:\n  1) Required (recommended)\n  2) Disabled\n' >"$TTY_DEVICE"
  [[ "$AGENT_AUTH_MODE" == "disabled" ]] && choice=2 || choice=1
  prompt_choice "Choose agent authentication" "$choice" 2
  if [[ "$PROMPT_VALUE" == "1" ]]; then
    AGENT_AUTH_MODE="required"
  else
    AGENT_AUTH_MODE="disabled"
    printf 'Type DISABLE to confirm unauthenticated agents: ' >"$TTY_DEVICE"
    IFS= read -r confirmation <"$TTY_DEVICE" || fail "Interactive input ended unexpectedly"
    [[ "$confirmation" == "DISABLE" ]] || fail "Agent authentication was not disabled"
    AGENT_AUTH_CONFIRMED=1
  fi

  printf '\nDatabase mode:\n  1) Managed local PostgreSQL 16 (recommended)\n  2) Existing external PostgreSQL 16+\n' >"$TTY_DEVICE"
  [[ "$DATABASE_MODE" == "external" ]] && choice=2 || choice=1
  prompt_choice "Choose database mode" "$choice" 2
  if [[ "$PROMPT_VALUE" == "1" ]]; then
    DATABASE_MODE="managed"
    DATABASE_VALUE=""
    prompt_yes_no "Use secure database defaults (nachopanel user/database and a random password)" yes
    use_defaults="$PROMPT_VALUE"
    if [[ "$use_defaults" == "1" ]]; then
      DATABASE_USER="nachopanel"
      DATABASE_NAME="nachopanel"
      DATABASE_PORT="5432"
      DATABASE_PASSWORD=""
      DATABASE_PASSWORD_SOURCE="generated"
    else
      prompt_line "PostgreSQL user" "$DATABASE_USER"; DATABASE_USER="$PROMPT_VALUE"
      prompt_line "PostgreSQL database" "$DATABASE_NAME"; DATABASE_NAME="$PROMPT_VALUE"
      prompt_line "PostgreSQL port" "$DATABASE_PORT"; DATABASE_PORT="$PROMPT_VALUE"
      DATABASE_PORT_SET=1
      prompt_password
    fi
  else
    DATABASE_MODE="external"
    use_supplied=0
    if [[ -n "$DATABASE_VALUE" ]]; then
      prompt_yes_no "Use the supplied external DATABASE_URL" yes
      use_supplied="$PROMPT_VALUE"
    fi
    if [[ "$use_supplied" != "1" ]]; then
      DATABASE_VALUE=""
      prompt_line "PostgreSQL host" "$DATABASE_HOST"; DATABASE_HOST="$PROMPT_VALUE"
      prompt_line "PostgreSQL port" "$DATABASE_PORT"; DATABASE_PORT="$PROMPT_VALUE"
      prompt_line "PostgreSQL user" "$DATABASE_USER"; DATABASE_USER="$PROMPT_VALUE"
      prompt_line "PostgreSQL database" "$DATABASE_NAME"; DATABASE_NAME="$PROMPT_VALUE"
      printf '\nExternal database SSL mode:\n  1) require (recommended)\n  2) prefer\n  3) disable\n' >"$TTY_DEVICE"
      case "$DATABASE_SSLMODE" in prefer) choice=2 ;; disable) choice=3 ;; *) choice=1 ;; esac
      prompt_choice "Choose SSL mode" "$choice" 3
      case "$PROMPT_VALUE" in 1) DATABASE_SSLMODE=require ;; 2) DATABASE_SSLMODE=prefer ;; 3) DATABASE_SSLMODE=disable ;; esac
      prompt_password
    fi
  fi

  printf '\nHTTPS proxy mode:\n  1) Install and configure Caddy (recommended)\n  2) Use an existing reverse proxy\n  3) No proxy (private HTTP testing only)\n' >"$TTY_DEVICE"
  case "$PROXY_MODE" in external) choice=2 ;; none) choice=3 ;; *) choice=1 ;; esac
  prompt_choice "Choose proxy mode" "$choice" 3
  case "$PROMPT_VALUE" in 1) PROXY_MODE=caddy ;; 2) PROXY_MODE=external ;; 3) PROXY_MODE=none ;; esac
}

read_root_secret_file() {
  local path="$1" label="$2" mode value
  [[ -f "$path" && -r "$path" ]] || fail "$label file cannot be read: $path"
  mode=$(stat -c '%a' "$path")
  (( (8#$mode & 077) == 0 )) || fail "$label file must not be accessible by group or other users: $path"
  value=$(<"$path")
  [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || fail "$label file must contain exactly one non-empty line"
  PROMPT_VALUE="$value"
}

generate_password() {
  DATABASE_PASSWORD=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
  [[ "$DATABASE_PASSWORD" =~ ^[A-Fa-f0-9]{48}$ ]] || fail "Failed to generate a PostgreSQL password"
  DATABASE_PASSWORD_SOURCE="generated"
}

urlencode() {
  local LC_ALL=C value="$1" output="" character encoded index
  for ((index=0; index<${#value}; index++)); do
    character="${value:index:1}"
    case "$character" in
      [a-zA-Z0-9.~_-]) output+="$character" ;;
      *) printf -v encoded '%%%02X' "'$character"; output+="$encoded" ;;
    esac
  done
  printf '%s' "$output"
}

build_external_database_url() {
  local encoded_user encoded_password encoded_database host="$DATABASE_HOST"
  [[ -n "$host" && ! "$host" =~ [[:space:]/@?#] ]] || fail "External PostgreSQL host is invalid"
  if [[ "$host" == *:* && "$host" != \[*\] ]]; then host="[$host]"; fi
  encoded_user=$(urlencode "$DATABASE_USER")
  encoded_password=$(urlencode "$DATABASE_PASSWORD")
  encoded_database=$(urlencode "$DATABASE_NAME")
  DATABASE_VALUE="postgresql://$encoded_user:$encoded_password@$host:$DATABASE_PORT/$encoded_database?sslmode=$DATABASE_SSLMODE"
  DATABASE_PASSWORD=""
}

validate_origin() {
  local value="$1" allow_http="$2" label="$3"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || fail "$label must be a single line"
  if [[ "$allow_http" == "1" ]]; then
    [[ "$value" =~ ^https?://(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9.-]+)(:[0-9]{1,5})?$ ]] || fail "$label must be an HTTP/HTTPS origin without a path"
  else
    [[ "$value" =~ ^https://(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9.-]+)(:[0-9]{1,5})?$ ]] || fail "$label must be an HTTPS origin without a path"
  fi
}

validate_configuration() {
  PUBLIC_URL="${PUBLIC_URL%/}"
  INSTALLER_PUBLIC_URL="${INSTALLER_PUBLIC_URL%/}"
  [[ -n "$PUBLIC_URL" ]] || fail "A public URL is required; pass --public-url or NACHO_PUBLIC_URL"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || fail "Invalid NachoPanel release version: $VERSION"
  [[ "$NODE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid Node.js version: $NODE_VERSION"
  [[ "$POSTGRESQL_VERSION" == "16" ]] || fail "Only PostgreSQL 16 is supported"
  [[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "Invalid GitHub repository; use OWNER/REPO"
  for source_url in "$RELEASE_BASE_URL" "$NODE_BASE_URL"; do
    [[ -z "$source_url" || ( "$source_url" =~ ^(https?|file)://[^[:space:]]+$ && "$source_url" != *$'\n'* && "$source_url" != *$'\r'* ) ]] || fail "Asset base URLs must use HTTP, HTTPS, or file without whitespace"
  done
  [[ "$AGENT_AUTH_MODE" == "required" || "$AGENT_AUTH_MODE" == "disabled" ]] || fail "Agent authentication must be required or disabled"
  if [[ "$AGENT_AUTH_MODE" == "disabled" ]]; then
    [[ $CONFIG_LOADED -eq 1 || $AGENT_AUTH_CONFIRMED -eq 1 ]] || fail "Disabling agent authentication requires explicit confirmation"
  fi
  [[ "$DATABASE_MODE" == "managed" || "$DATABASE_MODE" == "external" ]] || fail "Database mode must be managed or external"
  [[ "$PROXY_MODE" == "caddy" || "$PROXY_MODE" == "external" || "$PROXY_MODE" == "none" ]] || fail "Proxy mode must be caddy, external, or none"
  if [[ ! "$DATABASE_PORT" =~ ^[0-9]+$ ]] || (( DATABASE_PORT < 1 || DATABASE_PORT > 65535 )); then fail "PostgreSQL port is invalid"; fi
  if [[ ! "$APP_PORT" =~ ^[0-9]+$ ]] || (( APP_PORT < 1 || APP_PORT > 65535 )); then fail "Application port is invalid"; fi
  [[ "$API_ONLY" == "1" ]] || fail "Cloud deployments require NACHO_API_ONLY=1"
  [[ "$INTERNAL_HOST" == "127.0.0.1" || "$INTERNAL_HOST" == "::1" ]] || fail "Internal API runtime must bind to a loopback address"
  if [[ ! "$INTERNAL_PORT" =~ ^[0-9]+$ ]] || (( INTERNAL_PORT < 1 || INTERNAL_PORT > 65535 )); then fail "Internal API runtime port is invalid"; fi
  [[ "$INTERNAL_PORT" != "$APP_PORT" ]] || fail "Internal API runtime port must differ from the public application port"
  if [[ ! "$INSTALLER_PUBLIC_PORT" =~ ^[0-9]+$ ]] || (( INSTALLER_PUBLIC_PORT < 1 || INSTALLER_PUBLIC_PORT > 65535 )); then fail "Installer public port is invalid"; fi

  if [[ "$PROXY_MODE" == "none" ]]; then
    [[ $ALLOW_HTTP -eq 1 ]] || fail "Proxy mode none requires --allow-http"
    [[ "$PUBLIC_URL" == http://* ]] || fail "Proxy mode none requires an HTTP public URL"
    validate_origin "$PUBLIC_URL" 1 "Public URL"
    APP_HOST="${APP_HOST:-0.0.0.0}"
    INSTALLER_HOST="${INSTALLER_HOST:-0.0.0.0}"
    INSTALLER_PORT_VALUE="${INSTALLER_PORT_VALUE:-8090}"
  elif [[ "$PROXY_MODE" == "external" ]]; then
    validate_origin "$PUBLIC_URL" "$ALLOW_HTTP" "Public URL"
    APP_HOST="${APP_HOST:-0.0.0.0}"
    INSTALLER_HOST="${INSTALLER_HOST:-0.0.0.0}"
    INSTALLER_PORT_VALUE="${INSTALLER_PORT_VALUE:-8090}"
  else
    [[ "$PUBLIC_URL" =~ ^https://([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?)$ ]] || fail "Managed Caddy requires an HTTPS domain without a port or path"
    CADDY_DOMAIN="${BASH_REMATCH[1]}"
    [[ "$CADDY_DOMAIN" != "localhost" && ! "$CADDY_DOMAIN" =~ ^[0-9.]+$ ]] || fail "Managed Caddy requires a public DNS name"
    APP_HOST="127.0.0.1"
    INSTALLER_HOST="127.0.0.1"
    INSTALLER_PORT_VALUE="8091"
    if [[ $INSTALLER_GATEWAY_ENABLED -eq 1 ]]; then INSTALLER_PUBLIC_URL="https://$CADDY_DOMAIN:$INSTALLER_PUBLIC_PORT"; fi
  fi

  if [[ ! "$INSTALLER_PORT_VALUE" =~ ^[0-9]+$ ]] || (( INSTALLER_PORT_VALUE < 1 || INSTALLER_PORT_VALUE > 65535 )); then fail "Installer internal port is invalid"; fi
  if [[ $INSTALLER_GATEWAY_ENABLED -eq 1 && -n "$INSTALLER_PUBLIC_URL" ]]; then validate_origin "$INSTALLER_PUBLIC_URL" "$ALLOW_HTTP" "Installer public URL"; fi

  if [[ "$DATABASE_MODE" == "managed" ]]; then
    [[ "$DATABASE_USER" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || fail "Managed PostgreSQL user must contain lowercase letters, numbers, and underscores"
    [[ "$DATABASE_NAME" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || fail "Managed PostgreSQL database name must contain lowercase letters, numbers, and underscores"
    if [[ -n "$DATABASE_PASSWORD_FILE" ]]; then
      read_root_secret_file "$DATABASE_PASSWORD_FILE" "Database password"
      DATABASE_PASSWORD="$PROMPT_VALUE"
      DATABASE_PASSWORD_SOURCE="file"
    fi
    if [[ -n "$DATABASE_PASSWORD" ]]; then
      [[ ${#DATABASE_PASSWORD} -ge 12 && ${#DATABASE_PASSWORD} -le 256 ]] || fail "PostgreSQL password must contain 12-256 characters"
      DATABASE_VALUE=""
    elif [[ -z "$DATABASE_VALUE" ]]; then
      generate_password
    fi
  else
    if [[ -n "$DATABASE_FILE" ]]; then
      read_root_secret_file "$DATABASE_FILE" "Database URL"
      DATABASE_VALUE="$PROMPT_VALUE"
    fi
    if [[ -z "$DATABASE_VALUE" ]]; then
      [[ "$DATABASE_USER" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || fail "External PostgreSQL user is invalid; use DATABASE_URL for other identifiers"
      [[ "$DATABASE_NAME" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || fail "External PostgreSQL database name is invalid; use DATABASE_URL for other identifiers"
      [[ "$DATABASE_SSLMODE" == "require" || "$DATABASE_SSLMODE" == "prefer" || "$DATABASE_SSLMODE" == "disable" ]] || fail "External database SSL mode must be require, prefer, or disable"
      if [[ -n "$DATABASE_PASSWORD_FILE" ]]; then
        read_root_secret_file "$DATABASE_PASSWORD_FILE" "Database password"
        DATABASE_PASSWORD="$PROMPT_VALUE"
        DATABASE_PASSWORD_SOURCE="file"
      fi
      [[ -n "$DATABASE_PASSWORD" ]] || fail "External database credentials require --db-password-file, DATABASE_URL, or interactive input"
      build_external_database_url
    fi
    [[ "$DATABASE_VALUE" == postgresql://* || "$DATABASE_VALUE" == postgres://* ]] || fail "DATABASE_URL must use postgresql:// or postgres://"
    [[ "$DATABASE_VALUE" != *$'\n'* && "$DATABASE_VALUE" != *$'\r'* ]] || fail "DATABASE_URL must be a single line"
  fi
}

redact_database_url() {
  local value="$1"
  if [[ "$value" == *://*@* ]]; then
    printf '%s://***@%s' "${value%%://*}" "${value#*@}"
  else
    printf '[configured]'
  fi
}

show_summary_and_confirm() {
  local database_summary password_summary gateway_summary answer
  if [[ "$DATABASE_MODE" == "managed" ]]; then
    database_summary="managed PostgreSQL 16 on 127.0.0.1:$DATABASE_PORT, database=$DATABASE_NAME, user=$DATABASE_USER"
    [[ -n "$DATABASE_VALUE" ]] && password_summary="existing saved credential" || password_summary="$DATABASE_PASSWORD_SOURCE password"
  else
    database_summary="external $(redact_database_url "$DATABASE_VALUE")"
    password_summary="credential supplied"
  fi
  [[ $INSTALLER_GATEWAY_ENABLED -eq 1 ]] && gateway_summary="enabled (${INSTALLER_PUBLIC_URL:-external port 8090})" || gateway_summary="disabled"
  cat >"$TTY_DEVICE" <<EOF

Deployment summary
  Version:             $VERSION
  Public URL:          $PUBLIC_URL
  HTTPS proxy:         $PROXY_MODE
  Installer gateway:  $gateway_summary
  Agent authentication: $AGENT_AUTH_MODE
  Database:            $database_summary
  Database password:   $password_summary (redacted)

EOF
  prompt_yes_no "Apply this configuration" no
  answer="$PROMPT_VALUE"
  [[ "$answer" == "1" ]] || fail "Installation cancelled before system changes"
}

validate_platform() {
  local ID="" VERSION_ID="" VERSION=""
  [[ -r "$OS_RELEASE_FILE" ]] || fail "Cannot identify this Linux distribution"
  # shellcheck disable=SC1090
  source "$OS_RELEASE_FILE"
  case "${ID:-}" in
    ubuntu) [[ "${VERSION_ID:-}" == "22.04" || "${VERSION_ID:-}" == "24.04" ]] || fail "Supported Ubuntu versions are 22.04 and 24.04" ;;
    debian) [[ "${VERSION_ID:-}" == "12" ]] || fail "Supported Debian version is 12" ;;
    *) fail "Supported distributions are Ubuntu 22.04/24.04 and Debian 12" ;;
  esac
  [[ -d /run/systemd/system ]] || fail "systemd must be running as the service manager"
}

ensure_dependencies() {
  require_command apt-get
  log "Installing required operating-system packages"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar xz-utils coreutils findutils gawk sed grep passwd libc-bin util-linux systemd iproute2 gnupg
  for command in curl tar xz sha256sum awk sed grep find sort getent groupadd useradd runuser systemctl journalctl ss gpg stat od; do require_command "$command"; done
}

reconcile_managed_cluster() {
  local existing_cluster_port="$1" cluster_port="$2"
  if [[ -z "$existing_cluster_port" && -n "$cluster_port" && "$cluster_port" != "$DATABASE_PORT" ]]; then
    log "Recreating the new PostgreSQL cluster on requested port $DATABASE_PORT"
    pg_dropcluster --stop "$POSTGRESQL_VERSION" main
    cluster_port=""
  elif [[ -n "$existing_cluster_port" && $DATABASE_PORT_SET -eq 1 && "$cluster_port" != "$DATABASE_PORT" ]]; then
    fail "Existing PostgreSQL $POSTGRESQL_VERSION main cluster uses port $cluster_port; requested port $DATABASE_PORT cannot be applied"
  fi
  if [[ -z "$cluster_port" ]]; then
    if ss -ltnH "sport = :$DATABASE_PORT" | grep -q .; then fail "Port $DATABASE_PORT is already in use; choose another --db-port"; fi
    pg_createcluster --port "$DATABASE_PORT" "$POSTGRESQL_VERSION" main
    cluster_port="$DATABASE_PORT"
  fi
  PROMPT_VALUE="$cluster_port"
}

install_managed_postgresql() {
  local codename key_file keyring fingerprint existing_cluster_port cluster_port cluster_status psql password sql_file attempt
  local VERSION="" VERSION_CODENAME=""
  # shellcheck disable=SC1090
  source "$OS_RELEASE_FILE"
  codename="${VERSION_CODENAME:-}"
  [[ -n "$codename" ]] || fail "Linux distribution codename is unavailable"

  log "Installing managed PostgreSQL $POSTGRESQL_VERSION"
  if ! command -v pg_lsclusters >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-common
  fi
  existing_cluster_port=$(pg_lsclusters --no-header | awk -v version="$POSTGRESQL_VERSION" '$1 == version && $2 == "main" { print $3; exit }')
  keyring="/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg"
  install -d -m 0755 "$(dirname "$keyring")"
  key_file=$(mktemp)
  if ! curl -fsSL "https://www.postgresql.org/media/keys/ACCC4CF8.asc" -o "$key_file"; then rm -f "$key_file"; fail "Cannot download the PostgreSQL repository signing key"; fi
  fingerprint=$(gpg --batch --show-keys --with-colons "$key_file" | awk -F: '$1 == "fpr" { print $10; exit }')
  if [[ "$fingerprint" != "B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8" ]]; then rm -f "$key_file"; fail "PostgreSQL repository signing key verification failed"; fi
  gpg --batch --yes --dearmor --output "$keyring" "$key_file"
  chmod 0644 "$keyring"
  rm -f "$key_file"
  printf 'deb [signed-by=%s] https://apt.postgresql.org/pub/repos/apt %s-pgdg main\n' "$keyring" "$codename" > /etc/apt/sources.list.d/pgdg.list
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "postgresql-$POSTGRESQL_VERSION" "postgresql-client-$POSTGRESQL_VERSION"

  systemctl enable postgresql >/dev/null
  cluster_port=$(pg_lsclusters --no-header | awk -v version="$POSTGRESQL_VERSION" '$1 == version && $2 == "main" { print $3; exit }')
  reconcile_managed_cluster "$existing_cluster_port" "$cluster_port"
  cluster_port="$PROMPT_VALUE"
  if [[ -n "$DATABASE_VALUE" && "$DATABASE_PORT" != "$cluster_port" ]]; then
    fail "The saved database port $DATABASE_PORT does not match PostgreSQL cluster port $cluster_port"
  fi
  DATABASE_PORT="$cluster_port"
  pg_ctlcluster "$POSTGRESQL_VERSION" main start || true
  cluster_status=$(pg_lsclusters --no-header | awk -v version="$POSTGRESQL_VERSION" '$1 == version && $2 == "main" { print $4; exit }')
  [[ "$cluster_status" == "online" ]] || fail "PostgreSQL $POSTGRESQL_VERSION main cluster is not online"

  for ((attempt=1; attempt<=30; attempt++)); do
    if pg_isready -h 127.0.0.1 -p "$cluster_port" >/dev/null 2>&1; then break; fi
    sleep 1
  done
  pg_isready -h 127.0.0.1 -p "$cluster_port" >/dev/null 2>&1 || fail "PostgreSQL did not become ready"

  psql="/usr/lib/postgresql/$POSTGRESQL_VERSION/bin/psql"
  [[ -x "$psql" ]] || fail "PostgreSQL client is incomplete"
  if [[ -z "$DATABASE_VALUE" || -n "$DATABASE_PASSWORD" ]]; then
    password="$DATABASE_PASSWORD"
    [[ -n "$password" ]] || generate_password
    password="$DATABASE_PASSWORD"
    sql_file=$(mktemp)
    write_managed_database_sql "$sql_file" "$password"
    if ! runuser -u postgres -- "$psql" -v ON_ERROR_STOP=1 -p "$cluster_port" -d postgres <"$sql_file" >/dev/null 2>&1; then rm -f "$sql_file"; fail "PostgreSQL role or database creation failed; credentials were not logged"; fi
    rm -f "$sql_file"
    DATABASE_VALUE="postgresql://$(urlencode "$DATABASE_USER"):$(urlencode "$password")@127.0.0.1:$cluster_port/$(urlencode "$DATABASE_NAME")?sslmode=disable"
    DATABASE_PASSWORD=""
  else
    if ! runuser -u postgres -- "$psql" -v ON_ERROR_STOP=1 -p "$cluster_port" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DATABASE_NAME'" | grep -qx 1; then
      fail "The saved managed database is missing; restore it or provide new managed credentials"
    fi
  fi
  log "Managed PostgreSQL is ready on 127.0.0.1:$cluster_port"
}

ensure_database() {
  if [[ "$DATABASE_MODE" == "managed" ]]; then install_managed_postgresql; else log "Using the supplied external PostgreSQL database"; fi
}

write_managed_database_sql() {
  local target="$1" password="$2" password_sql
  password_sql=${password//\'/\'\'}
  {
    printf 'SET standard_conforming_strings = on;\n'
    printf "SELECT 'CREATE ROLE %s LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '%s') \\gexec\n" "$DATABASE_USER" "$DATABASE_USER"
    printf "ALTER ROLE %s WITH LOGIN PASSWORD '%s';\n" "$DATABASE_USER" "$password_sql"
    printf "SELECT 'CREATE DATABASE %s OWNER %s' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '%s') \\gexec\n" "$DATABASE_NAME" "$DATABASE_USER" "$DATABASE_NAME"
    printf "ALTER DATABASE %s OWNER TO %s;\n" "$DATABASE_NAME" "$DATABASE_USER"
  } >"$target"
  chmod 0600 "$target"
}

escape_env() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || fail "Environment values must be a single line"
  value=${value//\\/\\\\}; value=${value//\"/\\\"}; value=${value//\$/\\\$}; value=${value//\`/\\\`}
  printf '%s' "$value"
}

write_config() {
  install -d -m 0750 -o root -g nachopanel "$CONFIG_DIR"
  local temporary
  if [[ $CONFIG_CHANGED -eq 0 && -f "$ENV_FILE" ]]; then
    CONFIG_BACKUP=$(mktemp)
    cp -a "$ENV_FILE" "$CONFIG_BACKUP"
    CONFIG_EXISTED=1
  fi
  temporary=$(mktemp "$CONFIG_DIR/.nachopanel.env.XXXXXX")
  cat >"$temporary" <<EOF
NODE_ENV="production"
NACHO_VERSION="$(escape_env "$VERSION")"
NACHO_NODE_VERSION="$(escape_env "$NODE_VERSION")"
NACHO_POSTGRESQL_VERSION="$(escape_env "$POSTGRESQL_VERSION")"
NACHO_GITHUB_REPOSITORY="$(escape_env "$REPOSITORY")"
NACHO_PROXY_MODE="$(escape_env "$PROXY_MODE")"
NACHO_APP_HOST="$(escape_env "$APP_HOST")"
HOSTNAME="$(escape_env "$APP_HOST")"
PORT="$(escape_env "$APP_PORT")"
NACHO_API_ONLY="$(escape_env "$API_ONLY")"
NACHO_INTERNAL_HOST="$(escape_env "$INTERNAL_HOST")"
NACHO_INTERNAL_PORT="$(escape_env "$INTERNAL_PORT")"
NACHO_INSTALLER_HOST="$(escape_env "$INSTALLER_HOST")"
INSTALLER_PORT="$(escape_env "$INSTALLER_PORT_VALUE")"
NACHO_INSTALLER_PUBLIC_PORT="$(escape_env "$INSTALLER_PUBLIC_PORT")"
INSTALLER_GATEWAY_DISABLED="$([[ $INSTALLER_GATEWAY_ENABLED -eq 1 ]] && printf 0 || printf 1)"
NACHO_PUBLIC_URL="$(escape_env "$PUBLIC_URL")"
NACHO_AGENT_AUTH_MODE="$(escape_env "$AGENT_AUTH_MODE")"
NACHO_DATABASE_MODE="$(escape_env "$DATABASE_MODE")"
NACHO_DB_USER="$(escape_env "$DATABASE_USER")"
NACHO_DB_NAME="$(escape_env "$DATABASE_NAME")"
NACHO_DB_HOST="$(escape_env "$DATABASE_HOST")"
NACHO_DB_PORT="$(escape_env "$DATABASE_PORT")"
NACHO_DB_SSLMODE="$(escape_env "$DATABASE_SSLMODE")"
DATABASE_URL="$(escape_env "$DATABASE_VALUE")"
NACHO_DATA_DIR="$(escape_env "$DATA_DIR")"
NACHO_ARTIFACT_DIR="$(escape_env "$DATA_DIR/artifacts")"
EOF
  if [[ -n "$RELEASE_BASE_URL" ]]; then printf 'NACHO_RELEASE_BASE_URL="%s"\n' "$(escape_env "$RELEASE_BASE_URL")" >>"$temporary"; fi
  if [[ -n "$NODE_BASE_URL" ]]; then printf 'NACHO_NODE_BASE_URL="%s"\n' "$(escape_env "$NODE_BASE_URL")" >>"$temporary"; fi
  if [[ -n "$INSTALLER_PUBLIC_URL" ]]; then printf 'NACHO_INSTALLER_PUBLIC_URL="%s"\n' "$(escape_env "$INSTALLER_PUBLIC_URL")" >>"$temporary"; fi
  for name in NACHO_S3_BUCKET NACHO_S3_REGION NACHO_S3_ENDPOINT NACHO_S3_PATH_STYLE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
    if [[ -n "${!name:-}" ]]; then printf '%s="%s"\n' "$name" "$(escape_env "${!name}")" >>"$temporary"; fi
  done
  chmod 0600 "$temporary"
  chown root:root "$temporary"
  mv -f "$temporary" "$ENV_FILE"
  CONFIG_CHANGED=1
}

install_node_runtime() {
  local machine node_arch archive base expected actual staging
  machine=$(uname -m)
  case "$machine" in x86_64|amd64) node_arch="x64" ;; aarch64|arm64) node_arch="arm64" ;; *) fail "Unsupported architecture: $machine" ;; esac
  if [[ -x "$INSTALL_ROOT/runtime/node/bin/node" ]] && [[ "$($INSTALL_ROOT/runtime/node/bin/node --version)" == "v$NODE_VERSION" ]]; then return; fi
  archive="node-v$NODE_VERSION-linux-$node_arch.tar.xz"
  base="${NODE_BASE_URL:-https://nodejs.org/dist/v$NODE_VERSION}"
  base="${base%/}"
  staging=$(mktemp -d)
  curl -fsSL "$base/$archive" -o "$staging/$archive"
  curl -fsSL "$base/SHASUMS256.txt" -o "$staging/SHASUMS256.txt"
  expected=$(awk -v file="$archive" '$2 == file { print $1; exit }' "$staging/SHASUMS256.txt")
  actual=$(sha256sum "$staging/$archive" | awk '{print $1}')
  [[ -n "$expected" && "$actual" == "$expected" ]] || fail "Node.js checksum verification failed"
  rm -rf "$INSTALL_ROOT/runtime/node-v$NODE_VERSION" "$INSTALL_ROOT/runtime/node.new"
  mkdir -p "$INSTALL_ROOT/runtime/node-v$NODE_VERSION"
  tar -xJf "$staging/$archive" -C "$INSTALL_ROOT/runtime/node-v$NODE_VERSION" --strip-components=1
  ln -s "$INSTALL_ROOT/runtime/node-v$NODE_VERSION" "$INSTALL_ROOT/runtime/node.new"
  mv -Tf "$INSTALL_ROOT/runtime/node.new" "$INSTALL_ROOT/runtime/node"
  rm -rf "$staging"
}

download_release() {
  local base archive checksum staging expected actual unpack
  base="${RELEASE_BASE_URL:-https://github.com/$REPOSITORY/releases/download/v$VERSION}"
  base="${base%/}"
  archive="nachopanel-$VERSION.tar.gz"
  checksum="$archive.sha256"
  staging=$(mktemp -d)
  log "Downloading NachoPanel $VERSION from $REPOSITORY"
  curl -fsSL "$base/$archive" -o "$staging/$archive"
  curl -fsSL "$base/$checksum" -o "$staging/$checksum"
  expected=$(awk '{print $1; exit}' "$staging/$checksum")
  actual=$(sha256sum "$staging/$archive" | awk '{print $1}')
  [[ -n "$expected" && "$actual" == "$expected" ]] || fail "NachoPanel release checksum verification failed"
  NEW_RELEASE="$INSTALL_ROOT/releases/$VERSION-$(date -u +%Y%m%d%H%M%S)-$$"
  unpack="$INSTALL_ROOT/releases/.staging-$VERSION-$$"
  rm -rf "$unpack"; mkdir -p "$unpack"
  tar -xzf "$staging/$archive" -C "$unpack" --strip-components=1
  [[ -f "$unpack/server/host.mjs" && -f "$unpack/server/check-database.mjs" && -f "$unpack/server/migrate.mjs" && -f "$unpack/app/server.js" && -e "$unpack/node_modules/pg" ]] || fail "Release archive is incomplete"
  mv "$unpack" "$NEW_RELEASE"
  chown -R root:nachopanel "$NEW_RELEASE"
  chmod -R u=rwX,g=rX,o= "$NEW_RELEASE"
  rm -rf "$staging"
}

restore_caddy_configuration() {
  [[ $CADDY_CHANGED -eq 1 ]] || return 0
  if [[ -n "$CADDY_CONFIG_BACKUP" && -f "$CADDY_CONFIG_BACKUP" ]]; then cp -a "$CADDY_CONFIG_BACKUP" "$CADDY_FILE"; fi
  if [[ $CADDY_HAD_SNIPPET -eq 1 && -n "$CADDY_SNIPPET_BACKUP" && -f "$CADDY_SNIPPET_BACKUP" ]]; then
    cp -a "$CADDY_SNIPPET_BACKUP" "$CADDY_SNIPPET"
  else
    rm -f "$CADDY_SNIPPET"
  fi
  if command -v caddy >/dev/null 2>&1 && caddy validate --config "$CADDY_FILE" --adapter caddyfile >/dev/null 2>&1; then systemctl reload caddy >/dev/null 2>&1 || true; fi
  rm -f "$CADDY_SNIPPET_BACKUP"
  CADDY_CHANGED=0
}

restore_runtime_config() {
  [[ $CONFIG_CHANGED -eq 1 ]] || return 0
  if [[ $CONFIG_EXISTED -eq 1 && -n "$CONFIG_BACKUP" && -f "$CONFIG_BACKUP" ]]; then cp -a "$CONFIG_BACKUP" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
  rm -f "$CONFIG_BACKUP"
  CONFIG_CHANGED=0
}

rollback() {
  local code="$1"
  ROLLBACK_ENABLED=0
  trap - ERR
  restore_caddy_configuration
  restore_runtime_config
  if [[ $SWITCHED -eq 1 && -n "$PREVIOUS_RELEASE" && -d "$PREVIOUS_RELEASE" ]]; then
    log "Deployment failed; restoring $(basename "$PREVIOUS_RELEASE")"
    ln -s "$PREVIOUS_RELEASE" "$INSTALL_ROOT/current.rollback"
    mv -Tf "$INSTALL_ROOT/current.rollback" "$INSTALL_ROOT/current"
    systemctl daemon-reload || true
    systemctl restart "$SERVICE_NAME" || true
  elif [[ $SWITCHED -eq 1 ]]; then
    systemctl stop "$SERVICE_NAME" || true
    rm -f "$INSTALL_ROOT/current"
  fi
  exit "$code"
}

commit_deployment() {
  rm -f "$CONFIG_BACKUP" "$CADDY_SNIPPET_BACKUP"
  CONFIG_CHANGED=0
  CADDY_CHANGED=0
  SWITCHED=0
  ROLLBACK_ENABLED=0
  trap - ERR
}

activate_release() {
  PREVIOUS_RELEASE=$(readlink -f "$INSTALL_ROOT/current" 2>/dev/null || true)
  ln -s "$NEW_RELEASE" "$INSTALL_ROOT/current.new"
  mv -Tf "$INSTALL_ROOT/current.new" "$INSTALL_ROOT/current"
  SWITCHED=1
}

run_migrations() {
  export DATABASE_URL="$DATABASE_VALUE" NACHO_PROJECT_ROOT="$NEW_RELEASE" NACHO_VERSION="$VERSION"
  "$INSTALL_ROOT/runtime/node/bin/node" "$NEW_RELEASE/server/migrate.mjs"
}

check_external_database() {
  [[ "$DATABASE_MODE" == "external" ]] || return 0
  export DATABASE_URL="$DATABASE_VALUE" NACHO_PROJECT_ROOT="$NEW_RELEASE"
  "$INSTALL_ROOT/runtime/node/bin/node" "$NEW_RELEASE/server/check-database.mjs"
}

bootstrap_key() {
  export DATABASE_URL="$DATABASE_VALUE" NACHO_PROJECT_ROOT="$NEW_RELEASE" NACHO_VERSION="$VERSION"
  local result
  result=$("$INSTALL_ROOT/runtime/node/bin/node" "$NEW_RELEASE/server/admin-cli.mjs" key bootstrap --json)
  BOOTSTRAP_SECRET=$(printf '%s' "$result" | sed -n 's/.*"secret":"\([^"]*\)".*/\1/p')
}

wait_for_internal_health() {
  local response attempt
  for ((attempt=1; attempt<=45; attempt++)); do
    if response=$(curl -fsS "http://127.0.0.1:$APP_PORT/api/v1/health" 2>/dev/null) && printf '%s' "$response" | grep -q '"status":"ready"'; then return; fi
    sleep 1
  done
  journalctl -u "$SERVICE_NAME" -n 50 --no-pager >&2 || true
  fail "NachoPanel did not become healthy"
}

preflight_caddy() {
  getent ahosts "$CADDY_DOMAIN" >/dev/null 2>&1 || fail "DNS does not resolve for $CADDY_DOMAIN"
  if ! systemctl is-active --quiet caddy 2>/dev/null; then
    for port in 80 443; do
      if ss -ltnH "sport = :$port" | grep -q .; then fail "Port $port is already in use; choose proxy mode external"; fi
    done
    if [[ $INSTALLER_GATEWAY_ENABLED -eq 1 ]] && ss -ltnH "sport = :$INSTALLER_PUBLIC_PORT" | grep -q .; then fail "Port $INSTALLER_PUBLIC_PORT is already in use"; fi
  fi
}

write_caddy_snippet() {
  local target="$1"
  {
    printf 'https://%s {\n  encode zstd gzip\n  reverse_proxy 127.0.0.1:%s\n}\n' "$CADDY_DOMAIN" "$APP_PORT"
    if [[ $INSTALLER_GATEWAY_ENABLED -eq 1 ]]; then
      printf '\nhttps://%s:%s {\n  reverse_proxy 127.0.0.1:%s\n}\n' "$CADDY_DOMAIN" "$INSTALLER_PUBLIC_PORT" "$INSTALLER_PORT_VALUE"
    fi
  } >"$target"
  chmod 0644 "$target"
}

configure_caddy() {
  [[ "$PROXY_MODE" == "caddy" ]] || return 0
  local temporary caddy_preexisting=0
  if command -v caddy >/dev/null 2>&1; then caddy_preexisting=1; fi
  preflight_caddy
  log "Installing and configuring Caddy"
  DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
  install -d -m 0755 /etc/caddy/conf.d
  [[ -f "$CADDY_FILE" ]] || printf '# NachoPanel managed Caddy configuration\n' >"$CADDY_FILE"
  CADDY_CONFIG_BACKUP="$CADDY_FILE.nachopanel-backup-$(date -u +%Y%m%d%H%M%S)"
  cp -a "$CADDY_FILE" "$CADDY_CONFIG_BACKUP"
  if [[ -f "$CADDY_SNIPPET" ]]; then CADDY_SNIPPET_BACKUP=$(mktemp); cp -a "$CADDY_SNIPPET" "$CADDY_SNIPPET_BACKUP"; CADDY_HAD_SNIPPET=1; fi
  CADDY_CHANGED=1
  if [[ $caddy_preexisting -eq 0 ]]; then
    printf '# NachoPanel managed Caddy configuration\n\nimport /etc/caddy/conf.d/*.caddy\n' >"$CADDY_FILE"
  elif ! grep -Fqx 'import /etc/caddy/conf.d/*.caddy' "$CADDY_FILE"; then
    printf '\nimport /etc/caddy/conf.d/*.caddy\n' >>"$CADDY_FILE"
  fi
  temporary=$(mktemp /etc/caddy/conf.d/.nachopanel.XXXXXX)
  write_caddy_snippet "$temporary"
  mv -f "$temporary" "$CADDY_SNIPPET"
  if ! caddy validate --config "$CADDY_FILE" --adapter caddyfile; then
    fail "Caddy configuration validation failed"
  fi
  if ! systemctl enable --now caddy >/dev/null || ! systemctl reload caddy; then
    fail "Caddy failed to start or reload; the previous configuration was restored"
  fi
}

wait_for_public_health() {
  [[ "$PROXY_MODE" == "caddy" ]] || return 0
  local response attempt
  for ((attempt=1; attempt<=120; attempt++)); do
    if response=$(curl -fsS "$PUBLIC_URL/api/v1/health" 2>/dev/null) && printf '%s' "$response" | grep -q '"status":"ready"'; then return; fi
    sleep 1
  done
  journalctl -u caddy -n 50 --no-pager >&2 || true
  fail "Public HTTPS health check failed; verify DNS and ports 80/443"
}

cleanup_old_releases() {
  local current candidate line kept=0
  current=$(readlink -f "$INSTALL_ROOT/current" 2>/dev/null || true)
  while IFS= read -r line; do
    candidate=${line#* }
    [[ -n "$candidate" && -d "$candidate" ]] || continue
    [[ "$candidate" == "$current" ]] && continue
    kept=$((kept + 1))
    if [[ $kept -gt 2 ]]; then rm -rf -- "$candidate"; fi
  done < <(find "$INSTALL_ROOT/releases" -mindepth 1 -maxdepth 1 -type d ! -name '.staging-*' -printf '%T@ %p\n' | sort -rn)
}

collect_configuration() {
  load_existing_config
  apply_defaults
  if should_run_wizard; then run_wizard; fi
  apply_defaults
  validate_configuration
  if [[ $WIZARD_RAN -eq 1 ]]; then show_summary_and_confirm; fi
}

install_or_upgrade() {
  require_root
  validate_platform
  collect_configuration
  ensure_dependencies
  ensure_database
  getent group nachopanel >/dev/null || groupadd --system nachopanel
  id -u nachopanel >/dev/null 2>&1 || useradd --system --gid nachopanel --home-dir "$DATA_DIR" --shell /usr/sbin/nologin nachopanel
  install -d -m 0750 -o root -g nachopanel "$INSTALL_ROOT" "$INSTALL_ROOT/releases" "$INSTALL_ROOT/runtime"
  install -d -m 0750 -o nachopanel -g nachopanel "$DATA_DIR" "$DATA_DIR/artifacts"
  install_node_runtime
  download_release
  check_external_database
  write_config
  run_migrations
  activate_release
  install -m 0644 "$NEW_RELEASE/deploy/nachopanel.service" "$UNIT_FILE"
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null
  systemctl restart "$SERVICE_NAME"
  wait_for_internal_health
  configure_caddy
  wait_for_public_health
  install -m 0750 "$NEW_RELEASE/deploy/install.sh" /usr/local/sbin/nachopanelctl
  cleanup_old_releases || log "Warning: old release cleanup did not complete"
  bootstrap_key
  commit_deployment
  log "NachoPanel $VERSION is ready at $PUBLIC_URL"
  if [[ -n "$BOOTSTRAP_SECRET" ]]; then printf '\nAdministrator API Key (shown once):\n%s\n\n' "$BOOTSTRAP_SECRET"; else log "An active administrator API Key already exists; no new key was created"; fi
  log "Status: systemctl status $SERVICE_NAME"
  log "Manage: nachopanelctl <status|repair|upgrade|uninstall>"
}

show_status() {
  require_root
  load_existing_config
  systemctl status "$SERVICE_NAME" --no-pager || true
  if [[ -L "$INSTALL_ROOT/current" ]]; then log "Installed release: $(basename "$(readlink -f "$INSTALL_ROOT/current")")"; fi
  curl -fsS "http://127.0.0.1:${APP_PORT:-3000}/api/v1/health" || true
  printf '\n'
}

uninstall_service() {
  require_root
  systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f "$UNIT_FILE" /usr/local/sbin/nachopanelctl
  systemctl daemon-reload
  rm -rf "$INSTALL_ROOT"
  if [[ -f "$CADDY_SNIPPET" ]]; then
    rm -f "$CADDY_SNIPPET"
    if command -v caddy >/dev/null 2>&1 && caddy validate --config "$CADDY_FILE" --adapter caddyfile >/dev/null 2>&1; then systemctl reload caddy || true; fi
  fi
  if [[ $PURGE -eq 1 ]]; then
    rm -rf "$CONFIG_DIR" "$DATA_DIR"
    userdel nachopanel >/dev/null 2>&1 || true
    groupdel nachopanel >/dev/null 2>&1 || true
    log "NachoPanel configuration and artifacts were removed; PostgreSQL and Caddy data were preserved"
  else
    log "Service removed; configuration, artifacts, and PostgreSQL data were preserved"
  fi
}

main() {
  parse_args "$@"
  ROLLBACK_ENABLED=1
  trap 'rollback $?' ERR
  case "$ACTION" in
    install|upgrade|repair) install_or_upgrade ;;
    status) show_status ;;
    uninstall) uninstall_service ;;
    *) usage; exit 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
