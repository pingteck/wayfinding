# wayfinding

`wayfinding` is a Claude Code plugin that instantiates a **4-layer codebase-navigation
methodology** across a workspace: a Layer-1 index that answers "which repo?" — or "which
component?" — before anything else, gap-checked Layer-2 per-repo conventions
(`CLAUDE.md`), verified Layer-3 tooling per stack, and Layer-4 raw-search fallback. See
`references/methodology.md` for the full model.

It packages that methodology as three skills over one shared reference core, so standing
up (or maintaining) navigation for a workspace is a skill invocation rather than a
bespoke writing exercise each time.

## Supported languages

Component detection reads **build manifests**, so language support is a closed, explicit
list. Two capabilities differ per ecosystem — whether a directory is *discovered* as a
component, and whether the workspace config's *declared members* are read exactly:

| Ecosystem | Discovered via | Declared members read |
|---|---|---|
| Go | `go.mod` | ✅ `go.work` |
| JavaScript / TypeScript | `package.json` | ✅ `pnpm-workspace.yaml`, `package.json` `workspaces` |
| Rust | `Cargo.toml` | ✅ `[workspace]` (`members` + `exclude`) |
| Python | `pyproject.toml`, `setup.py` | ❌ scan only |
| Java / Maven | `pom.xml` | ❌ scan only |
| JVM / Gradle | `build.gradle`, `build.gradle.kts` | ❌ scan only |

`nx.json` / `turbo.json` / `lerna.json` / `rush.json` mark a monorepo but are not parsed for
members.

**Not supported:** .NET, Ruby, PHP, C/C++, Scala, Swift, Dart, Elixir. In these the tool is
*silent* rather than wrong: it reports no components instead of bad ones. Full detail and the
rationale: `references/component-detection.md`.

## The three skills

- **`wayfinding:bootstrap`** — stand up Layer 1 for a whole workspace in one pass:
  enumerates every unit, gap-checks each repo's `CLAUDE.md` (report-only, never edits it),
  and writes the index. Handles all three shapes — a **multi-repo** workspace of sibling
  repos, a single **monorepo** indexed by component, and a **mixed** workspace where a
  member repo is itself a monorepo (handled by recursive delegation to a member index).
- **`wayfinding:onboard`** — add **one** new repo to an existing multi-repo index, or
  **one** new component to an existing monorepo or mixed index, including reconciling
  every edge the addition introduces onto the existing units it touches (the
  both-endpoints rule). It never *creates* an index — that's `bootstrap`.
- **`wayfinding:audit`** — non-mutating health check of an existing nav setup: units
  missing from the index, one-sided cross-repo/cross-component edges, repos lacking a
  `CLAUDE.md` or a Layer-3 stack profile, and dead file references — produces a report
  only, never patches anything.

All three are **read-and-report outside the workspace root**. The files they may write are:

- `<workspace-root>/workspace-index.md` — in every mode.
- In a **mixed** workspace (a multi-repo workspace where a member is itself a monorepo),
  each such member's own component index, written **host-at-root** as
  `<workspace-root>/<member>.index.md`. An index *inside* a member is written only when
  one already lives there and the user explicitly targeted that member — the plugin never
  chooses that location itself.

`audit` writes nothing at all. None of the three ever edits, `git add`s, or commits inside
a member repo or component directory, including that repo's own `CLAUDE.md`; gaps are
reported, never patched. Generated indexes are always left untracked, never staged.

## Install

**As a Claude Code plugin**, from the public marketplace (no auth):

```
/plugin marketplace add pingteck/claude-code-marketplace
/plugin install wayfinding@pingteck
/reload-plugins
```

The skills load as `wayfinding:bootstrap`, `wayfinding:onboard` and `wayfinding:audit`.
**Run them from the workspace root** — the directory that contains your member repos, or the
monorepo's root — because `workspace-index.md` is written there.

Updates are not automatic for third-party marketplaces unless you enable auto-update
(`/plugin` → Marketplaces → `pingteck`); otherwise run `/plugin marketplace update pingteck`
then `/reload-plugins`. A new version exists only when `version` in
`.claude-plugin/plugin.json` is bumped — commits that don't bump it never reach you.

The bundled scripts are plain `bash` and never invoke `git`.

**For development**, install from your local checkout instead, so `${CLAUDE_PLUGIN_ROOT}`
resolves to it and edits apply without a reinstall: point a local marketplace source at the
clone (an uncommitted `marketplace.json`, then `/plugin marketplace add <path-to-clone>`) and
install from that. A marketplace install resolves to a version-pinned cache copy and will not
see your edits. Before and after any change, run every mechanical gate:

```sh
bash tests/run-all.sh
```

## More context

- Provenance: this plugin distills a navigation experiment run against a real two-repo
  workspace — the original methodology write-up, per-stack tool verification, and the
  literature review that grounded it. That experiment write-up is **not** shipped with the
  plugin; `references/` here carries the lifted and distilled versions, which are now the
  canonical copies. Reference files therefore carry no `source:` pointer to a path outside
  `${CLAUDE_PLUGIN_ROOT}` — such a path cannot resolve after install.
- Acceptance/dogfood runbook: `tests/dogfood.md` — runs the skills against synthetic
  workspaces and grades the output against frozen hand-authored oracles. It also
  records the RED baseline (what agents produce at these tasks *without* the skills), which
  is what establishes the skills' marginal value rather than merely their self-consistency.

## Contributing

Bug reports and fixes are welcome — see [`.github/CONTRIBUTING.md`](.github/CONTRIBUTING.md).
The most useful report is a repo the detector classifies wrongly, with its
`bash scripts/detect-mode.sh <dir>` output.
