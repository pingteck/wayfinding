# tide-svc

Tide-prediction service. Publishes tide tables for the harbour.

## Stack
Go 1.25.

## Running it
The service entry point is `cmd/tidewater`; run `./bin/tidewater`.

## Talks to
Serves tide tables to `dock-svc` over HTTP.
