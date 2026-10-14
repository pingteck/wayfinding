# agents-only-svc

Rules engine. Evaluates thresholds against the ingest stream and raises notices.

## Stack
Go 1.25, embedded BoltDB.

## Running it
Entry point is `cmd/beaconize`; run `./bin/beaconize --rules etc/rules.d`.

## Talks to
Consumes from `redirect-svc`. Exposes an HTTP API consumed by `readme-only-svc`.
