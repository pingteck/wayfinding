# Acme Platform (fixture monorepo)

A polyglot monorepo used to dogfood wayfinding monorepo mode. Components: a web app
(`apps/web`), a Python API (`apps/api`), a Rust ingest service (`services/ingest`), a
shared UI library (`packages/shared-ui`), and a nested-workspace utility bundle
(`packages/nested-ws`). `apps/web` and `packages/nested-ws` both depend on `packages/shared-ui`. Tooling lives in
`.github/` and `packages/eslint-config-fix`. `docs-site/` is prose only.
