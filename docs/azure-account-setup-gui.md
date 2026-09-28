# Setting up a fresh Azure / Entra ID account (GUI walkthrough)

For someone starting from zero who needs to register apps for OAuth2/PKCE SSO.
Every step is portal-based — no CLI required.

**Before you start, read Part 0.** Most people who "can't get Azure working" are
not stuck on signup; they are stuck on a permission they cannot see.

---

## Part 0 — Which wall are you actually hitting?

| Symptom | Wall | Go to |
| --- | --- | --- |
| No Microsoft account at all | Signup | Part 1 |
| Signed in, but **+ New registration** is greyed out, or you get "does not have authorization" / "Insufficient privileges" | **Tenant policy blocks app creation** | Part 4 |
| Asked for a credit card and unsure why | Confusing subscriptions with Entra ID | Part 2 |
| Signed in but see no tenant / "no directories" | Tenant not provisioned yet | Part 1, step 3 |

> **The single most common blocker:** a tenant admin has set *"Users can register
> applications"* to **No**. The portal then hides or rejects app registration with
> a generic error that never mentions the setting. No amount of retrying fixes it —
> it needs an admin. See Part 4.

---

## Part 1 — Create the account and tenant

1. Go to **https://entra.microsoft.com**
2. Sign in with a Microsoft account, or choose **Create one!** if you have none.
   A personal address (gmail, outlook) is fine.
3. On first sign-in Microsoft provisions a **tenant** (a directory) automatically,
   usually named *Default Directory* with a domain like
   `yourname.onmicrosoft.com`.

**Confirm it worked:** top-right avatar → you should see a directory name and a
**Directory ID** (a GUID). That GUID is your `TENANT_ID`.

If you see no directory, go to **Entra ID → Overview → Manage tenants →
Create**, choose type **Microsoft Entra ID**, and complete the wizard.

---

## Part 2 — You do NOT need a paid subscription

This is the most expensive misunderstanding in Azure onboarding.

| Thing | What it is | Needed here? |
| --- | --- | --- |
| **Entra ID tenant** | Your identity directory | **Yes** — free tier is enough |
| **Azure subscription** | Billing container for VMs, storage, etc. | **No** |

App registrations, scopes, app roles, and OAuth2/PKCE all live in **Entra ID**,
and all are covered by the free tier.

If the portal shows *"No subscriptions found"* — that is fine and expected.
It does **not** block app registration. If you are being pushed toward a credit
card, you have wandered into **portal.azure.com** subscription signup. Go back to
**entra.microsoft.com**.

---

## Part 3 — Verify you can actually register an app

Do this **before** following any SSO setup guide. Sixty seconds now saves an hour.

1. **entra.microsoft.com** → left nav **Applications** → **App registrations**
2. Click **+ New registration**
3. Name it `permission-test`, leave everything default, click **Register**

**If it succeeds:** you have what you need. Delete it (**Delete** on its Overview)
and proceed with the real setup.

**If the button is greyed out, or you get an authorization error:** stop. This is
a tenant policy, not something you are doing wrong. Go to Part 4.

---

## Part 4 — Fixing "you cannot register applications"

### The setting

**Entra ID → Users → User settings → App registrations**
→ *"Users can register applications"*

If this is **No**, every non-admin is blocked from creating app registrations.
The error surfaced to the user never names this setting.

### Who can change it

Only a **Global Administrator** or **Application Administrator**.

### Three ways forward

**Option A — Admin flips the setting.** Fastest if you can reach an admin. Ask
them to set *"Users can register applications"* to **Yes**. Tenant-wide.

**Option B — Admin grants a role instead.** More conservative and usually easier
to get approved, since it does not loosen the whole tenant:

> **Entra ID → Roles and administrators → Application Developer → Add assignment**

The **Application Developer** role lets a specific user register apps while the
tenant default stays **No**. This is the ask most security teams will accept.

**Option C — Use your own tenant.** If the blocked tenant is a corporate one you
do not control, create a personal tenant (Part 1) and do the development there.
Perfectly normal for local development and demos.

### The guest-account trap

If your sign-in name contains **`#EXT#`** you are a *guest* in that directory,
not a member. Guests are restricted further, and `allowedToCreateApps` may not
apply to them at all even when it is **Yes**.

Check: **Entra ID → Users → your user →** look at **User type**
(*Member* vs *Guest*) and **User principal name**.

Fix: have an admin either change your user type to **Member**, or grant the
**Application Developer** role (Option B), which works for guests too.

---

## Part 5 — Multi-factor authentication

Modern tenants enforce MFA by default. First sign-in will likely demand you
register a second factor.

