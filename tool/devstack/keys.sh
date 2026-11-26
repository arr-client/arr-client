#!/usr/bin/env bash
# Prints the keys and logins the running dev stack generated for itself, and the fingerprint of the
# self-signed certificate. Reads only; nothing is written to the repository. A service that has just
# started may need a few seconds before it has a key.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

compose() {
    docker compose -f "$here/compose.yaml" --profile best-effort "$@"
}

# inside SERVICE COMMAND... : output of a command in a running container, or nothing.
inside() {
    compose exec -T "$@" 2>/dev/null </dev/null || true
}

row() {
    printf '%-26s %s\n' "$1" "${2:-not available (not running, or not ready yet)}"
}

# Sonarr, Radarr, Lidarr, Readarr, Bookshelf and Prowlarr
xml_key() {
    inside "$1" cat /config/config.xml | sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p'
}

# Seerr, Overseerr and Jellyseerr
settings_key() {
    inside "$1" node -e 'console.log(require("/app/config/settings.json").main.apiKey)'
}

for service in sonarr radarr lidarr readarr prowlarr; do
    row "$service API key" "$(xml_key "$service")"
done
row "bazarr API key" "$(inside bazarr cat /config/config/config.yaml |
    sed -n '/^auth:/,/^[a-z]/s/^ *apikey: *//p' | tr -d "'\"")"
row "seerr API key" "$(settings_key seerr)"

# qBittorrent writes its config file a few seconds after a setting changes.
config=$(inside qbittorrent cat /config/qBittorrent/qBittorrent.conf)
webui=$(sed -n '/^\[WebUI\]/,/^$/p' <<<"$config")

# Until a password is set in its web UI, qBittorrent makes a new one at every start and logs it.
# The log outlives restarts, so it is only believed while the service runs with no password saved.
# The match stops at the first non-alphanumeric: some compose tools colour their log lines.
if [ -z "$config" ]; then
    password="not available (not running, or not ready yet)"
elif grep -q '^Password_PBKDF2=' <<<"$webui"; then
    password="the one you set in the web UI"
else
    password=$(compose logs qbittorrent 2>&1 |
        sed -n 's/.*temporary password is provided for this session: *\([[:alnum:]]*\).*/\1/p' |
        tail -n 1) || true
fi
row "qbittorrent user name" "admin"
row "qbittorrent password" "$password"
api_key=$(sed -n 's/^APIKey=//p' <<<"$webui")
no_key="none yet (create one in the web UI under Options, WebUI)"
[ -n "$config" ] || no_key=""
row "qbittorrent API key" "${api_key:-$no_key}"

# The best-effort profile; listed only when running.
key=$(xml_key bookshelf)
[ -z "$key" ] || row "bookshelf API key" "$key"
for service in overseerr jellyseerr; do
    key=$(settings_key "$service")
    [ -z "$key" ] || row "$service API key" "$key"
done

row "https-proxy certificate" \
    "$(inside https-proxy openssl x509 -in /certs/server.crt -noout -fingerprint -sha256 |
        sed 's/.*=/SHA-256 /')"
