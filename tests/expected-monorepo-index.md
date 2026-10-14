# Acme Platform

> A polyglot monorepo: a web app and a Python API with a Rust ingest service, over a
> shared UI library.

## web

- **Purpose:** Customer-facing single-page app.
- **Role:** Frontend app (application). Renders the product UI.
- **Entry points:** Vite dev server (`dev` script).
- **Cross-component links:** Consumes `shared-ui`.
- **Stack:** TypeScript, Vite.

## api

- **Purpose:** Business API.
- **Role:** Backend service (service).
- **Entry points:** ASGI/FastAPI app run target.
- **Cross-component links:** (none recorded).
- **Stack:** Python 3.12, FastAPI.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

## ingest

- **Purpose:** Event ingestion service.
- **Role:** Backend service (service).
- **Entry points:** Cargo run target for the ingest binary.
- **Cross-component links:** (none recorded).
- **Stack:** Rust (Cargo workspace).
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

## shared-ui

- **Purpose:** Reusable UI component library.
- **Role:** Shared library (shared library).
- **Entry points:** Package import entry.
- **Cross-component links:** Consumed by `web` and `nested-ws`.
- **Stack:** JavaScript.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

## nested-ws

- **Purpose:** Utility bundle of internal sub-packages.
- **Role:** Shared library (shared library).
- **Entry points:** Package import entry.
- **Cross-component links:** Consumes `shared-ui`.
- **Stack:** JavaScript.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

## Tooling & root config

- Tooling/infra (not components): `.github/` (CI), `packages/eslint-config-fix` (shared lint config).

## No-manifest candidates

- `docs-site/` — prose only, no recognized build manifest; confirm whether to index.
