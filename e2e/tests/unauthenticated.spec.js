const { test, expect } = require('@playwright/test')

// Everything here is reachable WITHOUT a Microsoft sign-in. The signed-in buttons
// (valid token, role-gated) need a real Entra ID tenant and are NOT covered.

test('landing page renders the signed-out state', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'OAuth2 Authorization Code + PKCE' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Not signed in' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sign in with Microsoft' })).toBeVisible()
})

test('"no token" button drives the real API through the browser and shows 401', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: /Call API with no token/ }).click()
  await expect(page.getByRole('heading', { name: 'Result' })).toBeVisible()
  await expect(page.getByText('GET /api/resource (no Authorization header)')).toBeVisible()
  await expect(page.locator('p', { hasText: /^HTTP\s*401/ })).toBeVisible()
})

test('deep route falls back to the SPA', async ({ page }) => {
  await page.goto('/some/deep/route')
  await expect(page.getByRole('button', { name: 'Sign in with Microsoft' })).toBeVisible()
})
