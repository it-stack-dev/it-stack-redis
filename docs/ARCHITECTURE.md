# Architecture — IT-Stack REDIS

## Overview

Redis provides caching, session management, and queue brokering for the IT-Stack collaboration and communications services.

## Role in IT-Stack

- **Category:** database
- **Phase:** 1
- **Server:** lab-db1 (10.0.50.12)
- **Ports:** 6379 (Redis)

## Dependencies

| Dependency | Type | Required For |
|-----------|------|--------------|
| FreeIPA | Identity | User directory |
| Keycloak | SSO | Authentication |
| PostgreSQL | Database | Data persistence |
| Redis | Cache | Sessions/queues |
| Traefik | Proxy | HTTPS routing |

## Data Flow

```
User → Traefik (HTTPS) → redis → PostgreSQL (data)
                       ↗ Keycloak (auth)
                       ↗ Redis (sessions)
```

## Security

- All traffic over TLS via Traefik
- Authentication delegated to Keycloak OIDC
- Database credentials via Ansible Vault
- Logs shipped to Graylog
