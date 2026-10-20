# EntrActive — Local Sign-In and Access Control Demo

## Recruiter-friendly overview
EntrActive is a complete demonstration of how a modern application securely signs users in with Microsoft, checks who they are, and controls which features they can use. It combines a simple web interface with a backend service and runs locally through Docker, making the full sign-in journey easy to reproduce and test. The project demonstrates practical experience with security, cloud identity, APIs, containers, and automated testing.

## Project description
A local end-to-end single sign-on application using Microsoft Entra ID, OAuth 2.0 with PKCE, a React web app, and a Spring Boot backend that validates tokens and role-based permissions.

---

# Local SSO stack — React SPA + Entra ID + Spring Boot

OAuth2 Authorization Code flow with PKCE, running end-to-end on Docker Desktop.
Implements the requirements in
[Requirements Specification – OAuth2 PKCE SSO Architecture (Local Docker Desktop).md](Requirements%20Specification%20%E2%80%93%20OAuth2%20PKCE%20SSO%20Architecture%20(Local%20Docker%20Desktop).md[...]

```
browser ──▶ spa (nginx :3000) ──▶ Entra ID (cloud) ──┐
                │                                     │ JWT
                └──────────▶ resource-server (:8080) ◀┘
```

Entra ID is **not** containerized — a real tenant is required. Everything else
runs locally.

## Prerequisites

- Docker Desktop 4.x with Compose v2, ≥4 GB RAM, ≥2 vCPUs
- Ports 3000 and 8080 free
- A Microsoft Entra ID tenant you can create app registrations in

## Run it

See the existing setup instructions below for platform-specific commands, configuration, tests, API collection, layout, and design decisions.
