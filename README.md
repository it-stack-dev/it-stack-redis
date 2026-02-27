# IT-Stack REDIS — Module 04

Redis provides caching, session management, and queue brokering for the IT-Stack collaboration and communications services.

**Category:** database · **Phase:** 1 · **Server:** lab-db1  
**Ports:** 6379 (Redis)

---

## Quick Start — Lab 01 (Standalone)

```bash
# Clone and run standalone lab
git clone https://github.com/it-stack-dev/it-stack-redis.git
cd it-stack-redis
make test-lab-01
```

## Lab Progression

| Lab | Name | Duration | Purpose |
|-----|------|----------|---------|
| [01-standalone](docs/labs/01-standalone.md) | Standalone | 30–60 min | Basic functionality in isolation |
| [02-external](docs/labs/02-external.md) | External Dependencies | 45–90 min | Network integration, external services |
| [03-advanced](docs/labs/03-advanced.md) | Advanced Features | 60–120 min | Production features, performance |
| [04-sso](docs/labs/04-sso.md) | SSO Integration | 90–120 min | Keycloak OIDC/SAML authentication |
| [05-integration](docs/labs/05-integration.md) | Advanced Integration | 90–150 min | Multi-module ecosystem integration |
| [06-production](docs/labs/06-production.md) | Production Deployment | 120–180 min | HA cluster, monitoring, DR |

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Module Manifest

See [$repo.yml](it-stack-redis.yml) for full module metadata.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [organization guide](https://github.com/it-stack-dev/.github/blob/main/CONTRIBUTING.md).

## License

Apache 2.0 — see [LICENSE](LICENSE).
