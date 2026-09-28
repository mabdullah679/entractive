# Entra ID setup

Two app registrations are required: one for the SPA (public client) and one for
the API. Entra ID itself cannot be containerized or emulated — this part is done
once, in the Azure portal, against a real tenant.

Everything below produces the five values that go in `.env`.

---

## 1. Register the API

**Entra ID → App registrations → New registration**

- Name: `sso-resource-server`
- Supported account types: *Accounts in this organizational directory only*
- Redirect URI: leave blank (an API has none)

From its **Overview**, copy:
- **Application (client) ID** → `.env` as `API_CLIENT_ID`
- **Directory (tenant) ID** → `.env` as `TENANT_ID`

### Expose an API

**Expose an API → Add a scope**

- Accept the default Application ID URI (`api://<API_CLIENT_ID>`)
- Scope name: `Api.Access`
- Who can consent: *Admins and users*
- Fill the consent display name/description, state **Enabled**

The full scope string is `api://<API_CLIENT_ID>/Api.Access` → `.env` as `API_SCOPE`.

### Define the app role

**App roles → Create app role** (this is what `GET /api/admin` gates on)

- Display name: `Resource Admin`
- Allowed member types: **Users/Groups**
- **Value: `Resource.Admin`** — must match `REQUIRED_ROLE` in `.env` exactly,
  and it is case-sensitive
- Description: anything; **Enable this app role**: checked

---

## 2. Register the SPA

**App registrations → New registration**

- Name: `sso-spa`
- Redirect URI: select platform **Single-page application (SPA)** and enter
  `http://localhost:3000`

> Choosing the **SPA** platform is what makes this a public PKCE client. If you
> pick "Web" instead, Entra ID expects a client secret and the flow fails with
> `AADSTS9002326` (cross-origin token redemption). There is no secret anywhere
> in this project by design (NFR-1).

From its **Overview**, copy the **Application (client) ID** → `.env` as `SPA_CLIENT_ID`.

### Grant it access to the API

**API permissions → Add a permission → My APIs →** `sso-resource-server`
→ **Delegated permissions** → check `Api.Access` → **Add permissions**

Then **Grant admin consent** for the tenant (or each user consents at first sign-in).

---

## 3. Assign the app role to yourself

The role is *not* granted by the steps above; it is assigned to a user.

**Entra ID → Enterprise applications →** `sso-resource-server`
→ **Users and groups → Add user/group** → pick your user → select the
**Resource Admin** role → **Assign**.

Without this, `GET /api/admin` correctly returns **403** while `/api/resource`
returns 200 — that is the FR-7 acceptance criterion, not a bug. To see the 403
path deliberately, test with a user who has no role assigned.

> Role assignment changes only appear in a **newly issued** token. Sign out, or
> clear the tab's sessionStorage, to force a fresh one.

---

## 4. Fill in `.env`

```bash
cp .env.example .env
```

| `.env` key | Where it came from |
| --- | --- |
| `TENANT_ID` | Either registration → Overview → Directory (tenant) ID |
| `SPA_CLIENT_ID` | `sso-spa` → Overview → Application (client) ID |
| `API_CLIENT_ID` | `sso-resource-server` → Overview → Application (client) ID |
| `API_SCOPE` | `api://<API_CLIENT_ID>/Api.Access` |
| `REQUIRED_ROLE` | The app role **Value**, e.g. `Resource.Admin` |

---

## Changing ports

If 3000 or 8080 are taken, set `SPA_HOST_PORT` / `API_HOST_PORT` in `.env` — but
Entra ID matches the redirect URI **exactly, including the port**. Change all of
these together or sign-in breaks with `AADSTS50011`:

1. `SPA_HOST_PORT` and `SPA_REDIRECT_URI` in `.env`
2. `CORS_ALLOWED_ORIGINS` in `.env` (the browser origin)
3. The SPA app registration's redirect URI in the portal
