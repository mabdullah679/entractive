# CLAUDE.md — entractive

Master rules (verification, branch + PR + CI, staging gate, reporting) live in
`~/.claude/CLAUDE.md`; read that first. This file is repo-specific only. Facts
below were verified on 2026-11-18 against the tree at the time.

## What this is
Public repo. React SPA + Spring Boot resource server validating Microsoft Entra
ID tokens (OAuth2 PKCE), run locally via Docker Compose, plus a Terraform/GitHub
Actions AWS deployment that is **currently torn down**. Entra ID is the only
external dependency (a real tenant is needed to sign in).

## Commands (all run and green)
- API tests: `cd resource-server && mvn test` (31 tests, offline, no env vars needed)
- SPA build: `cd spa && npm ci && npm run build`
- Stack: `cp .env.example .env && docker compose up --build -d` (placeholder GUIDs are enough for everything except a real sign-in); `docker compose down` after
- UI tests: `cd e2e && npm install && npx playwright install chromium && npx playwright test` (stack must be up on :3000/:8080; 3 tests, signed-out path only)
- Shell lint: `shellcheck --severity=error scripts/smoke.sh`
- Terraform static (no AWS): `terraform fmt -check -recursive infra`, then `terraform -chdir=infra/<bootstrap|stack> init -backend=false && ... validate`; `init` rewrites `.terraform.lock.hcl`, revert it

## Layout
`spa/` Vite + MSAL; `resource-server/` Spring Boot (`SecurityConfig.java` is the guard chain); `e2e/` Playwright; `infra/{bootstrap,stack}` Terraform; `Dockerfile.aws` single image (API + SPA) for AWS; `bruno/` API collection; `docs/` setup guides; `scripts/smoke.sh` post-deploy checks for the AWS image only.

## CI
- `.github/workflows/ci.yml`: PR/main checks, free runners, no AWS, no secrets (tests, SPA build, shell lint, terraform fmt/validate, gitleaks).
- `.github/workflows/deploy.yml`: AWS plan/apply/smoke via OIDC; runs only on push to `prod-hardening` and manual dispatch, never on PRs. Needs AWS resources that are destroyed; see README "Destroy and rebuild".
- Actions are pinned to full SHAs with a version comment; keep it that way.

## Do not touch / watch out
- Never run `terraform apply`, `aws`, or the deploy workflow without the owner's explicit yes (cloud provisioning, master section 7).
- Local `.env` is gitignored; never commit one.
- `bruno/.../environments/local.bru` and `docs/engineering-briefing.html` contain a real Entra tenant/client GUID; AWS account ID `346208529954` appears in README, Terraform and `deploy.yml`. Identifiers, not credentials, but owner content: do not redact or change silently.
- `smoke.sh` expects the AWS image (it serves the SPA); against the local compose API it reports SPA-route failures. That is expected, not a regression.
- README.md and README.txt must be updated together; every number and link in them must be re-checked against the repo.
- Logic changes need a test watched failing first (mutate guard, see red, reverse the exact edit).
- Observed: removing the `/api/**` scope guard still gives 401 for an anonymous call (the controller NPEs and the error dispatch is rejected), so a no-token UI test cannot detect that guard; the Java tests cover it.
