# bootstrap-entra.ps1 — one-paste Entra ID setup for the local SSO stack (PowerShell).
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
# Requires: Azure CLI (https://learn.microsoft.com/cli/azure/install-azure-cli).
# No jq needed here — az's JSON output is parsed with ConvertFrom-Json.
#
# This is a line-for-line port of bootstrap-entra.sh — every check and every
# idempotency guard mirrors the bash version, which was run and verified
# against a real tenant. If you hit something this script doesn't handle,
# the bash version (run under WSL2 or Git Bash) is the more battle-tested path.

#Requires -Version 5.1

# ---------------------------------------------------------------------------
# 0. Locate the repo root.
#
# Deliberately NOT a param() block: this script is designed to be pasted
# directly into an interactive PowerShell prompt (copy the whole file, paste,
# Enter) as well as saved and dot-run. param() only works as the first
# statement of a saved .ps1 invoked with -File/&, and silently does nothing
# useful when pasted inline. An environment variable works identically both
# ways, matching the bash version's $1-or-cwd convention.
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'

function Write-Step  { param($msg) Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "  [ok] $msg" -ForegroundColor Green }
function Write-Warn2 { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }

# Normalizes az's -o tsv output: $null, an empty line, or the literal string
# "null" (JMESPath [0] on an empty result) all collapse to "". Never call
# .Trim() directly on az output — different az/PowerShell version
# combinations disagree on whether "no result" comes back as $null or "".
function ConvertTo-CleanString {
  param($value)
  if ($null -eq $value) { return "" }
  $s = [string]$value
  $s = $s.Trim()
  if ($s -eq 'null') { return "" }
  return $s
}

$RepoRoot = if ($env:ENTRACTIVE_REPO_ROOT) { $env:ENTRACTIVE_REPO_ROOT } else { (Get-Location).Path }

if (-not (Test-Path (Join-Path $RepoRoot 'docker-compose.yml'))) {
  Write-Host "error: $RepoRoot does not look like the repo root (no docker-compose.yml found)." -ForegroundColor Red
  Write-Host "Run this from the repo root, or set the path first:" -ForegroundColor Red
  Write-Host '  $env:ENTRACTIVE_REPO_ROOT = "C:\path\to\entractive"' -ForegroundColor Red
  exit 1
}
$EnvFile = Join-Path $RepoRoot '.env'

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Write-Error "error: Azure CLI (az) is not installed. https://learn.microsoft.com/cli/azure/install-azure-cli"
  exit 1
}

# ---------------------------------------------------------------------------
# 2. Sign in (skips if already signed in to a usable tenant)
# ---------------------------------------------------------------------------
Write-Step "Checking Azure CLI login state..."
$accountJson = $null
try {
  $accountJson = az account show -o json 2>$null | ConvertFrom-Json
} catch {
  $accountJson = $null
}
if (-not $accountJson) {
  Write-Step "Not signed in — opening browser login..."
  az login | Out-Null
  $accountJson = az account show -o json | ConvertFrom-Json
}
$TenantId = $accountJson.tenantId
$CurrentUser = $accountJson.user.name
Write-Ok "Signed in as $CurrentUser, tenant $TenantId"

$UserObjectId = ConvertTo-CleanString (az ad signed-in-user show --query id -o tsv)
Write-Ok "User object ID: $UserObjectId"

# ---------------------------------------------------------------------------
# 3. API app registration (idempotent: find-or-create)
# ---------------------------------------------------------------------------
$ApiAppName    = "sso-resource-server"
$ApiRoleValue  = "Resource.Admin"
$ApiScopeValue = "Api.Access"

Write-Step "Looking for existing '$ApiAppName' app registration..."
$apiAppJson = az ad app list --display-name $ApiAppName --query "[?displayName=='$ApiAppName'] | [0]" -o json | ConvertFrom-Json

if (-not $apiAppJson) {
  Write-Step "Not found — creating '$ApiAppName'..."
  $apiAppJson = az ad app create --display-name $ApiAppName --sign-in-audience AzureADMyOrg -o json | ConvertFrom-Json
  Write-Ok "Created $ApiAppName"
} else {
  Write-Ok "Found existing $ApiAppName — reusing it"
}
$ApiClientId     = $apiAppJson.appId
$ApiAppObjectId  = $apiAppJson.id

