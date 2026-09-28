import { InteractionRequiredAuthError } from '@azure/msal-browser'
import { apiBaseUrl, loginRequest } from './authConfig'

/**
 * FR-3 / FR-4: acquire a token silently from the MSAL cache and attach it as a
 * bearer token. Only if MSAL says interaction is genuinely required do we fall
 * back to a redirect — that is what makes a reload within the token lifetime
 * silent.
 */
export async function callApi(instance, account, path) {
  let token
  try {
    const result = await instance.acquireTokenSilent({ ...loginRequest, account })
    token = result.accessToken
  } catch (err) {
    if (err instanceof InteractionRequiredAuthError) {
      await instance.acquireTokenRedirect({ ...loginRequest, account })
      return { status: 0, body: null, note: 'redirecting for interactive consent' }
    }
    throw err
  }

  const res = await fetch(`${apiBaseUrl}${path}`, {
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  })

  // Read the body as text first: a 401 from Spring Security carries an empty
  // body plus a WWW-Authenticate header, and res.json() would throw on it.
  return { status: res.status, body: parseBody(text) }
}

/**
 * Spring returns an empty body with 401/403, and JSON.parse('') throws — so
 * fall back to the raw text and make "nothing" legible rather than `null`.
 */
function parseBody(text) {
  if (!text) return '(empty body)'
  try { return JSON.parse(text) } catch { return text }
}

/** Calls the API deliberately without a token — exercises the 401 path. */
export async function callApiNoToken(path) {
  const res = await fetch(`${apiBaseUrl}${path}`)
  return { status: res.status, body: parseBody(await res.text()) }
}
