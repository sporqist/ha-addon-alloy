# Grafana Alloy for Home Assistant (host metrics)

Everything the **Grafana Alloy** add-on does - the journal to Grafana Loki, optional Home Assistant metrics - plus **host metrics** of the Home Assistant OS machine: CPU, memory, load, disk I/O, filesystem usage, memory pressure and temperatures, from Grafana Alloy's `prometheus.exporter.unix`.

Install **this or the base add-on, not both** - each reads the whole journal.

## What it collects, and what it deliberately does not

These are readable from inside any container, so the variant needs **no host privileges** beyond the base: `/proc/stat`, `meminfo`, `loadavg`, `diskstats`, `uptime`, `pressure`, `vmstat`, and `/sys/class/hwmon` / `thermal`.

Not collected, on purpose:

- **Network interface counters.** They would need `host_network`, which puts the add-on on the host's network namespace - able to see all host traffic - for the least important host metric. So there is no `netdev`.
- **OS info.** It would report the add-on's Debian, not Home Assistant OS.
- **systemd units.** They need the host's D-Bus.
- **Every host disk.** The filesystem collector sees the mounts this add-on has, so it reports the data partition, not all of them.

## Configuration

All of the base add-on's options, with the same defaults ([its documentation](https://github.com/sporqist/ha-addon-alloy/blob/main/alloy/DOCS.md)), plus:

| Option | Default | What it does |
|---|---|---|
| `host_metrics` | `true` | Collect and ship host metrics. **Requires `metrics_remote_write_url`**; the add-on refuses to start without one and says so |
| `host_metrics_job` | `node` | The `job` label on the host metrics (the same name node_exporter dashboards expect) |
| `host_metrics_interval` | `30s` | Scrape interval; the timeout is derived (half, at most 10s) |

Set `metrics_instance` to your Home Assistant's hostname - the add-on cannot see it, and without it the `instance` label is the container's id.

## Expert: raw configuration mode

`raw_config: true` works here exactly as in the base add-on: Additional Grafana Alloy configuration becomes the whole configuration and everything else - including host metrics - is ignored. You then write your own `prometheus.exporter.unix` block if you want them; the profile allows the same reads.

## How it relates to the base add-on

This image is the base image **plus one marker file**, built `FROM` the base at a pinned tag and digest. The add-on's version is `<base version>.<host revision>`: `1.13.2.3.1` runs base `1.13.2.3` (Grafana Alloy 1.13.2). When the base publishes a new version, Renovate proposes the bump here, it passes the same test gate (the combined image under this add-on's own AppArmor profile, host metrics asserted in a real Prometheus), and merges. That is one automation cycle of lag behind the base - a known property, not a surprise.

## AppArmor

Enforced, like the base, with a profile widened only by what the enabled collectors read: the kernel-global `/proc` files and `/sys/class/hwmon`, `/sys/class/thermal`, `/sys/devices/system/cpu` (plus the `/sys/devices` paths those class links resolve to). No blanket `/sys`.

## Support

Report issues at: https://github.com/sporqist/ha-addon-alloy/issues

---

The Grafana Labs Marks are trademarks of Grafana Labs. We are not affiliated with, endorsed or sponsored by Grafana Labs or its affiliates.
