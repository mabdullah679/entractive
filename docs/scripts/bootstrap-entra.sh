#!/usr/bin/env bash
# bootstrap-entra.sh — one-paste Entra ID setup for the local SSO stack.
#
# Does everything docs/entra-id-setup.md describes by hand, via the Azure CLI:
#   az login (if needed) -> create/find the two app registrations -> scope,
#   app role, redirect URI, permission grant, admin consent, role assignment
#   -> writes .env in the repo root.
#
# Idempotent: safe to re-run. Existing apps/scopes/roles/grants are found and
# reused rather than duplicated. An existing .env is backed up, never silently
# overwritten.
#
# Requires: az CLI (https://learn.microsoft.com/cli/azure/install-azure-cli),
# jq. Nothing else — no Docker, no repo build tooling, needed for this script.

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Locate the repo root (this script must be run from inside the clone, or
#    from anywhere if you pass the path as $1).
# ---------------------------------------------------------------------------
REPO_ROOT="${1:-$(pwd)}"
if [ ! -f "$REPO_ROOT/docker-compose.yml" ]; then
  echo "error: $REPO_ROOT does not look like the repo root (no docker-compose.yml found)." >&2
  echo "Run this from the repo root, or pass the path: bash bootstrap-entra.sh /path/to/entractive" >&2
  exit 1
fi
ENV_FILE="$REPO_ROOT/.env"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
command -v az  >/dev/null 2>&1 || { echo "error: Azure CLI (az) is not installed. https://learn.microsoft.com/cli/azure/install-azure-cli" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "error: jq is not installed (needed to parse az's JSON output)." >&2; exit 1; }

# ---------------------------------------------------------------------------
# 2. Sign in (skips if already signed in to a usable tenant)
# ---------------------------------------------------------------------------
log "Checking Azure CLI login state..."
if ! ACCOUNT_JSON=$(az account show -o json 2>/dev/null); then
  log "Not signed in — opening browser login..."
  az login >/dev/null
  ACCOUNT_JSON=$(az account show -o json)
fi
TENANT_ID=$(echo "$ACCOUNT_JSON" | jq -r '.tenantId')
CURRENT_USER=$(echo "$ACCOUNT_JSON" | jq -r '.user.name')
ok "Signed in as $CURRENT_USER, tenant $TENANT_ID"

# Resolve the signed-in user's object ID (needed later for role assignment).
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
ok "User object ID: $USER_OBJECT_ID"

# ---------------------------------------------------------------------------
# 3. API app registration (idempotent: find-or-create)
# ---------------------------------------------------------------------------
API_APP_NAME="sso-resource-server"
API_ROLE_VALUE="Resource.Admin"
API_SCOPE_VALUE="Api.Access"

log "Looking for existing '$API_APP_NAME' app registration..."
API_APP_JSON=$(az ad app list --display-name "$API_APP_NAME" --query "[?displayName=='$API_APP_NAME'] | [0]" -o json)

if [ "$API_APP_JSON" = "null" ] || [ -z "$API_APP_JSON" ]; then
  log "Not found — creating '$API_APP_NAME'..."
  API_APP_JSON=$(az ad app create --display-name "$API_APP_NAME" --sign-in-audience AzureADMyOrg -o json)
  ok "Created $API_APP_NAME"
else
  ok "Found existing $API_APP_NAME — reusing it"
fi
API_CLIENT_ID=$(echo "$API_APP_JSON" | jq -r '.appId')
API_APP_OBJECT_ID=$(echo "$API_APP_JSON" | jq -r '.id')

# --- Expose an API: identifierUri + Api.Access scope ---
EXISTING_SCOPE_ID=$(az ad app show --id "$API_CLIENT_ID" \
  --query "api.oauth2PermissionScopes[?value=='$API_SCOPE_VALUE'].id | [0]" -o tsv)

if [ -z "$EXISTING_SCOPE_ID" ] || [ "$EXISTING_SCOPE_ID" = "null" ]; then
  log "Adding scope '$API_SCOPE_VALUE'..."
  SCOPE_ID=$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s%N | md5sum | head -c 8)-0000-4000-8000-$(date +%s%N | md5sum | head -c 12)")
  cat > /tmp/entra-api-patch.$$.json <<JSON
{
  "identifierUris": ["api://$API_CLIENT_ID"],
  "api": {
    "oauth2PermissionScopes": [{
      "id": "$SCOPE_ID",
      "adminConsentDescription": "Allows the app to call the SSO demo resource server on behalf of the signed-in user.",
      "adminConsentDisplayName": "Access the resource server",
      "userConsentDescription": "Allows the app to call the SSO demo resource server on your behalf.",
      "userConsentDisplayName": "Access the resource server",
      "value": "$API_SCOPE_VALUE",
      "type": "User",
      "isEnabled": true
    }]
  }
}
JSON
  az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/$API_APP_OBJECT_ID" \
    --headers "Content-Type=application/json" \
    --body @/tmp/entra-api-patch.$$.json >/dev/null
  rm -f /tmp/entra-api-patch.$$.json
  ok "Scope '$API_SCOPE_VALUE' added"
