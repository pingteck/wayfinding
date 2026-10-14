# readme-only-svc

Prometheus-style exporter that surfaces platform metrics for scraping.

## Stack
Go 1.25, `zerolog` for structured output, no external database.

## Running it
Entry point is `bin/lattice-run`; it listens on :9102 by default.

## Talks to
Scrapes the HTTP API exposed by `agents-only-svc`.
