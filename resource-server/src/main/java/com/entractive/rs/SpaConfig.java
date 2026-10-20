package com.entractive.rs;

import java.io.IOException;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import org.springframework.web.servlet.resource.PathResourceResolver;

/**
 * Serves the built React SPA from the same origin as the API, so one HTTPS URL
 * fronts both and CORS is not involved. Only active when app.spa.dir is set
 * (the AWS image sets it; local docker-compose keeps the separate nginx SPA).
 *
 * History fallback: an unknown, extension-less path returns index.html so
 * client-side routes (and MSAL's redirect return) work. It must NEVER apply to
 * /api or /actuator, or a missing API route would answer 200 text/html.
 */
@Configuration
@ConditionalOnProperty("app.spa.dir")
class SpaConfig implements WebMvcConfigurer {

    private final String dir;

    SpaConfig(@Value("${app.spa.dir}") String dir) {
        this.dir = dir.endsWith("/") ? dir : dir + "/";
    }

    /** The resource handler never sees an empty path, so map "/" explicitly. */
    @Override
    public void addViewControllers(org.springframework.web.servlet.config.annotation.ViewControllerRegistry registry) {
        registry.addViewController("/").setViewName("forward:/index.html");
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        // Hashed build output: safe to cache for a year.
        registry.addResourceHandler("/assets/**")
                .addResourceLocations("file:" + dir + "assets/")
                .setCacheControl(CacheControl.maxAge(java.time.Duration.ofDays(365)).cachePublic().immutable());
        // Everything else (index.html, config.js, fallback): never cached, so a
        // new deploy or changed tenant is picked up immediately.
        registry.addResourceHandler("/**")
                .addResourceLocations("file:" + dir)
                .setCacheControl(CacheControl.noStore())
                .resourceChain(true)
                .addResolver(new SpaFallbackResolver());
    }

    static final class SpaFallbackResolver extends PathResourceResolver {
        @Override
        protected Resource getResource(String resourcePath, Resource location) throws IOException {
            Resource requested = location.createRelative(resourcePath);
            if (requested.exists() && requested.isReadable() && !resourcePath.isEmpty()) {
                return requested;
            }
            if (isFallbackEligible(resourcePath)) {
                Resource index = location.createRelative("index.html");
                return index.exists() ? index : null;
            }
            return null;
        }

        static boolean isFallbackEligible(String path) {
            if (path.equals("api") || path.startsWith("api/")
                    || path.equals("actuator") || path.startsWith("actuator/")) {
                return false;
            }
            String last = path.substring(path.lastIndexOf('/') + 1);
            return !last.contains(".");   // a missing *file* is a real 404
        }
    }
}
