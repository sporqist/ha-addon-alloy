# The host variant IS the base image plus one marker file. Everything - the
# Alloy binary, the generator, the healthcheck - comes from the published base,
# pinned by tag and digest, so the two add-ons cannot drift: Renovate bumps
# this line after every base publish, and that bump goes through the same gate
# (the e2e runs the combined image under this variant's own profile).
#
# The cost is one Renovate cycle of lag: a base change reaches alloy-host when
# Renovate's next pass opens and merges the digest bump.
ARG BASE_IMAGE=ghcr.io/sporqist/ha-addon-alloy:1.20.0@sha256:47557c3596d51a8b5551bde00b3bd845964530eefe9b5afd4a81c236d562b38c
FROM ${BASE_IMAGE}

# The generator reads this and adds prometheus.exporter.unix for the host.
RUN mkdir -p /etc/alloy-addon && printf 'host' > /etc/alloy-addon/variant

LABEL \
    org.opencontainers.image.title="Grafana Alloy for Home Assistant (host metrics)" \
    org.opencontainers.image.description="The Grafana Alloy add-on plus host metrics: CPU, memory, load, disk, pressure and temperatures of the Home Assistant OS host" \
    org.opencontainers.image.source="https://github.com/sporqist/ha-addon-alloy" \
    org.opencontainers.image.licenses="MIT"