# --- Expose an API: identifierUri + Api.Access scope ---
$existingScopeId = ConvertTo-CleanString (az ad app show --id $ApiClientId `
  --query "api.oauth2PermissionScopes[?value=='$ApiScopeValue'].id | [0]" -o tsv)

if ([string]::IsNullOrEmpty($existingScopeId)) {
  Write-Step "Adding scope '$ApiScopeValue'..."
  $scopeId = [guid]::NewGuid().ToString()
  $apiPatch = @{
    identifierUris = @("api://$ApiClientId")
    api = @{
      oauth2PermissionScopes = @(@{
        id                      = $scopeId
        adminConsentDescription = "Allows the app to call the SSO demo resource server on behalf of the signed-in user."
        adminConsentDisplayName = "Access the resource server"
        userConsentDescription  = "Allows the app to call the SSO demo resource server on your behalf."
        userConsentDisplayName = "Access the resource server"
        value                   = $ApiScopeValue
        type                    = "User"
        isEnabled               = $true
      })
    }
  } | ConvertTo-Json -Depth 6

  $tmpFile = New-TemporaryFile
  [System.IO.File]::WriteAllText($tmpFile.FullName, $apiPatch, (New-Object System.Text.UTF8Encoding $false))
  az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/applications/$ApiAppObjectId" `
    --headers "Content-Type=application/json" `
    --body "@$tmpFile" | Out-Null
  Remove-Item $tmpFile -ErrorAction SilentlyContinue
  Write-Ok "Scope '$ApiScopeValue' added"
} else {
  $scopeId = $existingScopeId
  Write-Ok "Scope '$ApiScopeValue' already exists — reusing it"
}

# --- App role: Resource.Admin ---
$existingRoleId = ConvertTo-CleanString (az ad app show --id $ApiClientId `
  --query "appRoles[?value=='$ApiRoleValue'].id | [0]" -o tsv)

if ([string]::IsNullOrEmpty($existingRoleId)) {
  Write-Step "Adding app role '$ApiRoleValue'..."
  $roleId = [guid]::NewGuid().ToString()
  $rolePatch = @{
    appRoles = @(@{
      id                 = $roleId
      allowedMemberTypes = @("User")
      description        = "Callers holding this role may access role-gated endpoints."
      displayName        = "Resource Admin"
      value              = $ApiRoleValue
      isEnabled          = $true
    })
  } | ConvertTo-Json -Depth 6

  $tmpFile = New-TemporaryFile
  [System.IO.File]::WriteAllText($tmpFile.FullName, $rolePatch, (New-Object System.Text.UTF8Encoding $false))
  az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/applications/$ApiAppObjectId" `
    --headers "Content-Type=application/json" `
    --body "@$tmpFile" | Out-Null
  Remove-Item $tmpFile -ErrorAction SilentlyContinue
  $RoleIdFinal = $roleId
  Write-Ok "App role '$ApiRoleValue' added"
} else {
  $RoleIdFinal = $existingRoleId
  Write-Ok "App role '$ApiRoleValue' already exists — reusing it"
}

# ---------------------------------------------------------------------------
# 4. SPA app registration (idempotent: find-or-create)
# ---------------------------------------------------------------------------
$SpaAppName = "sso-spa"
$SpaPort = if ($env:SPA_HOST_PORT) { $env:SPA_HOST_PORT } else { "3000" }
$SpaRedirectUri = "http://localhost:$SpaPort"

Write-Step "Looking for existing '$SpaAppName' app registration..."
$spaAppJson = az ad app list --display-name $SpaAppName --query "[?displayName=='$SpaAppName'] | [0]" -o json | ConvertFrom-Json

if (-not $spaAppJson) {
  Write-Step "Not found — creating '$SpaAppName'..."
  $spaAppJson = az ad app create --display-name $SpaAppName --sign-in-audience AzureADMyOrg -o json | ConvertFrom-Json
  Write-Ok "Created $SpaAppName"
} else {
  Write-Ok "Found existing $SpaAppName — reusing it"
}
$SpaClientId    = $spaAppJson.appId
$SpaAppObjectId = $spaAppJson.id

# --- Redirect URI under the `spa` platform (NOT `web` — that needs a secret) ---
$existingRedirectsJson = az ad app show --id $SpaClientId --query "spa.redirectUris" -o json
$existingRedirects = @($existingRedirectsJson | ConvertFrom-Json)

if ($existingRedirects -contains $SpaRedirectUri) {
  Write-Ok "Redirect URI $SpaRedirectUri already registered under the SPA platform"
} else {
  Write-Step "Adding redirect URI $SpaRedirectUri under the SPA platform..."
  $mergedUris = @($existingRedirects + $SpaRedirectUri | Select-Object -Unique)
  $spaPatch = @{ spa = @{ redirectUris = $mergedUris } } | ConvertTo-Json -Depth 6

  $tmpFile = New-TemporaryFile
  [System.IO.File]::WriteAllText($tmpFile.FullName, $spaPatch, (New-Object System.Text.UTF8Encoding $false))
  az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/applications/$SpaAppObjectId" `
    --headers "Content-Type=application/json" `
    --body "@$tmpFile" | Out-Null
  Remove-Item $tmpFile -ErrorAction SilentlyContinue
  Write-Ok "Redirect URI added under the SPA platform"
}

# --- API permission: SPA -> API's Api.Access scope ---
$scopeIdForPerm = ConvertTo-CleanString (az ad app show --id $ApiClientId `
  --query "api.oauth2PermissionScopes[?value=='$ApiScopeValue'].id | [0]" -o tsv)

