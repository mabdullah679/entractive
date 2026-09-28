# Verification record

What was actually proven on this machine, and how. Everything below was executed
and observed — nothing here is inferred from reading the source.

Date: 2026-09-25 · macOS (M1 Max) · Docker 29.8.0 · Compose v5.5.1

---

## 1. Automated tests — 13/13 green

`cd resource-server && mvn test`

Covers every resource-server-side acceptance criterion:

| Test | Asserts |
| --- | --- |
| `validTokenReturns200` | FR-8 — payload returned |
| `missingTokenReturns401` | FR-6 — no `Authorization` header |
| `malformedTokenReturns401` | FR-6 — not a JWT |
| `expiredTokenReturns401` | FR-6 — expiry enforced |
| `tamperedSignatureReturns401` | FR-5 — signed by an untrusted key |
| `wrongAudienceReturns401` | Token minted for a different API |
| `wrongIssuerReturns401` | Token from a different issuer |
| `missingRoleReturns403` | FR-7 — authenticated but not authorized |
| `correctRoleReturns200` | FR-7 — role satisfies the gate |
| `wrongRoleReturns403` | FR-7 — a different role does not |
| `corsPreflightAllowed` | §5 — SPA origin allowed |
| `corsPreflightFromOtherOriginRefused` | §5 — other origins refused |
| `healthIsPublic` | Compose healthcheck can reach health |

Tests run offline against a mock JWKS endpoint (`MockEntraId`), signing tokens
with a locally generated RSA key. No tenant required to run them.

## 2. Mutation testing — the guards were watched failing

Green tests prove nothing until the guard has been broken and seen to fail.
Three mutations were applied to `SecurityConfig.java`, each reverted by
reversing the exact edit and verified byte-identical with `diff` afterwards.

| Mutation | Result | What it proves |
| --- | --- | --- |
| Removed `AudienceValidator` from the decoder chain | `wrongAudienceReturns401` → **expected 401, got 200** | The audience check is load-bearing; without it a token for another API is accepted |
| Stopped mapping the `roles` claim to authorities | `correctRoleReturns200` → **expected 200, got 403** | The custom converter is load-bearing; with Spring's defaults the role gate 403s everyone regardless of token |
| Replaced the origin allowlist with `*` | `corsPreflightFromOtherOriginRefused` → **expected 403, got 200** | The CORS origin restriction is real, not decorative |

All three restored; full suite re-run green afterwards.

## 3. Live stack — HTTP verification

`docker compose up -d`, then curl against the running containers:

| Check | Result |
| --- | --- |
| `GET /` on the SPA | `200` |
| `GET /config.js` | Reflects `.env` values, regenerated per container start |
| `GET /some/deep/route` | `200` — SPA history fallback works |
| `GET /api/resource` (no header) | `401` + `WWW-Authenticate: Bearer` |
| `GET /api/resource` (garbage token) | `401` |
| `OPTIONS /api/resource` from `http://localhost:3100` | `200` + `Access-Control-Allow-Origin` |
| `OPTIONS /api/resource` from `http://evil.example.com` | `403` |

## 4. Browser verification

Headless Chrome against the running SPA:

- React mounts (`#root` populated), `h1` renders, **zero console or page errors**
- `window.__APP_CONFIG__` present with the values from `.env`
- Clicking "Call API with no token" performs a real cross-origin fetch and
  renders `HTTP 401` / `(empty body)` — proving CORS works in an actual browser,
  not just under curl
- Blanking `VITE_AZURE_CLIENT_ID` in the running container renders the
  "Configuration incomplete" guard naming the exact missing variable; the
  container was then restored and re-verified

## 5. Non-functional requirements

| ID | Requirement | Measured |
| --- | --- | --- |
| NFR-1 / NFR-5 | No secret in the SPA image | Tenant ID appears **0 times** in the built bundle. The only GUIDs present are MSAL's own hardcoded constants |
| NFR-2 | Stateless validation, no per-request IdP call | `NimbusJwtDecoder` caches the JWKS; session policy `STATELESS` |
| NFR-3 | Both healthy in <60s | **11s** from `docker compose up` on prebuilt images; resource server boots in 1.6s |
| NFR-4 | Request-level logging via `docker compose logs` | Confirmed, **including the 401 path** — see defect 3 below |
| NFR-6 | Works offline except the Entra ID hop | Container boots and serves 401s with no network; test suite runs fully offline |

---

## Defects found and fixed during the build

Recorded because each was a real failure caught by verification, not by reading
the code.

1. **Converter bean broke the entire application context.** Exposing the JWT
   authorities converter as a `@Bean` of type `Converter` caused Spring MVC's
   `FormattingConversionService` to adopt it as a general-purpose type
   converter, which cannot infer `<S>`/`<T>` from a lambda. Every test errored at
   context load. Fixed by building a concrete `JwtAuthenticationConverter`
   instead of publishing a lambda bean.

2. **The container could not boot without a live tenant.** `withIssuerLocation()`
   fetches Entra ID's discovery document *eagerly at startup* and aborts the
   context on failure, so the resource server crash-looped with a placeholder
   tenant ID. Anyone verifying their Docker setup before finishing the Entra
   registrations would have hit this. Fixed by deriving the JWKS URI by
   convention so key fetching is lazy.

3. **NFR-4 request logging produced no output at all.** A `@Component` +
   `@Order(MAX_VALUE)` filter is ordered *after* Spring Security's chain, so
   requests rejected with 401/403 short-circuited before it ran — a stated
   requirement with no live code path, which looked satisfied in source.
   Fixed with an explicit `FilterRegistrationBean` at `HIGHEST_PRECEDENCE`, then
   confirmed by observing 401 lines in `docker compose logs`.

4. **SPA healthcheck reported unhealthy while nginx was fine.** The check used
   `localhost`, which resolves to `::1` first inside the container, but nginx
   listens on IPv4 only — connection refused. Fixed to `127.0.0.1`.

5. **Empty response bodies rendered as `null`.** `JSON.parse('')` throws on
   Spring's empty 401 body. Fixed to render `(empty body)`, browser-confirmed.

---

## What was NOT verified

Stated plainly rather than implied, because these require a real tenant that
does not exist on this machine:

- **The interactive sign-in leg was never executed.** No real Entra ID tenant or
  app registrations were available, so FR-1 (redirect to the sign-in page),
  FR-2's live PKCE code exchange, FR-3 (silent renewal), and the `200` responses
  from a genuine Entra ID token were not observed end-to-end. The 401/403 paths,
  CORS, signature/audience/issuer/expiry validation and role mapping were all
  proven — against locally-signed tokens and a mock JWKS, which exercise the
  same `NimbusJwtDecoder` code path a real token takes.
- **The `.env` used for verification held placeholder GUIDs.** It is not
  committed. Acceptance criteria involving a real token remain for the owner to
  run after completing `docs/entra-id-setup.md`.
- **NFR-3 was measured on this M1 Max**, not on the spec's minimum-spec host
  (4 GB / 2 vCPU). 11s against a 60s budget leaves substantial headroom, but the
  minimum-spec figure is unmeasured.
- **Entra ID's `roles` claim shape is assumed, not observed** — app roles arrive
  as a `roles` string array. This follows Microsoft's documented v2.0 token
  format, but no real token was inspected to confirm it.
