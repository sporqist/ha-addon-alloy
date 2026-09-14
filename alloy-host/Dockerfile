# The host variant IS the base image plus one marker file. Everything - the
# Alloy binary, the generator, the healthcheck - comes from the published base,
# pinned by tag and digest, so the two add-ons cannot drift: Renovate bumps
# this line after every base publish, and that bump goes through the same gate
# (the e2e runs the combined image under this variant's own profile).
#
# The cost is one Renovate cycle of lag: a base change reaches alloy-host when
# Renovate's next pass opens and merges the digest bump.
ARG BASE_IMAGE=ghcr.io/sporqist/ha-addon-alloy:1.13.2.3@sha256:a0846111dab6b53f4439747b68c7ad9931688416d78c4b1b4f7fd3afa277a11f
FROM ${BASE_IMAGE}

# The generator reads this and adds prometheus.exporter.unix for the host.
RUN mkdir -p /etc/alloy-addon && printf 'host' > /etc/alloy-addon/variant

LABEL \
    org.opencontainers.image.title="Grafana Alloy for Home Assistant (host metrics)" \
    org.opencontainers.image.description="The Grafana Alloy add-on plus host metrics: CPU, memory, load, disk, pressure and temperatures of the Home Assistant OS host" \
    org.opencontainers.image.source="https://github.com/sporqist/ha-addon-alloy" \
    org.opencontainers.image.licenses="MIT"