else
  ok "Scope '$API_SCOPE_VALUE' already exists — reusing it"
fi

# --- App role: Resource.Admin ---
EXISTING_ROLE_ID=$(az ad app show --id "$API_CLIENT_ID" \
  --query "appRoles[?value=='$API_ROLE_VALUE'].id | [0]" -o tsv)

if [ -z "$EXISTING_ROLE_ID" ] || [ "$EXISTING_ROLE_ID" = "null" ]; then
  log "Adding app role '$API_ROLE_VALUE'..."
  ROLE_ID=$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s%N | md5sum | head -c 8)-0000-4000-8000-$(date +%s%N | md5sum | head -c 12)")
  cat > /tmp/entra-role-patch.$$.json <<JSON
{
  "appRoles": [{
    "id": "$ROLE_ID",
    "allowedMemberTypes": ["User"],
    "description": "Callers holding this role may access role-gated endpoints.",
    "displayName": "Resource Admin",
    "value": "$API_ROLE_VALUE",
    "isEnabled": true
  }]
}
JSON
  az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/$API_APP_OBJECT_ID" \
    --headers "Content-Type=application/json" \
    --body @/tmp/entra-role-patch.$$.json >/dev/null
  rm -f /tmp/entra-role-patch.$$.json
  ROLE_ID_FINAL="$ROLE_ID"
  ok "App role '$API_ROLE_VALUE' added"
else
  ROLE_ID_FINAL="$EXISTING_ROLE_ID"
  ok "App role '$API_ROLE_VALUE' already exists — reusing it"
fi

# ---------------------------------------------------------------------------
# 4. SPA app registration (idempotent: find-or-create)
# ---------------------------------------------------------------------------
SPA_APP_NAME="sso-spa"
SPA_PORT="${SPA_HOST_PORT:-3000}"
SPA_REDIRECT_URI="http://localhost:${SPA_PORT}"

log "Looking for existing '$SPA_APP_NAME' app registration..."
SPA_APP_JSON=$(az ad app list --display-name "$SPA_APP_NAME" --query "[?displayName=='$SPA_APP_NAME'] | [0]" -o json)

if [ "$SPA_APP_JSON" = "null" ] || [ -z "$SPA_APP_JSON" ]; then
  log "Not found — creating '$SPA_APP_NAME'..."
  SPA_APP_JSON=$(az ad app create --display-name "$SPA_APP_NAME" --sign-in-audience AzureADMyOrg -o json)
  ok "Created $SPA_APP_NAME"
else
  ok "Found existing $SPA_APP_NAME — reusing it"
