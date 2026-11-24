# Loki's image pin and its config.
# See context/gateway.md
FROM grafana/loki:3.7.10

COPY loki.yaml /etc/loki/loki.yaml

CMD ["-config.file=/etc/loki/loki.yaml"]
