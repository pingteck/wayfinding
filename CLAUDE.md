# CLAUDE.md — wayfinding

This repo is the **`wayfinding` Claude Code plugin**: a 4-layer codebase-navigation
methodology packaged as three skills (`bootstrap`, `onboard`, `audit`) over one shared
reference core. `README.md` is the user-facing description; `tests/dogfood.md` is the
acceptance runbook and the record of every agent run. The conventions below are
non-obvious, and most were learned by shipping the opposite first — follow them.

## Commands

```bash
bash tests/run-all.sh                       # every mechanical gate — run BEFORE and AFTER any change
bash scripts/detect-mode.sh <dir>           # the detector itself, on any real repo or workspace
bash tests/stage-fixture.sh <fixture> <dest> # stage a workspace fixture (.member-repo -> .git)
bash tests/stage-layer2-chain.sh <dest> [seed]  # THE multi-repo acceptance fixture; optional seed
                                            # (full|onboard-hub|audit-broken) pre-writes an index
```

`run-all.sh` covers the mechanical gates only. The index graders (`grade-multirepo-index.sh`,
`grade-mixed-index.sh`, `grade-monorepo-index.sh`, `grade-onboard-component.sh`,
`grade-layer2-chain.sh`, `grade-doc-precedence.sh`) grade output an **agent** produced and need
a dogfood run first — see `tests/dogfood.md`.

## What it is

- `.claude-plugin/plugin.json` + `skills/{bootstrap,onboard,audit}/SKILL.md` + `references/`
  (shared core) + `scripts/{detect-mode,check-doc-paths}.sh`.
- Skills are invoked as `wayfinding:bootstrap` / `:onboard` / `:audit`.
- `references/component-detection.md` — why `detect-mode.sh` enumerates components the way it
  does. `references/bootstrap-monorepo-mixed.md` — bootstrap's monorepo/mixed procedure,
  loaded only for those modes.

## Conventions

- **`detect-mode.sh` owns ALL mechanical set-membership; skill prose owns only the role
  label.** Never restate a membership rule in a skill — prose that restates the script drifts
  from it (it happened: bootstrap's walk-up prose described a `.git`/`CLAUDE.md` rule and a
  `mode=ambiguous` outcome the script had stopped producing).
- **Only `.git` marks a member repo** (`is_independent_repo`; also `check-doc-paths.sh`'s
  sibling skip). A bare `CLAUDE.md` once counted, so any monorepo with per-directory
  `CLAUDE.md` files read as a multi-repo workspace and lost every real component (measured:
  sentry, posthog, claude-code-action; next.js and grafana would follow via `AGENTS.md`).
  Never use a docs file as a repo marker. **Workspace fixtures carry `.member-repo` markers
  and must be staged with `tests/stage-fixture.sh`** — git cannot track a file named `.git`,
  and a hand `cp -r` silently turns the mixed fixture into `mode=monorepo`.
- **Reference shared files as `${CLAUDE_PLUGIN_ROOT}/references/…` and `…/scripts/…`** —
  never `../..` traversal, and never a path outside the plugin root: only within-plugin-root
  paths survive install. `references/` are canonical and carry no `source:` pointers.
- **Scripts are pure bash and never invoke git.**
- **Write posture (red-teamed three times — do not relitigate):** skills are read-and-report
  for Layer 2 and never write, `git add`, or commit inside a repo they didn't create. They
  write `workspace-index.md` at the workspace root and, in a mixed workspace, each member's
  index **host-at-root** as `<root>/<member>.index.md` — the fail-closed default. In-place
  (`<member>/workspace-index.md`) only when the user explicitly targeted that member. No
  consent prompt, ever. Generated indexes are never staged.
- **`bootstrap/SKILL.md` holds no monorepo/mixed procedure inline** — a multi-repo run reads
  the whole file. That procedure lives in `references/bootstrap-monorepo-mixed.md`. The
  **Safety boundary and Common mistakes stay in SKILL.md**, mixed-mode rules included:
  write-safety must never depend on a conditional load. Pinned by `tests/skill-shape.test.sh`.
- **Supported languages are a closed set, edited as a matched pair:** `MANIFESTS` /
  `MODULE_MANIFESTS` in `detect-mode.sh`, the table in `references/component-detection.md`,
  and its mirror in `README.md`. Discovery and declared-member reading are separate
  capabilities.
- **The monorepo veto is the same-ECOSYSTEM rule** (`veto_discovered` +
  `manifest_ecosystem`), not `root_ships_code`, and it compares build tools, not manifest
  filenames: a root `build.gradle.kts` over `build.gradle` children is one ecosystem. Reusing
  `root_ships_code` demotes every Maven/Gradle/Python monorepo, because declared-member
  reading has no parser for them.
- **Example names must not collide with a fixture the example DISAGREES with.** Agents copy
  the format doc's examples, so a name that also titles a fixture with *different* units
  invites a wrong heading. Vet with `grep -rli <name> tests/fixtures tests/expected-*.md`.
  Deliberate exception: the monorepo example and `tests/fixtures/monorepo` are both
  `Acme Platform` with the same components — that alignment is intentional.
- **No origin-workspace detail in any shipped file** — enforced by `run-all.sh` against
  `tests/origin-detail.pattern`, over exactly what `git add -A` would ship (computed from
  `.gitignore`). Add a name to the pattern file rather than reasoning about it.
- **Stack profiles are verification-command-first and dated**; discover paths, never
  hardcode.

## Testing method

- **Failing test first — including for skill edits.** Watch it fail. A green suite is not
  evidence when the tests predate the failure mode: recognising `build.gradle.kts` alone
  demoted mixed-DSL Gradle builds to plain repos with every gate green.
- **Prove the instrument can fail before trusting it.** Graders have mutation tests
  (`grade-multirepo-index.test.sh`, `layer2-seeds.test.sh`, `agent-checks.test.sh`) that
  assert each mutation actually changed the file. Judge checks by **output, not exit status**.
  Two traps that have bitten: BSD `sed` accepts GNU-only addresses (`0,/re/`, `,+1`) and
  silently edits nothing; and an interactive `grep` may be a shell wrapper that respects
  `.gitignore` — verify by hand with `/usr/bin/grep` or just run the suite.
- **Register predictions and decision rules before running agents**, and don't revise them
  after seeing results. Grade against disk, never against an agent's own report.
- **Agent runs must be isolated from this repo's instructions and git state.** A subagent
  spawned from a session in this repo starts with this file (and any other local instructions
  file) *as loaded at session start*, plus a git-status snapshot naming untracked fixtures —
  enough to tell it what it is being tested on. Use headless sessions started inside the
  staged workspace instead:
  `claude -p "<prompt>" --allowedTools "Read Glob Grep Write Edit Bash" --permission-mode acceptEdits --add-dir <plugin>/skills <plugin>/references <plugin>/scripts --no-session-persistence`.
  Run a no-tools probe session first and confirm its starting context holds nothing about the
  test. Write the prompt's file boundary in the skill's own terms ("the index file(s) the skill
  tells you to write") — a boundary written for one mode forbade mixed mode's member index.
- **Grade RED as well as GREEN.** `tests/dogfood.md` records what agents produce *without*
  the skills; that is what establishes marginal value. The load sits in `references/`, not in
  `SKILL.md` prose — keep `references/` intact through any trim.

## Releasing

Public repo `github.com/pingteck/wayfinding`, listed by URL in
`github.com/pingteck/claude-code-marketplace` (as `touchstone` is). Users receive a new version
only when `version` in `.claude-plugin/plugin.json` is bumped.
