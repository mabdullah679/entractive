# ---- build stage -----------------------------------------------------------
# Built inside Docker so the host needs no JDK or Maven (NFR-6 / reproducibility).
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build
# Copy the POM alone first so the dependency layer caches across source edits.
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q clean package -DskipTests

# ---- runtime stage ---------------------------------------------------------
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
# curl is needed for the compose healthcheck; the JRE alpine image has none.
RUN apk add --no-cache curl && adduser -D -u 10001 spring
COPY --from=build /build/target/*.jar app.jar
USER spring
EXPOSE 8080
ENTRYPOINT ["java","-XX:MaxRAMPercentage=75","-jar","/app/app.jar"]
