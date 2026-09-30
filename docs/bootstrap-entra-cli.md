# One-paste Entra ID setup (CLI)

[docs/entra-id-setup.md](entra-id-setup.md) walks the Azure portal by hand.
This does the same thing via the Azure CLI: paste one script, get a working
`.env` in the repo root. No portal clicking required.

Two scripts, same behavior — pick the one for your shell:

| Script | Shell | Verification status |
| --- | --- | --- |
| [scripts/bootstrap-entra.sh](scripts/bootstrap-entra.sh) | bash / zsh (macOS, Linux, WSL2, Git Bash) | **Run against a real tenant, twice** — see below |
| [scripts/bootstrap-entra.ps1](scripts/bootstrap-entra.ps1) | PowerShell (Windows, or pwsh anywhere) | **Not run** — no PowerShell available in the environment that wrote it. Carefully hand-reviewed and line-for-line mirrors the bash version's logic, but this is the honest status: read, not executed. |

If the PowerShell script hits a problem, the bash version under WSL2 or Git
Bash is the more battle-tested fallback — same script either way.

## What it does

Everything [entra-id-setup.md](entra-id-setup.md) describes by hand:

1. Signs in via `az login` (skipped if already signed in)
2. Creates the `sso-resource-server` API app registration — or finds it if it
   already exists
3. Adds the `Api.Access` scope and the `Resource.Admin` app role
4. Creates the `sso-spa` app registration under the **SPA** platform (not
   Web — see the warning in `entra-id-setup.md` on why that distinction
   matters)
5. Grants the SPA permission to call the API's scope, and admin-consents it
   tenant-wide
6. Creates service principals for both apps (required before the previous
   step can target them)
7. Assigns the `Resource.Admin` role to the signed-in user
8. Writes `.env` in the repo root with all five real values

**Idempotent.** Re-running it finds everything that already exists and skips
recreating it — safe to run again after a partial failure, or just to confirm
nothing has drifted. Confirmed live: creating from scratch and re-running
against the same tenant reports every check as already-satisfied on the
second pass, and produces byte-identical `.env` output both times.

**Never silently overwrites `.env`.** If one already exists, it's copied to
`.env.bak.<timestamp>` first.

## Run it

**macOS / Linux / WSL2 (bash, zsh)**

```bash
git clone https://github.com/<owner>/entractive.git
cd entractive
bash docs/scripts/bootstrap-entra.sh
```

**Windows (PowerShell)**

```powershell
git clone https://github.com/<owner>/entractive.git
cd entractive
.\docs\scripts\bootstrap-entra.ps1
```

If PowerShell blocks the script with an execution-policy error, run it for
this session only rather than changing the machine-wide policy:

```powershell
powershell -ExecutionPolicy Bypass -File .\docs\scripts\bootstrap-entra.ps1
```

Both scripts detect the repo root from the current directory (they check for
`docker-compose.yml`). Running from somewhere else:

```bash
# bash
bash docs/scripts/bootstrap-entra.sh /path/to/entractive
```
```powershell
# PowerShell
$env:ENTRACTIVE_REPO_ROOT = "C:\path\to\entractive"
.\docs\scripts\bootstrap-entra.ps1
```

## Prerequisites

- **Azure CLI** (`az`) — [learn.microsoft.com/cli/azure/install-azure-cli](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **jq** — bash script only. `brew install jq` / `apt install jq` / [jqlang.org/download](https://jqlang.org/download)
  (the PowerShell version parses JSON with `ConvertFrom-Json` and needs no
  extra tool)
- A Microsoft account. A tenant is auto-provisioned on first sign-in if you
  don't already have one, and app registrations need no paid Azure
  subscription

No Docker, no repo build tooling needed to run these scripts — they only talk
to Azure and write one file.

## Non-default ports

If 3000/8080 are taken, set the port env vars before running — the script
picks them up and writes the matching `SPA_HOST_PORT` / `API_HOST_PORT` /
`SPA_REDIRECT_URI` into `.env`, and registers the correct redirect URI on the
SPA app registration:

```bash
# bash
SPA_HOST_PORT=3100 API_HOST_PORT=8180 bash docs/scripts/bootstrap-entra.sh
```
```powershell
# PowerShell
$env:SPA_HOST_PORT = "3100"
$env:API_HOST_PORT = "8180"
.\docs\scripts\bootstrap-entra.ps1
```

Confirmed live: re-running with a new port adds the new redirect URI
alongside any existing one rather than replacing it, so switching ports and
switching back both keep working without re-running anything by hand.

## After it finishes

```bash
docker compose up --build -d
```

The role assignment (step 7) only affects **newly issued** tokens — if you
had an existing browser session before running this, sign out (or clear the
tab's session storage) so a fresh token picks it up.

## What it deliberately does not do

- **No client secret, anywhere.** The SPA is registered under the `spa`
  redirect platform specifically so it's a public PKCE client — consistent
  with NFR-1 in the requirements spec.
- **Doesn't touch `docker-compose.yml` or any other repo file** — only
  `.env`.
- **Doesn't grant broader directory permissions than needed.** It creates and
  configures exactly two app registrations and their service principals; it
  doesn't touch tenant-wide policy (if your account can't register apps at
  all, see the "insufficient privileges" section in
  [azure-account-setup-gui.md](azure-account-setup-gui.md)).
