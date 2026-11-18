# EntrActive — Local Sign-In and Access Control Demo

## Recruiter-friendly overview
EntrActive is a complete demonstration of how a modern application securely signs users in with Microsoft, checks who they are, and controls which features they can use. It combines a simple web interface with a backend service and runs locally through Docker, making the full sign-in journey easy to reproduce and test. The project demonstrates practical experience with security, cloud identity, APIs, containers, and automated testing.

## Project description
A local end-to-end single sign-on application using Microsoft Entra ID, OAuth 2.0 with PKCE, a React web app, and a Spring Boot backend that validates tokens and role-based permissions.

---

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
the five values below — see [docs/entra-id-setup.md](docs/entra-id-setup.md)
for the portal walkthrough, or
[docs/bootstrap-entra-cli.md](docs/bootstrap-entra-cli.md) to do the same
thing with one pasted script (bash or PowerShell) instead of clicking through
the portal. Then pick your shell.

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

A rebuild with warm Docker layers took 36 s to a healthy stack on the M1 Max
(measured 2026-11-18, SHA 57f11e6); the first build also downloads Maven and npm
dependencies and takes longer (not re-measured).

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

## What it does

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
| GET | `/api/resource` | Valid token (signature, issuer, audience) with scope `Api.Access` |
| GET | `/api/admin` | Same, plus the app role (`REQUIRED_ROLE`, default `Resource.Admin`) |
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

31 tests (20 API, 11 SPA-serving), run on 2026-11-18 at baseline: 31 passed, 0
failed. They cover valid, missing, malformed and expired tokens, untrusted
signature, wrong audience, wrong issuer, scope, role present/absent/mismatched,
CORS from allowed and disallowed origins, and the SPA-serving rules. They run
fully offline against a mock JWKS endpoint, so no tenant and no `.env` are
needed (verified: `mvn test` passes with no `AZURE_*` variables set).

### UI tests (Playwright)

[e2e/](e2e) drives the real page in Chromium against the running compose stack:

```bash
docker compose up --build -d          # with a .env, see Run it
cd e2e && npm install && npx playwright install chromium && npx playwright test
```

3 tests: the signed-out page renders, the "no token" button shows `401` that came
from the real API through the browser, and a deep route falls back to the SPA.
**Not covered:** anything after a Microsoft sign-in (valid token, role-gated
button) because that needs a real Entra ID tenant and an interactive login.

## API collection (Bruno)

