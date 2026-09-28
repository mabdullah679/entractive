// Runtime configuration.
//
// The PRD (Section 5) requires these values to be injected into the container via
// docker-compose / .env. Vite's import.meta.env is resolved at *build* time, which
// would bake the tenant into the image and break NFR-5. So the container writes
// window.__APP_CONFIG__ at startup (see docker/env.sh) and we read that first,
// falling back to import.meta.env for `npm run dev` outside Docker.
const runtime = (typeof window !== 'undefined' && window.__APP_CONFIG__) || {}

function cfg(key, fallback) {
  const value = runtime[key] ?? import.meta.env[key] ?? fallback
  return typeof value === 'string' ? value.trim() : value
}

export const clientId    = cfg('VITE_AZURE_CLIENT_ID', '')
export const tenantId    = cfg('VITE_AZURE_TENANT_ID', '')
export const redirectUri = cfg('VITE_AZURE_REDIRECT_URI', window.location.origin)
export const apiBaseUrl  = cfg('VITE_API_BASE_URL', 'http://localhost:8080')
// Scope the SPA requests for the resource server's exposed API (Section 5).
export const apiScope    = cfg('VITE_API_SCOPE', '')

// Surfaced by App.jsx so a misconfigured container fails loudly instead of
// bouncing the user to a confusing Entra ID error page.
export const configErrors = [
  !clientId && 'VITE_AZURE_CLIENT_ID is not set',
  !tenantId && 'VITE_AZURE_TENANT_ID is not set',
  !apiScope && 'VITE_API_SCOPE is not set',
].filter(Boolean)

export const msalConfig = {
  auth: {
    clientId,
    authority: `https://login.microsoftonline.com/${tenantId}`,
    redirectUri,
    postLogoutRedirectUri: redirectUri,
    // Entra ID issues v2.0 tokens for the API scope; keep the SPA a public client.
    navigateToLoginRequestUrl: false,
  },
  cache: {
    // sessionStorage survives a reload in the same tab (acceptance criterion:
    // "reloading the SPA re-authenticates silently") without persisting tokens
    // across browser restarts.
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false,
  },
  system: {
    loggerOptions: {
      loggerCallback: (level, message, containsPii) => {
        if (!containsPii) console.log(`[msal] ${message}`)
      },
      piiLoggingEnabled: false,
    },
  },
}

// FR-2: Authorization Code + PKCE is msal-browser's only flow for a public
// client — there is no secret anywhere in this bundle (NFR-1).
export const loginRequest = { scopes: [apiScope].filter(Boolean) }
