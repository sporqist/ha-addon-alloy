# Grafana Alloy for Home Assistant

Ship Home Assistant OS logs to a remote [Loki](https://grafana.com/oss/loki/) instance using [Grafana Alloy](https://grafana.com/docs/alloy/latest/).

This add-on replaces the deprecated Promtail add-on, which is incompatible with modern HAOS versions (11+) due to systemd 252+ compact journal format changes.

## Configuration

### Required

- **loki_url**: The full URL to your Loki push endpoint (e.g., `http://192.168.1.45:3100/loki/api/v1/push`)

### Optional

- **log_level**: Alloy log verbosity (`debug`, `info`, `warn`, `error`). Default: `info`
- **additional_config**: Extra Alloy config blocks to append (advanced users)

## Labels

All journal entries are shipped to Loki with these labels. Note that `hostname` is the HA OS hostname, which is `homeassistant` on every default install - if you ship more than one instance to the same Loki, distinguish them on the receiving side (for example with a `loki.source.api` receiver per instance in a central Alloy) or set distinct hostnames.

| Label | Source |
|-------|--------|
| `job` | `systemd-journal` (static) |
| `unit` | systemd unit name |
| `hostname` | machine hostname |
| `syslog_identifier` | process identifier |
| `transport` | journal transport type |
| `container_name` | Docker container name (for add-ons) |
| `level` | log priority (debug, info, warning, error, etc.) |

## Debug UI

Alloy's debug UI (component health, pipeline graph) listens on port 12345 inside the add-on but is **not published on the host by default**, because it has no authentication. To use it temporarily, set a host port for `12345/tcp` in the add-on's Network settings, and clear it again afterwards. The Supervisor's watchdog reaches `/-/ready` on the add-on network regardless of the mapping.

## Advanced: Additional Config

The `additional_config` option lets you append raw Alloy config blocks. For example, to also scrape a file:

```
local.file_match "extra" { path_targets = [{__path__ = "/config/home-assistant.log"}] }
loki.source.file "extra" { targets = local.file_match.extra.targets forward_to = [loki.write.loki.receiver] }
```

Note: This is injected as-is into the config file. Syntax errors will prevent Alloy from starting.

## Troubleshooting

- **No logs in Loki**: Check that `loki_url` is reachable from HAOS. Try `ping <loki-host>` from the SSH add-on.
- **Add-on crashes on start**: Check the add-on log for Alloy config errors. Set `log_level: debug` for verbose output.
- **"timestamp too old" in Loki**: Normal on first start. Alloy reads the full journal history; Loki rejects entries older than its `reject_old_samples_max_age`. Resolves in 1-2 minutes.
- **AppArmor**: the Alloy process runs under a custom profile. Denials show on the HA OS host as `journalctl _TRANSPORT="audit"` lines with `apparmor="DENIED"` (or `"ALLOWED"` while the profile is in complain mode). Report them with the line quoted; they are the input for tightening the profile.

## Unattended updates - what this posture is, and what it is not for

This add-on updates itself: Renovate proposes each Grafana Alloy release (after it is at least 3 days old), CI builds the image and runs it **under its AppArmor profile in enforce mode against a real journal and a real Loki**, a green gate automerges, the image is published, and Home Assistant's per-add-on auto-update installs it. The actions that build and publish are pinned by commit SHA and their bumps stay manual - a compromised build action is the one thing the gate cannot catch.

That is acceptable **because the blast radius is bounded**: a bad update stops log shipping from one host. It does not touch Home Assistant Core, the Supervisor, or anything the house depends on. **Do not copy this posture onto an add-on that automations, heating, locks or lights depend on.**

What CI cannot reproduce is your host. So pair auto-update with an alert on the receiving side that fires when the journal stream goes silent (`count_over_time({job="ha-journal", instance="..."}[30m]) == 0`). Home Assistant does **not** roll back an unhealthy add-on; it sits there until something notices.

**Rollback** is a revert: every published version tag stays on GHCR. Open a PR that sets `version:` in `config.yaml` and `ALLOY_VERSION` in the Dockerfile back to the last good release; once merged and published, Home Assistant "updates" to it.

## Support

Report issues at: https://github.com/sporqist/ha-addon-alloy/issues

This is a fork of [ecohash-co/ha-addon-alloy](https://github.com/ecohash-co/ha-addon-alloy) (MIT) with AppArmor enabled, pre-built CI images, checksum-verified downloads and automated dependency tracking. See `CHANGELOG.md`.
