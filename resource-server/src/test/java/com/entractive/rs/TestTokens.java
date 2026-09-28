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
     * A fake tenant ID, not a real endpoint. TenantIssuerValidator derives its two
     * accepted issuer strings from this ID by the same string convention the real
     * server uses — the JWKS lookup itself is redirected to the mock IdP
     * separately (see MockEntraId / ResourceServerAcceptanceTest).
     */
    static final String TENANT_ID = "11111111-1111-1111-1111-111111111111";

    /** The v2.0-shaped issuer: what MSAL mints when the authority has /v2.0. */
    static final String ISSUER_V2 = "https://login.microsoftonline.com/" + TENANT_ID + "/v2.0";
    /** The v1.0/STS-shaped issuer: what real Entra ID minted for this project's
     *  tenant against MSAL's default authority — see TenantIssuerValidator. */
    static final String ISSUER_STS = "https://sts.windows.net/" + TENANT_ID + "/";

    private static String issuer = ISSUER_V2;

    static void useIssuer(String value) { issuer = value; }
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

    /** A token in the v1.0/STS issuer shape — the real-world regression case. */
    static String validWithStsIssuer() {
        return sign(base().issuer(ISSUER_STS).build());
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
