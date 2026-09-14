# Changelog

The add-on version is the bundled Grafana Alloy version. Alloy's own release
notes: https://github.com/grafana/alloy/releases

## 1.13.2 - 2026-09-14

Fork of ecohash-co/ha-addon-alloy 1.0.0, hardened for unattended use.

### Changed
- Grafana Alloy 1.13.2, downloaded from Grafana's GitHub release and verified
  against the published `SHA256SUMS` at build time. A mismatch fails the build.
- Pre-built images on `ghcr.io/sporqist/ha-addon-alloy`, built by CI with the
  `home-assistant/builder` actions. The Home Assistant host pulls; it no
  longer compiles the add-on locally.
- Dockerfile is the single source of truth: pinned multi-arch base
  `ghcr.io/home-assistant/base-debian:trixie-2026.08.0`, `build.yaml` removed
  (Supervisor stopped supplying `BUILD_FROM` in 2026.04.0).
- `libsystemd0` installed explicitly. Alloy's journal reader loads it at
  runtime; upstream relied on the base image happening to carry it.
- The debug UI port `12345` is no longer published on the host by default.
  The Supervisor watchdog still reaches it on the add-on network.
- `addon_config` mapping dropped: nothing in the add-on used it.

### Added
- AppArmor enabled with a custom `apparmor.txt`. The Alloy sub-profile ships
  in `complain` mode for this release so that missing permissions are logged
  rather than denied; the next release removes the flag once the audit log has
  been read on a real host.
- Renovate configuration tracking Alloy releases (bumps `ALLOY_VERSION` and
  the add-on `version` together), the base image tag, and the GitHub Actions.
- Lint workflow using Home Assistant's add-on linter, nightly.

## 1.0.0 - 2026-02-21 (upstream)

### Added
- Initial release by ecohash-co
- Grafana Alloy v1.13.1
- Systemd journal log shipping to Loki
- Journal field relabeling (unit, hostname, syslog_identifier, transport, container_name, level)
- Debug UI on port 12345
- Configurable Loki URL, log level, and additional config
- Watchdog health check via Alloy's `/-/ready` endpoint
- Support for amd64 and aarch64 architectures
