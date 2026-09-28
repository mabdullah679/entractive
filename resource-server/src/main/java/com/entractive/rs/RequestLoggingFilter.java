package com.entractive.rs;

import java.io.IOException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * NFR-4: request-level logging visible through `docker compose logs`.
 *
 * Registered explicitly in LoggingConfig at HIGHEST_PRECEDENCE so it wraps the
 * whole security chain: it must run *around* Spring Security, not inside it, or
 * requests rejected with 401/403 short-circuit before the filter is reached and
 * never get logged at all. Never logs the Authorization header value.
 */
class RequestLoggingFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(RequestLoggingFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        long start = System.nanoTime();
        try {
            chain.doFilter(req, res);
        } finally {
            long ms = (System.nanoTime() - start) / 1_000_000;
            log.info("{} {} -> {} ({} ms) bearer={}",
                    req.getMethod(),
                    req.getRequestURI(),
                    res.getStatus(),
                    ms,
                    req.getHeader("Authorization") != null ? "present" : "absent");
        }
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        return req.getRequestURI().startsWith("/actuator/health");
    }
}
