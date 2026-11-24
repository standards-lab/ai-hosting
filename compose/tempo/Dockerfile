# Tempo's image pin and its config.
# See docs/gateway.md
FROM grafana/tempo:3.1.1

COPY tempo.yaml /etc/tempo/tempo.yaml

CMD ["-config.file=/etc/tempo/tempo.yaml"]
