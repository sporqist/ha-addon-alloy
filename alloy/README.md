# Grafana Alloy for Home Assistant

![Supports amd64 Architecture](https://img.shields.io/badge/amd64-yes-green.svg)
![Supports aarch64 Architecture](https://img.shields.io/badge/aarch64-yes-green.svg)

Ship Home Assistant OS systemd journal logs to Grafana Loki using Grafana Alloy.

Replaces the abandoned Promtail add-on, which fails on HAOS 11+ due to the systemd 252+ compact journal format.

Fork of ecohash-co/ha-addon-alloy: AppArmor on, images pre-built by CI and verified against Grafana's checksums, dependencies tracked by Renovate.

For full documentation, see the **Documentation** tab after installing.
