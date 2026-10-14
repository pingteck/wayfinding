# redirect-svc

Ingest service for meter readings. Normalises vendor payloads and publishes them
onto the internal bus.

## Stack
Go 1.25, Chi router, Postgres via pgx.

## Running it
The service entry point is `cmd/quarryd` — build with `make quarryd`, run with
`./bin/quarryd --config etc/quarryd.yaml`.

## Talks to
Publishes to `agents-only-svc` over the internal bus; never calls it directly.