fi
SPA_CLIENT_ID=$(echo "$SPA_APP_JSON" | jq -r '.appId')
SPA_APP_OBJECT_ID=$(echo "$SPA_APP_JSON" | jq -r '.id')

# --- Redirect URI under the `spa` platform (NOT `web` — that needs a secret) ---
EXISTING_REDIRECTS=$(az ad app show --id "$SPA_CLIENT_ID" --query "spa.redirectUris" -o json)
if echo "$EXISTING_REDIRECTS" | jq -e --arg uri "$SPA_REDIRECT_URI" 'index($uri) != null' >/dev/null 2>&1; then
  ok "Redirect URI $SPA_REDIRECT_URI already registered under the SPA platform"
else
  log "Adding redirect URI $SPA_REDIRECT_URI under the SPA platform..."
  MERGED_URIS=$(echo "$EXISTING_REDIRECTS" | jq --arg uri "$SPA_REDIRECT_URI" '. + [$uri] | unique')
  cat > /tmp/entra-spa-patch.$$.json <<JSON
{ "spa": { "redirectUris": $MERGED_URIS } }
JSON
  az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/$SPA_APP_OBJECT_ID" \
    --headers "Content-Type=application/json" \
    --body @/tmp/entra-spa-patch.$$.json >/dev/null
  rm -f /tmp/entra-spa-patch.$$.json
  ok "Redirect URI added under the SPA platform"
fi

# --- API permission: SPA -> API's Api.Access scope ---
SCOPE_ID_FOR_PERM=$(az ad app show --id "$API_CLIENT_ID" \
  --query "api.oauth2PermissionScopes[?value=='$API_SCOPE_VALUE'].id | [0]" -o tsv)
HAS_PERM=$(az ad app show --id "$SPA_CLIENT_ID" \
  --query "requiredResourceAccess[?resourceAppId=='$API_CLIENT_ID'] | [0].resourceAccess[?id=='$SCOPE_ID_FOR_PERM'] | [0].id" -o tsv 2>/dev/null || echo "")

if [ -z "$HAS_PERM" ]; then
  log "Granting SPA permission to call the API's '$API_SCOPE_VALUE' scope..."
  cat > /tmp/entra-perm-patch.$$.json <<JSON
{
  "requiredResourceAccess": [{
    "resourceAppId": "$API_CLIENT_ID",
    "resourceAccess": [{ "id": "$SCOPE_ID_FOR_PERM", "type": "Scope" }]
  }]
}
JSON
  az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/$SPA_APP_OBJECT_ID" \
    --headers "Content-Type=application/json" \
    --body @/tmp/entra-perm-patch.$$.json >/dev/null
  rm -f /tmp/entra-perm-patch.$$.json
  ok "Permission granted"
else
  ok "SPA already has permission to call the API"
fi

# ---------------------------------------------------------------------------
# 5. Service principals (required before consent / role assignment)
# ---------------------------------------------------------------------------
log "Ensuring service principals exist for both apps..."
API_SP_ID=$(az ad sp list --filter "appId eq '$API_CLIENT_ID'" --query "[0].id" -o tsv)
if [ -z "$API_SP_ID" ] || [ "$API_SP_ID" = "null" ]; then
  API_SP_ID=$(az ad sp create --id "$API_CLIENT_ID" --query id -o tsv)
  ok "Created service principal for the API"
else
  ok "Service principal for the API already exists"
fi

SPA_SP_ID=$(az ad sp list --filter "appId eq '$SPA_CLIENT_ID'" --query "[0].id" -o tsv)
if [ -z "$SPA_SP_ID" ] || [ "$SPA_SP_ID" = "null" ]; then
  SPA_SP_ID=$(az ad sp create --id "$SPA_CLIENT_ID" --query id -o tsv)
  ok "Created service principal for the SPA"
else
  ok "Service principal for the SPA already exists"
fi

