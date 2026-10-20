Entractive SSO stack - plain-text summary of README.md

What this is
A React single-page app, Microsoft Entra ID, and a Spring Boot API running in
Docker Desktop. A user signs in at Entra ID, the app receives a token, and the
API checks that token before returning data. Entra ID is the only thing not
running locally; you need a real tenant.

How to run it
1. Do the one-time Entra ID setup (docs/entra-id-setup.md, or the one-paste
   script in docs/bootstrap-entra-cli.md). That gives you five values.
2. Copy .env.example to .env and fill in those five values.
3. Run: docker compose up --build -d
4. Open http://localhost:3000
Commands for macOS/Linux, PowerShell and Command Prompt are in README.md.
If ports 3000 or 8080 are taken, change them in .env AND on the Entra ID app
registration, because Entra ID matches redirect addresses exactly.

What the API offers
/api/resource   any valid token
/api/admin      valid token that also carries the admin app role
/actuator/health  public

Tests
14 automated tests cover the API: valid, missing, malformed and expired tokens,
a forged signature, wrong audience, wrong issuer, role present or absent, and
allowed or refused browser origins. They run offline with no tenant.

New: Bruno API collection (bruno/entractive-sso)
What was done: a ready-made set of 16 requests in three folders.
- 00-stack-health (4): checks the API and the web app are up.
- 01-api-rejects-unauthenticated (5): checks the API refuses callers with no
  or bad tokens, and that browser origin rules work.
- 02-authenticated-calls (7): sign-in, token exchange, protected calls, an
  admin-only call, a wrong-token-type call, and token refresh. Steps that must
  come first are placed directly before the steps that need them.
What worked: the first two folders were run against the live containers and
all 9 requests passed.
What did not work / not proven: the third folder needs a real person to sign
in, so it was never run with a real token. The step that reads the sign-in
code was fixed and tested against a pretend server, not a real Entra ID code.
How to use: open the folder in Bruno, pick the "local" environment, and first
edit environments/local.bru so the IDs and ports match your .env.
A mismatch between that file and the running app was found and fixed during
testing; the config.js request will flag it if it happens again.


AWS deployment (added 2026-10-20)
What was done: the app was put on AWS with Terraform and a GitHub Actions pipeline. The pipeline logs in to AWS without any stored keys, runs the tests, builds one container holding both the website and the API, creates the network, load balancer and container service, and then runs a smoke test. It ran green once from the prod-hardening branch.
What worked: the site opened over https at an API Gateway address. Without a token, with a junk token, and with a forged token the API refused with 401. Calling the load balancer directly gave 403. A real browser sign-in then worked: the valid-token button returned 200, the tampered-token button 401, and the admin button 200. The API log in CloudWatch shows the same 200s and 401.
What did not work as planned: the first design used CloudFront and S3, but AWS refused to create CloudFront because the account is not verified. It was replaced by API Gateway. The CloudFront version is in git history, never run.
What was not proven: the sign-in was done by the owner and the log only shows that a token was present, not who it was. Costs are estimates, about 6 or 7 US cents per hour while running. No load or failover tests.
It was checked live on 2026-10-20 and the owner signed in personally; then everything was destroyed the same day to save money. The two Entra app registrations were kept. To rebuild: re-run the pipeline (gh workflow run ci-cd --ref prod-hardening), after the one-time bootstrap in infra/bootstrap and the four Entra ID values stored in AWS Parameter Store. Details are in README.md.
Tests are now 31 (not 14): 20 for the API rules and 11 for serving the website safely. The rules that decide who gets in were each deliberately broken once to confirm a test fails.

Other notes: AWS has not verified this account for CloudFront, which is why API Gateway is used. The account limit on VPCs was raised from 5 to 10. The pull-request check on GitHub shows red: the pipeline failed to get the Terraform lock because the push run and the pull-request run started at the same moment. A change to skip the lock for the read-only plan was pushed but never tested, because everything had already been destroyed. Rebuilding also needs the bootstrap step again, since that was destroyed too.
