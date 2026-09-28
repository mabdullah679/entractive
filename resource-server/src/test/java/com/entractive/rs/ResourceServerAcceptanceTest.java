package com.entractive.rs;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.io.IOException;
import java.util.List;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;

/**
 * Walks every acceptance criterion in Section 7 of the requirements spec that
 * lives on the resource-server side of the boundary.
 */
@SpringBootTest
@AutoConfigureMockMvc
class ResourceServerAcceptanceTest {

    private static final MockEntraId MOCK_IDP;

    static {
        try {
            MOCK_IDP = new MockEntraId();
        } catch (IOException e) {
            throw new IllegalStateException("could not start mock IdP", e);
        }
    }

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        // Point the decoder at the mock discovery document rather than Microsoft.
        registry.add("app.auth.issuer-uri", MOCK_IDP::baseUrl);
        registry.add("app.auth.jwk-set-uri", () -> MOCK_IDP.baseUrl() + "/discovery/v2.0/keys");
        registry.add("app.auth.audience", () -> TestTokens.AUDIENCE);
        registry.add("app.auth.required-role", () -> "Resource.Admin");
        registry.add("app.cors.allowed-origins", () -> "http://localhost:3000");
    }

    @AfterAll
    static void tearDown() {
        MOCK_IDP.stop();
    }

    @Autowired
    MockMvc mvc;

    @Test
    @DisplayName("FR-8: valid token returns 200 with the payload")
    void validTokenReturns200() throws Exception {
        mvc.perform(get("/api/resource").header("Authorization", "Bearer " + TestTokens.validNoRoles()))
           .andExpect(status().isOk())
           .andExpect(jsonPath("$.subject").value("test-subject-oid"))
           .andExpect(jsonPath("$.preferredUsername").value("dev@example.com"));
    }

    @Test
    @DisplayName("FR-6: no Authorization header returns 401")
    void missingTokenReturns401() throws Exception {
        mvc.perform(get("/api/resource"))
           .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("FR-6: malformed token returns 401")
    void malformedTokenReturns401() throws Exception {
        mvc.perform(get("/api/resource").header("Authorization", "Bearer not-a-jwt"))
           .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("FR-6: expired token returns 401")
    void expiredTokenReturns401() throws Exception {
        mvc.perform(get("/api/resource").header("Authorization", "Bearer " + TestTokens.expired()))
           .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("FR-5: token signed by an untrusted key returns 401")
    void tamperedSignatureReturns401() throws Exception {
        mvc.perform(get("/api/resource").header("Authorization", "Bearer " + TestTokens.badSignature()))
           .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Token minted for a different API returns 401")
    void wrongAudienceReturns401() throws Exception {
        mvc.perform(get("/api/resource").header("Authorization", "Bearer " + TestTokens.wrongAudience()))
           .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Token from a different issuer returns 401")
    void wrongIssuerReturns401() throws Exception {
        mvc.perform(get("/api/resource").header("Authorization", "Bearer " + TestTokens.wrongIssuer()))
           .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("FR-7: valid token lacking the required role returns 403, not 401")
    void missingRoleReturns403() throws Exception {
        mvc.perform(get("/api/admin").header("Authorization", "Bearer " + TestTokens.validNoRoles()))
           .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("FR-7: token carrying the required role returns 200")
    void correctRoleReturns200() throws Exception {
        mvc.perform(get("/api/admin")
                .header("Authorization", "Bearer " + TestTokens.valid(List.of("Resource.Admin"))))
           .andExpect(status().isOk())
           .andExpect(jsonPath("$.requiredRole").value("Resource.Admin"));
    }

    @Test
    @DisplayName("FR-7: a different role does not satisfy the gate")
    void wrongRoleReturns403() throws Exception {
        mvc.perform(get("/api/admin")
                .header("Authorization", "Bearer " + TestTokens.valid(List.of("Some.Other.Role"))))
           .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("Section 5: CORS preflight from the SPA origin is allowed")
    void corsPreflightAllowed() throws Exception {
        mvc.perform(options("/api/resource")
                .header("Origin", "http://localhost:3000")
                .header("Access-Control-Request-Method", "GET")
                .header("Access-Control-Request-Headers", "authorization"))
           .andExpect(status().isOk())
           .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:3000"));
    }

    @Test
    @DisplayName("CORS preflight from an unregistered origin is refused")
    void corsPreflightFromOtherOriginRefused() throws Exception {
        mvc.perform(options("/api/resource")
                .header("Origin", "http://evil.example.com")
                .header("Access-Control-Request-Method", "GET"))
           .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("Health endpoint is reachable unauthenticated for the compose healthcheck")
    void healthIsPublic() throws Exception {
        mvc.perform(get("/actuator/health"))
           .andExpect(status().isOk());
    }
}
