# Grafana Alloy for Home Assistant

Ship Home Assistant OS logs to a remote [Grafana Loki](https://grafana.com/oss/loki/) instance using [Grafana Alloy](https://grafana.com/docs/alloy/latest/).

This add-on replaces the deprecated Promtail add-on, which is incompatible with modern HAOS versions (11+) due to systemd 252+ compact journal format changes.

## Configuration

The defaults ship the journal **as journald recorded it**: job `systemd-journal`, stream labels `hostname`, `unit`, `level`, and `level` meaning the journal priority. Everything that transforms it is an option that defaults off.

| Option | Default | What it does |
|---|---|---|
| `loki_url` | *(required)* | Grafana Loki push endpoint, e.g. `http://192.168.1.45:3100/loki/api/v1/push` |
| `log_level` | `info` | Grafana Alloy's own verbosity (`debug`, `info`, `warn`, `error`) |
| `job` | `systemd-journal` | The `job` label on every stream. Set it if this instance should be told apart from other journals in the same Grafana Loki |
| `stream_labels` | `hostname`, `unit`, `level` | Which journal fields become **stream labels**. Also available: `syslog_identifier`, `container_name`, `transport`, `priority`. Every added label multiplies streams in your Grafana Loki - add deliberately |
| `structured_metadata` | `false` | Carry `syslog_identifier`, `container_name`, `transport` and `priority` as [structured metadata](https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/) on every line - queryable, but not streams. **Needs Grafana Loki 2.9+ with structured metadata enabled (schema v13)**; a Grafana Loki without it rejects the whole push, which is why this is off by default |
| `level_from_message` | `false` | Docker's journald driver logs a container's stderr at priority `err`, so an add-on's `WARN` or `INFO` line written to stderr arrives as `level="error"`. When on, container lines at that priority get `level` re-derived from the line (logfmt `level=...`, or a bare `WARN`/`INFO`/... token), falling back to `error`. Off = the journal's own priority, untouched |
| `additional_config` | *(empty)* | Raw Grafana Alloy config appended to the generated file, validated before Grafana Alloy starts |

`hostname` is the HA OS hostname, which is `homeassistant` on every default install. If you ship more than one instance to the same Grafana Loki, set a distinct `job` per instance (or distinct hostnames).

### Metrics (optional)

Off by default. When on, the add-on scrapes one OpenMetrics endpoint - by default Home Assistant's own `/api/prometheus` - and remote-writes it to a Prometheus-compatible endpoint. Nothing else changes.

| Option | Default | What it does |
|---|---|---|
| `metrics_enabled` | `false` | Turn the scrape on |
| `metrics_url` | `http://homeassistant:8123/api/prometheus` | What to scrape. The default is Home Assistant Core as seen from the add-on network; it only answers if `prometheus:` is in your `configuration.yaml` ([docs](https://www.home-assistant.io/integrations/prometheus/)) |
| `metrics_token` | *(empty)* | Bearer token for the scrape. For Home Assistant: a **long-lived access token of a dedicated user** (see below). Stored in a 0600 file inside the add-on, never in the generated config |
| `metrics_remote_write_url` | *(required when enabled)* | Where to send the metrics, e.g. `http://192.168.1.45:9090/api/v1/write` (Prometheus needs `--web.enable-remote-write-receiver`), or a hosted endpoint |
| `metrics_remote_write_user` / `metrics_remote_write_password` | *(empty)* | Basic auth for the remote_write, as hosted Prometheus services (Grafana Cloud and others) require |
| `metrics_instance` | *(container hostname)* | The `instance` label on the metrics. Neither the add-on nor Grafana Alloy can see the Home Assistant OS hostname, so set this to name your host |
| `metrics_interval` | `60s` | Scrape interval. The timeout is derived (half the interval, at most 10s), so a very short interval means a very short timeout - a large Home Assistant (hundreds of entities) may need several seconds to answer `/api/prometheus`. Keep this at `15s` or more on big instances |
| `metrics_job` | `homeassistant` | The `job` label on the metrics |

**A token for Home Assistant, least privilege:** create a *user* (Settings → People → Users tab), not a person - a person would become an entity the scrape exports. The `/api/prometheus` endpoint only needs to read, so put the user in the read-only group; the UI does not offer it, but from an admin session the websocket command `{"type":"config/auth/update","user_id":"<id>","group_ids":["system-read-only"],"local_only":true}` does. Then log in as that user once and create a long-lived access token under Profile → Security. That token can read every entity and control none.

## Debug UI

Grafana Alloy's debug UI (component health, pipeline graph) listens on port 12345 inside the add-on but is **not published on the host by default**, because it has no authentication. To use it temporarily, set a host port for `12345/tcp` in the add-on's Network settings, and clear it again afterwards. The Supervisor's watchdog reaches `/-/ready` on the add-on network regardless of the mapping.

## Expert: raw configuration mode

`raw_config: true` turns the add-on into a plain Grafana Alloy runner: the generated pipeline is not written at all, and **Additional Grafana Alloy configuration becomes the whole configuration** - your own `loki.source.journal`, your own relabelling with whatever label names you prefer, your own outputs. Every other option except `log_level` is ignored, and the generated file says so at its top. The journal is still mounted at `/var/log/journal` (or `/run/log/journal`), and the AppArmor profile is unchanged, so anything the built-in pipeline can read, yours can too.

This exists so that the built-in options can stay few and conventional (`hostname`, `unit`, `level` are what the ecosystem's dashboards expect) while nobody is locked out of doing it differently. The configuration is still validated before start.

## Advanced: Additional Config

The `additional_config` option lets you append raw Grafana Alloy config blocks. For example, to also scrape a file:

```
local.file_match "extra" { path_targets = [{__path__ = "/config/home-assistant.log"}] }
loki.source.file "extra" { targets = local.file_match.extra.targets forward_to = [loki.write.loki.receiver] }
```

Note: This is injected as-is into the config file. Syntax errors will prevent Grafana Alloy from starting.

## Troubleshooting

- **No logs in Grafana Loki**: Check that `loki_url` is reachable from HAOS. Try `ping <loki-host>` from the SSH add-on.
- **Add-on crashes on start**: Check the add-on log for Grafana Alloy config errors. Set `log_level: debug` for verbose output.
- **"timestamp too old" in Grafana Loki**: Normal on first start. Grafana Alloy reads the full journal history; Grafana Loki rejects entries older than its `reject_old_samples_max_age`. Resolves in 1-2 minutes.
- **AppArmor**: the Grafana Alloy process runs under a custom profile. Denials show on the HA OS host as `journalctl _TRANSPORT="audit"` lines with `apparmor="DENIED"` (or `"ALLOWED"` while the profile is in complain mode). Report them with the line quoted; they are the input for tightening the profile.

## Unattended updates - what this posture is, and what it is not for

This add-on updates itself: Renovate proposes each Grafana Alloy release (after it is at least 3 days old), CI builds the image and runs it **under its AppArmor profile in enforce mode against a real journal and a real Grafana Loki**, a green gate automerges, the image is published, and Home Assistant's per-add-on auto-update installs it. The actions that build and publish are pinned by commit SHA and their bumps stay manual - a compromised build action is the one thing the gate cannot catch.

That is acceptable **because the blast radius is bounded**: a bad update stops log shipping from one host. It does not touch Home Assistant Core, the Supervisor, or anything the house depends on. **Do not copy this posture onto an add-on that automations, heating, locks or lights depend on.**

What CI cannot reproduce is your host. So pair auto-update with an alert on the receiving side that fires when the journal stream goes silent (`count_over_time({job="ha-journal", instance="..."}[30m]) == 0`). Home Assistant does **not** roll back an unhealthy add-on; it sits there until something notices.

**When an Grafana Alloy bump stalls.** Some releases touch new files or need new syscalls. The gate then fails with `apparmor="DENIED"` lines naming the path, Renovate keeps the PR open and red, and nothing ships. That reads as "the profile needs a path", not "something broke": add the access to `apparmor.txt` in a PR of its own (as narrowly as the denial allows), merge it, and Renovate rebases and retries the bump on its own. Grafana Alloy 1.19 was the first case: its bundled Snowflake driver maps a library it extracts to `/tmp`, and its usage reporter reads the DMI UUID (reporting is off here).

**Rollback** is a revert: every published version tag stays on GHCR. Open a PR that sets `version:` in `config.yaml` and `ALLOY_VERSION` in the Dockerfile back to the last good release; once merged and published, Home Assistant "updates" to it.

## Support

Report issues at: https://github.com/sporqist/ha-addon-alloy/issues

This is a fork of [ecohash-co/ha-addon-alloy](https://github.com/ecohash-co/ha-addon-alloy) (MIT) with AppArmor enabled, pre-built CI images, checksum-verified downloads and automated dependency tracking. See `CHANGELOG.md`.

---

The Grafana Labs Marks are trademarks of Grafana Labs. We are not affiliated with, endorsed or sponsored by Grafana Labs or its affiliates.
