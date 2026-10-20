package com.entractive.rs;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.forwardedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/**
 * The AWS image serves the SPA and the API from one origin. Serving public
 * static files must not weaken the API: these tests pin the ordering between
 * the public SPA rules and the protected /api/** rules.
 */
@SpringBootTest
@AutoConfigureMockMvc
class SpaServingTest {

    private static final MockEntraId MOCK_IDP;
    private static final Path SPA_DIR;

    static {
        try {
            MOCK_IDP = new MockEntraId();
            SPA_DIR = Files.createTempDirectory("spa");
            Files.writeString(SPA_DIR.resolve("index.html"), "<html><div id=\"root\"></div>SPA-INDEX</html>");
            Files.writeString(SPA_DIR.resolve("config.js"), "window.__APP_CONFIG__ = {};");
            Files.createDirectories(SPA_DIR.resolve("assets"));
            Files.writeString(SPA_DIR.resolve("assets/app-abc123.js"), "console.log('x')");
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("app.spa.dir", SPA_DIR::toString);
        registry.add("app.auth.tenant-id", () -> TestTokens.TENANT_ID);
        registry.add("app.auth.jwk-set-uri", () -> MOCK_IDP.baseUrl() + "/discovery/v2.0/keys");
        registry.add("app.auth.audience", () -> TestTokens.AUDIENCE);
        registry.add("app.auth.required-scope", () -> "Api.Access");
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
    @DisplayName("GET / is public and forwards to index.html (MockMvc does not follow forwards; the live container is checked separately)")
    void rootServesIndex() throws Exception {
        mvc.perform(get("/")).andExpect(status().isOk()).andExpect(forwardedUrl("/index.html"));
        mvc.perform(get("/index.html")).andExpect(status().isOk())
           .andExpect(content().string(containsString("SPA-INDEX")));
    }

    @Test
    @DisplayName("Client-side route falls back to index.html (MSAL return path)")
    void deepRouteFallsBack() throws Exception {
        mvc.perform(get("/some/spa/route")).andExpect(status().isOk())
           .andExpect(content().string(containsString("SPA-INDEX")));
    }

    @Test
    @DisplayName("config.js is served and never cached")
    void configIsNoStore() throws Exception {
        mvc.perform(get("/config.js")).andExpect(status().isOk())
           .andExpect(header().string("Cache-Control", containsString("no-store")));
    }

    @Test
    @DisplayName("Hashed assets are cached immutably")
    void assetsAreImmutable() throws Exception {
        mvc.perform(get("/assets/app-abc123.js")).andExpect(status().isOk())
           .andExpect(header().string("Cache-Control", containsString("immutable")));
    }

    @Test
    @DisplayName("A missing file (has an extension) is a real 404, not index.html")
    void missingFileIs404() throws Exception {
        mvc.perform(get("/assets/nope.js")).andExpect(status().isNotFound());
        mvc.perform(get("/missing.js")).andExpect(status().isNotFound());
        mvc.perform(get("/deep/missing.css")).andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("Serving the SPA does not open the API: no token -> 401")
    void apiStillRequiresToken() throws Exception {
        mvc.perform(get("/api/resource")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/admin")).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Unknown /api path without a token is 401, never the SPA index")
    void unknownApiPathNotIndex() throws Exception {
        mvc.perform(get("/api/does-not-exist"))
           .andExpect(status().isUnauthorized())
           .andExpect(content().string(not(containsString("SPA-INDEX"))));
    }

    @Test
    @DisplayName("Unknown /api path WITH a valid token is 404, never the SPA index")
    void unknownApiPathWithTokenIs404() throws Exception {
        mvc.perform(get("/api/does-not-exist").header("Authorization", "Bearer " + TestTokens.validNoRoles()))
           .andExpect(status().isNotFound())
           .andExpect(content().string(not(containsString("SPA-INDEX"))));
    }

    @Test
    @DisplayName("Scope guard still applies with the SPA enabled")
    void scopeGuardStillApplies() throws Exception {
        mvc.perform(get("/api/resource").header("Authorization", "Bearer " + TestTokens.wrongScope()))
           .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("Non-GET to a non-API path is not public")
    void postElsewhereNotPublic() throws Exception {
        mvc.perform(post("/anything")).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Security headers are present on the SPA response")
    void securityHeaders() throws Exception {
        mvc.perform(get("/"))
           .andExpect(header().string("X-Content-Type-Options", "nosniff"))
           .andExpect(header().string("X-Frame-Options", "DENY"))
           .andExpect(header().string("Strict-Transport-Security", containsString("max-age=31536000")))
           .andExpect(header().string("Content-Security-Policy", containsString("frame-ancestors 'none'")))
           .andExpect(header().string("Referrer-Policy", "strict-origin-when-cross-origin"));
    }
}
