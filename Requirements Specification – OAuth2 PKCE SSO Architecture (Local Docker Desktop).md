# Requirements Specification – OAuth2/PKCE SSO Architecture (Local Docker Desktop)

Sep 24, 2026 · @Shakeel Ahmad

## 1. Purpose and scope

This document specifies the requirements for standing up the SSO authentication architecture — React SPA, MSAL Library, Microsoft Entra ID, and a Spring Boot Resource Server — as a fully local, containerized environment using Docker Desktop.

**Purpose:** enable developers to build, test, and demo the OAuth2 Authorization Code flow with PKCE end-to-end on a local machine, without provisioning cloud infrastructure for the application tiers.

**In scope:**

- Dockerized React SPA and Spring Boot Resource Server, orchestrated via Docker Compose
- Local network configuration so containers can reach each other and the host browser
- Integration with a real Microsoft Entra ID tenant (cloud-hosted identity provider — Entra ID itself is not containerized)
- Environment configuration for redirect URIs, CORS, and JWT validation

**Out of scope:** production deployment topology, CI/CD pipeline, cloud hosting of the resource server, and horizontal scaling.

## 2. System overview

| Component | Role | Runs where |
| --- | --- | --- |
| React SPA | Public client; renders UI, initiates login | Docker container |
| MSAL Library | Handles PKCE code exchange, token cache, silent renewal | Bundled inside the SPA container |
| Microsoft Entra ID | Identity provider; authenticates user, issues JWT | Microsoft cloud (not containerized) |
| Spring Boot Resource Server | Protected API; validates JWT, serves data | Docker container |

The SPA and resource server run as sibling containers on a shared Docker network. Entra ID remains a cloud dependency — a real tenant is required since there is no supported way to fully emulate Entra ID's authorization endpoints locally.

## 3. Local Docker Desktop environment

**Host requirements:**

- Docker Desktop 4.x or later (Windows, macOS, or Linux), with Docker Compose v2
- Minimum 4 GB RAM and 2 vCPUs allocated to Docker Desktop
- Ports 3000 (SPA) and 8080 (resource server) free on the host

**Containers:**

| Service | Base image | Exposed port | Notes |
| --- | --- | --- | --- |
| `spa` | `node:20-alpine` (build) → `nginx:alpine` (serve) | 3000:80 | Multi-stage build; serves the compiled React bundle |
| `resource-server` | `eclipse-temurin:21-jre-alpine` | 8080:8080 | Spring Boot fat jar |

**Networking:**

- Both services join a user-defined bridge network (e.g. `sso-net`) so they can address each other by service name
- The browser reaches both services via `localhost`, not the internal Docker DNS names, since the user's machine — not another container — makes the requests

**Orchestration:** a single `docker-compose.yml` at the project root defines both services, the shared network, and environment variable injection (see Section 5).

## 4. Functional requirements

| ID | Requirement |
| --- | --- |
| FR-1 | The SPA shall redirect an unauthenticated user to Entra ID's sign-in page via MSAL |
| FR-2 | MSAL shall use the Authorization Code flow with PKCE (no client secret in the SPA) |
| FR-3 | On an active cached session, MSAL shall acquire a token silently without a redirect |
| FR-4 | The SPA shall attach the JWT as `Authorization: Bearer <token>` on every call to the resource server |
| FR-5 | The resource server shall validate the JWT's signature against Entra ID's public signing keys |
| FR-6 | The resource server shall reject expired or malformed tokens with `401 Unauthorized` |
| FR-7 | The resource server shall evaluate roles/claims in the token and return `403 Forbidden` for insufficient authorization |
| FR-8 | On success, the resource server shall return `200 OK` with the requested data |

## 5. Configuration requirements

**Entra ID app registration:**

- A registered SPA application (public client, PKCE-only — no client secret)
- Redirect URI set to `http://localhost:3000` (or the container's published port)
- API permissions scoped to the resource server's exposed API
- A registered API application for the Spring Boot resource server, exposing an App ID URI and defined app roles/scopes

**Environment variables (`docker-compose.yml` / `.env`):**

| Variable | Consumed by | Purpose |
| --- | --- | --- |
| `VITE_AZURE_CLIENT_ID` | spa | MSAL app registration client ID |
| `VITE_AZURE_TENANT_ID` | spa | Entra ID tenant ID |
| `VITE_AZURE_REDIRECT_URI` | spa | `http://localhost:3000` |
| `VITE_API_BASE_URL` | spa | `http://localhost:8080` |
| `AZURE_TENANT_ID` | resource-server | Used to build the JWKS/issuer URI for token validation |
| `AZURE_CLIENT_ID` | resource-server | Expected audience claim on incoming tokens |

**CORS:** the resource server must allow `http://localhost:3000` as an allowed origin for `Authorization` and `Content-Type` headers.

## 6. Non-functional requirements

| ID | Requirement |
| --- | --- |
| NFR-1 | No client secret shall be stored in the SPA container or its image — PKCE only |
| NFR-2 | JWT validation on the resource server shall be stateless (no per-request call back to Entra ID) |
| NFR-3 | `docker compose up` shall bring both services to a ready state in under 60 seconds on the minimum-spec host |
| NFR-4 | Container logs shall be readable via `docker compose logs` for both services, with request-level logging on the resource server |
| NFR-5 | Secrets (client IDs, tenant ID) shall be supplied via `.env`, excluded from version control via `.gitignore` |
| NFR-6 | The setup shall work offline for everything except the Entra ID authentication calls themselves |

## 7. Acceptance criteria

- [ ] `docker compose up` starts both containers and both report healthy
- [ ] Navigating to `http://localhost:3000` with no prior session redirects to the Entra ID sign-in page
- [ ] Successful sign-in returns the user to the SPA with a valid JWT held by MSAL
- [ ] A call to `GET /api/resource` with the JWT attached returns `200 OK` and the expected payload
- [ ] The same call with no `Authorization` header returns `401 Unauthorized`
- [ ] The same call with an expired or tampered token returns `401 Unauthorized`
- [ ] A token lacking the required role/claim returns `403 Forbidden`
- [ ] Reloading the SPA within the token's lifetime re-authenticates silently (no redirect)

## 8. Assumptions, constraints, out of scope

**Assumptions:**

- A real Microsoft Entra ID tenant with app registrations already exists or can be created by the developer
- Developers have local admin rights to run Docker Desktop
- The host machine can reach Microsoft's public Entra ID endpoints over the internet

**Constraints:**

- Entra ID cannot be run fully offline or containerized; the identity provider hop always requires network access
- Localhost redirect URIs must match exactly what is registered in Entra ID, including port

**Out of scope:**

- Production/staging deployment (Kubernetes, cloud container registries)
- CI/CD pipeline definition
- Multi-tenant or B2C configurations
- Load testing and horizontal scaling of the resource server
