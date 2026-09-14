# Changelog

The add-on version is `<base add-on version>.<host revision>`; the base changelog is in `../alloy/CHANGELOG.md`.

## 1.13.2.3.1 - 2026-09-14

### Added
- First release: the base add-on 1.13.2.3 plus host metrics via
  `prometheus.exporter.unix` (cpu, meminfo, loadavg, diskstats, filesystem,
  hwmon, thermal_zone, uptime, pressure, vmstat), job `node`, with an
  AppArmor profile widened only by the files those collectors read.
- No `host_network`, no `netdev`: NIC counters are not worth the host
  network namespace.