- Install **Microsoft Authenticator** (iOS/Android) before you start
- If the CLI fails with **`AADSTS50076`** ("must use multi-factor
  authentication"), that is MFA, not a broken account — sign in through the
  browser once, or use `az login --tenant <TENANT_ID>`

---

## Part 6 — The two registrations for OAuth2/PKCE

Once Part 3 passes, you need **two** app registrations. Two, not one: the SPA
*requests* tokens, the API is the *audience* those tokens are minted for. That
separation is what makes audience validation meaningful — without it, a token
issued for any other app would be accepted.

### 6a. The API

**App registrations → + New registration**
- Name: `sso-resource-server`
- Accounts: *Accounts in this organizational directory only*
- Redirect URI: **leave blank** (an API has none)

Copy from **Overview**: **Application (client) ID** and **Directory (tenant) ID**.

**Expose an API → Add a scope**
- Accept the default Application ID URI (`api://<client-id>`)
- Scope name `Api.Access`, consent *Admins and users*, state **Enabled**

**App roles → Create app role**
- Display name `Resource Admin`, member types **Users/Groups**
- **Value `Resource.Admin`** — case-sensitive, must match your config exactly
- Tick **Do you want to enable this app role?**

### 6b. The SPA

**App registrations → + New registration**
- Name: `sso-spa`
- Redirect URI: choose platform **Single-page application (SPA)**, enter
  `http://localhost:3000`

> **Critical.** Choosing **Web** instead of **SPA** makes Entra expect a client
> secret, and the flow dies with **`AADSTS9002326`** (cross-origin token
> redemption). A browser app cannot hold a secret — that is the entire reason
> PKCE exists. If you picked wrong: **Authentication →** delete the Web platform,
> **Add a platform → Single-page application**.

Copy its **Application (client) ID**.

### 6c. Connect them

**On the SPA → API permissions → Add a permission → My APIs →**
`sso-resource-server` → **Delegated permissions** → tick `Api.Access` → **Add**.

Then **Grant admin consent** (needs an admin; without it each user consents
individually at first sign-in — which also works).

### 6d. Assign the role to a human

The app role exists but is granted to nobody until you assign it.

**Entra ID → Enterprise applications →** `sso-resource-server`
→ **Users and groups → + Add user/group** → pick the user → choose
**Resource Admin** → **Assign**.

> Without this, role-gated endpoints return **403** while ordinary endpoints
> return **200**. That is correct behaviour, not a bug — the user is
> authenticated but not authorized.

---

## Part 7 — Common errors decoded

| Code | Meaning | Fix |
| --- | --- | --- |
| `AADSTS50011` | Redirect URI mismatch | The registered URI must match **exactly**, including port and trailing slash. Using port 3100? Register `http://localhost:3100`, not 3000. |
| `AADSTS9002326` | Cross-origin token redemption | App registered as **Web** instead of **SPA**. Fix the platform (6b). |
| `AADSTS50076` | MFA required | Complete MFA in a browser; for CLI use `az login --tenant <id>`. |
| `AADSTS65001` | User/admin has not consented | Grant admin consent (6c), or consent at first sign-in. |
| `AADSTS700016` | App not found in directory | Wrong client ID, or you are signing into the wrong tenant. |
| `AADSTS90002` | Tenant not found | Wrong tenant ID, or the directory was never provisioned. |
| "Insufficient privileges" | Tenant blocks app registration | Part 4. |

**403 with a valid token and no Azure error code** is not an Azure problem — the
token is genuine but lacks the app role. Do 6d, then sign out and back in: role
changes only appear in a **newly issued** token.

---

## Part 8 — The five values you end up with

| Value | Where it came from |
| --- | --- |
| `TENANT_ID` | Either registration → Overview → Directory (tenant) ID |
| `SPA_CLIENT_ID` | `sso-spa` → Overview → Application (client) ID |
| `API_CLIENT_ID` | `sso-resource-server` → Overview → Application (client) ID |
| `API_SCOPE` | `api://<API_CLIENT_ID>/Api.Access` |
| `REQUIRED_ROLE` | The app role **Value**, e.g. `Resource.Admin` |

These are **identifiers, not secrets** — client IDs and a tenant ID are not
credentials, and this setup has no client secret at all. Still keep them out of
version control, since they identify your tenant.

---

## Fastest path for someone completely stuck

1. **entra.microsoft.com**, sign in (Part 1)
2. Try registering a throwaway app (Part 3) — **do this first**
3. Blocked? It is tenant policy. Ask an admin for the **Application Developer**
   role, or use a personal tenant (Part 4)
4. Not blocked? Follow Part 6, twice
5. Hit an `AADSTS` code? Part 7
