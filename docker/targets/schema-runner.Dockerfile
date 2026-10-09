# Supply an isolated context containing only the qualified release bundle and reviewed executor scripts.
FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
ARG SOURCE_COMMIT
LABEL org.opencontainers.image.source="https://github.com/amitkohad/temporal" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      io.nexusflow.image.purpose="guarded-schema-executor"
# Debian supplies infrastructure clients; Temporal binaries and the token helper are fork-built artifacts.
RUN apt-get update && \
    apt-get install --no-install-recommends -y bash python3 postgresql-client ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /etc/temporal/release
COPY --chmod=0555 release/ /etc/temporal/release/
COPY --chmod=0555 release/build/bin/temporal-sql-tool /usr/local/bin/temporal-sql-tool
COPY --chmod=0555 release/executor/entra-token /usr/local/bin/entra-token
COPY --chmod=0555 scripts/deployment/schema.sh scripts/deployment/schema-operation.py scripts/deployment/release-evidence.py /usr/local/bin/
WORKDIR /etc/temporal/release
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/schema.sh"]
CMD ["--help"]