# Mimir's image pin and its config, run as a single binary.
# See context/gateway.md
FROM grafana/mimir:3.2.6

COPY mimir.yaml /etc/mimir/mimir.yaml

CMD ["-config.file=/etc/mimir/mimir.yaml", "-target=all"]
