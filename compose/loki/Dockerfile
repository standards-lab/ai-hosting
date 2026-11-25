# Loki's image pin and its config.
# See docs/gateway.md
FROM grafana/loki:3.7.10

COPY loki.yaml /etc/loki/loki.yaml

CMD ["-config.file=/etc/loki/loki.yaml"]
