import React from 'react'
import ReactDOM from 'react-dom/client'
import { PublicClientApplication, EventType } from '@azure/msal-browser'
import { MsalProvider } from '@azure/msal-react'
import { msalConfig, configErrors } from './authConfig'
import App from './App'
import './styles.css'

async function boot() {
  const root = ReactDOM.createRoot(document.getElementById('root'))

  if (configErrors.length) {
    root.render(<ConfigError errors={configErrors} />)
    return
  }

  const msalInstance = new PublicClientApplication(msalConfig)
  // msal-browser v3 requires an explicit initialize() before any other call.
  await msalInstance.initialize()

  // Completes the redirect leg of the PKCE flow when Entra ID sends the user
  // back with ?code=... Must run before render so the account is available.
  await msalInstance.handleRedirectPromise()

  const accounts = msalInstance.getAllAccounts()
  if (accounts.length > 0) msalInstance.setActiveAccount(accounts[0])

  msalInstance.addEventCallback((event) => {
    if (event.eventType === EventType.LOGIN_SUCCESS && event.payload?.account) {
      msalInstance.setActiveAccount(event.payload.account)
    }
  })

  root.render(
    <MsalProvider instance={msalInstance}>
      <App />
    </MsalProvider>,
  )
}

function ConfigError({ errors }) {
  return (
    <main className="shell">
      <h1>Configuration incomplete</h1>
      <p>The SPA container started but is missing required environment variables:</p>
      <ul>{errors.map((e) => <li key={e}><code>{e}</code></li>)}</ul>
      <p>Set them in <code>.env</code> at the project root, then <code>docker compose up -d --force-recreate spa</code>.</p>
    </main>
  )
}

boot().catch((err) => {
  document.getElementById('root').textContent = `Startup failed: ${err.message}`
})
