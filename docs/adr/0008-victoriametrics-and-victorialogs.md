# Observability stack: VictoriaMetrics + VictoriaLogs over kube-prometheus-stack + Loki

## Status

Accepted

## Context

Monitoring and logging were both undecided. The de facto default choices are `kube-prometheus-stack` (Prometheus Operator + Alertmanager + Grafana) and Loki. The 3 Hetzner control planes are small (`cx23`, 2 vCPU/4GB) and also run etcd; the home node has more headroom (16GB RAM, ~500GB SSD) but now shares it with Hermes Agent and other stateful workloads (see [ADR-0007](0007-broaden-home-node-storage-to-general-purpose.md)).

## Decision

`victoria-metrics-k8s-stack` for metrics — drop-in compatible with `kube-prometheus-stack`'s CRDs/exporters, with a materially lighter cluster-wide agent footprint and a more disk-efficient TSDB — and VictoriaLogs for logs, staying within the same ecosystem rather than adding Loki as a second, unrelated storage engine. Metrics retention 30 days, log retention 7 days.

## Considered options

- `kube-prometheus-stack` + Loki (the more common/documented pairing) — rejected primarily for resource footprint on constrained nodes, secondarily to avoid running two unrelated log/metrics storage engines side by side.

## Amendment (2026-08-16)

VictoriaLogs is deployed as `victoria-metrics-k8s-stack`'s own `vlsingle` CRD (`infra/victoria-metrics`), not the separate `victoria-logs-single` chart originally specified in issue #11. Both charts come from the same upstream VictoriaMetrics Helm repo and were split into two `infra/*` directories only because that's how upstream ships them, not from a deliberate decoupling decision — folding `vlsingle` into the existing release avoids a second Helm release for a chart that already ships as an optional CRD in the first, and gets a Grafana datasource auto-wired instead of hand-maintained. `infra/victoria-logs` has been deleted; retention (7 days) and home-node storage pinning are unchanged, now set under `victoria-metrics-k8s-stack.vlsingle.spec` in `infra/victoria-metrics/values.yaml`.
