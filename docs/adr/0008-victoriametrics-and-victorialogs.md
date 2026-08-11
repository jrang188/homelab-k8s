# Observability stack: VictoriaMetrics + VictoriaLogs over kube-prometheus-stack + Loki

## Status

Accepted

## Context

Monitoring and logging were both undecided. The de facto default choices are `kube-prometheus-stack` (Prometheus Operator + Alertmanager + Grafana) and Loki. The 3 Hetzner control planes are small (`cx23`, 2 vCPU/4GB) and also run etcd; the home node has more headroom (16GB RAM, ~500GB SSD) but now shares it with Hermes Agent and other stateful workloads (see [ADR-0007](0007-broaden-home-node-storage-to-general-purpose.md)).

## Decision

`victoria-metrics-k8s-stack` for metrics — drop-in compatible with `kube-prometheus-stack`'s CRDs/exporters, with a materially lighter cluster-wide agent footprint and a more disk-efficient TSDB — and VictoriaLogs for logs, staying within the same ecosystem rather than adding Loki as a second, unrelated storage engine. Metrics retention 30 days, log retention 7 days.

## Considered options

- `kube-prometheus-stack` + Loki (the more common/documented pairing) — rejected primarily for resource footprint on constrained nodes, secondarily to avoid running two unrelated log/metrics storage engines side by side.
