# Grafana's image pin, its anonymous admin access, its datasources, and its health check.
# See context/gateway.md
FROM grafana/grafana:13.3.2

ENV GF_AUTH_ANONYMOUS_ENABLED=true \
    GF_AUTH_ANONYMOUS_ORG_ROLE=Admin

COPY provisioning /etc/grafana/provisioning

HEALTHCHECK --start-period=30s --start-interval=1s --interval=5s --timeout=3s --retries=5 \
    CMD ["wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/health"]
