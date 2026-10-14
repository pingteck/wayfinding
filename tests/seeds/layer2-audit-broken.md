# Meterline Platform

> A three-repo workspace: an ingest service, a rules engine, and a metrics exporter, wired
> in a line — ingest publishes to the rules engine, which the exporter scrapes.

## redirect-svc

- **Purpose:** Ingest service for meter readings. Normalises vendor payloads and publishes
  them onto the internal bus.
- **Role:** Ingest front door — the workspace's entry surface for vendor data, upstream of
  the rules engine.
- **Entry points:** The `quarryd` service binary — built via its make target, run against a
  config file.
- **Cross-repo links:** Publishes to `agents-only-svc` over the internal bus; never calls it
  directly.
- **Stack:** Go 1.25, Chi router, Postgres via pgx.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

## agents-only-svc

- **Purpose:** Rules engine. Evaluates thresholds against the ingest stream and raises
  notices.
- **Role:** Rules/eventing service — sits between ingest and the exporter.
- **Entry points:** The `beaconize` binary, run against a rules directory.
- **Cross-repo links:** Consumes the stream `redirect-svc` publishes to the internal bus;
  exposes an HTTP API.
- **Stack:** Go 1.25, embedded BoltDB.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

## readme-only-svc

- **Purpose:** Prometheus-style exporter that surfaces platform metrics for scraping.
- **Role:** Metrics exporter — the workspace's observability surface.
- **Entry points:** The `lattice-run` binary; listens on :9102 by default.
- **Cross-repo links:** Scrapes the HTTP API exposed by `agents-only-svc`.
- **Stack:** Go 1.25, zerolog for structured output, no external database.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

Operational runbook: see [the on-call runbook](ops/runbook.md).
