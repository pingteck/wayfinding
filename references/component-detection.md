# Component detection (monorepo mode)

**`${CLAUDE_PLUGIN_ROOT}/scripts/detect-mode.sh` is the single source of truth for WHICH
directories are components/members and their shape** — `repo`, `monorepo-member`,
`component`, `root-component`, `tooling`, or `no-manifest-candidate`. `bootstrap`, `onboard` and `audit`
**call the script** for enumeration (exactly as they already call `check-doc-paths.sh`);
none of the three skills, nor this file, re-derives membership by independent eyeball. Two
runs of the script on the same tree produce the identical set, or the frozen-oracle grade
goes flaky.

This file explains the classification mechanism so a human/agent understands *why* the
script enumerates what it does, and it owns the one piece of judgment the script
deliberately leaves out: the **role *label*** (application / service / shared library) on
an already-selected component. **Labeling is the agent's job; membership is the script's**
— this file does not independently decide which directories count.

The script runs at a workspace/monorepo root, and — recursively, one level deep in v1 —
per monorepo-member repo in a mixed workspace (see `layer1-index-format.md`'s Mixed
variant). It never writes anything; it only enumerates and classifies.

## Two inputs

- **Declared workspace members** — the repo's own authoritative grouping, from any of:
  `package.json` `workspaces`, `pnpm-workspace.yaml`, `go.work`, Cargo `[workspace]
  members`, `nx.json`, `turbo.json`, `lerna.json`, `rush.json` (this is exactly the
  script's `WORKSPACE_CONFIGS` list, plus the `package.json`/`Cargo.toml` checks it runs
  separately). `project.json` is **not** a recognized workspace config in v1.
