package com.entractive.rs;

import java.util.Set;

import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;

/**
 * Accepts either issuer shape Entra ID mints for a single tenant.
 *
 * Depending on the app registration and how the authority was configured on the
 * client, Entra ID issues tokens with either:
 *   - the v2.0 issuer:      https://login.microsoftonline.com/{tenant}/v2.0
 *   - the v1.0/STS issuer:  https://sts.windows.net/{tenant}/
 *
 * Both are genuine, Microsoft-published issuers for the same tenant — MSAL's
 * default authority (no explicit /v2.0 suffix) mints the v1.0 shape even when
 * the rest of the flow is v2.0. Spring's JwtValidators.createDefaultWithIssuer
 * only accepts one fixed string, which rejected valid same-tenant tokens.
 * Restricting to a hardcoded single issuer bought no additional security here —
 * the audience check (AudienceValidator) is what actually scopes tokens to this
 * API; this validator only confirms the token came from the expected tenant.
 */
class TenantIssuerValidator implements OAuth2TokenValidator<Jwt> {

    private final Set<String> validIssuers;

    TenantIssuerValidator(String tenantId) {
        this.validIssuers = Set.of(
                "https://login.microsoftonline.com/" + tenantId + "/v2.0",
                "https://sts.windows.net/" + tenantId + "/");
    }

    @Override
    public OAuth2TokenValidatorResult validate(Jwt jwt) {
        String iss = jwt.getIssuer() != null ? jwt.getIssuer().toString() : null;
        if (iss != null && validIssuers.contains(iss)) {
            return OAuth2TokenValidatorResult.success();
        }
        return OAuth2TokenValidatorResult.failure(new OAuth2Error(
                "invalid_token",
                "Token issuer %s is not one of the expected issuers for this tenant".formatted(iss),
                null));
    }
}
