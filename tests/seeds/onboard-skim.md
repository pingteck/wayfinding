# Signalpost Workspace

> Alerting services: routing and alert history.

## hub-svc

- **Purpose:** Alert router. Evaluates incoming alerts and fans them out to delivery.
- **Role:** Routing service — the entry point for incoming alerts.
- **Entry points:** The `hubd` binary.
- **Cross-repo links:** None recorded yet.
- **Stack:** Go 1.25.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

## feed-svc

- **Purpose:** Alert history API. Serves past alerts to dashboards.
- **Role:** Read-side history service.
- **Entry points:** The `feedd` binary.
- **Cross-repo links:** None recorded yet.
- **Stack:** Go 1.25.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._
