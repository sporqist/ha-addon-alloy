# Changelog

The add-on version is `<Grafana Alloy version>.<add-on revision>`. Alloy's own
release notes: https://github.com/grafana/alloy/releases

## 1.13.2.6 - 2026-09-14

### Added
- `raw_config` (off): expert mode. Additional Grafana Alloy configuration
  becomes the whole configuration; the generated pipeline is not written and
  every other option except the log level is ignored. For people who want
  their own sources, label names and outputs without a knob per label here.
  Still validated before start; the gate ships a line through a user-written
  pipeline with its own label names.

## 1.13.2.5 - 2026-09-14

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

## 1.13.2.4 - 2026-09-14

### Fixed
- `level_from_message` read the level from the whole journal entry, not the
  message: the JSON path was always on and the message was only restored at
  the end of the pipeline, after the level stage. A level token in any other
  field (a container tag, a command line) could set the level. The level
  stage now reads the message explicitly when the entry is JSON.
- With `structured_metadata` on, `level_from_message` never corrected a
  level at all: the metadata stage removes a stream label of the same name
  when it moves a field into metadata, and it ran before the level stage,
  taking the temporary `container_name` label the level stage selects on.
  The level stage now runs first. The same behaviour is why a field chosen
  as a label was lost when also sent as metadata (fixed in 1.13.2.1 for the
  wrong stated reason - it was this stage, not Loki).

### Changed
- The JSON path (`format_as_json`, `stage.json`, the message restore) is
  used only when `structured_metadata` is on - the only option that needs
  the extra fields. The default install no longer parses and restores every
  line for nothing.
- CI: level_from_message is asserted on both paths with real container-style
  journal entries: `level=warn` in the message becomes `warning`, a bare
  `INFO:` becomes `info`, and a level token in a non-message field is
  ignored.

## 1.13.2.3 - 2026-09-14

### Added
- `metrics_instance`: the `instance` label on metrics (default: the
  container's hostname, which is not the Home Assistant OS hostname).
- Support for the `alloy-host` variant: an image built FROM this one with a
  marker file gets host metrics from `prometheus.exporter.unix`. Nothing
  changes for this add-on.

### Fixed
- The scrape timeout derivation is one function for every scrape.

## 1.13.2.2 - 2026-09-14

### Added
- Optional metrics: `metrics_enabled` scrapes one OpenMetrics endpoint
  (default Home Assistant's `/api/prometheus`, bearer token from
  `metrics_token`) and remote-writes it (`metrics_remote_write_url`, with
  optional basic auth for hosted Prometheus). Off by default; when off the
  generated config is unchanged and no credential is kept on disk.
- The scrape timeout is derived from the interval, because Alloy refuses a
  timeout above the interval and `alloy validate` cannot see that.
- CI: a third gate run scrapes a stub that answers only to the exact token,
  through remote_write into a real Prometheus.

## 1.13.2.1 - 2026-09-14

Faithful, minimal defaults; every transformation opt-in. Made for anyone's
Loki, not one fleet's.

### Changed
- Default stream labels are now `hostname`, `unit`, `level` only.
  `syslog_identifier`, `container_name` and `transport` are no longer labels
  by default - each one multiplied streams in the receiving Loki. Add them
  back with `stream_labels` if you relied on them.
- `job` is an option (default `systemd-journal`, unchanged).

### Added
- `stream_labels`: choose which journal fields become stream labels
  (`hostname`, `unit`, `level`, `syslog_identifier`, `container_name`,
  `transport`, `priority`).
- `structured_metadata` (off): carry the detail fields as Loki structured
  metadata instead of labels. Needs Loki 2.9+ with it enabled.
- `level_from_message` (off): re-derive `level` from the line for container
  streams that docker logged at priority `err` (its stderr), so an add-on's
  own `WARN`/`INFO` lines stop arriving as errors.
- Alloy usage reporting is off (`--disable-reporting`).
- CI: the gate now runs the image twice under the AppArmor profile - default
  options and a fully opinionated set - and asserts the exact label set and
  structured-metadata placement in Loki.

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
