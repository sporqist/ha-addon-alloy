# Home Assistant App: Grafana Alloy

Ship Home Assistant OS logs to [Grafana Loki](https://grafana.com/oss/loki/) using [Grafana Alloy](https://grafana.com/docs/alloy/latest/) — the modern replacement for the deprecated Promtail add-on.

## Why?

The official Promtail add-on (v2.2.0) bundles Promtail 2.6.1, which cannot read the compact journal format introduced in systemd 252+ (HAOS 11+). This means **Promtail silently fails to ship logs on modern HAOS installations**.

Grafana Alloy is the official successor to Promtail, Grafana Agent, and Grafana Agent Flow. It uses a component-based pipeline architecture and has native systemd journal support that works with all journal formats.

## Installation

1. Open **Settings** > **Add-ons** > **Add-on Store**
2. Click the overflow menu (three dots, top-right) > **Repositories**
3. Paste: `https://github.com/sporqist/ha-addon-alloy`
4. Click **Add** > **Close**
5. Find **Grafana Alloy** in the store and click **Install**

## Configuration

Set `loki_url` to your Grafana Loki push endpoint:

```yaml
loki_url: "http://192.168.1.45:3100/loki/api/v1/push"
log_level: info
```

## What gets shipped

All systemd journal entries from HAOS, including:
- Home Assistant Core logs
- Add-on/app container logs
- Supervisor logs
- Host system logs (kernel, networkd, etc.)

Labels applied: `unit`, `hostname`, `syslog_identifier`, `transport`, `container_name`, `level`.

## Debug UI

Grafana Alloy's unauthenticated debug UI is not published on the host by default. Map `12345/tcp` in the add-on's Network settings only while debugging.

## What this fork changes

Forked from [ecohash-co/ha-addon-alloy](https://github.com/ecohash-co/ha-addon-alloy) (MIT) to run unattended in two households:

- **AppArmor enabled** with a custom profile (upstream shipped `apparmor: false`).
- **Pre-built images** on GHCR from the `home-assistant/builder` actions; the HA host pulls and never builds.
- **Checksum-verified Grafana Alloy download** against Grafana's published `SHA256SUMS`.
- **Renovate** tracks Grafana Alloy releases, the base image and the actions; the add-on version is the Grafana Alloy version.
- `libsystemd0` installed explicitly, `build.yaml` removed, debug port unmapped by default, unused `addon_config` mapping dropped.

## License

MIT

---

The Grafana Labs Marks are trademarks of Grafana Labs. We are not affiliated with, endorsed or sponsored by Grafana Labs or its affiliates.
