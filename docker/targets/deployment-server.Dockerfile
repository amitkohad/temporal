ARG RUNTIME_BASE
FROM ${RUNTIME_BASE}
ARG SOURCE_COMMIT
ARG SERVER_VERSION
ARG BUILD_DRIVER_SHA256
LABEL org.opencontainers.image.source="https://github.com/amitkohad/temporal" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.opencontainers.image.version="${SERVER_VERSION}" \
      io.nexusflow.build.driver.sha256="${BUILD_DRIVER_SHA256}"
COPY --chmod=0555 bin/temporal-server /usr/local/bin/temporal-server
WORKDIR /etc/temporal
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/temporal-server"]
CMD ["start"]