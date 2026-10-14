---
name: audit
description: Use when health-checking an existing nav setup — repos missing from the index, one-sided cross-repo edges, repos lacking a CLAUDE.md or Layer-3 stack profile, dead file refs in the Layer-1 index, and (mixed workspaces) one-sided cross-file delegation between a parent index and a monorepo-member's own index. Non-mutating: produces a report only. For first-time setup, use bootstrap (whole workspace) or onboard (one repo).
---

# audit

Health-check an **existing** `workspace-index.md` against the repos it describes, and
produce a gap report. Read this whole skill before doing anything — the point of `audit`
is to *find* drift, not describe a healthy-looking index. A report that doesn't flag a
one-sided edge, a dead link, or a one-sided delegation when one is actually there is a
failed audit, not a clean one.

## Safety boundary (read first — non-negotiable)

`audit` is **non-mutating** — not the same claim as "read-only." It:

- **Never writes, edits, `git add`s, or commits anything** — not `workspace-index.md`,
  not a member's own `<member>.index.md`, not a report file, not any repo's `CLAUDE.md`,
  regardless of how obvious or small the fix looks. Every finding below is *reported*,
  never patched. If a fix is warranted, that's a separate, human-gated follow-up
  (possibly `onboard` or `bootstrap`, run deliberately afterward) — not something this
  skill does inline. This includes a **stale duplicate** member index file (Step 4) — it
  is named in the report, never deleted.
- **Its one permitted side effect is executing the bundled
  `${CLAUDE_PLUGIN_ROOT}/scripts/check-doc-paths.sh`.** That script itself only reads —
  it walks `.md` files and checks that linked paths exist — but *running a script* is a
  real action, not nothing, so don't describe this skill as "read-only." Call it what it
  is: **non-mutating, runs a bundled script.** The script takes no user-supplied
  arguments beyond a nav-doc file path this skill derives itself (the workspace index,
  each member repo's `CLAUDE.md`, and — in mixed mode — each resolved monorepo-member's
  own index file — see Step 6) — never pass raw user text into it, and never point it at
  the whole workspace root or at `${CLAUDE_PLUGIN_ROOT}`.
- **Default output is a printed report**, not a file. Do not write the report to disk
  unless the user has explicitly asked for a saved copy in this invocation.

If you find yourself about to `Write` or `Edit` anything, or about to run
`check-doc-paths.sh` against anything other than the index file, a member repo's
`CLAUDE.md`, or (mixed mode) a resolved monorepo-member's own index file (see Step 6) —
e.g. the whole workspace root, or `${CLAUDE_PLUGIN_ROOT}` — stop, that's out of scope for
this skill.
- This boundary is shape-independent: it holds identically whether the index under audit
  is a multi-repo index, a monorepo (component) index, or a mixed workspace (a delegating
  parent index plus one or more members' own component indexes).

## Step 0 — read the shared references

Read, in this order, using `${CLAUDE_PLUGIN_ROOT}` (never `../..` — the plugin may be
installed anywhere; only paths rooted at `${CLAUDE_PLUGIN_ROOT}` are guaranteed to
resolve):

1. `${CLAUDE_PLUGIN_ROOT}/references/methodology.md` — the 4-layer model, so you know
   what each layer of drift you're checking actually means.
2. `${CLAUDE_PLUGIN_ROOT}/references/layer1-index-format.md` — the exact contract
   `workspace-index.md` must satisfy: the five required fields per repo, and — the rule
   this skill exists to enforce — the **both-endpoints rule**: if repo A's Cross-repo
   links says "calls B," repo B's Cross-repo links must say "called by A." A one-sided
   edge is a defect, full stop. Also read the **Mixed variant**: a `monorepo-member`'s
   Role gains the `(monorepo member)` tag, its **Components** field carries a
   **delegation pointer** to the member's own component index (host-at-root
   `<member>.index.md`, or in-place `<member>/workspace-index.md`) plus an explicit
   **boundary marker** ("this member owns its own components; the parent's scope ends
   here") — you'll need this exact shape to validate delegation in Step 4. Also note the
   capabilities-not-paths rule and the `check-doc-paths.sh` exemptions (URLs, `~`-paths,
   `/UPPER/PLACEHOLDER/` examples, `#anchor`s) — you'll need to distinguish a genuine
   dead ref from a benign exemption when reading the guard's output in Step 6.
3. List `${CLAUDE_PLUGIN_ROOT}/references/stack-profiles/` and skim each file's
   `verified:` header and "Languages/build tool" section, so you know which stacks are
   profiled going into Step 5.
4. `${CLAUDE_PLUGIN_ROOT}/references/component-detection.md` — explains *why*
   `${CLAUDE_PLUGIN_ROOT}/scripts/detect-mode.sh` enumerates components the way it does.
   Relevant whenever Step 1's script run reports `mode=monorepo`, or emits any
   `monorepo-member` unit (mixed mode).

**`${CLAUDE_PLUGIN_ROOT}/scripts/detect-mode.sh` is the mechanical authority for
on-disk enumeration** — not an ad-hoc `.git`/`CLAUDE.md` eyeball test. Every "on disk vs.
in the index" comparison below (Step 2) is against *this script's* output (`mode=`,
`root=`, and `unit <shape> <relpath>` lines) — the same script `bootstrap` and `onboard`
run. `audit` never re-derives membership or shape by hand.

