package com.entractive.rs;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.Date;
import java.util.List;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

/**
 * Mints JWTs signed with a locally-generated RSA key, and publishes the matching
 * JWKS so the resource server can validate them without touching Entra ID.
 * This is what lets the 401/403 acceptance criteria be proven offline.
 */
final class TestTokens {

    /**
     * Set to the mock IdP's own base URL before tokens are minted. Spring's
     * withIssuerLocation() requires the discovery document's `issuer` to equal
     * the location it fetched, so both sides must agree on this value.
     */
    private static String issuer = "https://login.microsoftonline.com/test-tenant/v2.0";

    static void setIssuer(String value) { issuer = value; }
    static String issuer() { return issuer; }
    static final String AUDIENCE = "test-api-client-id";
    static final String KEY_ID   = "test-key-1";

    private static final KeyPair KEY_PAIR = generate();

    private static KeyPair generate() {
        try {
            KeyPairGenerator gen = KeyPairGenerator.getInstance("RSA");
            gen.initialize(2048);
            return gen.generateKeyPair();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    /** The JWKS document the mock Entra ID endpoint serves. */
    static String jwksJson() {
        RSAKey key = new RSAKey.Builder((RSAPublicKey) KEY_PAIR.getPublic())
                .keyID(KEY_ID)
                .algorithm(JWSAlgorithm.RS256)
                .build();
        return "{\"keys\":[" + key.toPublicJWK().toJSONString() + "]}";
    }

    static String valid(List<String> roles) {
        return sign(builder().claim("roles", roles).build());
    }

    static String validNoRoles() {
        return sign(builder().build());
    }

    static String expired() {
        Instant past = Instant.now().minusSeconds(7200);
        return sign(base()
                .issueTime(Date.from(past))
                .expirationTime(Date.from(past.plusSeconds(3600)))
                .build());
    }

    static String wrongAudience() {
        return sign(base().audience("some-other-api").build());
    }

    static String wrongIssuer() {
        return sign(base().issuer("https://evil.example.com/v2.0").build());
    }

    /** Correctly-structured token signed with a key the server does not trust. */
    static String badSignature() {
        try {
            KeyPair rogue = generate();
            SignedJWT jwt = new SignedJWT(
                    new JWSHeader.Builder(JWSAlgorithm.RS256).keyID(KEY_ID).build(),
                    builder().build());
            jwt.sign(new RSASSASigner((RSAPrivateKey) rogue.getPrivate()));
            return jwt.serialize();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static JWTClaimsSet.Builder builder() {
        return base();
    }

    private static JWTClaimsSet.Builder base() {
        Instant now = Instant.now();
        return new JWTClaimsSet.Builder()
                .issuer(issuer)
                .audience(AUDIENCE)
                .subject("test-subject-oid")
                .claim("preferred_username", "dev@example.com")
                .claim("name", "Dev User")
                .claim("scp", "Api.Access")
                .issueTime(Date.from(now))
                .expirationTime(Date.from(now.plusSeconds(3600)));
    }

    private static String sign(JWTClaimsSet claims) {
        try {
            SignedJWT jwt = new SignedJWT(
                    new JWSHeader.Builder(JWSAlgorithm.RS256).keyID(KEY_ID).build(), claims);
            jwt.sign(new RSASSASigner((RSAPrivateKey) KEY_PAIR.getPrivate()));
            return jwt.serialize();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private TestTokens() {}
}
