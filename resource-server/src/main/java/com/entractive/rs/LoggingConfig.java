package com.entractive.rs;

import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

@Configuration
class LoggingConfig {

    /**
     * Registered ahead of Spring Security's filter chain (NFR-4). A plain
     * @Component + @Order(MAX_VALUE) filter is ordered *after* the security
     * chain, so a 401 short-circuits the request and nothing is ever logged —
     * the requirement would look satisfied in code while producing no output.
     */
    @Bean
    FilterRegistrationBean<RequestLoggingFilter> requestLoggingFilter() {
        FilterRegistrationBean<RequestLoggingFilter> registration =
                new FilterRegistrationBean<>(new RequestLoggingFilter());
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE);
        registration.addUrlPatterns("/*");
        return registration;
    }
}
