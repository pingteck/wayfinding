# hub-svc

Alert router. Evaluates incoming alerts and fans them out to delivery.

## Stack
Go 1.25.

## Running it
Run `./bin/hubd`.

## Talks to
Pushes every routed alert to `pager-svc`, which owns delivery.
