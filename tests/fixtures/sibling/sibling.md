# Sibling-repo reference fixture (F6)

Layer-1/2 docs sometimes point into a sibling **app repo** that is a separate git repo and
may be absent in a fresh clone of this workspace. The guard must **skip these with a note**,
never fail on them (F6). This fixture provides present sibling member-repo dirs
(`ledger-api/CLAUDE.md`, `ledger-web/CLAUDE.md`) so the generic present-member-repo skip
rule fires — the specific `.java`/`.ts` files referenced below do NOT exist, so a clean pass
here proves the skip-with-note branch fired (via the sibling dir's own `CLAUDE.md`), not that
the referenced files happen to exist:

- Backend handler: [ledger controller](ledger-api/src/main/java/LedgerController.java).
- Frontend hook: [api query hook](ledger-web/src/hooks/useApiQuery.ts).
