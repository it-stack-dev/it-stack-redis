# Dockerfile — IT-Stack REDIS wrapper
# Module 04 | Category: database | Phase: 1
# Base image: redis:7-alpine

FROM redis:7-alpine

# Labels
LABEL org.opencontainers.image.title="it-stack-redis" \
      org.opencontainers.image.description="Redis cache and session store" \
      org.opencontainers.image.vendor="it-stack-dev" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/it-stack-dev/it-stack-redis"

# Copy custom configuration and scripts
COPY src/ /opt/it-stack/redis/
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