$hasPerm = ConvertTo-CleanString (az ad app show --id $SpaClientId `
  --query "requiredResourceAccess[?resourceAppId=='$ApiClientId'] | [0].resourceAccess[?id=='$scopeIdForPerm'] | [0].id" -o tsv)

if ([string]::IsNullOrEmpty($hasPerm)) {
  Write-Step "Granting SPA permission to call the API's '$ApiScopeValue' scope..."
  $permPatch = @{
    requiredResourceAccess = @(@{
      resourceAppId  = $ApiClientId
      resourceAccess = @(@{ id = $scopeIdForPerm; type = "Scope" })
    })
  } | ConvertTo-Json -Depth 6

  $tmpFile = New-TemporaryFile
  [System.IO.File]::WriteAllText($tmpFile.FullName, $permPatch, (New-Object System.Text.UTF8Encoding $false))
  az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/applications/$SpaAppObjectId" `
    --headers "Content-Type=application/json" `
    --body "@$tmpFile" | Out-Null
  Remove-Item $tmpFile -ErrorAction SilentlyContinue
  Write-Ok "Permission granted"
} else {
  Write-Ok "SPA already has permission to call the API"
}

# ---------------------------------------------------------------------------
# 5. Service principals (required before consent / role assignment)
# ---------------------------------------------------------------------------
Write-Step "Ensuring service principals exist for both apps..."

$apiSpId = ConvertTo-CleanString (az ad sp list --filter "appId eq '$ApiClientId'" --query "[0].id" -o tsv)
if ([string]::IsNullOrEmpty($apiSpId)) {
  $apiSpId = ConvertTo-CleanString (az ad sp create --id $ApiClientId --query id -o tsv)
  Write-Ok "Created service principal for the API"
} else {
  Write-Ok "Service principal for the API already exists"
}

$spaSpId = ConvertTo-CleanString (az ad sp list --filter "appId eq '$SpaClientId'" --query "[0].id" -o tsv)
if ([string]::IsNullOrEmpty($spaSpId)) {
  $spaSpId = ConvertTo-CleanString (az ad sp create --id $SpaClientId --query id -o tsv)
  Write-Ok "Created service principal for the SPA"
} else {
  Write-Ok "Service principal for the SPA already exists"
}

# ---------------------------------------------------------------------------
# 6. Tenant-wide admin consent for the delegated scope
# ---------------------------------------------------------------------------
$grantFilter = "clientId eq '$spaSpId' and resourceId eq '$apiSpId'"
$grantsJson = az rest --method GET `
  --uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=$grantFilter" `
  -o json | ConvertFrom-Json
$existingGrant = $null
if ($grantsJson.value -and $grantsJson.value.Count -gt 0) {
  $existingGrant = $grantsJson.value[0].id
}

if ([string]::IsNullOrEmpty($existingGrant)) {
  Write-Step "Granting tenant-wide admin consent for '$ApiScopeValue'..."
  $grantBody = @{
    clientId     = $spaSpId
    consentType  = "AllPrincipals"
    resourceId   = $apiSpId
    scope        = $ApiScopeValue
  } | ConvertTo-Json -Depth 6

  $tmpFile = New-TemporaryFile
  [System.IO.File]::WriteAllText($tmpFile.FullName, $grantBody, (New-Object System.Text.UTF8Encoding $false))
  az rest --method POST `
    --uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" `
    --headers "Content-Type=application/json" `
    --body "@$tmpFile" | Out-Null
  Remove-Item $tmpFile -ErrorAction SilentlyContinue
  Write-Ok "Admin consent granted"
} else {
  Write-Ok "Admin consent already granted"
}

# ---------------------------------------------------------------------------
# 7. Assign the Resource.Admin role to the signed-in user
# ---------------------------------------------------------------------------
$assignmentsJson = az rest --method GET `
  --uri "https://graph.microsoft.com/v1.0/users/$UserObjectId/appRoleAssignments" `
  -o json | ConvertFrom-Json

$existingAssignment = $null
foreach ($a in $assignmentsJson.value) {
  if ($a.appRoleId -eq $RoleIdFinal -and $a.resourceId -eq $apiSpId) {
    $existingAssignment = $a.id
    break
  }
}

if ([string]::IsNullOrEmpty($existingAssignment)) {
  Write-Step "Assigning '$ApiRoleValue' role to $CurrentUser..."
  $assignBody = @{
    principalId = $UserObjectId
    resourceId  = $apiSpId
    appRoleId   = $RoleIdFinal
  } | ConvertTo-Json -Depth 6

  $tmpFile = New-TemporaryFile
  [System.IO.File]::WriteAllText($tmpFile.FullName, $assignBody, (New-Object System.Text.UTF8Encoding $false))
  az rest --method POST `
    --uri "https://graph.microsoft.com/v1.0/users/$UserObjectId/appRoleAssignments" `
    --headers "Content-Type=application/json" `
    --body "@$tmpFile" | Out-Null
  Remove-Item $tmpFile -ErrorAction SilentlyContinue
  Write-Ok "Role assigned — sign out/in (or clear session storage) if you have an existing session, so a fresh token picks it up"
} else {
  Write-Ok "Role already assigned to $CurrentUser"
}

# ---------------------------------------------------------------------------
# 8. Write .env (back up any existing one first — never silently overwrite)
# ---------------------------------------------------------------------------
$ApiScope = "api://$ApiClientId/$ApiScopeValue"
$ApiPort = if ($env:API_HOST_PORT) { $env:API_HOST_PORT } else { "8080" }

if (Test-Path $EnvFile) {
  $stamp = Get-Date -Format "yyyyMMddHHmmss"
  $backup = "$EnvFile.bak.$stamp"
  Copy-Item -Path $EnvFile -Destination $backup
  Write-Warn2 "Existing .env backed up to $(Split-Path $backup -Leaf)"
}

$envLines = @(
  "TENANT_ID=$TenantId"
  "SPA_CLIENT_ID=$SpaClientId"
  "API_CLIENT_ID=$ApiClientId"
  "API_SCOPE=$ApiScope"
  "REQUIRED_ROLE=$ApiRoleValue"
  ""
  "SPA_REDIRECT_URI=http://localhost:$SpaPort"
  "API_BASE_URL=http://localhost:$ApiPort"
  "CORS_ALLOWED_ORIGINS=http://localhost:$SpaPort"
)

if ($SpaPort -ne "3000" -or $ApiPort -ne "8080") {
  $envLines += ""
  $envLines += "SPA_HOST_PORT=$SpaPort"
  $envLines += "API_HOST_PORT=$ApiPort"
}

# .NET WriteAllText with an explicit no-BOM UTF8Encoding, not Set-Content
# -Encoding utf8: Windows PowerShell 5.1's utf8 always writes a UTF-8 BOM,
# which breaks some .env parsers (Docker Compose's env_file handling has had
# BOM issues historically) — better not to risk it. Joined with `n so line
# endings are LF regardless of platform, matching the bash version's output
# and .env's usual convention.
$envContent = ($envLines -join "`n") + "`n"
[System.IO.File]::WriteAllText($EnvFile, $envContent, (New-Object System.Text.UTF8Encoding $false))

Write-Ok ".env written to $EnvFile"

Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host " Done. Every value above came from YOUR tenant ($TenantId)."
Write-Host " Next: docker compose up --build -d   (from $RepoRoot)"
Write-Host "----------------------------------------------------------------------"
