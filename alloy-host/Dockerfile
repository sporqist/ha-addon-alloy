# The host variant IS the base image plus one marker file. Everything - the
# Alloy binary, the generator, the healthcheck - comes from the published base,
# pinned by tag and digest, so the two add-ons cannot drift: Renovate bumps
# this line after every base publish, and that bump goes through the same gate
# (the e2e runs the combined image under this variant's own profile).
#
# The cost is one Renovate cycle of lag: a base change reaches alloy-host when
# Renovate's next pass opens and merges the digest bump.
ARG BASE_IMAGE=ghcr.io/sporqist/ha-addon-alloy:1.19.2.1@sha256:04e0557e7b67448e9bd9f66099b98f454a227364ca78aebb60d47a7a5db13e47
FROM ${BASE_IMAGE}

# The generator reads this and adds prometheus.exporter.unix for the host.
RUN mkdir -p /etc/alloy-addon && printf 'host' > /etc/alloy-addon/variant

LABEL \
    org.opencontainers.image.title="Grafana Alloy for Home Assistant (host metrics)" \
    org.opencontainers.image.description="The Grafana Alloy add-on plus host metrics: CPU, memory, load, disk, pressure and temperatures of the Home Assistant OS host" \
    org.opencontainers.image.source="https://github.com/sporqist/ha-addon-alloy" \
    org.opencontainers.image.licenses="MIT"
