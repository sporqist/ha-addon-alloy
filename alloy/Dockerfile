# https://developers.home-assistant.io/docs/apps/configuration#app-dockerfile
#
# THE DOCKERFILE IS THE SINGLE SOURCE OF TRUTH. build.yaml is gone: since
# Supervisor 2026.04.0 BUILD_FROM is no longer supplied, and the
# home-assistant/builder actions build straight from this file with BuildKit.
#
# Debian, not Alpine, on purpose: Alloy's journal source (loki.source.journal)
# reads the journal through libsystemd, which is glibc-linked. That library is
# what makes this add-on work at all, so it is installed by name below rather
# than relied on as a side effect of the base image.
#
# Pinned tag, multi-arch manifest (amd64 + arm64). Renovate tracks it.
FROM ghcr.io/home-assistant/base-debian:trixie-2026.08.0

# Renovate tracks this against grafana/alloy releases and bumps config.yaml's
# version in the same PR: the add-on version IS the Alloy version.
ARG ALLOY_VERSION="1.13.2"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        jq \
        libsystemd0 \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# TARGETARCH comes from BuildKit (amd64 | arm64). The release archive is
# verified against Grafana's published SHA256SUMS before it is unpacked; a
# checksum mismatch or a missing entry fails the build.
ARG TARGETARCH
RUN set -eux; \
    if [ -z "${TARGETARCH}" ]; then \
        echo "TARGETARCH is not set - build with Docker BuildKit." && exit 1; \
    fi; \
    case "${TARGETARCH}" in \
        amd64) asset="alloy-linux-amd64" ;; \
        arm64) asset="alloy-linux-arm64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" && exit 1 ;; \
    esac; \
    base="https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}"; \
    cd /tmp; \
    curl -fsSL -o "${asset}.zip" "${base}/${asset}.zip"; \
    curl -fsSL -o SHA256SUMS "${base}/SHA256SUMS"; \
    grep -E " ${asset}\.zip$" SHA256SUMS > "${asset}.sha256"; \
    test -s "${asset}.sha256"; \
    sha256sum -c "${asset}.sha256"; \
    unzip -q "${asset}.zip" -d extract; \
    install -m 0755 "extract/${asset}" /usr/bin/alloy; \
    rm -rf "${asset}.zip" SHA256SUMS "${asset}.sha256" extract; \
    /usr/bin/alloy --version

COPY rootfs /

# The Supervisor reads container health from this; the `watchdog` key in
# config.yaml is obsolete. /-/ready is served on the container's own address,
# so it works with the debug port unmapped on the host.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:12345/-/ready || exit 1

LABEL \
    org.opencontainers.image.title="Grafana Alloy for Home Assistant" \
    org.opencontainers.image.description="Ship the Home Assistant OS journal to Loki with Grafana Alloy" \
    org.opencontainers.image.source="https://github.com/sporqist/ha-addon-alloy" \
    org.opencontainers.image.licenses="MIT"
