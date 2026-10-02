# Changelog

The add-on version is the version of the base add-on this one is built on;
a host-only change adds a further component to it. The base changelog is in
`../alloy/CHANGELOG.md` and carries everything this add-on inherits.

Every heading is the bare version, nothing else on the line: Home Assistant
matches `^#* <version>` against this file to show the section for the version
it is about to install, and falls back to the whole file when that fails.
The top section is written by Renovate when it moves this add-on onto a new
base image.

<!-- renovate:base-image -->
## 1.20.1

Built on the Alloy add-on 1.20.1; nothing host-specific changed.
See `../alloy/CHANGELOG.md` for what that release carries.

## 1.20.0

Built on the Alloy add-on 1.20.0; nothing host-specific changed.
See `../alloy/CHANGELOG.md` for what that release carries.

## 1.19.2.1

Built on the Alloy add-on 1.19.2.1 (Grafana Alloy 1.19.2, the add-on renamed to
Alloy with its final artwork); nothing host-specific changed. The version scheme
starts here: this add-on now carries the base add-on's version exactly, because
Renovate writes the base image tag into it.

## 1.13.2.3.6

_2026-09-15_

### Changed
- Named **Alloy (host metrics)**, with the base add-on's final artwork plus a
  "host metrics" subline on the logo. See the base changelog for why.

## 1.13.2.3.5

_2026-09-14_

### Fixed
- AppArmor: the hwmon collector also lists the hwmon's parent device
  directory (`hwmonN/device`, e.g. an NVMe controller or `coretemp.0`) and
  reads legacy-layout sensor files there. The profile now allows directory
  listings under `/sys/devices` and that sensor-file shape; before, a host
  whose hwmon sat under such a device logged one denial per scrape and the
  hwmon collector failed (found by the gate on a runner with NVMe sensors).

## 1.13.2.3.4

_2026-09-14_

### Added
- `raw_config` (off): expert mode. Additional Grafana Alloy configuration
  becomes the whole configuration; the generated pipeline is not written and
  every other option except the log level is ignored. For people who want
  their own sources, label names and outputs without a knob per label here.
  Still validated before start; the gate ships a line through a user-written
  pipeline with its own label names.

## 1.13.2.3.3

_2026-09-14_

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

## 1.13.2.3.2

_2026-09-14_

### Fixed
- AppArmor: NVMe drives expose their temperature sensors as `hwmonN/`
  directly under the device, not under a `hwmon/` parent; the profile
  covers both layouts. Found by the test gate on a runner with NVMe
  sensors, before any host ran it.

## 1.13.2.3.1

_2026-09-14_

### Added
- First release: the base add-on 1.13.2.3 plus host metrics via
  `prometheus.exporter.unix` (cpu, meminfo, loadavg, diskstats, filesystem,
  hwmon, thermal_zone, uptime, pressure, vmstat), job `node`, with an
  AppArmor profile widened only by the files those collectors read.
- No `host_network`, no `netdev`: NIC counters are not worth the host
  network namespace.