## Step 1 — run `detect-mode.sh`, then locate the index(es)

The workspace root is the current working directory (the directory containing member
repos as subdirectories), unless the user names a different one explicitly. Run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/detect-mode.sh <workspace-root-or-target>
```

Treat every line of the output as fact — `mode=`, `root=`, and `unit <shape> <relpath>` —
exactly as `bootstrap` does. **Route on `mode=`:**

- **`mode=ambiguous`** — the script couldn't decide mechanically. Stop and say so; that's
  not a gap to report, it's a precondition audit can't proceed past. Do not guess.
- **`mode=plain-repo`** — a confident classification: one unit, nothing to route between.
  **Check for an existing `<root>/workspace-index.md` before you stop.** If none exists, say
  there is nothing to audit — a single repo has no Layer-1 index by design. If one *does*
  exist, this root was previously indexed as a monorepo and has since been reclassified:
  **report that as a classification-change finding** ("previously indexed as a monorepo; now
  classifies as plain-repo — its component sections no longer correspond to detected units"),
  and stop. That is a real audit finding, not a clean no-op. Never delete the index yourself.
- **`mode=multi-repo`** — every unit is a plain `repo`. Read
  `<workspace-root>/workspace-index.md`. If it does not exist, stop and say so: there is
  nothing to audit — that's `bootstrap`'s job, not `audit`'s. Do not create one. Proceed
  in **multi-repo mode** (Steps 2–6 below, unbranched).
- **`mode=monorepo`** — the target itself is a monorepo; `unit component/root-component/
  tooling/no-manifest-candidate` lines are its on-disk truth set. Read
  `<workspace-root>/workspace-index.md` (same missing-file handling as above). Proceed in
  **monorepo mode** (Steps 2–6, monorepo branches).
  Component unit paths are container-qualified (`apps/api`); the index H2 for a component
  is the path's **last segment** (`## api`), never the full path.
  **`unit root-component .`** is a code-shipping root and counts as a component in the truth
  set. Reconcile it against the H2 named after the **root directory** (root at
  `services/gateway/` → `## gateway`), never against a heading of `.`. If the index has no
  such H2, that is an ordinary missing-component gap — report it, don't invent a rule.
