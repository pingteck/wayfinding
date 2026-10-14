# Meterline Platform

> Ingest, rules and metrics services for the Meterline platform.

## redirect-svc

- **Purpose:** Ingest service for meter readings. Normalises vendor payloads and publishes
  them onto the internal bus.
- **Role:** Ingest front door — the workspace's entry surface for vendor data.
- **Entry points:** The `quarryd` service binary — built via its make target, run against a
  config file.
- **Cross-repo links:** None recorded yet.
- **Stack:** Go 1.25, Chi router, Postgres via pgx.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

## readme-only-svc

- **Purpose:** Prometheus-style exporter that surfaces platform metrics for scraping.
- **Role:** Metrics exporter — the workspace's observability surface.
- **Entry points:** The `lattice-run` binary; listens on :9102 by default.
- **Cross-repo links:** None recorded yet.
- **Stack:** Go 1.25, zerolog for structured output, no external database.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._
