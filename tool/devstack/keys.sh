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

# Until a password is set in its web UI, qBittorrent makes a new one at every start and logs it.
# The match stops at the first non-alphanumeric: some compose tools colour their log lines.
password=$(compose logs qbittorrent 2>&1 |
    sed -n 's/.*temporary password is provided for this session: *\([[:alnum:]]*\).*/\1/p' |
    tail -n 1) || true
row "qbittorrent user name" "admin"
printf '%-26s %s\n' "qbittorrent password" \
    "${password:-not in the log (not running, or you set your own in the web UI)}"
# qBittorrent writes its config file a few seconds after a key is created.
api_key=$(inside qbittorrent cat /config/qBittorrent/qBittorrent.conf |
    sed -n '/^\[WebUI\]/,/^$/s/^APIKey=//p')
printf '%-26s %s\n' "qbittorrent API key" \
    "${api_key:-none yet (create one in the web UI under Options, WebUI)}"

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
