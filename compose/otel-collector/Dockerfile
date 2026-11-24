# The OpenTelemetry Collector's image pin, contrib distribution, and its config.
# See context/gateway.md
FROM otel/opentelemetry-collector-contrib:0.165.0

COPY otel-collector.yaml /etc/otelcol-contrib/otel-collector.yaml

CMD ["--config=/etc/otelcol-contrib/otel-collector.yaml"]