# ---------------------------------------------------------------------------
# 6. Tenant-wide admin consent for the delegated scope
# ---------------------------------------------------------------------------
EXISTING_GRANT=$(az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?\$filter=clientId eq '$SPA_SP_ID' and resourceId eq '$API_SP_ID'" \
  -o json | jq -r '.value[0].id // empty')

if [ -z "$EXISTING_GRANT" ]; then
  log "Granting tenant-wide admin consent for '$API_SCOPE_VALUE'..."
  cat > /tmp/entra-grant.$$.json <<JSON
{
  "clientId": "$SPA_SP_ID",
  "consentType": "AllPrincipals",
  "resourceId": "$API_SP_ID",
  "scope": "$API_SCOPE_VALUE"
}
JSON
  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" \
    --headers "Content-Type=application/json" \
    --body @/tmp/entra-grant.$$.json >/dev/null
  rm -f /tmp/entra-grant.$$.json
  ok "Admin consent granted"
else
  ok "Admin consent already granted"
fi

# ---------------------------------------------------------------------------
# 7. Assign the Resource.Admin role to the signed-in user
# ---------------------------------------------------------------------------
EXISTING_ASSIGNMENT=$(az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/users/$USER_OBJECT_ID/appRoleAssignments" \
  -o json | jq -r --arg role "$ROLE_ID_FINAL" --arg sp "$API_SP_ID" \
    '.value[] | select(.appRoleId == $role and .resourceId == $sp) | .id' | head -1)

if [ -z "$EXISTING_ASSIGNMENT" ]; then
  log "Assigning '$API_ROLE_VALUE' role to $CURRENT_USER..."
  cat > /tmp/entra-roleassign.$$.json <<JSON
{
  "principalId": "$USER_OBJECT_ID",
  "resourceId": "$API_SP_ID",
  "appRoleId": "$ROLE_ID_FINAL"
}
JSON
  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/users/$USER_OBJECT_ID/appRoleAssignments" \
    --headers "Content-Type=application/json" \
    --body @/tmp/entra-roleassign.$$.json >/dev/null
  rm -f /tmp/entra-roleassign.$$.json
  ok "Role assigned — sign out/in (or clear session storage) if you have an existing session, so a fresh token picks it up"
else
  ok "Role already assigned to $CURRENT_USER"
fi

# ---------------------------------------------------------------------------
# 8. Write .env (back up any existing one first — never silently overwrite)
# ---------------------------------------------------------------------------
API_SCOPE="api://${API_CLIENT_ID}/${API_SCOPE_VALUE}"
API_PORT="${API_HOST_PORT:-8080}"

if [ -f "$ENV_FILE" ]; then
  BACKUP="${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$ENV_FILE" "$BACKUP"
  warn "Existing .env backed up to $(basename "$BACKUP")"
fi

cat > "$ENV_FILE" <<ENVFILE
TENANT_ID=${TENANT_ID}
SPA_CLIENT_ID=${SPA_CLIENT_ID}
API_CLIENT_ID=${API_CLIENT_ID}
API_SCOPE=${API_SCOPE}
REQUIRED_ROLE=${API_ROLE_VALUE}

SPA_REDIRECT_URI=http://localhost:${SPA_PORT}
API_BASE_URL=http://localhost:${API_PORT}
CORS_ALLOWED_ORIGINS=http://localhost:${SPA_PORT}
ENVFILE

if [ "$SPA_PORT" != "3000" ] || [ "$API_PORT" != "8080" ]; then
  {
    echo ""
    echo "SPA_HOST_PORT=${SPA_PORT}"
    echo "API_HOST_PORT=${API_PORT}"
  } >> "$ENV_FILE"
fi

ok ".env written to $ENV_FILE"

echo ""
echo "----------------------------------------------------------------------"
echo " Done. Every value above came from YOUR tenant ($TENANT_ID)."
echo " Next: docker compose up --build -d   (from $REPO_ROOT)"
echo "----------------------------------------------------------------------"