[bruno/entractive-sso](bruno/entractive-sso) is a [Bruno](https://www.usebruno.com)
collection that exercises every endpoint. Open that folder in Bruno (or run
`bru run <folder> --env local` from inside it) and select the `local`
environment. Each folder runs its prerequisites first, in order.

| Folder | Needs sign-in? | What it covers |
| --- | --- | --- |
| `00-stack-health` | No | API health, SPA healthz, runtime `config.js`, deep-route fallback |
| `01-api-rejects-unauthenticated` | No | `401` for missing/malformed token, CORS preflight allowed and refused |
| `02-authenticated-calls` | **Yes** | Authorize, token exchange, `/api/resource`, `/api/admin`, ID-token-as-bearer `401`, refresh grant |

Before running: edit `environments/local.bru` so `spaClientId`, `apiClientId`,
`apiScope`, `redirectUri` and `apiBaseUrl` match your `.env` (the checked-in
values are one developer's tenant and ports 3100/8180). The `config.js` request
fails loudly if they have drifted from the running container.

Folder `02` cannot be fully scripted: Entra ID needs an interactive sign-in. Sign
in at the SPA once and either set the `entraSsoCookie` runtime variable
(`ESTSAUTHPERSISTENT` from DevTools) or paste a live `accessToken`. Pasting only
`accessToken` covers `/api/resource` and `/api/admin`; the ID-token and refresh
requests also need `idToken` and `refreshToken`, which only the token exchange sets.

## Layout

| Path | What |
| --- | --- |
| [spa/src/authConfig.js](spa/src/authConfig.js) | MSAL config, runtime env loading |
| [spa/src/api.js](spa/src/api.js) | Silent token acquisition + bearer calls |
| [spa/docker/env.sh](spa/docker/env.sh) | Writes `/config.js` from container env at startup |
| [resource-server/src/main/java/com/entractive/rs/SecurityConfig.java](resource-server/src/main/java/com/entractive/rs/SecurityConfig.java) | JWT validation, role mapping, CORS |
| [resource-server/src/main/java/com/entractive/rs/AudienceValidator.java](resource-server/src/main/java/com/entractive/rs/AudienceValidator.java) | Rejects tokens minted for another API |
| [e2e/](e2e) | Playwright UI tests against the compose stack |
| [.github/workflows/ci.yml](.github/workflows/ci.yml) | Pull-request checks (no AWS access) |
| [docs/azure-account-setup-gui.md](docs/azure-account-setup-gui.md) | Starting from zero: account, tenant, and the permission walls |
| [docs/entra-id-setup.md](docs/entra-id-setup.md) | App registration walkthrough |
| [docs/bootstrap-entra-cli.md](docs/bootstrap-entra-cli.md) | Same setup, scripted — one paste instead of the portal |
| [docs/getting-started.html](docs/getting-started.html) | Interactive, self-contained setup guide (open in a browser) |
| [docs/engineering-briefing.html](docs/engineering-briefing.html) | Standalone technical reference — architecture, CLI command reference, error codes, known defects |
| [docs/verification.md](docs/verification.md) | What was proven on 2026-09-25, and how (that record says 13 tests; the suite has grown since) |
| [bruno/entractive-sso](bruno/entractive-sso) | Bruno collection: one request per endpoint and failure mode |

## Design decisions (local stack)

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

---

# Deployed on AWS (Terraform + GitHub Actions)

The same app, run as a production-style deployment in AWS account `346208529954`, region `ap-southeast-2`, built and deployed by a GitHub Actions pipeline that authenticates with OIDC (no AWS keys stored anywhere). Branch: `prod-hardening`. Entra ID is still external: the deployment uses its own app registrations, `sso-aws-spa` and `sso-aws-resource-server`.

```
browser ──HTTPS──▶ API Gateway (HTTP API, *.execute-api.ap-southeast-2.amazonaws.com)
                        │  adds secret header X-Origin-Verify
                        ▼
                   ALB :80 (403 unless header matches) ──▶ ECS Fargate task :8080
                                                           Spring Boot: serves the SPA + /api/** + /actuator/health
browser ◀──redirect──▶ Entra ID (cloud)      task pulls IDs from SSM Parameter Store, JWKS from Entra
```

Not contained in AWS: the Entra ID tenant and app registrations. The IDs live in SSM Parameter Store under `/pf-entractive/` and are read at task start.

## Deployed on AWS: evidence

| Item | Value |
|---|---|
| Date | 2026-10-20 |
| URL pattern | `https://<id>.execute-api.ap-southeast-2.amazonaws.com` (this run: `i33sbovbcd`) |
| Deployed commit | `98c81e2`, run `39395659656` (GitHub Actions: test, plan, apply, smoke all green) |
| Smoke test (`scripts/smoke.sh`, run by the pipeline) | all checks passed: `/` 200 and contains the React root, deep route falls back to the app, HSTS/CSP/nosniff headers, `config.js` points at the deployed origin, `/actuator/health` UP, no token, garbage token, `alg=none` token and a forged RS256 token (wrong key, wrong audience) all returned 401, direct hits on the ALB DNS name returned 403 |
| Real sign-in | Sign-in completed by the owner personally on 2026-10-20 (owner-attested). The resource server's CloudWatch log showed `GET /api/resource -> 200` and `GET /api/admin -> 200` with a bearer token present, but a log line cannot say who signed in, so the log is corroboration, not proof of identity. In the same session "Tampered token" returned 401. |
| Status | Verified live on 2026-10-20, then torn down the same day to save cost (stack and bootstrap both destroyed). The URL no longer responds. The two Entra app registrations were left in place; the deployment's redirect URI was removed from `sso-aws-spa`. |

Resources created (all prefixed `pf-entractive-`, tagged `project=portfolio`, `repo=entractive`, `managed-by=terraform`): 1 VPC with 2 public subnets, internet gateway and route table (no NAT gateway); 2 security groups; 1 ALB with listener, rule and target group; 1 ECS cluster, task definition and service (Fargate, 0.25 vCPU, 1 GB); 1 execution role; 1 CloudWatch log group (7-day retention); 1 API Gateway HTTP API with stage, 2 integrations and 2 routes; plus, from the bootstrap step, a state bucket, an ECR repository, 4 SSM parameters and 2 GitHub OIDC roles.

Estimated cost while up: about 0.065 USD per hour (Fargate about 0.018, ALB about 0.03, three public IPv4 addresses about 0.015, the rest negligible). This is an estimate from published rates, not an invoice.

## Destroy and rebuild

Destroy (stack first, bootstrap last; both need AWS credentials for account 346208529954):

```
cd infra/stack     && terraform init && terraform destroy -var image_tag=x
cd ../bootstrap    && terraform destroy
```

## Rebuild with one command

The bootstrap was also destroyed, so a rebuild is three steps. (0) The `prod-hardening` branch was deleted after the merge, and the pipeline's AWS role trusts only that branch (`infra/bootstrap/main.tf`, variable `github_branch`), so recreate it from `main` first: `git push origin main:refs/heads/prod-hardening`. (1) With AWS credentials for the account and Terraform 1.10 or newer: `cd infra/bootstrap && terraform init && terraform apply` (needs the existing GitHub OIDC provider and the `portfolio-ci-boundary` policy; the role trust pins this repo's immutable GitHub IDs in `github_subject_repo`). (2) Set the four SSM parameters, then re-run the pipeline (`gh workflow run ci-cd --ref prod-hardening`, or push to `prod-hardening`); it builds the image, applies Terraform and smoke-tests the result.

```
aws ssm put-parameter --name /pf-entractive/tenant-id     --type String --overwrite --value <tenant id>
aws ssm put-parameter --name /pf-entractive/spa-client-id --type String --overwrite --value <spa client id>
aws ssm put-parameter --name /pf-entractive/api-client-id --type String --overwrite --value <api client id>
aws ssm put-parameter --name /pf-entractive/api-scope     --type String --overwrite --value api://<api client id>/Api.Access
```

No code change is needed to point the deployment at a different tenant: update the parameters and re-run the pipeline. After a new deploy the API Gateway URL changes, so add the new `https://<id>.execute-api...` address as a SPA redirect URI on the SPA app registration (`docs/entra-id-setup.md`) or sign-in will be refused.

## What it does (AWS)

| Action | Expected result | Evidence |
|---|---|---|
| Open the URL | React app loads over HTTPS | smoke test, browser |
| Sign in with Microsoft | Redirect to Entra ID and back, PKCE, no secret in the bundle | browser |
| Valid token to `/api/resource` | 200 | browser + CloudWatch log |
| No token, garbage token, forged token, wrong-audience token | 401 | smoke test |
| Valid token with the wrong scope or no `Api.Access` scope | 403 | unit tests |
| Valid token without the admin role to `/api/admin` | 403 | unit tests |
| Call the ALB directly (skipping API Gateway) | 403 | smoke test |

## Interfaces (AWS)

| Method and path | Auth |
|---|---|
| `GET /`, `/config.js`, `/assets/**`, client-side routes | public |
| `GET /actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness` | public |
| `GET /api/resource` | bearer token: valid signature, issuer, audience, scope `Api.Access` |
| `GET /api/admin` | same, plus app role `Resource.Admin` |

## Tests and pipeline (AWS)

- Resource server: `cd resource-server && mvn test`. 31 tests (20 API, 11 SPA-serving), offline with a mock JWKS endpoint, no tenant or AWS needed. Needs JDK 21 or newer and Maven.
- The audience guard, issuer guard, scope guard, the `/api` exclusion from the SPA fallback, the ordering of the public-SPA rule versus the `/api` guard, and the missing-file 404 were each mutated and the matching test was seen going red, then the exact edit was reversed.
- Pipeline (`.github/workflows/deploy.yml`): lint/test/build, then `terraform fmt`/`validate`/`plan` with a read-only role, then image build, `terraform apply` with a scoped role, and `scripts/smoke.sh`. It runs only on push to `prod-hardening` and manual dispatch; pull requests are checked by `ci.yml` (resource-server tests, SPA build, shell lint, `terraform fmt`/`validate` with the backend disabled, gitleaks), which needs no AWS access. All actions in both workflows are pinned to commit SHAs.

## Layout (AWS additions)

| Path | Role |
|---|---|
| [Dockerfile.aws](Dockerfile.aws) | multi-stage image: builds the SPA and the API, runs as non-root uid 10001 |
| [resource-server/docker/aws-entrypoint.sh](resource-server/docker/aws-entrypoint.sh) | writes the SPA runtime config from env vars, then starts Java |
| [resource-server/src/main/java/com/entractive/rs/SpaConfig.java](resource-server/src/main/java/com/entractive/rs/SpaConfig.java) | static serving and SPA fallback |
| [resource-server/src/main/java/com/entractive/rs/SecurityConfig.java](resource-server/src/main/java/com/entractive/rs/SecurityConfig.java) | JWT validation, scope guard, security headers |
| [infra/bootstrap/main.tf](infra/bootstrap/main.tf) | state bucket, ECR, SSM parameters, GitHub OIDC roles (applied by hand once) |
| [infra/stack/](infra/stack) | VPC, ALB, ECS, API Gateway |
| [scripts/smoke.sh](scripts/smoke.sh) | post-deploy checks |
| [.github/workflows/deploy.yml](.github/workflows/deploy.yml) | the pipeline |

## Design decisions (AWS)

- **API Gateway, not CloudFront + S3.** CloudFront with S3 was built and passed `terraform plan`, but AWS refused to create the distribution ("Your account must be verified before you can add new CloudFront resources"). An ALB cannot serve HTTPS without an owned domain and certificate, and MSAL's PKCE flow needs HTTPS, so API Gateway's built-in certificate was the cheapest working option. The CloudFront version is in git history (`infra/stack/spa.tf`, last present in commit `5275a4d^`).
- **ALB is public with a header lock.** API Gateway's outbound addresses are not published, so the security group cannot be narrowed to them. The listener returns 403 unless the secret header is present. The header lives in Terraform state (encrypted S3).
- **SPA served by the API container.** One origin means no CORS and one image to deploy; the cost is that a SPA change redeploys the API.
- **No NAT gateway.** The task has a public IP, inbound only from the ALB security group, outbound only on 443.

## AWS account notes

- CloudFront cannot be created on this account until AWS verifies it (contact AWS Support); that is why the edge is API Gateway.
- The account's VPC quota was raised from 5 to 10 during this work (the six projects had used all 5).

## Known issue: red check on the pull request (resolved by removing PR runs; root cause unproven)

Pull-request runs of `ci-cd` failed at "plan (read-only role)" on commits `98c81e2` (run 39395664651) and `3db1240` (run 39401060143), while the push runs succeeded. The role was assumed fine in both. The log error is `Error acquiring the state lock ... PreconditionFailed ... GetObject 404`: the PR run and the push run start within seconds of each other and contend for the S3 lock file while the push run's plan/apply holds or releases it. The earlier hypothesis (the plan role's trust not matching the pull_request subject) is contradicted by pull-request runs that passed on commits `5275a4d`, `5f93a2c` and `fcfa232`. A local attempt to reproduce the race with 3 concurrent plans (and then 3 x 6 back-to-back plans) did not fail, so the race was not reproduced. The `-lock=false` change is unproven (not exercised against live AWS; the stack was already destroyed). Separately, on 2026-11-18 `deploy.yml` stopped running on pull requests altogether, because with the stack destroyed its plan job could only fail there; PR checks are now `ci.yml`. The lock-contention root cause was never established.

## Not established

- The sign-in proof is one browser session. It reused an existing Microsoft login, so the password page was not exercised.
- CloudFront + S3 was never applied (account not verified by AWS).
- Cost figures are estimates; no bill was read.
- Load, failover and multi-AZ task behaviour were not tested (one task, by design).
- Terraform state for the bootstrap step is local (not in S3), because it creates the bucket.
