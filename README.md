# Local SSO stack — React SPA + Entra ID + Spring Boot

OAuth2 Authorization Code flow with PKCE, running end-to-end on Docker Desktop.
Implements the requirements in
[Requirements Specification – OAuth2 PKCE SSO Architecture (Local Docker Desktop).md](Requirements%20Specification%20%E2%80%93%20OAuth2%20PKCE%20SSO%20Architecture%20(Local%20Docker%20Desktop).md).

```
browser ──▶ spa (nginx :3000) ──▶ Entra ID (cloud) ──┐
                │                                     │ JWT
                └──────────▶ resource-server (:8080) ◀┘
```

Entra ID is **not** containerized — a real tenant is required. Everything else
runs locally.

## Prerequisites

- Docker Desktop 4.x with Compose v2, ≥4 GB RAM, ≥2 vCPUs
  - **macOS:** Apple silicon or Intel; both images build for the host arch
  - **Windows:** the WSL2 backend (the default). Run the commands from
    PowerShell, Command Prompt, or a WSL2 shell — Docker Desktop exposes the
    same `docker` CLI to all three
- Ports 3000 and 8080 free (overridable — see below)
- A Microsoft Entra ID tenant you can create app registrations in

No JDK, Maven, or Node install is needed on the host — both images build inside
Docker. Commands below are given for macOS/Linux and for Windows; `docker` and
`docker compose` invocations are byte-identical across all of them, so only the
surrounding shell builtins (copy a file, open a browser, chain commands) differ.

## Run it

Step 1 is the same everywhere: do the one-time Entra ID setup, which produces
the five values below — see [docs/entra-id-setup.md](docs/entra-id-setup.md).
Then pick your shell.

**macOS / Linux (bash, zsh)**

```bash
# 2. Configure
cp .env.example .env
$EDITOR .env          # TENANT_ID, SPA_CLIENT_ID, API_CLIENT_ID, API_SCOPE, REQUIRED_ROLE

# 3. Start
docker compose up --build -d

# 4. Open
open http://localhost:3000
```

**Windows (PowerShell)**

```powershell
# 2. Configure
Copy-Item .env.example .env
notepad .env          # TENANT_ID, SPA_CLIENT_ID, API_CLIENT_ID, API_SCOPE, REQUIRED_ROLE

# 3. Start
docker compose up --build -d

# 4. Open
Start-Process http://localhost:3000
```

**Windows (Command Prompt)**

```bat
REM 2. Configure
copy .env.example .env
notepad .env

REM 3. Start
docker compose up --build -d

REM 4. Open
start http://localhost:3000
```

First build takes ~2 minutes (Maven and npm dependency downloads); subsequent
`docker compose up` reaches healthy in about 11 seconds.

These are identical on macOS, Linux, and Windows:

```bash
docker compose ps              # both should read (healthy)
docker compose logs -f         # request-level logs from the resource server
docker compose down            # stop
```

### If ports 3000 / 8080 are taken

Set `SPA_HOST_PORT` / `API_HOST_PORT` in `.env`. Entra ID matches redirect URIs
exactly, so you must also update `SPA_REDIRECT_URI`, `CORS_ALLOWED_ORIGINS`, and
the redirect URI on the app registration. See
[docs/entra-id-setup.md](docs/entra-id-setup.md#changing-ports).

## What the app does

The SPA's buttons map one-to-one onto the spec's acceptance criteria:

| Button | Expected |
| --- | --- |
| Sign in with Microsoft | Redirect to Entra ID, return with a token (FR-1, FR-2) |
| Valid token | `200` + payload (FR-8) |
| No token | `401` (FR-6) |
| Tampered token | `401` (FR-5, FR-6) |
| Role-gated | `200` with the app role, `403` without (FR-7) |

Reload the page while signed in: MSAL re-acquires the token silently from
sessionStorage with no redirect (FR-3).

## Endpoints

| Method | Path | Auth |
| --- | --- | --- |
| GET | `/api/resource` | Any valid token |
| GET | `/api/admin` | Valid token carrying the app role |
| GET | `/actuator/health` | Public (used by the compose healthcheck) |

## Tests

With a JDK 21 and Maven on the host:

**macOS / Linux**

```bash
cd resource-server && mvn test
```

**Windows (PowerShell)**

```powershell
cd resource-server; mvn test
```

**Windows (Command Prompt)**

```bat
cd resource-server && mvn test
```

Without them — Docker only, which is all `docker compose up` needs. Same image
the Dockerfile builds with, and no `.env` required; only the path syntax differs:

**macOS / Linux**

```bash
docker run --rm -v "$PWD/resource-server":/build -w /build \
  maven:3.9-eclipse-temurin-21 mvn -B test
```

**Windows (PowerShell)**

```powershell
docker run --rm -v "${PWD}/resource-server:/build" -w /build `
  maven:3.9-eclipse-temurin-21 mvn -B test
```

**Windows (Command Prompt)**

```bat
docker run --rm -v "%cd%/resource-server:/build" -w /build maven:3.9-eclipse-temurin-21 mvn -B test
```

14 tests covering every resource-server acceptance criterion — valid token,
missing/malformed/expired token, untrusted signature, wrong audience, wrong
issuer, role present/absent/mismatched, and CORS from allowed and disallowed
origins. They run fully offline against a mock JWKS endpoint, so no tenant is
needed to run them.

## Layout

| Path | What |
| --- | --- |
| [spa/src/authConfig.js](spa/src/authConfig.js) | MSAL config, runtime env loading |
| [spa/src/api.js](spa/src/api.js) | Silent token acquisition + bearer calls |
| [spa/docker/env.sh](spa/docker/env.sh) | Writes `/config.js` from container env at startup |
| [resource-server/src/main/java/com/entractive/rs/SecurityConfig.java](resource-server/src/main/java/com/entractive/rs/SecurityConfig.java) | JWT validation, role mapping, CORS |
| [resource-server/src/main/java/com/entractive/rs/AudienceValidator.java](resource-server/src/main/java/com/entractive/rs/AudienceValidator.java) | Rejects tokens minted for another API |
| [docs/azure-account-setup-gui.md](docs/azure-account-setup-gui.md) | Starting from zero: account, tenant, and the permission walls |
| [docs/entra-id-setup.md](docs/entra-id-setup.md) | App registration walkthrough |
| [docs/verification.md](docs/verification.md) | What was proven, and how |

## Notes on two design decisions

**Config is injected at runtime, not build time.** Vite resolves
`import.meta.env` when the bundle is compiled, which would bake your tenant ID
into the image and contradict the spec's requirement to supply these via
`.env`/compose. Instead the container generates `/config.js` from its
environment on every start, so one image works across tenants and changing
`.env` needs only a restart.

**JWKS is fetched lazily.** Spring's `withIssuerLocation()` calls Microsoft's
discovery endpoint *during startup* and aborts the context if it fails, so the
container would refuse to boot before the Entra ID registrations exist or
without internet. The JWKS URI is derived by convention instead; a bad tenant
surfaces as a `401` on the first request rather than a crash loop.
