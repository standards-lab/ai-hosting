# Postgres's image pin, its development credential, and its health check.
# See context/gateway.md
FROM postgres:19.0-alpine

ENV POSTGRES_USER=agentgateway \
    POSTGRES_PASSWORD=agentgateway \
    POSTGRES_DB=agentgateway

HEALTHCHECK --start-period=30s --start-interval=1s --interval=5s --timeout=3s --retries=5 \
    CMD ["pg_isready", "-h", "127.0.0.1", "-U", "agentgateway", "-d", "agentgateway"]
