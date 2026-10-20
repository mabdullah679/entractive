#!/usr/bin/env bash
# Post-deploy smoke test. Everything here is provable WITHOUT an Entra sign-in:
# it checks the SPA is served over HTTPS, the API is healthy, and the API
# refuses missing / garbage / forged / wrong-audience tokens.
#
# NOT covered (needs a real Entra login): an authenticated 200 from /api/resource.
#
# Usage: scripts/smoke.sh https://<id>.execute-api.<region>.amazonaws.com [alb-dns-name]
# Requires: bash, curl, openssl, base64.
set -uo pipefail

BASE="${1:?usage: smoke.sh <https://site-url> [alb-dns-name]}"
BASE="${BASE%/}"
ALB="${2:-}"
fail=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then printf 'PASS  %-58s %s\n' "$1" "$3"
  else printf 'FAIL  %-58s expected %s got %s\n' "$1" "$2" "$3"; fail=1; fi
}
contains() { # name needle haystack
  if printf '%s' "$3" | grep -q -- "$2"; then printf 'PASS  %-58s\n' "$1"
  else printf 'FAIL  %-58s missing "%s"\n' "$1" "$2"; fail=1; fi
}
code() { curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$@" 2>/dev/null || echo 000; }

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Forge an RS256-signed JWT with a throwaway key: structurally valid, signature
# NOT from Entra. $1 = audience
forge() {
  local key hdr pay sig
  key=$(mktemp); openssl genrsa -out "$key" 2048 2>/dev/null
  hdr=$(printf '{"alg":"RS256","typ":"JWT","kid":"forged"}' | b64url)
  pay=$(printf '{"iss":"https://login.microsoftonline.com/00000000-0000-0000-0000-000000000000/v2.0","aud":"%s","sub":"attacker","scp":"Api.Access","roles":["Resource.Admin"],"exp":4102444800}' "$1" | b64url)
  sig=$(printf '%s.%s' "$hdr" "$pay" | openssl dgst -sha256 -sign "$key" | b64url)
  rm -f "$key"
  printf '%s.%s.%s' "$hdr" "$pay" "$sig"
}
# alg=none token
forge_none() {
  local hdr pay
  hdr=$(printf '{"alg":"none","typ":"JWT"}' | b64url)
  pay=$(printf '{"sub":"attacker","aud":"x","exp":4102444800}' | b64url)
  printf '%s.%s.' "$hdr" "$pay"
}

echo "== SPA over HTTPS"
check "GET / is 200"                         200 "$(code "$BASE/")"
body=$(curl -sS --max-time 20 "$BASE/")
contains "index.html contains the React root"  'id="root"' "$body"
check "deep route /some/spa/route falls back to index (200)" 200 "$(code "$BASE/some/spa/route")"
hdrs=$(curl -sSI --max-time 20 "$BASE/")
contains "HSTS header present"               'strict-transport-security' "$(printf '%s' "$hdrs" | tr 'A-Z' 'a-z')"
contains "CSP header present"                'content-security-policy' "$(printf '%s' "$hdrs" | tr 'A-Z' 'a-z')"
contains "X-Content-Type-Options present"    'x-content-type-options: nosniff' "$(printf '%s' "$hdrs" | tr 'A-Z' 'a-z')"
cfg=$(curl -sS --max-time 20 "$BASE/config.js")
contains "config.js sets window.__APP_CONFIG__" '__APP_CONFIG__' "$cfg"
contains "config.js points redirect URI at this origin" "VITE_AZURE_REDIRECT_URI: \"$BASE\"" "$cfg"
if printf '%s' "$cfg" | grep -qi 'secret'; then echo "FAIL  config.js mentions a secret"; fail=1; else echo "PASS  config.js carries no secret"; fi

echo "== API health (public)"
h=$(curl -sS --max-time 20 "$BASE/actuator/health")
contains "/actuator/health reports UP" '"status":"UP"' "$h"
check "/actuator/health/readiness is 200"    200 "$(code "$BASE/actuator/health/readiness")"

echo "== API rejects bad credentials"
check "no token -> 401"                      401 "$(code "$BASE/api/resource")"
check "no token on /api/admin -> 401"        401 "$(code "$BASE/api/admin")"
check "garbage bearer -> 401"                401 "$(code -H 'Authorization: Bearer not-a-jwt' "$BASE/api/resource")"
check "alg=none token -> 401"                401 "$(code -H "Authorization: Bearer $(forge_none)" "$BASE/api/resource")"
check "forged RS256 token (wrong key, wrong aud) -> 401" 401 "$(code -H "Authorization: Bearer $(forge some-other-api)" "$BASE/api/resource")"
check "forged RS256 token on /api/admin -> 401" 401 "$(code -H "Authorization: Bearer $(forge some-other-api)" "$BASE/api/admin")"

echo "== API errors are not rewritten into the SPA (401 stays a 401)"
ctype=$(curl -sS -o /dev/null -w '%{content_type}' --max-time 20 "$BASE/api/resource")
if printf '%s' "$ctype" | grep -qi 'text/html'; then echo "FAIL  401 from /api came back as HTML"; fail=1; else echo "PASS  401 from /api is not HTML ($ctype)"; fi

if [ -n "$ALB" ]; then
  echo "== Origin lock: the ALB refuses requests that did not come through API Gateway"
  # Without the secret header API Gateway injects, the listener answers 403 for
  # every path. A 200/401 here would mean the lock is open.
  for path in /actuator/health /api/resource /; do
    a=$(code --max-time 10 "http://$ALB$path")
    if [ "$a" = 403 ]; then echo "PASS  direct ALB $path blocked ($a)"; else echo "FAIL  direct ALB $path returned $a"; fail=1; fi
  done
fi

echo
if [ $fail -eq 0 ]; then echo "SMOKE: ALL PASSED"; else echo "SMOKE: FAILURES"; fi
exit $fail
# lock-race proof 1
# lock-race proof 2
