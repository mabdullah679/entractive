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
