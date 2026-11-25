# The OpenTelemetry Collector's image pin, contrib distribution, and its config.
# See docs/gateway.md
FROM otel/opentelemetry-collector-contrib:0.166.0

COPY otel-collector.yaml /etc/otelcol-contrib/otel-collector.yaml

CMD ["--config=/etc/otelcol-contrib/otel-collector.yaml"]
