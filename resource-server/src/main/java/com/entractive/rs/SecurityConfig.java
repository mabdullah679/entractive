package com.entractive.rs;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtClaimNames;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.JwtGrantedAuthoritiesConverter;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

@Configuration
@EnableMethodSecurity   // enables @PreAuthorize on the controller (FR-7)
public class SecurityConfig {

    private final String tenantId;
    private final String jwksUri;
    private final String audience;
    private final List<String> allowedOrigins;

    SecurityConfig(
            @Value("${app.auth.tenant-id}") String tenantId,
            @Value("${app.auth.jwk-set-uri}") String jwksUri,
            @Value("${app.auth.audience}") String audience,
            @Value("${app.cors.allowed-origins}") List<String> allowedOrigins) {
        this.tenantId = tenantId;
        this.jwksUri = jwksUri;
        this.audience = audience;
        this.allowedOrigins = allowedOrigins;
    }

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            // No cookies or server-side session: the bearer token is the whole
            // credential, so CSRF protection is not applicable (NFR-2).
            .csrf(csrf -> csrf.disable())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                // CORS preflight carries no Authorization header by design.
                .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                .requestMatchers("/actuator/health/**").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt
                    .decoder(jwtDecoder())
                    .jwtAuthenticationConverter(jwtAuthenticationConverter())));
        return http.build();
    }

    /**
     * FR-5: validates the signature against Entra ID's published JWKS.
     *
     * NimbusJwtDecoder fetches the JWKS once and caches the keys, so steady-state
     * validation makes no per-request network call (NFR-2). Issuer and expiry are
     * checked by the default validator; audience is checked explicitly below,
     * because a signature-valid token minted for a *different* API would
     * otherwise be accepted.
     */
    @Bean
    JwtDecoder jwtDecoder() {
        // Build the JWKS URI from the issuer by convention rather than calling
        // withIssuerLocation(), which fetches the OpenID discovery document
        // *eagerly at startup* and aborts the whole context if Microsoft is
        // unreachable or the tenant ID is a placeholder. Deriving it keeps the
        // container bootable offline (NFR-6) and before the Entra ID app
        // registrations exist; a bad tenant then surfaces as a 401 on the first
        // request instead of a crash loop.
        NimbusJwtDecoder decoder = NimbusJwtDecoder
                .withJwkSetUri(jwksUri)
                .jwsAlgorithm(SignatureAlgorithm.RS256)
                .build();

        // JwtValidators.createDefault() supplies expiry/not-before checks without
        // pinning a single issuer string — issuer is validated separately below,
        // since Entra ID legitimately mints two different issuer shapes for one
        // tenant (see TenantIssuerValidator).
        OAuth2TokenValidator<Jwt> withTiming = JwtValidators.createDefault();
        OAuth2TokenValidator<Jwt> withIssuer = new TenantIssuerValidator(tenantId);
        OAuth2TokenValidator<Jwt> withAudience = new AudienceValidator(audience);
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(withTiming, withIssuer, withAudience));
        return decoder;
    }

    /**
     * Entra ID delivers app roles in a "roles" claim and delegated permissions in
     * "scp". Spring's default converter only reads "scope"/"scp", so app roles
     * would silently never become authorities — and every @PreAuthorize on a role
     * would 403 regardless of the token. Map both.
     *
     * Deliberately NOT a @Bean: a bean of type Converter gets picked up by Spring
     * MVC's FormattingConversionService, which cannot infer <S>/<T> from a lambda
     * and fails the whole context at startup.
     */
    private JwtAuthenticationConverter jwtAuthenticationConverter() {
        JwtGrantedAuthoritiesConverter scopes = new JwtGrantedAuthoritiesConverter();
        scopes.setAuthorityPrefix("SCOPE_");
        scopes.setAuthoritiesClaimName("scp");

        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setPrincipalClaimName(JwtClaimNames.SUB);
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            Collection<GrantedAuthority> authorities = new ArrayList<>(scopes.convert(jwt));
            List<String> roles = jwt.getClaimAsStringList("roles");
            if (roles != null) {
                roles.forEach(r -> authorities.add(new SimpleGrantedAuthority("ROLE_" + r)));
            }
            return authorities;
        });
        return converter;
    }

    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(allowedOrigins);
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("Authorization", "Content-Type"));
        config.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
