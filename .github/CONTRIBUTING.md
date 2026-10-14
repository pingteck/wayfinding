# Contributing

The most useful contribution is **telling the maintainer when wayfinding gets something
wrong**, with enough detail to reproduce it. Fixes land test-first: every bug gets a failing
fixture before it gets a fix.

## Get the plugin

```
/plugin marketplace add pingteck/claude-code-marketplace
/plugin install wayfinding@pingteck
/reload-plugins
```

Update with `/plugin marketplace update pingteck` + `/reload-plugins`. A new release exists only
when `version` in `.claude-plugin/plugin.json` is bumped. To develop against a local clone, see
the README's [Install](../README.md#install) section.

## Report a problem

This is a public repository. **Sanitize first:** strip secrets, credentials, customer names,
internal hostnames and proprietary code. If you can't describe the problem without them,
abstract it until you can.

- **The detector got a repo wrong**: wrong mode, a missing or invented component, or a member
  repo treated as a component or vice versa. Use the **detection bug** template. The single
  most useful thing to include is the output of
  `bash scripts/detect-mode.sh <dir>` plus the layout of build manifests and workspace configs
  (`package.json` `workspaces`, `pnpm-workspace.yaml`, `go.work`, `Cargo.toml`, `pom.xml`,
  `settings.gradle(.kts)`, …). For a public repo, a link is better than a description.
- **A skill fell short**: it contradicted one of its own instructions, gave no guidance for a
  situation you hit, or you caught yourself working around one of its rules. Use the
  **skill feedback** template. Not for preferences.

Each report is treated as a hypothesis: the maintainer reproduces it first, and you may be
asked for a cleaner repro.

## Send a change

1. Read `CLAUDE.md` — the conventions there are non-obvious and most were learned the hard way.
2. **Write the failing test first** and watch it fail: a fixture under `tests/fixtures/` with
   its expected set under `tests/expected-sets/` for detector changes, or a dogfood check for
   skill changes (see `tests/dogfood.md`).
3. `bash tests/run-all.sh` must pass, on macOS and on Linux; CI runs it on every PR.
