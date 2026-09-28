package com.entractive.rs;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class ResourceController {

    private final String requiredRole;

    ResourceController(@Value("${app.auth.required-role}") String requiredRole) {
        this.requiredRole = requiredRole;
    }

    /**
     * FR-8: any validly-authenticated caller gets the payload. Reaching this
     * method already means the JWT passed signature, issuer, expiry and audience
     * checks — anything else was rejected with 401 by the filter chain (FR-6).
     */
    @GetMapping("/resource")
    public Map<String, Object> resource(@AuthenticationPrincipal Jwt jwt) {
        return Map.of(
                "message", "Protected payload served from the Spring Boot resource server",
                "servedAt", Instant.now().toString(),
                "subject", String.valueOf(jwt.getClaimAsString("sub")),
                "preferredUsername", String.valueOf(jwt.getClaimAsString("preferred_username")),
                "name", String.valueOf(jwt.getClaimAsString("name")),
                "scopes", nullSafe(jwt.getClaimAsStringList("scp")),
                "roles", nullSafe(jwt.getClaimAsStringList("roles")),
                "audience", nullSafe(jwt.getAudience()),
                "expiresAt", String.valueOf(jwt.getExpiresAt()));
    }

    /**
     * FR-7: role-gated. A valid token that lacks the configured app role is
     * authenticated but not authorized, so Spring returns 403 — not 401.
     */
    @GetMapping("/admin")
    @PreAuthorize("hasRole(@resourceController.requiredRole)")
    public Map<String, Object> admin(@AuthenticationPrincipal Jwt jwt) {
        return Map.of(
                "message", "Role-gated payload — your token carried the required app role",
                "requiredRole", requiredRole,
                "roles", nullSafe(jwt.getClaimAsStringList("roles")),
                "servedAt", Instant.now().toString());
    }

    /** Referenced by the @PreAuthorize expression above. */
    public String getRequiredRole() {
        return requiredRole;
    }

    private static List<String> nullSafe(List<String> in) {
        return in == null ? List.of() : in;
    }
}
