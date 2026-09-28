#!/bin/sh
# Writes the runtime config the SPA reads (see src/authConfig.js).
# Runs on every container start, so `docker compose up` picks up .env changes
# without rebuilding the image.
set -eu

OUT=/usr/share/nginx/html/config.js

# Default the redirect URI to the published SPA port if not supplied.
: "${VITE_AZURE_REDIRECT_URI:=http://localhost:3000}"
: "${VITE_API_BASE_URL:=http://localhost:8080}"
: "${VITE_AZURE_CLIENT_ID:=}"
: "${VITE_AZURE_TENANT_ID:=}"
: "${VITE_API_SCOPE:=}"

cat > "$OUT" <<JS
window.__APP_CONFIG__ = {
  VITE_AZURE_CLIENT_ID: "${VITE_AZURE_CLIENT_ID}",
  VITE_AZURE_TENANT_ID: "${VITE_AZURE_TENANT_ID}",
  VITE_AZURE_REDIRECT_URI: "${VITE_AZURE_REDIRECT_URI}",
  VITE_API_BASE_URL: "${VITE_API_BASE_URL}",
  VITE_API_SCOPE: "${VITE_API_SCOPE}"
};
JS

echo "[spa] runtime config written to $OUT"
[ -n "${VITE_AZURE_CLIENT_ID}" ] || echo "[spa] WARNING: VITE_AZURE_CLIENT_ID is empty"
[ -n "${VITE_AZURE_TENANT_ID}" ] || echo "[spa] WARNING: VITE_AZURE_TENANT_ID is empty"
