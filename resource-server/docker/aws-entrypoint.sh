#!/bin/sh
# AWS image entrypoint: writes the SPA runtime config (/app/spa/config.js) from
# environment variables injected by ECS (secrets come from SSM Parameter Store),
# then starts the resource server. Same contract as spa/docker/env.sh, so
# changing a tenant/client ID needs no image rebuild - only a task restart.
set -eu

OUT=/app/spa/config.js

# IDs/URLs only. Refuse anything that could break out of the JS string literal.
clean() {
  case "$1" in
    *[!A-Za-z0-9:/._-]*) echo "[entrypoint] refusing unsafe value for $2" >&2; exit 1 ;;
  esac
  printf '%s' "$1"
}

CLIENT_ID=$(clean "${SPA_CLIENT_ID:-}" SPA_CLIENT_ID)
TENANT_ID=$(clean "${AZURE_TENANT_ID:-}" AZURE_TENANT_ID)
SCOPE=$(clean "${API_SCOPE:-}" API_SCOPE)
PUBLIC_URL=$(clean "${PUBLIC_URL:-}" PUBLIC_URL)

cat > "$OUT" <<JS
window.__APP_CONFIG__ = {
  VITE_AZURE_CLIENT_ID: "${CLIENT_ID}",
  VITE_AZURE_TENANT_ID: "${TENANT_ID}",
  VITE_AZURE_REDIRECT_URI: "${PUBLIC_URL}",
  VITE_API_BASE_URL: "",
  VITE_API_SCOPE: "${SCOPE}"
};
JS
echo "[entrypoint] wrote $OUT (redirect=${PUBLIC_URL:-unset})"
case "$CLIENT_ID$TENANT_ID" in *PLACEHOLDER*) echo "[entrypoint] WARNING: Entra IDs are still PLACEHOLDER values - sign-in will not work" ;; esac

exec java -XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError -jar /app/app.jar
