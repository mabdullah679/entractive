import React, { useState } from 'react'
import { useMsal, useIsAuthenticated } from '@azure/msal-react'
import { loginRequest, apiBaseUrl } from './authConfig'
import { callApi, callApiNoToken } from './api'

export default function App() {
  const { instance, accounts, inProgress } = useMsal()
  const isAuthenticated = useIsAuthenticated()
  const account = instance.getActiveAccount() ?? accounts[0]
  const [result, setResult] = useState(null)
  const [busy, setBusy] = useState(false)

  // FR-1: no session -> redirect to the Entra ID sign-in page.
  const signIn  = () => instance.loginRedirect(loginRequest)
  const signOut = () => instance.logoutRedirect()

  async function run(label, fn) {
    setBusy(true)
    setResult({ label, pending: true })
    try {
      const r = await fn()
      setResult({ label, ...r })
    } catch (err) {
      setResult({ label, error: err.message })
    } finally {
      setBusy(false)
    }
  }

  if (inProgress !== 'none' && !isAuthenticated) {
    return <main className="shell"><h1>Signing in…</h1><p className="muted">Completing the PKCE exchange with Entra ID.</p></main>
  }

  return (
    <main className="shell">
      <h1>OAuth2 Authorization Code + PKCE</h1>
      <p className="muted">React SPA → Microsoft Entra ID → Spring Boot resource server, all local via Docker Compose.</p>

      {!isAuthenticated ? (
        <section className="card">
          <h2>Not signed in</h2>
          <p>You have no cached session. Signing in redirects to Entra ID.</p>
          <button className="primary" onClick={signIn}>Sign in with Microsoft</button>
          <hr />
          <p className="muted">You can still exercise the unauthenticated path:</p>
          <button onClick={() => run('GET /api/resource (no Authorization header)', () => callApiNoToken('/api/resource'))}>
            Call API with no token → expect 401
          </button>
        </section>
      ) : (
        <>
          <section className="card">
            <h2>Signed in</h2>
            <dl>
              <dt>Name</dt><dd>{account?.name ?? '—'}</dd>
              <dt>Username</dt><dd>{account?.username ?? '—'}</dd>
              <dt>Tenant</dt><dd><code>{account?.tenantId ?? '—'}</code></dd>
              <dt>API base</dt><dd><code>{apiBaseUrl}</code></dd>
            </dl>
            <button onClick={signOut}>Sign out</button>
          </section>

          <section className="card">
            <h2>Exercise the resource server</h2>
            <p className="muted">Each button maps to an acceptance criterion in Section 7 of the spec.</p>
            <div className="row">
              <button className="primary" disabled={busy}
                onClick={() => run('GET /api/resource (bearer token)', () => callApi(instance, account, '/api/resource'))}>
                Valid token → 200
              </button>
              <button disabled={busy}
                onClick={() => run('GET /api/resource (no Authorization header)', () => callApiNoToken('/api/resource'))}>
                No token → 401
              </button>
              <button disabled={busy}
                onClick={() => run('GET /api/resource (tampered token)', async () => {
                  const res = await fetch(`${apiBaseUrl}/api/resource`, {
                    headers: { Authorization: 'Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.dGFtcGVyZWQ.c2lnbmF0dXJl' },
                  })
                  return { status: res.status, body: await res.text() }
                })}>
                Tampered token → 401
              </button>
              <button disabled={busy}
                onClick={() => run('GET /api/admin (role-gated)', () => callApi(instance, account, '/api/admin'))}>
                Role-gated → 200 or 403
              </button>
            </div>
          </section>
        </>
      )}

      {result && (
        <section className="card">
          <h2>Result</h2>
          <p><strong>{result.label}</strong></p>
          {result.pending && <p className="muted">Calling…</p>}
          {result.error && <p className="err">Error: {result.error}</p>}
          {result.status !== undefined && (
            <>
              <p>HTTP <span className={statusClass(result.status)}>{result.status || '—'}</span>{result.note ? ` · ${result.note}` : ''}</p>
              <pre>{typeof result.body === 'string' ? result.body : JSON.stringify(result.body, null, 2)}</pre>
            </>
          )}
        </section>
      )}
    </main>
  )
}

function statusClass(status) {
  if (status >= 200 && status < 300) return 'ok'
  if (status === 401 || status === 403) return 'warn'
  return 'err'
}
