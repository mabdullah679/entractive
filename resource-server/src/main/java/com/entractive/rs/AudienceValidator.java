package com.entractive.rs;

import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;

/**
 * Rejects a token whose audience is not this API.
 *
 * Entra ID sets `aud` to either the API's client ID or its App ID URI
 * (api://<client-id>) depending on how the client requested the scope, so accept
 * both spellings of the same identity.
 */
class AudienceValidator implements OAuth2TokenValidator<Jwt> {

    private final String expectedAudience;

    AudienceValidator(String expectedAudience) {
        this.expectedAudience = expectedAudience;
    }

    @Override
    public OAuth2TokenValidatorResult validate(Jwt jwt) {
        var audiences = jwt.getAudience();
        if (audiences != null && (audiences.contains(expectedAudience)
                || audiences.contains("api://" + expectedAudience))) {
            return OAuth2TokenValidatorResult.success();
        }
        return OAuth2TokenValidatorResult.failure(new OAuth2Error(
                "invalid_token",
                "Token audience %s does not include the expected audience".formatted(audiences),
                null));
    }
}
