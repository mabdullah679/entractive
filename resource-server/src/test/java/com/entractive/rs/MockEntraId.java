package com.entractive.rs;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

import com.sun.net.httpserver.HttpServer;

/**
 * Minimal stand-in for Entra ID's JWKS endpoint, so the resource server's real
 * NimbusJwtDecoder path (signature, issuer, expiry, audience) is exercised
 * without network access.
 *
 * The server builds its JWKS URI by convention rather than fetching an OpenID
 * discovery document (see SecurityConfig), so only the JWKS document itself
 * needs to be served here. The authorization and token endpoints are NOT
 * emulated — the browser-facing half of the flow still requires a real tenant,
 * exactly as the spec states.
 */
final class MockEntraId {

    private final HttpServer server;
    private final String baseUrl;

    MockEntraId() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        int port = server.getAddress().getPort();
        baseUrl = "http://127.0.0.1:" + port;

        server.createContext("/discovery/v2.0/keys", exchange -> respond(exchange, TestTokens.jwksJson()));
        server.setExecutor(null);
        server.start();
    }

    private static void respond(com.sun.net.httpserver.HttpExchange exchange, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().add("Content-Type", "application/json");
        exchange.sendResponseHeaders(200, bytes.length);
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(bytes);
        }
    }

    String baseUrl() {
        return baseUrl;
    }

    void stop() {
        server.stop(0);
    }
}
