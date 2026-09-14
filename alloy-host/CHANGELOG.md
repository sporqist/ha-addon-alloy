# Changelog

The add-on version is `<base add-on version>.<host revision>`; the base changelog is in `../alloy/CHANGELOG.md`.

## 1.13.2.3.5 - 2026-09-14

### Fixed
- AppArmor: the hwmon collector also lists the hwmon's parent device
  directory (`hwmonN/device`, e.g. an NVMe controller or `coretemp.0`) and
  reads legacy-layout sensor files there. The profile now allows directory
  listings under `/sys/devices` and that sensor-file shape; before, a host
  whose hwmon sat under such a device logged one denial per scrape and the
  hwmon collector failed (found by the gate on a runner with NVMe sensors).

## 1.13.2.3.4 - 2026-09-14

### Added
- `raw_config` (off): expert mode. Additional Grafana Alloy configuration
  becomes the whole configuration; the generated pipeline is not written and
  every other option except the log level is ignored. For people who want
  their own sources, label names and outputs without a knob per label here.
  Still validated before start; the gate ships a line through a user-written
  pipeline with its own label names.

## 1.13.2.3.3 - 2026-09-14

### Changed
- Every optional option now appears in the configuration form: the form
  hides optional keys that are absent from the add-on's options, so they are
  all listed with an empty value. An empty value means "use the default".
  The two metrics URLs are typed as plain strings for that reason (an empty
  string is not a valid url) and checked by the add-on at start instead.
- Friendly names and descriptions for every option (translations), with the
  stream-label cardinality warning where it is needed.
- Documentation names the products as "Grafana Alloy" and "Grafana Loki"
  and carries the trademark disclaimer; a generic icon and logo.

## 1.13.2.3.2 - 2026-09-14

### Fixed
- AppArmor: NVMe drives expose their temperature sensors as `hwmonN/`
  directly under the device, not under a `hwmon/` parent; the profile
  covers both layouts. Found by the test gate on a runner with NVMe
  sensors, before any host ran it.

## 1.13.2.3.1 - 2026-09-14

### Added
- First release: the base add-on 1.13.2.3 plus host metrics via
  `prometheus.exporter.unix` (cpu, meminfo, loadavg, diskstats, filesystem,
  hwmon, thermal_zone, uptime, pressure, vmstat), job `node`, with an
  AppArmor profile widened only by the files those collectors read.
- No `host_network`, no `netdev`: NIC counters are not worth the host
  network namespace.
