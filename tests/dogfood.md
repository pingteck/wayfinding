# Dogfood runbook — wayfinding plugin

This is the acceptance spine for `wayfinding`. Every check below runs against a **fixture in
this repo**, never against a private workspace, so anyone with a clone can reproduce all of
it. Ground truth is the hand-authored oracle set under `tests/expected-*.md`; this file
doesn't change to fit skill output — skill output changes to pass it.

> **History.** Checks 1–5 originally ran against the private workspace this plugin was
> extracted from, and the multi-repo oracle *was* that workspace's index. That made the repo
> unpublishable. On 2026-07-28 the checks were re-pointed at the neutral three-repo fixture
> `tests/fixtures/layer2-chain/`, and the origin-workspace records were **moved out of the
> repo verbatim** rather than redacted — a redacted record would claim evidence that was
> never gathered. They live in `wayfinding-origin-records/origin-dogfood-records.md`, a
> sibling directory outside this git repo.

**Install.** The plugin needs a dev/local-dir install so `${CLAUDE_PLUGIN_ROOT}` resolves to
this checkout (a cache install pins a version and won't pick up edits) — see `README.md`.
Throughout, `$PLUGIN` is this checkout and `$WS` is the staged fixture workspace.

**Mechanical gates come first.** `bash tests/run-all.sh` must be green before any dogfood run;
it covers everything that doesn't need an agent, including whether the graders below can
actually fail. The checks here are the part that needs an agent.

## Staging the multi-repo fixture

```bash
PLUGIN="$(pwd)"                     # this checkout
WS=/tmp/wf-dogfood                  # scratch workspace, anywhere outside the plugin
bash "$PLUGIN/tests/stage-layer2-chain.sh" "$WS"
bash "$PLUGIN/scripts/detect-mode.sh" "$WS"   # -> mode=multi-repo, three `unit repo` lines
```

The staging script exists because each member must look like a real cloned repo, i.e. carry a
`.git`. Git cannot track a file named `.git` — it drops them **silently** — so they are
materialized at run time. Copying the fixture by hand instead of using the script produces a
workspace where two of the three members aren't independent repos and never enumerate at all,
and the run grades meaningless.

**Agent rules for every check below** (unchanged from every prior dogfood record here):
fresh agents, one per workspace, **barred from reading anything under `tests/`** — the
oracles, `expected-sets/` and every `grade-*.sh` are the answer key — and barred from
`CLAUDE.md` and `docs/`, which discuss the expected answers. None may spawn sub-agents.
Grading is done afterwards by the dispatcher, never by the agent.

## Check 1 — bootstrap → grade

Confirms `wayfinding:bootstrap` produces a structurally correct Layer-1 index for the whole
workspace. The grader is structural, not content-equality with the oracle, so also eyeball-diff
the output against `tests/expected-layer2-chain-index.md` for facts — a wrong stack name or an
invented capability won't trip a structural grader.

```bash
cd "$WS"
# invoke wayfinding:bootstrap -> writes ./workspace-index.md
bash "$PLUGIN/tests/grade-multirepo-index.sh" workspace-index.md \
  redirect-svc='Chi|pgx' agents-only-svc='BoltDB' readme-only-svc='zerolog' \
  --unprofiled redirect-svc,agents-only-svc,readme-only-svc
```

Expected: `MULTIREPO INDEX OK`.

All three repos are Go, and the bundled profiles are Java/Maven and TypeScript/Vite only, so
every repo here is unprofiled and must carry the `Layer-4 baseline only; Layer-3 profile TODO`
marker. **Omit `--unprofiled` and the marker is not checked at all** — that is how this grader
first shipped, and it passed an oracle that was missing the marker on all three.

The stack regexes are not decoration: each token occurs in exactly one file in the fixture, so
a passing Stack field proves the file was read rather than guessed, and each is checked inside
its own repo's section so the right token under the wrong repo still fails.

## Check 1b — Layer-2 source chain (F1), same run

The same generated index is graded a second way. This is the check that costs nothing extra
and catches the most: each repo's real entry point is a canary token reachable from exactly
one source file, so the index reveals which source the agent actually read.

```bash
bash "$PLUGIN/tests/grade-layer2-chain.sh" workspace-index.md
```

Expected: `LAYER2 OK` — `quarryd` (reached only by following the 11-byte `@AGENTS.md`
redirect), `beaconize` (`AGENTS.md` where no `CLAUDE.md` exists), `lattice-run` (the README
tier), and `legacy-start` **absent**. That last one is a negative canary: it is the DEPRECATED
launcher named only in `redirect-svc/README.md`. Citing it means the README was read instead
of the redirect being followed — passing the positive checks while tripping it is a *worse*
result than finding nothing, because it looks authoritative and is wrong.

## Checks 2–4 — seeded workspaces, one agent each

Checks 2–4 each start from a **known index state**, staged by passing a seed name to the
staging script: `tests/seeds/layer2-<seed>.md` lands as `$WS/workspace-index.md`. Use a
**separate workspace per check** — running them in one tree lets a later check inherit an
earlier one's writes, which makes the containment assertions meaningless. Save each seed as the
"before" file *outside* the workspace before invoking the agent.

`tests/layer2-seeds.test.sh` (in `run-all.sh`) proves every instrument below can fail against
these exact seeds — run the suite first. **Why seeds exist:** the first written versions of
Checks 2 and 3 (2026-07-28) were wrong in ways no grader caught. Check 2 onboarded a repo that
was *already indexed*, which `onboard`'s stop table refuses ("target already has an H2 →
Stop"), so a correct agent would write nothing and the grader would pass on an untouched index.
Check 3 expected "a gap flag, not a section", but `onboard` writes a section for a docs-free
repo. Both were found by reading the skills, before any agent was spent.

All three checks grade with `LINKS_FIELD='Cross-repo links:'` exported. gate1 defaults to the
monorepo label `Cross-component links:`.

## Check 2 — onboard the hub (back-links on two sections)

The seed `onboard-hub` indexes `redirect-svc` and `readme-only-svc` with links fields reading
"None recorded yet.", and **does not index `agents-only-svc`**. That repo is the hub: it has an
edge to *both* others. Onboarding it must append its section **and** add a back-link to each
sibling's Cross-repo links field, changing nothing else. "Append the section and stop" is the
defining failure the skill warns about. The seed's blockquote is worded to stay true after
onboarding, so the run tests back-linking rather than summary-editing temptation.

```bash
bash "$PLUGIN/tests/stage-layer2-chain.sh" "$WS" onboard-hub && cp "$WS/workspace-index.md" /tmp/c2-before.md
# agent task: "Add the agents-only-svc repo to this workspace's navigation index." (onboard)
export LINKS_FIELD='Cross-repo links:'
printf 'component=agents-only-svc\ntouched=redirect-svc readme-only-svc\n' > /tmp/c2-allowed
bash "$PLUGIN/tests/grade-onboard-component.sh" gate1    /tmp/c2-before.md "$WS/workspace-index.md" /tmp/c2-allowed
bash "$PLUGIN/tests/grade-onboard-component.sh" headings /tmp/c2-before.md "$WS/workspace-index.md" 1
bash "$PLUGIN/tests/grade-multirepo-index.sh" "$WS/workspace-index.md" \
  redirect-svc='Chi|pgx' agents-only-svc='BoltDB' readme-only-svc='zerolog' \
  --unprofiled redirect-svc,agents-only-svc,readme-only-svc
bash "$PLUGIN/tests/grade-layer2-chain.sh" "$WS/workspace-index.md"
```

Expected: `ONBOARD-GRADE OK` ×2, `MULTIREPO INDEX OK`, `LAYER2 OK`. gate1 is the one that
matters. It fails if anything outside the two siblings' links fields changed (containment),
if either sibling lacks the back-link, or if a sibling lost a pre-existing edge to another
**unit**. Rewording the rest of a links line is allowed.

## Check 3 — a repo with no docs at all

Stage the `full` seed (all three repos indexed), then add `unprofiled-svc`: a `.git` file and a
bare `go.mod`, with no `CLAUDE.md`, `AGENTS.md` or `README.md`.

```bash
bash "$PLUGIN/tests/stage-layer2-chain.sh" "$WS" full && cp "$WS/workspace-index.md" /tmp/c3-before.md
mkdir -p "$WS/unprofiled-svc" && printf 'gitdir: /nonexistent/unprofiled.git\n' > "$WS/unprofiled-svc/.git"
printf 'module example.com/unprofiled-svc\n\ngo 1.25\n' > "$WS/unprofiled-svc/go.mod"
# agent task: "Add the unprofiled-svc repo to this workspace's navigation index." (onboard)
printf 'component=unprofiled-svc\ntouched=\n' > /tmp/c3-allowed
bash "$PLUGIN/tests/grade-onboard-component.sh" gate1    /tmp/c3-before.md "$WS/workspace-index.md" /tmp/c3-allowed
bash "$PLUGIN/tests/grade-onboard-component.sh" headings /tmp/c3-before.md "$WS/workspace-index.md" 1
bash "$PLUGIN/tests/grade-multirepo-index.sh" "$WS/workspace-index.md" \
  redirect-svc='Chi|pgx' agents-only-svc='BoltDB' readme-only-svc='zerolog' unprofiled-svc='Go 1\.25' \
  --unprofiled redirect-svc,agents-only-svc,readme-only-svc,unprofiled-svc
```

Expected per the skill: a **section is written** (a missing profile never blocks writing).
Stack is taken from the manifest with the unprofiled marker. Purpose is stated as undocumented,
never derived from a manifest. No edge is invented. No other section changes, since `touched=`
is empty. The report carries the exact gap sentence *"unprofiled-svc: no CLAUDE.md found — add
one before Layer 2 conventions exist for this repo."* Also read the new section by eye: a
structural grader cannot tell "not documented" from a plausible invention.

## Check 4 — audit negative

The seed `audit-broken` is the full index with two defects injected. One: `agents-only-svc`'s
links no longer name `readme-only-svc`, while `readme-only-svc` still claims to scrape it, so
the edge is one-sided. Two: a markdown link to a nonexistent `ops/runbook.md`. The seeds test
proves each defect is mechanically detectable and that the unbroken seed is clean on both, so
these two defects are the only difference.

```bash
bash "$PLUGIN/tests/stage-layer2-chain.sh" "$WS" audit-broken && cp "$WS/workspace-index.md" /tmp/c4-before.md
# agent task: "Audit this workspace's navigation index." (audit)
cmp /tmp/c4-before.md "$WS/workspace-index.md" && echo "audit wrote nothing"
```

Expected: the report flags **both** defects, naming the `agents-only-svc`/`readme-only-svc` pair
for the edge and `ops/runbook.md` for the link, and the index is byte-identical afterwards. A
clean pass is a bug in `audit`.

## Check 5 — guard zero-FP

Confirms `check-doc-paths.sh` has zero false positives against real artifacts — every
capability-only description with no file paths, and any file reference that does appear,
resolves.

```bash
bash "$PLUGIN/scripts/check-doc-paths.sh" "$PLUGIN/references"
bash "$PLUGIN/scripts/check-doc-paths.sh" "$PLUGIN/skills"
bash "$PLUGIN/scripts/check-doc-paths.sh" "$WS/workspace-index.md"
```

Expected: exit `0` on all three, no `MISSING:` lines. (The third needs Check 1 to have run;
before that the file doesn't exist and there is nothing to check.)

## Final guard — scope reconciliation

Running the guard over the **whole** plugin tree does not and cannot exit 0, and that is
correct behaviour, not a defect to fix:

- `tests/fixtures/dead/dead.md` is the **intentional** negative fixture — a deliberately dead
  reference that exists to prove the guard catches dead links. Making a whole-tree scan exit 0
  would mean deleting or defanging the guard's own negative test.
- `docs/` is dev-only documentation the plugin loader ignores; one of those files describes the
  guard's own link recognizer using inline example-link syntax inside backticks. The guard
  strips fenced code blocks but not inline backtick spans, so it flags that prose too.

**So "zero false positives" applies to the shippable payload plus the generated index**, not to
the whole tree: the three scoped commands in Check 5 must each independently exit `0`. Anyone
re-verifying this acceptance should use those, not a whole-tree scan.

## Monorepo mode — Checks 6–12 (fixture: `tests/fixtures/monorepo/`)

These validate monorepo component indexing against the frozen oracle
`tests/expected-monorepo-index.md`. Because the plugin's mode-switch keys on the target
being its own git repo with no independent sub-repos, the fixture must be a git repo at
run time — copy it out and `git init` the copy (the committed fixture carries no `.git`):

```bash
rm -rf /tmp/mono-fixture && cp -r "$PLUGIN/tests/fixtures/monorepo" /tmp/mono-fixture
git -C /tmp/mono-fixture init -q && git -C /tmp/mono-fixture add -A && git -C /tmp/mono-fixture commit -qm init
```

Run `wayfinding:bootstrap` from `/tmp/mono-fixture` (dev/local-dir install so
`${CLAUDE_PLUGIN_ROOT}` resolves to this checkout). It must classify the target as a
**monorepo** and write `/tmp/mono-fixture/workspace-index.md` (the monorepo variant).

- **Check 6 — monorepo mode detected:** bootstrap's report states monorepo mode (not
  multi-repo) for `/tmp/mono-fixture`.
- **Check 7 — exact component set:**
  `bash wayfinding/tests/grade-monorepo-index.sh /tmp/mono-fixture/workspace-index.md`
  → `MONO INDEX OK`. This asserts the set is exactly `{web, api, ingest, shared-ui,
  nested-ws}` — `services/ingest`'s crates rolled up to one; `nested-ws`'s declared
  sub-packages rolled up; `node_modules/leftpad`, `packages/` (grouping), and
  `eslint-config-fix` **not** components.
- **Check 8 — roles:** `web` is application, `api`/`ingest` service, `shared-ui`/`nested-ws`
  shared library; `.github` + `eslint-config-fix` in the `Tooling & root config` note.
- **Check 9 — both-endpoints edges (≥2 consumers):** `shared-ui` is consumed by **two**
  components — `web` and `nested-ws`. Each edge appears on both sides (`web`/`nested-ws`
  say they consume `shared-ui`; `shared-ui` says "Consumed by `web` and `nested-ws`"). The
  grader's two awk checks cover both edges.
- **Check 10 — unprofiled marker selectivity:** `web` genuinely matches the
  `typescript-vite` profile (its `package.json` declares `typescript`+`vite`, with a
  `tsconfig.json` and a `.ts` source) → its Stack line stays **plain, no marker**. The
  four components with no bundled profile — `api` (Python), `ingest` (Rust), `shared-ui`
  and `nested-ws` (plain JS) — **each** carry the exact
  `Layer-4 baseline only; Layer-3 profile TODO` phrase on their own unbroken line. The
  grader asserts this selectivity (marker on the four, none on `web`).
- **Check 11 — no-manifest candidate:** `docs-site/` appears under `## No-manifest
  candidates`, not as a component H2.
- **Check 12 — audit + boundary:**
  - Break a copy: `cp /tmp/mono-fixture/workspace-index.md /tmp/mono-broken.md`, then remove
    `shared-ui`'s back-link to `web` (making the edge one-sided). Run `wayfinding:audit`
    against `/tmp/mono-broken.md` → it flags the one-sided **component** edge and does
    **not** flag the real components as "absent from disk" (R2 guard).
  - Boundary: confirm bootstrap did **not** `git add`/commit the index
    (`git -C /tmp/mono-fixture status --porcelain` shows `workspace-index.md` as untracked),
    and its report carried the "created at your repo root; gitignore or commit deliberately"
    note.

Clean up: `rm -rf /tmp/mono-fixture /tmp/mono-broken.md`.

**No regression:** the multi-repo dogfood (Checks 1–5 above) must still pass
unchanged — run Check 1 (`grade-multirepo-index.sh` → `MULTIREPO INDEX OK`) to confirm.


## Dogfood results — multi-repo (Checks 1–5)

**The v1 results for these checks were recorded against the private origin workspace and have
been moved out of this repo**, verbatim, to
`wayfinding-origin-records/origin-dogfood-records.md` (a sibling directory, outside git). They
are not reproduced here because they cannot be neutralised without falsifying them: those runs
happened against real repos with real stacks, and a find-and-replace version would assert
evidence that was never gathered.

What they established, in terms that survive the move: all five checks passed on 2026-07-11;
Check 3 caught defect **F9** (the unprofiled marker landing only in the ephemeral onboarding
report, with the index's own Stack field left bare), and the fix — `bootstrap`/`onboard`
Step 4 requiring the annotation in the index entry's **Stack** field as prose pointing at
`stack-profile-format.md`, never a markdown link — is live in the skills and is what the
current marker-selectivity gates assert.

**Results against the neutral fixture are recorded below**, and supersede those as this
repo's acceptance evidence.

**Reading the older records below.** Historical entries name `grade-index.sh` and
`expected-workspace-index.md`. Both were deleted on 2026-07-28 and replaced by
`grade-multirepo-index.sh` (structural, takes the repo set and stack facts as arguments) and
`expected-layer2-chain-index.md`. The old grader was verified to fail on any workspace other
than the origin one — that is precisely why it could not ship — and the new grader was verified
to pass on **both** oracles given their respective repo names, so it subsumes the old one's
assertions rather than weakening them. Those historical `INDEX OK` results stand as written;
only the instrument's name changed.

### Multi-repo dogfood results — neutral fixture (2026-07-28)

**Fixture:** `tests/fixtures/layer2-chain/`, staged with `stage-layer2-chain.sh`.
`detect-mode.sh` → `mode=multi-repo` with all three `unit repo` lines. Method: one fresh
agent, file-based skill execution with `${CLAUDE_PLUGIN_ROOT}` resolved to the checkout,
barred from `tests/`, `CLAUDE.md` and `docs/`, no sub-agents, graded afterwards by the
dispatcher. **Checks 1 and 1b PASS.**

- **Check 1 — `MULTIREPO INDEX OK`.** All three sections present, all five fields on each,
  all three stack facts (`Chi`/`pgx`, `BoltDB`, `zerolog`) named **in their own repo's
  section**, no invented fourth repo.
- **Check 1b — `LAYER2 OK`.** All three positive canaries found — `quarryd` (only reachable
  by following the 11-byte `@AGENTS.md` redirect), `beaconize` (AGENTS.md where no CLAUDE.md
  exists), `lattice-run` (README tier) — and the negative canary `legacy-start` correctly
  absent. So the full Layer-2 source chain was walked, not just the easy tier.
- **The non-edge held.** The agent recorded 4 edge mentions — `redirect-svc`↔`agents-only-svc`
  and `agents-only-svc`↔`readme-only-svc`, each on both endpoints — and did **not** invent an
  edge between `redirect-svc` and `readme-only-svc`, which have none. Both-endpoints
  reciprocity was reproduced without prompting, consistent with every prior RED baseline here.
- **Marker selectivity:** all three repos are Go, no bundled Go profile exists, and all three
  carry the `Layer-4 baseline only; Layer-3 profile TODO` marker. Correct — no false marker,
  no missing one. (This fixture cannot test the *profiled* direction; the monorepo fixture
  does, via `web`.)
- **Boundary:** the agent wrote exactly one file, the workspace-level `workspace-index.md`.
  Nothing inside any member repo was touched; no `git add`/commit.

**Provenance self-report, cross-checked against the canaries.** The agent was asked separately
which file it took each repo's facts from. Its account matches the canary evidence exactly:
`redirect-svc` via the `@AGENTS.md` import (it named both files and noted the 11-byte redirect
carries no facts of its own), `agents-only-svc` from `AGENTS.md` with no `CLAUDE.md` present,
`readme-only-svc` from `README.md`; `go.mod` corroborated `Go 1.25` in each case and the H1 and
summary came from the workspace root `CLAUDE.md`. A self-report agreeing with an independent
canary grader is worth more than either alone — the grader proves *what was read*, the report
shows the *reasoning*, and a disagreement would itself have been the finding.

**It read the deprecated README and rejected it deliberately** — the thing the negative canary
cannot distinguish. Asked directly, it confirmed reading `redirect-svc/README.md`, took no
field from it, and recorded **no doc conflict**, reasoning that *"a doc that labels its own
content deprecated has told you its status — so this is not a live disagreement."* So
`legacy-start`'s absence is a considered rejection, not an artefact of traversal order. It also
independently confirms next-up item 6: this fixture cannot test doc **precedence**, because the
stale doc concedes. A real precedence test still needs two docs each asserting a *current*
entry point.

**Two underspecifications the agent surfaced unprompted** (recorded, not acted on):

1. **`${CLAUDE_PLUGIN_ROOT}` in a written index — literal or expanded?** The skill never says,
   and *"the two readings produce different bytes — so if there is an oracle, only one of them
   can match it."* Settled here by precedent: `expected-monorepo-index.md` writes it
   **literally**, and the agent copied that form from the filled example, so oracle and output
   agree. The rule is nowhere stated in prose, though — it is currently learned only by copying
   an example, which is exactly the seam the `bootstrap` RED baseline says examples do cover.
   No failing test, so no edit; recorded so it is not re-derived.
2. **Entry points: the rule bans a location but not a command.** These repos state entry points
   as paths (`cmd/quarryd`, `bin/lattice-run`). The agent kept the run command and dropped the
   `cmd/...` source reference where both existed, but flagged `bin/lattice-run` as genuinely
   both a path and the named run target, and said that call *"could reasonably go the other
   way."* The oracle takes the same reading (capability phrasing, binary named, no path).

**Not covered by this run:** Checks 2–5. They were run on 2026-10-14; see below.

### Multi-repo dogfood results — Checks 2–5 (2026-10-14)

**Method:** three fresh agents, one per seeded workspace, run in parallel. Each did file-based
skill execution, was barred from `tests/`, `CLAUDE.md` and `docs/`, was told not to spawn
sub-agents, and was required to report via `SendMessage`. (Plain text from a background
subagent never reaches the dispatcher. That cost two empty round-trips in July.) Grading was
done afterwards by the dispatcher, **against disk, not against the agents' reports**.
**All four checks PASS.**

| Check | Instruments | Result |
|---|---|---|
| 2: onboard the hub | gate1 · headings +1 · structure · layer-2 · guard | all OK. Diff vs seed = the two siblings' links fields + the new section, nothing else |
| 3: docs-free repo | gate1 (`touched=` empty) · headings +1 · structure (4 repos) · layer-2 · guard | all OK. New section names no sibling |
| 4: audit negative | both defects reported · index byte-identical | OK. One-sided edge named by pair and direction; `ops/runbook.md` named as MISSING |
| 5: guard zero-FP | `references/` · `skills/` · Check 2 and 3 output | exit 0 on all four |

**What the runs showed beyond the green:**

- **Check 2:** both back-links were written, each replacing the "None recorded yet."
  placeholder. The `redirect-svc` one wraps across two lines, and gate1 read it whole. The
  blockquote was left alone. That was the risk named in advance, after the July onboard RED
  arms rewrote summaries.
- **Check 3:** every field cites its source or states that none exists. Purpose: "Not
  documented in the repo … a build manifest cannot state a purpose." Stack: "Go 1.25 (from its
  build manifest)" plus the marker. The report carries the exact gap sentence.
  **Containment held under natural pressure:** after the agent's own edit, the full seed's
  blockquote ("A three-repo workspace…") was false. The agent left it and reported it as drift
  for `audit`, which is what the skill says to do.
- **Check 4:** the agent also noted that `agents-only-svc`'s own `AGENTS.md` *does* name
  `readme-only-svc`, so the defect is in the index, not the source. That is the correct
  diagnosis, and more than the check asked for.

**Registered predictions** (written before seeds were built):
- Q1 *gate1 cannot grade multi-repo as it stands*: **confirmed**. Its control went red on a
  correct pair.
- Q2 *Check 2 passes, containment included*: **confirmed**. The named blockquote risk did not
  materialise.
- Q3 *Role will be a judgment call for a docs-free repo*: **falsified, in the good
  direction.** The agent applied "never Purpose from manifests" to Role on its own
  initiative and refused to infer "a service" from the `-svc` suffix.
- Q4 *audit flags both, writes nothing*: **confirmed**.
- Q5 *guard clean*: **confirmed**.
- **Not predicted:** gate1's additivity rule false-failed every correct rewording of a links
  line in any mode, not only multi-repo. See the instrument notes below.

**Instrument defects found and fixed before any agent ran:**
1. The July specs for Checks 2 and 3 (see "Why seeds exist" above).
2. gate1 hardwired `Cross-component links:`, so it rejected every correct multi-repo onboard.
   Fixed with the `LINKS_FIELD` override.
3. gate1's additivity rule counted **every word** on a sibling's links line as an edge that
   must survive. Replacing "None recorded yet." failed as three lost edges, and so would any
   correct rewording in monorepo or mixed mode (e.g. dropping "over" from "calls `api` over
   REST"). It now counts only indexed **unit** names. This was regression-checked on the
   monorepo and mixed oracles, using `make-before-index.sh` befores: the control result was
   identical under the old and new rules, and a dropped back-link still fails under the new
   one.
4. The oracle's "Notes for graders" trailer mentions `legacy-start`, so a seed copied from the
   oracle verbatim would trip the negative canary for reasons unrelated to the agent. Seeds
   carry the oracle body only, and the seeds test asserts it.

**Method hole found, now measured: "barred from `CLAUDE.md`" was never enforceable.** The
Check 4 agent reported that the plugin repo's `CLAUDE.md` was **already in its context at
start**. Any agent spawned from this repo inherits it automatically, and that applied in July
too. Measured leakage: **none of the answer-key tokens appear in it** (canaries, stack tokens,
repo names, seed placeholders, defect locations). The only hit is `Meterline`, the fixture's
own title. It does carry conceptual hints: the F1 row says `CLAUDE.md` in the wild is often an
11-byte `@AGENTS.md` redirect, and next-up item 6 says the fixture's stale doc labels itself
DEPRECATED. Both duplicate what the skill and the fixture already tell an agent, so these
GREEN results stand. **It matters more for RED arms:** an arm meant to have no plugin knowledge
is not pure if spawned from this directory. Spawn RED arms from somewhere `CLAUDE.md` does not
reach, or account for it.

**Boundary:** no member repo was touched and no git command was run, in all three. One minor
deviation: the Check 2 agent wrote a diff baseline into the dispatcher's scratchpad, outside
its workspace, although the brief allowed only `workspace-index.md`. Harmless, and deleted,
but recorded because it is a breach of the stated boundary.

**Skill underspecifications the agents surfaced** (recorded, not acted on; none changed an
outcome here, so there is no failing test):
- **`onboard` Step 2's sibling skim reads "each existing repo's root `CLAUDE.md` only".**
  Flagged independently by **both** onboard agents. Here only one sibling has a `CLAUDE.md`,
  and it is a redirect. Both agents followed the full source chain instead. Read literally,
  the skim misses a sibling whose mention of the new repo lives only in `AGENTS.md`/`README.md`.
  **That is a concrete failing-test design:** a sibling documents an edge to the new repo
  that the new repo's own docs do *not* state. On this fixture the new repo always states its
  own edges, so the literal reading costs nothing.
- **`audit` Step 5** attaches the stack-profile check to the has-a-`CLAUDE.md` branch only.
  **Step 6** runs the path guard on each repo's `CLAUDE.md` but not on its `@import` target or
  on an `AGENTS.md`/`README.md` that holds the conventions.
- **No stated fallback** for Entry points when a manifest names none, or for Role in any case.
  The "never from manifests" rule is written for Purpose alone; agents extend it by analogy.


## Monorepo dogfood results

**Date:** 2026-07-12 (re-run after enriching the fixture: `web` made a genuine TypeScript+Vite
*profiled* component, and a **second** `shared-ui` consumer added — see the fixture-enrichment
note below). **Branch:** `nav-experiment`. Invocation path: **file-based skill
execution** — fresh naive subagents (barred from `expected-monorepo-index.md`,
`grade-monorepo-index.sh`, and `docs/`) read the SKILL.md by absolute path with
`${CLAUDE_PLUGIN_ROOT}` resolved to the plugin checkout, and ran against a copy of the
committed fixture `git init`ed at run time (so the mode-switch sees a real single git
repo). Live NL-triggering remains the separate supervised backlog item, unchanged. All
checks PASS.

- **Check 6 — monorepo mode detected:** the naive bootstrap agent classified
  `/tmp/mono-fixture` as a monorepo (root is one git repo, no independent sub-repos, has
  top-level manifests + `pnpm-workspace.yaml`) and produced the monorepo-variant index.
- **Check 7 — exact component set:** `grade-monorepo-index.sh` on the generated index →
  `MONO INDEX OK`, exit 0. Set is exactly `{web, api, ingest, shared-ui, nested-ws}`:
  `services/ingest`'s two crates rolled up to one; `packages/nested-ws`'s declared
  sub-packages rolled up; `node_modules/leftpad` (on disk, gitignored) excluded by the
  prune step; `packages/` grouping dir and `eslint-config-fix` not components.
- **Check 8 — roles:** web `(application)`, api/ingest `(service)`, shared-ui/nested-ws
  `(shared library)`; `.github/` + `packages/eslint-config-fix` collapsed into the
  `Tooling & root config` note.
- **Check 9 — both-endpoints edges (≥2 consumers):** the naive agent derived **both**
  consumer edges from the manifests — `web` and `nested-ws` each "Consumes `shared-ui`",
  and `shared-ui` says "Consumed by `web` and `nested-ws`". Both edges present on both
  sides; the grader's two awk checks pass.
- **Check 10 — unprofiled marker selectivity:** the naive agent independently matched
  `web` to the `typescript-vite` profile and left its Stack line **plain (no marker)**,
  while emitting the exact `Layer-4 baseline only; Layer-3 profile TODO` phrase on exactly
  the four unprofiled components (`api`, `ingest`, `shared-ui`, `nested-ws`). This proves
  **selectivity in monorepo mode** — a profiled stack stays clean while unprofiled ones are
  marked — from a fresh derivation, not just presence. The grader now asserts both
  directions (mutation-tested: web-wrongly-marked → FAIL, unprofiled-marker-dropped → FAIL).
- **Check 11 — no-manifest candidate:** `docs-site/` listed under `## No-manifest
  candidates`, not as a component.
- **Check 12a — audit negative (monorepo mode):** a fresh naive audit agent, run against a
  copy with shared-ui's back-link to web deleted, flagged the one-sided `web → shared-ui`
  component edge **and** enumerated the 5 on-disk components via `component-detection.md`
  with **no** false "absent from disk" finding — the R2 defect (per-repo `.git`/`CLAUDE.md`
  disk test) is gone. Non-mutating: wrote nothing.
- **Check 12b — safety boundary:** bootstrap wrote `workspace-index.md` at the monorepo
  root as **untracked** (`git status` → `?? workspace-index.md`); it did not `git add` or
  commit it, and the agent's report carried the gitignore-or-commit note.
- **No regression:** the multi-repo grader still returned `INDEX OK` on its workspace at the
  time — multi-repo behavior unchanged.

**Fixture-enrichment note (2026-07-12) — closes the two backlog Minors this fixture carried:**

1. *Marker selectivity in monorepo mode.* History: the Task-3 oracle first marked only
   `api` unprofiled; an earlier dogfood found `web` was then JS+Vite *without* TypeScript,
   so it matched no bundled profile, and the oracle was corrected to mark all five. That
   left the fixture with **no profiled component**, so it could only prove "marker appears
   on an unprofiled stack," not "a profiled stack stays clean" — selectivity in monorepo
   mode was unproven here (only in the v1 origin-workspace dogfood). This pass makes `web` a
   **genuine TypeScript+Vite** component (`package.json` declares `typescript`+`vite`, plus
   a `tsconfig.json` and a `.ts` source) so it truly matches `typescript-vite.md`. `web`'s
   oracle Stack line is now plain (no marker); the four others stay marked. The grader's
   marker check was upgraded from presence-only to **per-component selectivity** and
   mutation-tested (web-wrongly-marked → FAIL; any unprofiled marker dropped → FAIL). The
   naive bootstrap agent reproduced the split from scratch (Check 10 above).

2. *≥2-consumer shared library.* The spec's Validation called for a shared lib with **two**
   consumers; the fixture had one (`web`). `packages/nested-ws` now also depends on
   `shared-ui`, so `shared-ui` has two consumers and the oracle records "Consumed by `web`
   and `nested-ws`". A second both-endpoints grader check (`nested-ws`↔`shared-ui`) was
   added and mutation-tested (drop either side → FAIL).

Both changes are additive to the fixture; the component set `{web, api, ingest, shared-ui,
nested-ws}`, all role tags, the traps, and the no-manifest candidate are unchanged, and the
multi-repo path (`grade-index.sh`, `expected-workspace-index.md`) is byte-untouched.

## v1 hardening — Checks 13–14 (2026-07-12)

- **Check 13 — bootstrap invoked from *inside* a member repo (cwd-inside-repo resolution).**
  Bootstrap Step 1 now resolves the workspace root before classifying. Two fresh naive
  bootstrap agents (barred from the oracles/graders) validated both directions:
  - *Walk-up (positive):* set up a scratch workspace `ws-root/` with a cross-repo
    `CLAUDE.md` and two independent member repos (`repo-a` Go API, `repo-b` Vite+React+TS
    UI), then invoked bootstrap with cwd = `ws-root/repo-a`. The agent detected cwd was
    itself a repo whose parent is a managed workspace root (cross-repo `CLAUDE.md` + sibling
    repos), **walked up one level** to `ws-root`, classified multi-repo, indexed **both**
    repos, wrote the index at `ws-root` only (untracked, nothing inside either member
    touched), and emitted the "invoked from inside member `repo-a`… naming a target
    explicitly would have overridden this" note. `repo-b` matched `typescript-vite` (no
    marker); `repo-a` (Go) got the unprofiled marker — selectivity holds in multi-repo mode.
  - *No walk-up (negative / no-regression):* re-ran the monorepo dogfood (cwd =
    `mono-fixture`). The agent checked cwd's children, found components (not independent
    repos), and correctly **did not** walk up — cwd stood as the monorepo root, `MONO INDEX
    OK`. The cwd-resolution addition does not change monorepo classification when the parent
    is not a managed workspace.
- **Check 14 — F6 sibling-repo skip-with-note fixture.** `tests/fixtures/sibling/sibling.md`
  references absent `ledger-api/…` and `ledger-web/…` paths; `check-doc-paths.sh`
  must **skip these with a note** (exit 0), not fail. Covered by `check-doc-paths.test.sh`
  (`ALL PASS`), which asserts both exit 0 **and** the `skipping sibling-repo ref` note text.
  Mutation-tested: disabling the skip branch turns both refs into `MISSING` → exit 1, so the
  fixture is a load-bearing gate on F6 (previously behavior-only, no committed fixture).

## Mixed mode — dogfood (PLAN 3, 2026-07-13)

Validates mixed-workspace traversal (a multi-repo workspace where one member is itself a
monorepo) via recursive delegation + the authoritative `detect-mode.sh`. Fixtures:
`tests/fixtures/mixed/` (member `plain-api` = plain Java repo; `trap-lib` = single-package
lib, the H1 false-positive trap; `web-monorepo` = a pnpm monorepo of `web`/`admin`/`ui`).
Oracle: `tests/expected-mixed-index.md` + `tests/expected-mixed-web-monorepo.index.md`.
Graders: `grade-detect-mode.sh` (set-equality, extras-check) + `grade-mixed-index.sh`
(cross-file delegation both-endpoints).

**Setup:** `bash tests/stage-fixture.sh tests/fixtures/mixed /tmp/mixdog && git -C /tmp/mixdog init && git add -A && git commit`.
*(Updated 2026-10-14: this originally read `cp -r`. Only a `.git` entry marks a member repo now, and
committed fixtures carry `.member-repo` markers instead, so a hand copy leaves `plain-api`/`trap-lib`/
`web-monorepo` as plain directories and the whole run degrades to a single monorepo. Always stage.)*
Run `wayfinding:bootstrap` from `/tmp/mixdog` (file-based; `${CLAUDE_PLUGIN_ROOT}` = the
plugin checkout). Bootstrap Step 1 calls `detect-mode.sh` (authoritative).

**Result (2026-07-13): ALL PASS — fresh naive subagent, barred from `expected-*`,
`grade-*.sh`, and `expected-sets/`.**

- **Detection:** `detect-mode.sh /tmp/mixdog` → `mode=mixed`, units `monorepo-member
  web-monorepo`, `repo plain-api`, `repo trap-lib`. `grade-detect-mode.sh mixed … mixed` →
  `DETECT OK`. The trap (`trap-lib`, single-package `package.json`, no workspace config)
  correctly stayed a plain `repo`, not a `monorepo-member` (H1 threshold).
- **Delegation (both-endpoints, cross-file):** the naive bootstrap wrote the parent
  `workspace-index.md` (three H2s; `web-monorepo` tagged `(monorepo member)` with the
  boundary marker "this member owns its own components; the parent's scope ends here" + a
  delegation pointer) AND `web-monorepo.index.md` **host-at-root** (member index, written
  *before* the parent pointer — M4), listing `web`/`admin` (application) + `ui` (shared
  library) with the `ui` edge on both endpoints. `grade-mixed-index.sh` → `MIXED INDEX OK`.
- **Recursion:** exercised at one level (parent → member monorepo). Deeper nesting is
  designed-supported, bounded (§4), tested at one level.
- **Safety boundary (D3 host-at-root posture):** the member index was written **host-at-root**
  (`/tmp/mixdog/web-monorepo.index.md`), **never** in-place inside `web-monorepo/`; the naive
  agent ran **no** `git add`/commit (`git status` → both indexes untracked); it added the
  gitignore note. No consent prompt.
- **No regression:** `grade-detect-mode.sh` green on the existing monorepo + multirepo
  fixtures (multi-repo byte-for-oracle unchanged); `check-doc-paths.test.sh` `ALL PASS`;
  `detect-mode-safety.test.sh` `SAFETY OK`; payload guards (`references`, `skills`) exit 0.

---

## Sub-project 2 — onboard-a-component (PLAN 4, 2026-07-25)

**Method:** six FRESH naive subagents, one per check, each confined to its own seeded scratch
workspace and **barred from reading anything under `wayfinding/tests/`** (the oracles,
`expected-sets/`, every `grade-*.sh`, and `make-before-index.sh` are the answer key). None was
allowed to spawn sub-agents. Grading was done afterwards by the dispatcher, never by the agents.

**Why six workspaces and not one:** running several checks against a single tree makes the
heading-delta and `noop` assertions meaningless (a later check inherits an earlier one's writes),
and mixing the strip-and-restore run with the overlay run in one tree produces a two-candidate
ambiguity that neither gate is testing. A/C carry the base fixture only; B/D carry the overlay.

| Check | Workspace | Task given to the agent | Result |
|---|---|---|---|
| A | monorepo, base | "Onboard the `nested-ws` component." | `gate1` OK · `headings +1` OK · `MONO INDEX OK` |
| B | monorepo + overlay | "Onboard the `billing` component." | `gate1` OK · `headings +1` OK · `edge billing↔shared-ui` OK · `edge billing↔left-pad --absent` OK · `MONO INDEX OK` (6-component set) |
| C | mixed, base | "Onboard the `ui` component into the `web-monorepo` member." | `gate1` OK · `headings +1` OK · `MIXED INDEX OK` |
| D | mixed + overlay | "Onboard the `reporting` component into the `web-monorepo` member." | `gate1` OK · `headings +1` OK · `edge reporting↔ui` OK · `edge reporting↔admin --absent` OK · `MIXED INDEX OK` (4-component set incl. the parent shallow list) |
| E | monorepo, base | "Onboard `docs-site`." (a `no-manifest-candidate`) | `headings +0` OK — no component H2 minted; note-section entry gained the remediation sentence |
| F | monorepo, base | "Onboard the `shared-ui` component." (already indexed) | `noop` OK — stopped, wrote zero bytes |

**Boundary:** `git status --porcelain` in all six workspaces shows only untracked (`??`) index
files. Nothing was `git add`ed or committed. C and D each wrote exactly two files (member index,
then parent) in the binding order; A, B, E wrote one; F wrote none.

**What the checks actually proved, beyond "it ran":**

- **B** proved the D4 resolution rule works in both directions on evidence the docs never state:
  the agent read `apps/billing/package.json`, took `shared-ui: workspace:*` as an edge, **dropped
  `left-pad: ^1.3.0`** as a registry range, and found the *reverse* edge by reading
  `packages/shared-ui/package.json`'s `devDependencies` — the half no fixture would have exercised
  without the overlay's overwriting manifest.
- **D** proved name resolution is by declared manifest name, not basename: it resolved the scoped
  `@acme/ui` to the `ui` component, and **rejected `admin: ^2.0.0`** even though `admin` is a real
  sibling component — the registry-collision trap. It also found `web`'s manifest dependency on
  `@acme/reporting` and back-linked `web`, an edge neither component's prose documents.
- **E** proved the non-set-changing veto: the graded component set was untouched and the index's
  `^## ` count did not move.
- **F** proved the fail-closed stop table fires before anything is written.

**Unprompted finding from the agents (worth keeping):** both C and D independently flagged that the
seeded index files contain trailing "Notes for graders" prose asserting they are "hand-authored
ground truth… not to be overwritten by `bootstrap`/`onboard`" — text that contradicts the task they
were given. Both treated it as untrusted *data* carried in from the test oracles rather than as an
instruction overriding the skill, and both said so explicitly, one noting it "reads exactly like a
prompt-injection test embedded in a data file." That is the desired behaviour, and it was not
prompted for.

**Skill feedback the agents volunteered (no code change made; recorded for a future pass):** the
`Purpose` and `Entry points` fields have no stated fallback when a component ships no prose at all
and no declared entry surface — three agents independently had to make a judgment call there, and
each said so rather than inventing detail.

### Added after the final whole-branch review — the two remaining Gate-4 negatives

The final review found Gate 4 had shipped 2 of its 6 specified negative cases. Two of the four
missing ones were grader-testable and were built (`--no-shallow-list`, marker selectivity, and a
new `gate1-parent` containment mode); the other two are agent-behaviour stops and are dogfooded
here, same rules as A–F (fresh agents, barred from `tests/`, own workspace).

| Check | Workspace | Task given to the agent | Result |
|---|---|---|---|
| G | monorepo, base, index already complete | "Onboard the new component." (no target named, nothing un-indexed) | `noop` OK — stopped with "nothing to onboard", wrote zero bytes |
| H | mixed + overlay, **both** index locations present | "Onboard the `reporting` component into the `web-monorepo` member." | `gate1` OK · `headings +1` OK · `gate1-parent` OK · `MIXED INDEX OK` · stale duplicate left byte-identical and **not deleted** |

**H is the one that mattered.** Both `<root>/web-monorepo.index.md` and
`web-monorepo/workspace-index.md` existed, byte-identical. The agent resolved which was
authoritative from the parent's delegation pointer — exactly the rule `audit` and `bootstrap`
already share — wrote the host-at-root file, and left the in-place copy untouched while reporting
it as a stale duplicate. An earlier draft of this design would have made onboard stop dead here;
adopting the siblings' rule is what lets it proceed correctly.

**Two pre-existing inconsistencies the agents surfaced unprompted** (neither in scope for onboard,
both correctly left alone and reported):
- `apps/admin/package.json` declares `"ui": "workspace:*"` unscoped while `packages/ui`'s manifest
  name is `@acme/ui`, so under the strict declared-name resolution rule that dependency resolves to
  nothing — yet the index records the `admin ↔ ui` edge anyway. Reconciling that is `audit`'s job.
- The member index's `## No-manifest candidates` note names the fixture's real-code dirs and is now
  stale (it omits `reporting`), though its conclusion — "(none)" — remains true. onboard is not
  authorised to refresh note prose outside the Step 4a path, so it was left and flagged.

---

## RED baseline — the Iron Law's missing half (2026-07-26)

**Why this exists.** An audit on 2026-07-26 found all three `SKILL.md` files were written and
repeatedly edited across four plans **without ever consulting `superpowers:writing-skills` or
Anthropic's `anthropic-best-practices.md`**. Everything above this line is GREEN evidence — agents
complying *with* the skill, graded against frozen oracles. Nobody had ever watched an agent attempt
these tasks *without* it, so the skill's marginal value over baseline was unestablished. That is the
RED half of the Iron Law, and this section is it. Scope: **`onboard` only** — `bootstrap` and
`audit` still have no baseline.

**Method.** Eight fresh agents, four checks (A, B, D, F — the diagnostic subset) × two arms, one
agent per workspace, seeded by the same recipe as A–H above.

- **Arm 1 (pure RED):** the workspace and the goal. Nothing else. Explicitly barred from all of
  `wayfinding`.
- **Arm 2 (references-only):** additionally allowed `references/**` and `scripts/detect-mode.sh` —
  but **not** `skills/`. This arm is what separates the skill's marginal value from the
  *references'*; without it, a RED failure cannot distinguish "the procedure matters" from "they
  just didn't know the format."

Both arms barred from `tests/`; none allowed to spawn sub-agents; graded afterwards by the
controller on the identical gates GREEN passed.

**Task wording.** The GREEN instruction ("Onboard the `X` component") was de-jargoned to "Add the
`X` component to this workspace's navigation index" — *onboard* is skill vocabulary an unskilled
agent has no referent for. Critically the replacement asserts **nothing about current state**, so
check F's already-indexed trap stays live exactly as it was in GREEN.

| Check | Gate | Arm 1 | Arm 2 | GREEN |
|---|---|---|---|---|
| A `nested-ws` | `gate1` / `headings` / `MONO INDEX` | ❌ / ✅ / ✅ | ❌ / ✅ / ✅ | all ✅ |
| B `billing` | `gate1` / `headings` / 2× `edge` / `MONO INDEX` | ❌ / ✅ / ✅✅ / ✅ | ✅ / ✅ / ✅✅ / ✅ | all ✅ |
| D `reporting` | `gate1` / `headings` / `gate1-parent` / 2× `edge` / `MIXED INDEX` | ❌ / ✅ / ❌ / ✅✅ / ❌ | ❌ / ✅ / ❌ / ✅✅ / ✅ | all ✅ |
| F `shared-ui` | `noop` | ✅ | ✅ | ✅ |
| **Fully passing** | | **1 / 4** | **2 / 4** | **4 / 4** |

Boundary clean in all eight: index files untracked, nothing `git add`ed or committed.

### Every RED failure but one is the same defect: containment

Five of six failures are agents rewriting prose **outside the allowed change set** — the summary
blockquote, `ui`'s Purpose, the No-manifest note, the parent's Purpose and Stack lines. None of it
is factually wrong; some is better prose than the oracle's. It simply isn't theirs to touch.
`gate1`/`gate1-parent` is the only discipline no agent exhibits unprompted.

The sixth failure is arm 1's D tagging `reporting` `(application)`. That belongs to
**`references/component-detection.md`, not `SKILL.md`** — arm 2 held the ordered role rule and got
`(service)`. Arm 1 did not *miss* the right label; it considered and rejected it:

> "Inventing a fourth term such as `(service)` — more descriptive of what `reporting` actually is,
> but the shallow list appears to be a controlled enumeration; introducing an unseen term risks
> breaking whatever consumes it."

It inferred the taxonomy was closed at the three terms **visible in the mixed fixture** — a sound
inference that fails only because that fixture contains no service. Keep that reference intact
through extraction.

### What the skill does NOT add — reproduced unprompted, both arms

- **Both-endpoints reciprocity** — all 8. Derived from the artifact by A1: *"`web` says 'Consumes
  `shared-ui`'; `shared-ui` says 'Consumed by `web`'. This is why I also edited the `shared-ui`
  entry."* This is the skill's stated thesis, and it is the one thing nobody needed telling.
- **The D4 edge rule, both directions** — B1/B2 accepted `shared-ui: workspace:*`, rejected
  `left-pad: ^1.3.0` as a registry range, found the reverse `shared-ui → billing` devDependency by
  reading the *other* manifest, and rejected the `node_modules/leftpad` decoy on two independent
  grounds.
- **Declared-name resolution + the registry-collision trap** — D1 and D2 both resolved scoped
  `@acme/ui` → `ui` and both rejected `admin: ^2.0.0`, each finding a second disqualifier the
  skill's own rule does not state: `apps/admin` declares no `version`, so `^2.0.0` cannot resolve
  locally regardless of pnpm's `link-workspace-packages`. D1 also reasoned about blast radius —
  recording it *"would have obliged me to write 'Consumed by `reporting`' onto `admin`'s entry — a
  second, load-bearing falsehood in a different section."*
- **The fail-closed stop** — both F arms wrote zero bytes. F1: *"Appending a second `## shared-ui`
  section would have produced a duplicate heading and a self-contradicting index."*
- **Mixed-mode structure** — both D arms wrote member-then-parent in the binding order, extended the
  parent's `Shallow list:` preserving the verbatim prefix, checked the ~15 soft cap, and correctly
  declined to mint a `## reporting` H2 in the parent.
- **Nested-workspace roll-up, unprofiled-marker selectivity** (exact phrase, correctly selective),
  **the write boundary**, and **prompt-injection resistance** — D2 flagged the oracles' "must not be
  overwritten" prose, reasoned about it explicitly, and proceeded.

### The organising principle

**Anything a static index demonstrates by example, agents learn from the example. Anything about the
*process of changing* it cannot be demonstrated by a static document at all** — and that is where
every RED failure landed. Containment is a property of a *diff*; no index, however good, can teach
it. The role-tag failure is the same principle from the other side: where the artifact
under-determines the answer, agents reason carefully and still land wrong, and a reference closes it.

### Scope limits (do not over-read this result)

- **`onboard` only.** 464 of the 1,314 `SKILL.md` lines. `bootstrap` (461) and `audit` (389) have no
  baseline. **Running RED for `bootstrap` is the real remaining gap.**
- **These agents had a crutch a cold-start user does not:** a complete, internally consistent index
  already in the target format. Nearly every convention they "inferred unprompted" was inferred by
  copying neighbours. That is fair to `onboard`, whose premise *is* an existing index — but **none
  of it generalizes to `bootstrap`**, which has no such teacher.
- **Grader note (minor, not a live defect):** `edge --absent` is token-exact. D1 passed it while
  writing `admin@^2.0.0` on the links line; an agent *claiming* the edge in that form would also
  pass.

---

## Containment gate — a pre-registered RED that came back negative (2026-07-26)

The RED baseline above prompted a proposed edit: the skill's containment rules are written over
**fields** and **sections** (*"No other field of any existing section was altered"*, *"Nothing else
in the parent may change"*), and the index's summary blockquote is neither — yet that is where 4 of
the 6 containment failures landed. The hypothesis was that GREEN passed `gate1` by *inferring* the
general principle rather than following a stated rule, i.e. a fragile pass.

**The Iron Law applies to edits, not just new skills** (`superpowers:writing-skills`: *"Edit skill
without testing? Same violation... Not for 'just adding a section'"*). The RED baseline is a failing
test for *the skill's absence*, **not** for this edit — GREEN passed `gate1` 8/8 with the current
skill, on fixtures already carrying the tempting prose. So the edit required its own failing test.

**Pre-registered decision rule, fixed before running:** 5/5 contain → no failing test → **no edit**.
Any rep breaks → RED, and author as a *contract on the diff's shape*, never a prohibition.

**Test design.** Five reps of check D (mixed + overlay) against the **current** `SKILL.md`, with the
competing incentive amplified to its strongest realistic form — the member index seeded so the
addition falsifies **three separate claims at once**: the blockquote's `"a pnpm monorepo of exactly
three components"`, `ui`'s `"shared by both apps"`, and the notes' `"applied to the three
components"`. Agents barred from `tests/`, no sub-agents.

**Result: 5/5 contained.** `gate1`, `headings +1`, and `gate1-parent` OK in every rep; **3/3
falsified claims left intact in all five**; boundary clean everywhere. Zero cross-rep variance —
the convergence `writing-skills` names as the signal that wording is binding.

**Disposition: NO EDIT.** The fragility hypothesis is falsified. The containment rule holds under
deliberately amplified pressure without ever naming the blockquote. Recorded here so it is not
re-derived: *someone will notice this gap again and propose the same edit; it was tested and
rejected.*

**Why the form would have mattered had it broken.** `writing-skills`' "Match the Form to the
Failure" classifies this as a **shaping** failure (output has the wrong diff shape), not a
discipline failure — the RED agents did not know the rule and skip it, they reasoned from a
competing principle in good faith. D1 stated it outright: *"My edit was only complete if it didn't
leave the file asserting things that had just become false."* For shaping failures under a competing
incentive, prohibitions measurably backfire — *"the prohibition arm produced clearly more of the
unwanted content than the recipe arm... and trended worse than even the no-guidance control."* So
"never touch the blockquote" was the predicted-to-backfire form, and enumerating protected regions
would have been the wrong fix regardless: agents would re-derive the same principle for whatever
region the list forgot.

**Net, measured in both directions on one instrument:**

| Arm | Containment (`gate1` / `gate1-parent`) |
|---|---|
| No skill, no refs | fails 3 of 3 applicable checks |
| Refs, no skill | fails 2 of 3 |
| **Current skill, amplified pressure** | **passes 5 of 5** |

---

## RED baseline — `bootstrap` (2026-07-26)

`onboard`'s RED above does **not** generalize: those agents were handed a complete, internally
consistent index and inferred most conventions by copying neighbours. `bootstrap` creates an index
from nothing and has no such teacher, so it needed its own baseline. This is it.

**Method.** Six fresh agents, three modes × two arms, one agent per workspace, barred from
`tests/`, none allowed sub-agents, graded afterwards by the controller.

- **Arm 1 (pure):** the workspace and the goal. Barred from all of `wayfinding`.
- **Arm 2 (references-only):** additionally `references/**` and `scripts/detect-mode.sh` — **no
  `skills/`**. This arm is what separates the SKILL's value from the REFERENCES'.

Multi-repo used a thin scratch copy of the real workspace (both repos' `CLAUDE.md` + manifests), so
the existing `grade-index.sh` applies unchanged. Monorepo and mixed used the committed fixtures.
Task wording stated only the goal — "a single Markdown document, at the workspace root, that an
agent unfamiliar with this codebase should read first" — naming no field, tag, filename or rule, so
the format itself is what was under test.

| | Multi-repo | Monorepo | Mixed | Total |
|---|---|---|---|---|
| **Arm 1 — pure** | `INDEX FAILED` | `MONO INDEX FAILED` | `MIXED INDEX FAILED` | **0 / 3** |
| **Arm 2 — references, no `SKILL.md`** | `INDEX OK` | `MONO INDEX OK` | `MIXED INDEX FAILED` | **2 / 3** |

Safety boundary clean in all six: every generated file untracked, nothing `git add`ed or committed.

### Arm 1 didn't fail the contract — it never found it

All three pure agents wrote **`NAVIGATION.md`**, not `workspace-index.md`. By the plugin's contract
no index exists at all: `audit` and `onboard` both locate the index by filename and parse the field
labels, so this output is invisible to the rest of the plugin. Zero field labels, zero role tags,
zero markers, no tooling/no-manifest notes, no delegation. All three built the document out of
directory trees and per-file paths — inverting the staleness principle Layer 1 exists to enforce —
and M1/N1 additionally hauled Layer-2 rules wholesale into the index (M1: *"§3 is the longest
section and substantially restates the guides. An index arguably should route, not contain."*).

**The arm-1 documents are genuinely good.** M1's is arguably a better human onboarding doc than the
oracle: it led with "this checkout contains no application source code", catalogued every documented
path that doesn't exist, and caught that the workspace `CLAUDE.md` claims two separate git repos
where there is one. X1 caught the `trap-lib` false-positive trap unprompted and refused to flatten
the member's components ("their names are only unique *within* that workspace").

They are simply **not interoperable**, and each agent picked its own filename — X1 said so outright:
*"`NAVIGATION.md` vs `INDEX.md` vs `README.md`… Genuinely arbitrary."* That is the answer to what
`bootstrap` adds: baseline agents each write a good document; the plugin's value is that they all
write the **same** one.

### Arm 2 reproduced the contract from `references/` alone

Including, in X2, the whole of mixed mode: recursive delegation, host-at-root filename, the verbatim
`Shallow list:` prefix, the boundary marker, the backtick-prose pointer (not a link), and the
correct location choice for a parent-scoped run. That is the most intricate behaviour in the plugin,
and a reference doc carried it with no procedure attached.

### The two seams where `SKILL.md` is load-bearing

**1. Profile matching — a measured failure.** X2's *only* miss was marker selectivity: it credited
`typescript-vite` on `"dev": "vite"` alone, but the mixed fixture's `web`/`admin` declare **no
TypeScript**, so all three components are unprofiled and the oracle carries 3 markers. Where the
rule lives:

- `references/stack-profile-format.md` says **nothing** about matching (grep for "match" is empty).
- `skills/bootstrap/SKILL.md` Step 4 states it: *"match on language/build-tool, e.g. … 'TypeScript
  + Vite' against `stack-profiles/typescript-vite.md`."*

So the document the unprofiled marker *points at* as "the contract a new profile would need to
satisfy" teaches how to **author** a profile, not how to decide one **applies**. Real seam, and it
produced an actual graded failure. **NOT ACTED ON:** n=1 is one agent's judgement call, and
`superpowers:writing-skills` is explicit that single samples lie (5+ reps against a no-guidance
control). Recorded for a future pass; confirm with reps before changing a shipped reference.

**2. The output filename — no failing test.** N2 and M2 independently ranked this their single
biggest uncertainty (M2: *"Nothing in my permitted references specifies it for multi-repo mode. I
inferred `workspace-index.md` from the mixed variant's in-place form."*). It is named in
`layer1-index-format.md` only in passing, inside the *mixed* variant. Both guessed right, so there
is **no RED** and nothing was authored — recorded only.

### Net, across both skills

`onboard`'s RED showed its procedural prose largely restates what agents do unprompted.
`bootstrap`'s shows the opposite about the *package* — without `references/` there is no index at
all — while locating the load in `references/`, not in the 461 lines of `SKILL.md`, which
contributes the filename, the matching rule, and the write posture. Both point the trim at
`SKILL.md` prose and confirm `references/` must travel intact through extraction.

**Still unmeasured:** `audit` (389 lines) has no baseline.

## Declared-member gate — Checks 15–19 (2026-07-26)

Adds `tests/detect-mode-declared.test.sh` to the mechanical suite: five fixtures under
`tests/fixtures/declared/`, graded by the existing `grade-detect-mode.sh` against
`expected-sets/declared-*.set`. Closes findings **F3/F4/F5**
(the OSS reconnaissance findings → *Resolution*); **F1 and F2 remain open**.

```bash
bash tests/detect-mode-declared.test.sh      # -> DECLARED OK
```

- **Check 15 — `go-workspace`** (mirrors prometheus/prometheus): block-form `use ( . … )`
  parses; all declared members emit at their declared depth; a code-shipping root emits
  `root-component .`; **zero** `no-manifest-candidate` lines where the pre-fix script emitted
  four (eighteen on the real repo).
- **Check 16 — `pnpm-negation`** (mirrors vercel/turborepo): `!packages/turbo` is subtracted
  even though the dir carries a valid manifest and the additive scan finds it. `docs/*`
  entries are real components, not doc dirs.
- **Check 17 — `root-ships-code`** (mirrors grafana/grafana): root `go.mod` with **no** `.`
  declaration still yields `root-component .`, and `pkg/` is not a phantom candidate.
- **Check 18 — `negation-substring`**: `!packages/turbo` must NOT suppress
  `packages/turbo-extra`. Guards this project's dominant defect class (substring vs.
  whole-token, six occurrences to date).
- **Check 19 — `go-single-line`**: single-line `use ./x`, one member three levels deep so
  only the declared reader can reach it; root ships no code, so the legitimate
  `no-manifest-candidate internal` must survive (negative case — the F5 fix must not
  over-fire).

**Regression posture.** All five were verified RED against `git show HEAD:scripts/detect-mode.sh`
before the fix. The three frozen oracles (multirepo / monorepo / mixed) were diffed
byte-for-byte against a pre-change baseline capture, not merely re-graded — the binding
guardrail is that multi-repo behaviour stays byte-for-oracle unchanged, and it does.

**Not covered by any fixture (known, deliberate):** F2's dead end — a `monorepo-member` that
returns `mode=ambiguous` on its own run. It survives this fix untouched: alertmanager declares
no workspace, so its promotion comes from the glob fallback, not the declared set. That was a
registered prediction (C1) and it was falsified; see the scorecard in the findings doc.

## Checks 20–21 — onboard sibling skim and doc precedence (2026-10-14)

Fixtures `tests/fixtures/onboard-skim/` (seed `tests/seeds/onboard-skim.md`) and
`tests/fixtures/doc-precedence/`. Their graders are proven able to fail by
`tests/agent-checks.test.sh` (in `run-all.sh`) before any agent ran.

- **Check 20 — onboard sibling skim.** The new repo `pager-svc` names no sibling. `hub-svc`
  documents its edge to it only in `AGENTS.md`, and `feed-svc` only in `README.md`. Neither
  has a `CLAUDE.md`, so onboard Step 2's literal rule ("read each existing repo's root
  `CLAUDE.md` only") reads nothing and misses both edges. Graded by gate1
  (`component=pager-svc`, `touched=hub-svc feed-svc`) plus structural reciprocity.
- **Check 21 — doc precedence.** `tide-svc`'s `CLAUDE.md` names entry point `tidewater` and
  its `README.md` names `ebbtide`. Both are current, and neither marks itself stale.
  `grade-doc-precedence.sh` enforces bootstrap Step 3: naming exactly one is a coin toss and
  FAILS; naming both or neither PASSES only with the conflict stated.

**Pre-registered decision rule:** a skill edit only if at least one of 3 clean reps fails;
otherwise NO EDIT. This follows the containment-gate precedent above.

### Result: 6/6 PASS in clean-room runs → NO EDIT for either

| Check | Rep 1 | Rep 2 | Rep 3 |
|---|---|---|---|
| 20 skim | gate1 OK · structure OK | gate1 OK · structure OK | gate1 OK · structure OK |
| 21 precedence | conflict stated, both named | conflict stated, both named | conflict stated, both named |

No session changed any file other than `workspace-index.md`, checked with `find -newer`.
Prediction P1 ("at least one rep coin-tosses toward `CLAUDE.md`, since tier order reads like
precedence order") was **falsified**: no clean session treated chain order as a tiebreak.

**The nuance the decision rule does not capture: the skim passes by OVERRIDING the skill.**
All three clean skim sessions, and every one of the five contaminated and Check 2/3 onboard
agents before them, independently reported that the literal "root `CLAUDE.md` only" rule
"reads nothing and misses both links", and deliberately read the first source-chain tier
with content instead. The *output* is correct. The *instruction* is wrong for any repo
without a `CLAUDE.md`, and a more literal-minded agent would follow it into the miss. Under
the pre-registered rule this is NO EDIT. Whether "every agent must disobey this sentence to
pass" should count as RED is a judgment left to the maintainer, not reopened after the
results.

### Method: subagents could not be isolated; headless sessions could

The first round used subagents spawned from this session. **All six were contaminated, and
all six said so:** their starting context held this repo's `CLAUDE.md`, whose next-up list
described both test designs, plus a **git-status snapshot naming the untracked fixtures and
graders**. Moving `CLAUDE.md` off disk changed nothing. Subagents receive the copy loaded
**when the parent session started**: one agent quoted an item that had already been deleted
from the file. That round passed 6/6 too, but it is recorded as contaminated and not counted.

The clean round used **headless `claude -p` sessions started with the staged workspace as
cwd**: `--allowedTools "Read Glob Grep Write Edit Bash"`, `--add-dir` for only `skills/`,
`references/` and `scripts/`, and `--no-session-persistence`. The Agent tool was not allowed,
so they could not spawn sub-agents. **The isolation was verified before the run** with a
no-tools probe session asked to report its starting context. It held only the fixture's own
`CLAUDE.md`, no memory, no git status, and none of the test vocabulary. "wayfinding"
appeared only inside directory paths. `--bare` would be stricter still (no hooks, no
auto-memory), but it requires an API key.

## Bootstrap trim — regression in all three modes (2026-10-14)

`skills/bootstrap/SKILL.md` went from **536 to 377 lines**. Every monorepo- and mixed-only
block moved verbatim to `references/bootstrap-monorepo-mixed.md`, which Step 1 loads only when
`detect-mode.sh` reports `mode=monorepo` or `mode=mixed`. Step 0 no longer reads
`component-detection.md` unconditionally. The **Safety boundary and Common mistakes stay in
SKILL.md on purpose**, including their mixed-mode write rules: write-safety must never depend on
a conditional load. The earlier "~60% inert" estimate measured at **~30%**.

**Instruments.**
- `tests/skill-shape.test.sh` (in `run-all.sh`) was watched RED on the pre-trim file. It covers:
  no mode-specific paragraphs inline, both routes loading the reference, Step 0 not reading
  `component-detection.md`, and the Safety boundary still stating host-at-root, in-place and
  `git add`.
- **A one-time conservation check:** every non-blank line removed from SKILL.md appears verbatim
  in the reference. The 23 exceptions are exactly the deliberate edits: re-aimed "above/below"
  pointers, a renamed heading, the Step 0.2 rewrite, and the remediation sentence gaining
  `build.gradle.kts`. That sentence was updated identically in onboard, so both skills still
  write the same text.

**Clean-room regression** (headless `claude -p` from each staged workspace, as in Checks 20–21):

| Mode | Result | Read the new reference? |
|---|---|---|
| multi-repo (layer2-chain) | `MULTIREPO INDEX OK` · `LAYER2 OK` | **No**, correctly: *"I skipped `bootstrap-monorepo-mixed.md` because it's only needed for monorepo or mixed mode."* |
| monorepo | `MONO INDEX OK` | yes |
| mixed, rep 1 | `MIXED INDEX OK`; member index written **before** the parent (timestamps) | yes |
| mixed, rep 2 | `MIXED INDEX OK`; member before parent | yes |

The write boundary held in all four: nothing in-place, nothing outside the generated indexes.

**The first mixed round FAILED, and the cause was the dispatcher's prompt, not the trim.** Its
hard constraint said "do not create any file except `workspace-index.md`". Mixed mode
legitimately writes a second file, `<root>/<member>.index.md`. Both sessions noticed the
conflict, obeyed the prompt over the skill, and said so. The fix was to allow "the index
file(s) the skill itself tells you to write at the workspace root", without naming the member
file, which would leak the answer. **Lesson:** a boundary written for one mode can forbid
another mode's correct behaviour. Write the prompt's boundary in the skill's own terms.

**Found by those two sessions, recorded, not fixed:** `layer1-index-format.md` calls a pointer
to a not-yet-populated member index *valid*, while bootstrap's Common mistakes calls a pointer
written before its member index *a dangling reference, not a valid "not yet populated" note*.
In a normal run the two never collide, because bootstrap always writes the member index first.
They give opposite instructions only when the member index cannot be written. One session wrote
the pointer and the other omitted it.

**Instrument limitation noticed:** `grade-monorepo-index.sh` hardcodes the monorepo fixture's
roles, edges and candidate beyond its set argument, so it cannot grade any other monorepo (for
example a mixed member index). `grade-mixed-index.sh` validates the member index instead.

## Onboard skim reworded — verified clean-room (2026-10-14)

The maintainer ruled that "every agent must disobey this sentence to pass" counts as a
defect, so onboard Step 2's sibling skim was rewritten as a positive recipe. For each
existing repo, read the **first Layer-2 source it actually has** (its `CLAUDE.md`, plus the
import when that file is a redirect, else `AGENTS.md`, else `README.md`). The cost guarantee
is unchanged: one read per existing repo.

**Evidence the old wording was defective, and that the new wording fixes it:**

| | Agents passing Check 20 | Agents reporting they had to deviate from the skim wording |
|---|---|---|
| Before: all onboard runs on 2026-10-14, contaminated and clean | 8/8 | **8/8** |
| After: 3 clean skim reps + 1 Check 2 (hub) regression | 4/4 (gate1, structure, layer-2) | **0/4** |

That result was predicted and registered before the run. No session wrote outside the index.
Remaining judgment calls the agents raised are small and recurring, and none affected a
grade: replacing versus appending to a "None recorded yet." placeholder; where to place the
new section (end of file versus flow order); how far Role may lean on sibling docs; and a
blockquote that drifts stale. Every run correctly left that last one to `audit`.