- **Discovered projects** — directories bearing a recognized **build manifest**. The
  recognized set is **closed** (adding an ecosystem = editing this list):
  `pyproject.toml`, `setup.py`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`, `build.gradle.kts`,
  `package.json`.

## Supported ecosystems (the closed set, stated plainly)

Two capabilities are separate, and a language can have one without the other:
**component discovery** (a directory carrying this manifest is recognized as a unit) and
**declared-member reading** (the workspace config is parsed, so members are honored exactly
— globs expanded, `!` negations subtracted; see step 2 above).

| Ecosystem | Manifest discovered | Declared members parsed |
|---|---|---|
| Go | `go.mod` | ✅ `go.work` (`use`, single-line and block form) |
| JavaScript / TypeScript | `package.json` | ✅ `pnpm-workspace.yaml`; `package.json` `workspaces` |
| Rust | `Cargo.toml` | ✅ `Cargo.toml` `[workspace]` `members`, with `exclude` honored as a subtraction |
| Python | `pyproject.toml`, `setup.py` | ❌ none (no `[tool.uv.workspace]` / PDM / Rye reader) |
| Java / Maven | `pom.xml` | ❌ none (`<modules>` is not read) |
| JVM / Gradle | `build.gradle`, `build.gradle.kts` | ❌ none (`settings.gradle(.kts)` `include` is not read) |

**Recognized as a workspace config but never parsed for members:** `nx.json`, `turbo.json`,
`lerna.json`, `rush.json`. Their presence marks a directory as a monorepo; their contents
are not read, so members come from the scan instead.

### Known gaps — real repos this tool cannot see

- **Not supported at all:** .NET (`.csproj`/`.sln`), Ruby (`Gemfile`/`.gemspec`), PHP
  (`composer.json`), C/C++ (`CMakeLists.txt`), Scala (`build.sbt`), Swift (`Package.swift`),
  Dart (`pubspec.yaml`), Elixir (`mix.exs`). A repo in these languages is **silent**, not
  wrong — it reports no components rather than bad ones, and typically classifies as a plain
  repo. That is the intended failure direction for a closed set.
- **Where a declared reader is missing**, that ecosystem falls through to the scan. It still
  works, but the repo's own grouping is not honored: nested members deeper than one level are
  missed, and declared exclusions are not applied.

Adding an ecosystem means editing `MANIFESTS` in `detect-mode.sh` **and** this table — they
are a matched pair, and a change to one without the other is a defect.

## The mechanism (as implemented by the script, in this order)

This section documents *how* `detect-mode.sh` mechanically arrives at its set — it is not
a separate procedure an agent re-runs by hand.

1. **Prune the search tree.** Skip any directory in the **built-in ignore set** (exact
   basename match): `node_modules/`, `vendor/`, `target/`, `dist/`, `build/`, `.venv/`,
   `__pycache__/`, `.git/` (`IGNORE_DIRS` in `detect-mode.sh`). Build output and vendored
   trees carry manifests; this prune is the single biggest false-component defense.
   **Declared negation globs prune too** (below) — a `!`-prefixed workspace entry is an
   authoritative exclusion and beats discovery, so a negated dir is dropped even when it
   carries a perfectly good manifest. Arbitrary `.gitignore` entries beyond the built-in
   set remain out of scope (reading them needs `git`, which this script never invokes).
2. **Read the declared member set — authoritatively.** Where a workspace config names
   members, the script honors that set **exactly**: `*` globs are **expanded against the
   real tree** (so `apps/*` yields the actual member dirs, not one opaque entry),
   `!`-prefixed entries are **subtracted**, and a declared member is emitted **at its
   declared depth however deep it is** (`documentation/examples/remote_storage` is a real
   `go.work` member and appears as one). `go.work` is parsed in **both** forms —
   single-line `use ./x` and the block `use ( … )`. A declared `.` means the root itself is
   a member (see *Root that ships code*).
3. **Fill gaps by scan — additive, never replacing step 2.** Any not-yet-covered directory
   bearing a recognized manifest is a candidate, so an **undeclared** but manifested dir is
   still found. The declared set is authoritative about *exclusion*, not about
   *completeness*: real workspace configs routinely omit navigable code (a `go.work` names
   auxiliary modules while the bulk of the repo sits in the root module). For a polyglot
   repo with no unifying config, the scan does the load-bearing work.
4. **Roll up to the top-level area.** A component is the **shallowest coherent top-level
   area**; deeper manifests inside it collapse into it (they are that component's Layer 2).
   A `rust/` dir that is a Cargo workspace of three crates is **one** component. **Roll-up wins over declared nested members:** a declared `workspaces`/`[workspace]` array *inside*
   an already-anchored component does not force a deeper-than-top-level router entry.
5. **Classify each component's role** (first match wins):
   1. **tooling / infra** — the dir is a known infra/CI dir (`.github/`, `docker/`,
      `bin/`, `scripts/`, `tools/`) **or** its own directory name matches a tooling
      pattern: `eslint-config-*` or `prettier-*`. (A broader wildcard matching any
      directory name ending in "-config" was considered and intentionally **dropped** —
      it is over-broad and would misclassify an ordinary app dir like `payment-config/`;
      only the two named prefixes count.)
   2. **application / service** — it produces a deployable/runnable artifact. Tag it
      `(application)` if it is a user-facing app (a web app with a dev/build script, a
      CLI/desktop app); tag it `(service)` if it is a backend service (a `Dockerfile` or
      container entrypoint, an HTTP/RPC server, a long-running worker binary) with no
      browser UI.
   3. **library (shared)** — **the default** — importable/consumed code with no
      deployable artifact of its own.

## Container rules (not components)

- A bare **grouping directory** (e.g. `packages/` itself, no manifest of its own — Cargo's
  *virtual manifest* case) is a container, not a component.
- An **aggregator root is the container, never a component** — a virtual `[workspace]` root
  or a root `package.json` that only aggregates members describes the monorepo, not a unit.

## Root that ships code (`root-component`)

A root that ships **real code alongside** its aggregator manifest is its own unit, emitted as
`unit root-component .`. The script treats the root as code-shipping when either:

- **`.` is a declared workspace member** (`go.work`'s `use ( . … )`), or
- the root carries a manifest that is **more than a workspace container**: `go.mod`,
  `pom.xml`, `pyproject.toml`, `setup.py`, `build.gradle`, `build.gradle.kts`, or a `Cargo.toml` with a
  `[package]` section.

A bare root `package.json` **does not** count. Holding devDependencies and a `workspaces`
array at the root is the near-universal JS convention and does not mean the root ships a
module — counting it would turn most JS monorepos into their own component.

**Why this shape exists.** Go's one-`go.mod`-per-repo model makes root-ships-code the norm,
not an edge case, and the root is frequently the *most* important unit in the repo. It is a
distinct shape rather than `component .` because a component path's last segment names the
unit, and a unit named `.` is nonsense. Consumers should name it after the **repo/root
itself** (see *Output*).

## No-manifest fallback (never silently drop real code)

A directory with **substantial source but no recognized manifest** (a docs site, a bare
package with no `pyproject.toml`, a dir keyed by a non-standard manifest such as
`.claude-plugin/plugin.json`) is emitted by the script as a `no-manifest-candidate` —
**listed for human confirmation, never silently dropped, and never silently promoted**.

**Suppressed when the root ships code.** A `no-manifest-candidate` means *"real code this
tree cannot explain."* If the root is code-shipping, an unmanifested subdirectory **is**
explained — it is a package of the root module — so it is not emitted. Without this, one
plain Go repo produced ~18 phantom candidates (every `.go` package dir), which is worse than
useless: it buries the real signal and mis-describes the repo. The suppression is keyed to
the root-ships-code test above, so an aggregator-root monorepo still flags its unexplained
dirs normally.
An agent may *flag* one to a human, but confirming it does **not** move it into the
graded component set within this sub-project — this veto is explicitly **non-set-changing
in v1**; only the script adds or removes a directory from the set.

## Output

`detect-mode.sh` emits one line per unit: `unit component <relpath>`,
`unit root-component .`, `unit tooling <relpath>`, `unit no-manifest-candidate <relpath>`
(plus `unit repo` / `unit monorepo-member` at the multi-repo/mixed level). `bootstrap` adds
the role *label*
to each `component` unit and writes the result into the monorepo index variant
(`layer1-index-format.md`); `audit` uses the script's enumeration, unmodified, as its
on-disk truth set — it does not re-derive the set by independent eyeball.

Component units are **container-qualified** (`apps/api`, `packages/shared-ui`), exactly as
tooling units are — the path is root-relative and identifies the directory unambiguously,
so two same-named components in different containers never collapse. Consumers name the
component by the path's **last segment**.

**`root-component .` is the one exception to last-segment naming.** Its path is always
literally `.`, so name it after the **root directory itself** (for a repo at
`services/gateway/`, that is `gateway`) and treat it as an ordinary component thereafter —
it takes a role label and gets a component heading like any other. Never write a heading of
`.`.