- **`mode=mixed`** — a multi-repo workspace where one or more `unit monorepo-member
  <name>` lines appear alongside plain `unit repo <name>` lines. Read the **parent**
  `<workspace-root>/workspace-index.md` (same missing-file handling as above; it is the
  ordinary multi-repo shape plus one delegating H2 per `monorepo-member`, per
  `layer1-index-format.md`'s Mixed variant). Then, **for each `monorepo-member <m>`**,
  locate its own component index by checking, in this order: `<workspace-root>/<m>.index.md`
  (host-at-root — the default) and `<m>/workspace-index.md` (in-place — only valid if
  that member was bootstrapped directly). Record what you found:
  - **Exactly one location has a file** — read it; this is `<m>`'s resolved index for the
    rest of this audit.
  - **Both locations have a file** — read whichever the parent's own delegation pointer
    (its Components field) resolves to; record the other path as a **stale duplicate**
    (surfaced in Step 4, never deleted).
  - **Neither location has a file** — record `<m>` as **unresolved**; this becomes a
    **dangling delegation** finding in Step 4, and Steps 2, 3, and 5's per-`<m>`
    component-level checks are skipped for it (there is nothing to read).

  Proceed in **mixed mode**: plain `repo` units get the ordinary multi-repo treatment;
  `monorepo-member` units get the mixed-mode notes in Steps 2–6 plus the new Step 4.

List the units you got back before going further, e.g.: `repo catalog-api`,
`monorepo-member web-monorepo` (mixed) — same as `bootstrap` reports them.

## Step 2 — units on disk vs. units in the index

Compare the `unit` lines from Step 1 against the `##` sections actually present in the
index you read:

- **On disk, missing from the index** — record each such unit by name. This is a finding
  even if it's brand new or looks unimportant; `audit` doesn't judge whether a unit
  *should* be indexed, only reports that it isn't.
- **In the index, absent from disk** — record this too (a stale section for a unit no
  longer at that path); it's the mirror-image gap.

**Monorepo mode:** compare the `unit component/tooling/no-manifest-candidate` lines
(Step 1's script run against the monorepo root) against the `##` component sections in
the index. Tooling and no-manifest-candidate units are **not** expected to have their own
`##` component section (per `layer1-index-format.md`'s `## Tooling & root config` /
`## No-manifest candidates` notes) — don't flag those as "missing from index" the way a
component would be. Indexed components are **not** falsely flagged as absent.

Compare on the unit path's **last segment**: `detect-mode.sh` emits container-qualified
component paths (`unit component apps/api`) and the index names that component `## api`.
Comparing the raw path against the H2 would report every component as missing. Where two
enumerated components share a last segment (e.g. `apps/report` and `services/report`), the
index cannot distinguish them — report that as an **ambiguity finding**, not as drift.

**Mixed mode:** at the **parent** level, compare Step 1's `unit repo`/`unit
monorepo-member` lines against the parent index's `##` sections exactly as multi-repo
mode does — a `monorepo-member` is a single H2 in the parent, same as a plain repo, just
with a delegation pointer instead of full fields. Then, **for each `monorepo-member <m>`
whose own index file was resolved in Step 1** (exactly-one or both-locations case), run
`${CLAUDE_PLUGIN_ROOT}/scripts/detect-mode.sh <workspace-root>/<m>` to get `<m>`'s own
component truth set, and compare it against the `##` component sections **inside `<m>`'s
own resolved index file** (not the parent) — identical to the monorepo-mode comparison
above, just scoped to that file. If `<m>` was **unresolved** in Step 1, skip this
comparison for it — Step 4's dangling-delegation finding already covers the gap.

## Step 3 — one-sided cross-repo edges (key detection)

For every `##` section in the index, read its **Cross-repo links** field and extract
every sibling repo it names. For each named sibling:

- Open that sibling's own `##` section elsewhere in the same index.
- Confirm the sibling's **Cross-repo links** field states the same relationship back
  (worded from its side — it doesn't need identical text, just a mention of the same
  contract with the first repo).
- If the sibling's section says nothing about the first repo at all — no line, no
  mention — that is a **one-sided edge**: report it explicitly, naming both repos and
  which side is missing. E.g.: `"one-sided edge: storefront-web → catalog-api
  ('calls the backend REST API') has no back-link on catalog-api's Cross-repo links
  (expected something like 'called by storefront-web')."`

Do this for **every** edge named by **every** section — don't stop at the first clean
match and assume the rest are fine. A both-endpoints violation on even one edge is a
finding; report all of them, not just the first.

**Monorepo mode:** apply the identical both-endpoints check to **`Cross-component links`**
— a component naming a sibling must be named back by that sibling. A one-sided component
edge is reported exactly like a one-sided cross-repo edge.

**Mixed mode:** apply the ordinary Cross-repo links both-endpoints check to
`monorepo-member` H2s in the **parent** index exactly like a plain repo — its Cross-repo
links names sibling repos/members, and any of those siblings must name it back.
Separately, apply the identical Cross-component links both-endpoints check **inside**
each resolved `<m>`'s own index file, exactly as monorepo mode does above. These two
checks are independent — a clean parent-level edge for `<m>` doesn't imply its
component-level edges inside `<m>.index.md` are clean, and vice versa; check both.

## Step 4 — mixed mode: cross-file delegation both-endpoints (new key detection)

**Applies only when Step 1 reported `mode=mixed`.** Skip this step entirely in
multi-repo or monorepo mode.

This is a **different defect class** from Steps 2–3: those check contents *within* a
file (sections present, edges reciprocated). This step checks that the **link between
two files** — the parent's delegation pointer and the member's own index file —
resolves in both directions, the same both-endpoints discipline applied across files
instead of within one.

For **each** `monorepo-member <m>` named in the parent index:

- **Parent → member (dangling check):** using what Step 1 resolved, if `<m>`'s own index
  file was found at **neither** `<workspace-root>/<m>.index.md` nor
  `<m>/workspace-index.md`, report a **dangling delegation**: `"<m>: parent delegates to
  <pointer path>, but no index file exists there (checked host-at-root and in-place)."`
  A pointer to a genuinely-not-yet-populated placeholder — a file that **exists** and
  says so, per `layer1-index-format.md`'s Mixed variant ("run bootstrap on this member to
  populate") — is **not** dangling; only a missing file is. Distinguish the two in the
  report.
- **Populated check:** if `<m>`'s index file was found, confirm it actually lists
  components (at least one `##` component section) rather than being an empty stub. If
  it exists, is not an explicit "not yet populated" placeholder, and lists no component
  sections, report it: `"<m>: index file at <path> exists but lists no components."`
- **Stale-duplicate check:** if Step 1 found `<m>`'s index at **both** locations, report
  the stale one by path, and note which location the parent's own pointer actually
  resolves to. Don't delete either file.
- **Member → parent (orphan check):** list `<workspace-root>/*.index.md` files
  (host-at-root candidates), and for each `monorepo-member` unit from Step 1 also check
  `<m>/workspace-index.md` (in-place candidate). (This root-level `*.index.md` glob is a
  deliberate, necessary exception to Step 0's "never re-derive membership by hand" rule —
  `detect-mode.sh` enumerates directories/units, not host-at-root index *files*, so
  finding orphaned ones requires listing those files directly; this is not membership
  re-derivation.) For every index file found this way,
  confirm the **parent** `workspace-index.md` has a `##` section for that member whose
  Components field delegates to it. If no parent section points at it — a member index
  file exists on disk with nothing in the parent naming it — report an **orphan member
  index**: `"<path>: a member index file exists but no section in
  <workspace-root>/workspace-index.md delegates to it."`

Reuse the both-endpoints framing from Step 3: a one-sided delegation (parent points at
nothing real, or a member index that nothing points at) is a defect exactly like a
one-sided Cross-repo/Cross-component edge — report **every** instance found, not just
the first. If every `monorepo-member` resolves cleanly in both directions, say so
explicitly ("no one-sided delegations found"). If the workspace isn't mixed, say this
step is not applicable rather than omitting it silently.

## Step 5 — CLAUDE.md and Layer-3 profile gaps

For each repo actually present on disk (from Step 2):

- **No `CLAUDE.md` at the repo root:** before recording anything, check the rest of the
  **Layer-2 source chain** — `AGENTS.md`, then `README.md`. Record the finding that is
  actually true: `"<repo>: conventions are in AGENTS.md; no CLAUDE.md."` when one exists, and
  `"<repo>: no CLAUDE.md found."` only when no tier has conventions. A repo with a complete
  `AGENTS.md` is not undocumented, and reporting it as such is a false finding.
- **`CLAUDE.md` is only an `@` import** (e.g. a ~11-byte `@AGENTS.md` redirect): not a
  finding in itself — follow the import and audit the target as that repo's conventions.
  An existence check passes here while the file supplies no facts, so check content, not
  presence.
- **Has a `CLAUDE.md`:** read it, and check the repo's Stack field in the index against
  the profiles listed in Step 0.3 (same matching rule as bootstrap/onboard: language/build
  tool, e.g. "Java + Maven" against `stack-profiles/java-maven-lombok.md`). If none match,
  record:
  `"<repo>: no Layer-3 stack profile match for '<stack>' — Layer-4 baseline only."` A
  matched profile is not a finding; only the absence is.

Do not attempt to fix either gap — no `CLAUDE.md` is created, no profile is written.

**Monorepo mode:** do **not** flag each component for a missing per-directory `CLAUDE.md`
(they legitimately have none). Instead check the monorepo's **root** `CLAUDE.md` once, and
check each component's Stack field for a profile match / the unprofiled marker as usual.

**Mixed mode:** a `monorepo-member <m>` is gap-checked at **two** levels — once as a
plain repo (its own root `CLAUDE.md`, per the ordinary rule above), and once as a
monorepo root for its own components (per the Monorepo mode note above, applied to `<m>`'s
own root `CLAUDE.md` and each component's Stack field **inside `<m>`'s own resolved index
file**). If `<m>` was **unresolved** in Step 1 (dangling, per Step 4), there is nothing to
check at the component level — skip it there; the dangling-delegation finding already
covers that gap. The plain-repo-level check (`<m>`'s own root `CLAUDE.md`) still applies
regardless of whether its component index resolved.

## Step 6 — run the guard for dead file refs

Run the guard **once per Layer 1-2 nav doc it's meant to police** — never against the raw
workspace root. Passing the whole workspace root recurses into every `.md` file on disk,
including this plugin's own test fixtures and dev docs, which are not the audited
workspace's nav docs and would produce permanent false positives. Instead:

1. **The index file under audit** — `${CLAUDE_PLUGIN_ROOT}/scripts/check-doc-paths.sh
   <workspace-root>/workspace-index.md` (or the specific index path, if the user named
   one other than the default). The script accepts a single file as its scan argument —
   `find` treats a file path as its own start point, so this checks exactly that file's
   links.
2. **Each on-disk member repo's top-level `CLAUDE.md`** (Layer-2 nav docs) — one guard
   call per repo, passing that repo's `CLAUDE.md` file directly, e.g.
   `${CLAUDE_PLUGIN_ROOT}/scripts/check-doc-paths.sh <repo>/CLAUDE.md`. Never pass the
   repo directory itself — that would recurse into vendored `node_modules` docs, build
   output, and other non-nav `.md` files that aren't this skill's concern. A
   `monorepo-member` counts as a member repo for this call — scan its own root
   `CLAUDE.md` too.

Do **not** scan `${CLAUDE_PLUGIN_ROOT}` itself — the plugin's own tests/docs/fixtures are
not part of the audited workspace's nav docs.

For each of these calls:

- If it exits 0 with no `MISSING:` lines: record that this file's guard passed clean.
- If it prints one or more `MISSING: <file> -> <ref>` lines: include every one of them
  in the report, verbatim — each is a dead file reference in a Layer 1/2 doc. Don't
  filter or summarize them away; the negative-test case this skill must catch is exactly
  one injected dead ref, and it must show up in the report.
- Lines prefixed `note: skipping sibling-repo ref` are informational, not findings —
  don't report them as dead refs.

Because the scan is correctly scoped to just these nav docs, a genuinely healthy
workspace yields a clean Step 6 across all calls — there is no fixture/scratch noise to
explain away.

**Monorepo mode:** there are no per-component top-level `CLAUDE.md` files to scan. Run the
guard against the **index file** and the **monorepo root `CLAUDE.md`** only — never
per-component directories (which would recurse into vendored trees), and never the whole
monorepo root directory.

**Mixed mode:** run the guard against the same targets multi-repo mode actually scans —
the **parent** `workspace-index.md` (item 1) and each on-disk member repo's own root
`CLAUDE.md` (item 2), treating each `monorepo-member <m>` like any other member repo for
its own root `CLAUDE.md` (one call per member, its `CLAUDE.md` file only). There is no
workspace-root-level `CLAUDE.md` scan — multi-repo mode never scans one, so mixed mode
doesn't invent one either. **Additionally**, for each `monorepo-member <m>` whose own
index file was **resolved** in Step 1, run the guard
against that file too — `${CLAUDE_PLUGIN_ROOT}/scripts/check-doc-paths.sh
<workspace-root>/<m>.index.md` (or the in-place `<m>/workspace-index.md` path,
whichever was resolved) — same single-file-argument rule as item 1, never `<m>`'s
directory. Skip this call for an `<m>` that was **unresolved** (dangling) in Step 1/4 —
there is no file to scan; that gap is already reported as a dangling delegation, not a
guard failure.

## Step 7 — print the report, nothing else

Print a single report covering, in order:

1. **Units on disk missing from the index** (Step 2), and any stale index sections for
   units no longer on disk. Report **ambiguity findings** from the same step as their own
   named category — two enumerated components sharing a last path segment (e.g.
   `apps/report` and `services/report`) that the index cannot distinguish. An ambiguity is
   not drift, and it must not be folded into either list above or it will be read as a
   missing or stale unit and "fixed" wrongly.
2. **One-sided cross-repo/cross-component edges** (Step 3) — every one found, naming
   both sides and which lacks the back-link. If none: say so explicitly ("no one-sided
   edges found").
3. **Mixed-mode cross-file delegation findings** (Step 4) — every dangling delegation,
   unpopulated member index, stale duplicate, and orphan member index found, named by
   path. If the workspace is mixed and every delegation resolves cleanly: say so
   explicitly ("no one-sided delegations found"). If the workspace isn't mixed: say this
   check is not applicable, rather than omitting the section.
4. **CLAUDE.md / Layer-3 profile gaps** (Step 5), per repo (including each
   `monorepo-member`'s own root `CLAUDE.md`, at both levels where mixed mode applies).
5. **Dead file refs from `check-doc-paths.sh`** (Step 6) — per file scanned (the parent
   index, each member repo's `CLAUDE.md`, and — mixed mode — each resolved
   `monorepo-member`'s own index file), the guard's exit status and every `MISSING:`
   line found, or "guard passed clean" if none. Note that the scan is scoped to these
   Layer 1-2 (and, in mixed mode, delegated Layer-1) nav docs by design, not the whole
   workspace.
6. A closing line restating the boundary: this run wrote nothing and modified nothing;
   the only action taken beyond reading was executing `check-doc-paths.sh` against the
   index, each member repo's `CLAUDE.md`, and (mixed mode) each resolved member index
   file.

If every one of Steps 2–6 comes back clean, say so plainly ("no gaps found") — don't
pad a clean audit with speculative suggestions; report what's actually true of the
current index and repos.

## Common mistakes to avoid

- Calling this skill "read-only" instead of "non-mutating, runs a bundled script" — it
  does execute `check-doc-paths.sh`, which is a real action even though the script itself
  only reads.
- Writing the report to a file by default — the default output is printed, not saved.
- "Fixing" a one-sided edge, a missing `CLAUDE.md`, a dead ref, or a one-sided delegation
  instead of reporting it — any fix is a separate, human-gated follow-up, not part of
  this skill. This includes deleting a stale duplicate member index file (Step 4) —
  name it, don't touch it.
- Stopping edge-checking after the first one-sided edge (or delegation) found instead of
  checking every edge on every section, and every `monorepo-member` in a mixed workspace.
- Passing the whole workspace root (or `${CLAUDE_PLUGIN_ROOT}`) to `check-doc-paths.sh`
  instead of the index file, each member repo's `CLAUDE.md`, and (mixed mode) each
  resolved member index file individually — the whole-root form drags in this plugin's
  own test fixtures and dev docs and can never come back clean. Treating a `note:
  skipping sibling-repo ref` line as a dead-ref finding is also a mistake.
- Referencing `../..`-style relative paths for shared plugin files instead of
  `${CLAUDE_PLUGIN_ROOT}/...`.
- Running this skill when no `workspace-index.md` exists yet — that's `bootstrap`.
- Re-deriving on-disk membership or shape by eyeballing `.git`/`CLAUDE.md` presence or
  the index's own field labels instead of running `detect-mode.sh` and trusting its
  `mode=`/`unit` output — including in mixed mode, where the on-disk truth set is the
  script's `unit repo`/`unit monorepo-member` lines, not a scan improvised by hand.
- Conflating Step 3 (within-file Cross-repo/Cross-component edges) with Step 4
  (cross-file delegation between a parent and a member's own index) — they are different
  defect classes and both must run in a mixed workspace.
- Treating a valid "not yet populated" placeholder member index as dangling, or an
  actually-missing index file as merely "not yet populated" — read the file to tell
  the two apart before reporting either.
