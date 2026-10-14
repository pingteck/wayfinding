---
name: onboard
description: Use when adding ONE repo to an existing multi-repo workspace index, or ONE component to an existing monorepo or mixed-workspace index — a new repo or component exists on disk but has no section in the index yet. For a whole workspace from scratch, use bootstrap; for a health-check of an existing index, use audit.
---

# onboard

Add **one** new repo to an **existing** `workspace-index.md`, in one pass. Read this
whole skill before doing anything — the defining move is not "append a section," it's
**reconciling every cross-repo edge the new repo introduces onto the existing repos it
touches**. An index where the new repo says "calls backend" but `catalog-api`'s own
section is silent about it is a defect, not a partial success.

## Safety boundary (read first — non-negotiable)

This skill is **read-and-report only outside the workspace root**. It:

- **Writes only these files**, and never any other path:
  - `mode=multi-repo` → `<workspace-root>/workspace-index.md`
  - `mode=monorepo` → `<root>/workspace-index.md` (the monorepo variant)
  - `mode=mixed` → the member's component index — `<workspace-root>/<m>.index.md`, or
    `<m>/workspace-index.md` **only if that is where the index already lives and the user
    targeted `<m>`** — **plus** `<workspace-root>/workspace-index.md`, and only to
    reconcile an already-present `Shallow list:` (never to create one).
- **This skill never *creates* an index, so it never chooses a location.** If the target
  index does not exist, stop and point at `bootstrap`. An in-place member index is
  therefore never this skill's decision — it is a file `bootstrap` already placed there
  under explicit member-targeting.
- **Never writes, `git add`s, or commits inside any member repo or component directory** —
  not even to fix an obvious gap. Gaps are *reported*, never patched. Never `git add` a
  generated index; always emit the gitignore note.

If you find yourself about to `Write` or `Edit` any path other than one of the files listed
above, stop — that's out of scope for this skill.

## Step 0 — read the shared references

Read, in this order, using `${CLAUDE_PLUGIN_ROOT}` (never `../..` — the plugin may be
installed anywhere; only paths rooted at `${CLAUDE_PLUGIN_ROOT}` are guaranteed to
resolve):

1. `${CLAUDE_PLUGIN_ROOT}/references/methodology.md` — the 4-layer model. Layer 1 is what
   you're updating here.
2. `${CLAUDE_PLUGIN_ROOT}/references/layer1-index-format.md` — the exact contract
   `workspace-index.md` must satisfy: required fields, and — the part this skill lives or
   dies by — the **both-endpoints rule** for cross-repo links: if repo A's Cross-repo
   links says "calls B," repo B's Cross-repo links must say "called by A," even if B's
   own `CLAUDE.md` never mentions A. A one-sided edge is a defect, full stop.
3. List `${CLAUDE_PLUGIN_ROOT}/references/stack-profiles/` and skim each file's
   `verified:` header and "Languages/build tool" section, so you know which stacks are
   profiled before matching the new repo's stack in Step 4.

## Step 1 — locate the existing index and the repo to onboard

Run `${CLAUDE_PLUGIN_ROOT}/scripts/detect-mode.sh` on the target directory (the current
working directory unless the user named one). It is the **sole authority** on the mode, the
root, and which directories are units — do not re-derive any of that by eyeball. Read its
`mode=`, `root=`, and `unit <shape> <relpath>` lines, then branch:

- **`mode=multi-repo`** → the repo path, Steps 2–7 below, unchanged.
- **`mode=monorepo`** → the component path (Step 1a), index = `<root>/workspace-index.md`.
- **`mode=mixed`** → the component path against a member's index (Step 1b).
- **`mode=ambiguous`** → stop and ask; never guess.
- **`mode=plain-repo`** → one unit, nothing to route between; there is no index to add to.
  Stop and say so — this is a confident classification, not a question. If a
  `<root>/workspace-index.md` exists anyway, the root was previously indexed as a monorepo
  and has been reclassified: name the file, report the mismatch, and change nothing.

Component unit paths are container-qualified (`apps/api`); the component's **name** — the
H2 you write and match against — is the path's **last segment** (`api`).

**`unit root-component .`** is a code-shipping root that is itself a unit (a repo with one
`go.mod` at the root, say). Its path is literally `.`, so name it after the **root
directory** instead — root at `services/gateway/` → `## gateway` — and treat it as an
ordinary component for every rule below. Never write a heading of `.`.

**Read the existing index first, in every mode.** If it does not exist, stop and say so:
this skill *adds to* an existing index; for a workspace with no index yet, that is
`bootstrap`. Do not create one here.

- Identify the **one repo being onboarded** — the one the user named, or (if unnamed) the
  single `unit repo <relpath>` line from Step 1's `detect-mode.sh` run that has **no**
  existing `##` section in `workspace-index.md`. Selecting from those lines, rather than
  re-deriving repo-ness independently, keeps this consistent with the "sole authority"
  rule above. If more than one un-indexed `unit repo` line exists and the user didn't say
  which one, ask rather than guessing — onboarding the wrong repo, or several at once, is
  out of scope (multiple new repos in one pass is what re-running `bootstrap` is for).
- Note every existing `##` section already in the index — you will need this list intact
  in Step 5 to reconcile against.

### Step 1a — resolve the target component (monorepo mode)

The **candidate set** is the run's `unit component <relpath>` lines minus the components
already having an H2 — where "already having an H2" is evaluated **only over the index's
component region** (the H2s before `## Tooling & root config` / `## No-manifest candidates`
/ any trailing notes section), matched on the unit's **last segment**. Scanning the whole
file for `^## <name>` instead lets any heading collision silently and permanently subtract
a real component from every future run.

**Report the derived candidate set and every subtraction you applied**, so a wrong
subtraction is visible rather than silent.

Then apply this table — every row is fail-closed:

| Situation | Do this |
|---|---|
| The named target is not enumerated by the script at all | Stop — it is pruned or not on disk. Never index it on the user's say-so. |
| The target is `tooling` or `no-manifest-candidate` | The note-section path (Step 4a). No component H2, ever. |
| The target already has an H2 | Stop — refreshing an existing entry is `audit`/`bootstrap`, not onboard. |
| The candidate set is empty | Stop — "nothing to onboard"; write nothing. |
| Several candidates and the user named none | Ask which. |
| The index has H2s with no on-disk unit | Proceed, **report** the drift, fix nothing — that is `audit`'s job. |

Two enumerated components can share a last segment (`apps/report`, `services/report`). If
the resolved target's last segment is ambiguous, **stop and report both paths** — the index
cannot distinguish them, and picking one silently makes the other unreachable.

**If you were invoked from inside a member** (`detect-mode.sh` reports `mode=monorepo` with
`root=` that member), you are on this path and the parent is not in view. Check the parent
directory for a host-at-root `<parent>/<basename>.index.md`; if one exists, **name it and
the parent's `Shallow list:` in your report** — a member-scoped run cannot reconcile the
parent, and leaving that silent is how the parent goes stale.

### Step 1b — resolve the member and its index (mixed mode)

The parent run enumerates `unit monorepo-member <m>` and `unit repo <r>` lines and **no
component lines at all** — a member's components are only visible by running the script on
the member. So:

1. **Resolve the member.** A target given as a **path** belongs to whichever
   `unit monorepo-member <m>` contains it. A target given as a **bare name** requires
   running `${CLAUDE_PLUGIN_ROOT}/scripts/detect-mode.sh` on **each** `monorepo-member` unit
   and matching. If the name matches components in more than one member, **stop and ask** —
   never pick one.
2. **Enumerate that member's components** by the run on `<m>` (it reports `mode=monorepo` in
   the ordinary case). Step 1a's candidate-set rules then apply **within the member's index**.
   **Verify `root=` is `<m>` before using the output.** The script may resolve *up* one level,
   returning the parent's classification instead of the member's; and a member the parent
   called a `monorepo-member` can still come back `plain-repo` or `ambiguous`. In either case
   the two views disagree — **stop and report both answers**, never pick one.
3. **Locate the member's index** — never create one:

   | On disk | Do this |
   |---|---|
   | Only `<workspace-root>/<m>.index.md` | Use it (host-at-root, the parent-scoped default). |
   | Only `<m>/workspace-index.md` | Use it **only if the user targeted `<m>`**; it exists because `bootstrap` was run on `<m>` directly. |
   | **Both** | Use whichever the **parent's delegation pointer** (its `Components:` field) resolves to, and **report the other as a stale duplicate** — never delete it. This is the same rule `audit` and `bootstrap` already apply. |
   | Neither | Stop — "run `bootstrap` on `<m>` first." |

**Invoked from inside a member yourself?** That resolves as `mode=monorepo`, not this mode
— see the guard at the end of Step 1a for the parent-directory check it requires.

## Step 2 — gap-check the new repo's CLAUDE.md, report only

- **List the repo's top level first**, then walk the **Layer-2 source chain** in order,
  stopping at the first tier that yields content and recording which one you used:
  1. `CLAUDE.md`, read in full;
  2. **its `@` imports** — `@AGENTS.md` is an import directive meaning "that file's contents
     belong here"; a `CLAUDE.md` that is *only* an import is a redirect (often ~11 bytes) and
     the imported file is the real source;
  3. `AGENTS.md` — equivalent to `CLAUDE.md` per `methodology.md`; many repos ship one and no
     `CLAUDE.md`;
  4. `README.md` and any architecture doc either points at — **admissible on its own**, no
     pointer required;
  5. manifests, for Stack and Entry points only — never Purpose;
  6. nothing — say so; "not documented in the repo" is a true and useful statement.
- Record the gap that is **actually true**: if conventions live in `AGENTS.md`, the gap is
  *"conventions are in AGENTS.md; no CLAUDE.md — consider a CLAUDE.md importing it"*, **not**
  "add one before Layer 2 conventions exist" — that would tell the user to write a file they
  already have. Only when no tier yielded anything is `"<repo>: no CLAUDE.md found — add one
  before Layer 2 conventions exist for this repo."` the correct text. Do not create one.
- Note any other gaps *for the report only* — a stack claim with
  no matching profile (handled in Step 4), a missing entry-point description, a mention of
  a sibling repo that the sibling's own file doesn't mention back (you fix the **index's**
  copy of that edge in Step 5 — you still don't edit either repo's file).
- Also skim each **existing** repo's own `CLAUDE.md` (already on disk from before this
  skill ran) for any mention of the new repo — some edges are only documented from the
  existing side (e.g. `catalog-api`'s `CLAUDE.md` might already describe a webhook
  receiver the new repo calls, before the new repo's own docs mention it). Fold anything
  you find into the edge list you reconcile in Step 5 — an edge documented on only one
  side, in either direction, is the failure mode this skill exists to prevent.
  - **Scope this skim tightly — one conventions source per existing repo, and stop there.**
    For each existing repo, read the **first source in the Layer-2 chain that it actually
    has**: its root `CLAUDE.md` (plus the file it `@`-imports, when the `CLAUDE.md` is only
    a redirect), else its `AGENTS.md`, else its `README.md`. That one source is where the
    repo states its cross-repo edges. Pull in a further doc *only* if that source explicitly
    points at one to resolve a specific suspected edge. Do **not** recursively crawl each
    repo's whole `docs/` tree — an open-ended crawl is what turns this scan unbounded. Kept
    to one source per repo, the cost is exactly **one read per existing repo** (`O(R)` in the
    repo count; a redirect's import travels with it) — it grows linearly and stays correct
    at any workspace size; it does not explode.
  - **Never cap or sample this scan to save reads.** Skimming *every* existing repo is
    what makes cross-repo edges complete; skipping some to bound cost would silently
    reintroduce the one-sided-edge defect this skill exists to prevent. If a very large
    workspace makes the `O(R)` reads feel heavy, that is acceptable cost, not a reason to
    truncate — the correctness of the both-endpoints rule is not negotiable against it.
- **Never edit, `git add`, or commit anything inside any repo** — new or existing —
  including CLAUDE.md files, regardless of how small or obviously-correct the fix looks.

**Monorepo mode:** components legitimately have no per-directory `CLAUDE.md` — do **not**
record a "no CLAUDE.md" gap for the component. Gap-check the **monorepo's own root docs**
once (root `CLAUDE.md` plus anything it points at); that is the shared Layer-2 source for
all components. Read the new component's own `README`/docs if it has them. Never edit,
`git add`, or commit anything inside the monorepo or any component.

## Step 3 — derive the new repo's five Layer-1 fields, capabilities not paths

From what you read in Step 2, derive the five required fields (label text verbatim, per
`layer1-index-format.md`) — never invent facts, never guess a stack or capability you
didn't confirm in the repo's own docs. **Ground each field in the new repo's *own*
sources.** A capability only inferable from another repo's docs or from cross-repo context
is an inference, not a fact — omit it, or mark it "(inferred)"; and only attribute a fact
to a source you actually drew it from:

- **Purpose** — one or two sentences: what this repo is *for*.
- **Role** — its position relative to the other repos, distinct from Purpose.
- **Entry points** — capabilities an agent starts from (a REST API base path, a CLI run
  target, a dev-server command) — never a file path, line number, or directory tree.
- **Cross-repo links** — every edge to a sibling repo as a capability/contract, drawn from
  the new repo's own docs plus anything the workspace root `CLAUDE.md` states as shared
  (same auth provider, same payment provider, same deploy target, etc.) plus anything
  found on the existing-repo side in Step 2. This field is the input to Step 5 — write
  down every sibling this repo touches, you'll reconcile each one next.
- **Stack** — languages, frameworks, key infra, as named in the repo's own docs.

Do not include file paths, line numbers, or directory trees anywhere in these fields. If a
file reference is truly unavoidable it must be a real, existing path and must survive
`${CLAUDE_PLUGIN_ROOT}/scripts/check-doc-paths.sh` — prefer avoiding file references in
Layer 1 entirely.

**Monorepo mode:** use the **monorepo variant**'s field labels (`layer1-index-format.md`):
**Purpose / Role (+ role tag) / Entry points / Cross-component links / Stack**. Assign the
role tag by the ordered rule in `${CLAUDE_PLUGIN_ROOT}/references/component-detection.md` —
`(application)` for a user-facing app, `(service)` for a backend service with no browser UI,
`(shared library)` as the default. The label is yours; **membership is the script's**.

**Deriving Cross-component links.** Three sources, in this order:

1. the monorepo's root docs (read once in Step 2);
2. the new component's own docs/README;
3. **declared manifest dependencies, in both directions.** Read the new component's own
   manifest for edges *out*, and **one manifest per enumerated component** for edges *in*.
   Resolve a component's manifest from its **qualified unit path**, never by guessing:
   `unit component packages/shared-ui` means the manifest is the recognized build manifest
   sitting directly in `packages/shared-ui/` — `package.json`, `Cargo.toml`, `go.mod`,
   `pyproject.toml`, `setup.py`, `pom.xml`, or `build.gradle`. Read that file itself; do
   not search below the component's own directory for a deeper one.

A declared dependency is an edge **only if both** hold:

- **(i) it is internal** — version spec `workspace:`, `file:`, `link:`, a Cargo `path = `,
  or a go.mod `replace`. A registry range (`^1.3.0`) is **not** an edge, however suggestive
  the name;
- **(ii) it resolves to an enumerated component by that component's declared manifest
  name** (`package.json` `name`, Cargo `[package] name`, go.mod `module`) — never by
  directory basename. A scoped `"@acme/ui": "workspace:*"` must resolve to the component
  whose manifest declares `"name": "@acme/ui"`; basename matching would silently drop it.

Anything satisfying neither is **dropped and named in the report**, never written.

**Never cap or sample the reverse scan.** It is one manifest read per component — cheaper
per unit than the per-repo source reads the multi-repo path does — and truncating it silently
reintroduces the one-sided-edge defect this skill exists to prevent.

**Heading discipline.** Never emit a line beginning with `#` that came from a component's
own docs; write `^## ` only as your own section scaffolding. A correct component onboard
changes the index's `^## ` count by **exactly one**.

## Step 4 — match a stack profile, or record the gap (unprofiled degradation)

Check the new repo's Stack (from Step 3) against the profiles listed in Step 0.3 (match on
language/build-tool, e.g. "Java + Maven" against `stack-profiles/java-maven-lombok.md`,
"TypeScript + Vite" against `stack-profiles/typescript-vite.md`):

**Monorepo mode:** this step is identical for a component — match its Stack against the
same profiles, and the unprofiled-marker rule below (own unbroken line beneath the Stack
facts, present only on a genuine no-match) applies unchanged. Read "repo" as "component"
throughout.

- **Match found:** note in the report which profile applies and its verified envelope.
  **Do not** add any unprofiled-stack annotation to this repo's Stack field — that
  annotation is reserved for the no-match case below.
- **No match — durable annotation is mandatory (this is not optional, and the report
  alone does not satisfy it):** in the index entry you write in Step 5a — not just the
  report, which is ephemeral and does not survive — record, on **its own line directly
  beneath the new repo's Stack facts**, the exact phrase **"Layer-4 baseline only;
  Layer-3 profile TODO"**, plus a pointer to
  `${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md` as the contract a new profile
  would need to satisfy. Write it as prose (a plain filename/path mention), never as a
  markdown link `[..](...)` — a live link to `stack-profile-format.md` would not resolve
  relative to `workspace-index.md` and would trip `check-doc-paths.sh`.

  **Keep the marker on a single unbroken line — never hard-wrap it across a newline.** The
  phrase `Layer-4 baseline only; Layer-3 profile TODO` must appear as one contiguous run
  of text so an exact-string audit (`grep`, or the `audit` skill) finds *every* unprofiled
  repo; if you break it across lines to fit a column width, that audit silently
  under-counts. Putting it on its own line (rather than appended to a possibly-long Stack
  line) is precisely so it fits without wrapping. Shape to match, verbatim except for the
  repo's own stack facts:

  ```
  - **Stack:** Python 3.12, FastAPI, Pandas, managed Postgres.
    _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._
  ```

  Never fabricate a profile, never let a missing profile block writing the repo's Layer-1
  section — the *only* difference from a profiled repo is this one marker line beneath the
  Stack facts. Also still mention the gap in the report (Step 7) — that's additional,
  not a substitute for the index-entry annotation.

**Before moving to Step 5, double-check:** if the new repo has no profile match, this
annotation is on its Stack line *in the section you're about to write* — and if it does
match a profile, the Stack line stays plain (no annotation). Getting this backwards is a
defect this skill exists to prevent.

### Step 4a — the target is `tooling` or `no-manifest-candidate` (no H2, ever)

`detect-mode.sh` owns membership, and confirming a candidate does **not** promote it. So:

- **Never write a component H2 for it** — the graded component set must be unchanged, and
  the index's `^## ` count must not move.
- Ensure it is listed in the matching note section — `## No-manifest candidates` or
  `## Tooling & root config` — creating that section only if it is missing. **Locate note
  sections by their position in the trailing note region, not by the first `^## <name>`
  match**: a component may legitimately be named the same as a reserved section, and
  matching the first occurrence would append into that component's section.
- End the entry with the remediation: *"add a recognized build manifest (`package.json`,
  `pyproject.toml`, `setup.py`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`, or
  `build.gradle.kts`) to have it indexed as a component."*
- Say in the report that the trace is **durable until the next `bootstrap` regenerate**,
  which rebuilds the note sections from the script's enumeration.

Then skip Steps 5–6's append/reconcile entirely and go to the report.

## Step 5 — append the new section, then reconcile every incident edge (the core step)

This is two sub-steps, in order, and the second one is not optional:

**5a — Append.** Add one new `##` section for the new repo, with the five fields from
Step 3, at the end of `workspace-index.md` (or wherever fits the existing file's repo
ordering), field labels verbatim.

**5b — Reconcile (the both-endpoints rule, applied).** Re-scan the Cross-repo links field
you just wrote for the new repo. For **every** existing repo it names, open that existing
repo's `##` section elsewhere in the same `workspace-index.md` and add the corresponding
back-link to *its* Cross-repo links field — the same relationship, stated from that repo's
side (e.g. if the new repo's section says "calls catalog-api's REST API," the
`catalog-api` section must gain "called by `<new-repo>`" or an equivalent statement of
the same contract from its side). Do this for every existing repo touched, one at a time,
checking off each as you go:

- [ ] For each sibling named in the new repo's Cross-repo links: located that sibling's
      existing section, added/updated its back-link.
- [ ] For each sibling-side mention found in Step 2 (an existing repo's own docs
      referencing the new repo that the new repo's docs didn't state): the new repo's
      Cross-repo links field also reflects it (update Step 3's field if you missed it).
- [ ] No existing repo section was otherwise altered — only the Cross-repo links field of
      a repo actually incident to the new repo gets a new line.

You are editing **the index's** copy of each existing repo's Cross-repo links field, not
the existing repo's own `CLAUDE.md` (Step 2's / the safety boundary's rule still applies —
this is the one part of an existing repo's index section this skill is allowed to touch,
and it is *only* this field, *only* to add the back-link).

Before moving on, defensively re-read the new repo's section and every section you edited:
confirm each edge now appears on **both** endpoints, worded from each side. If you can't
find the matching line on both sides, the reconciliation isn't done yet — go fix it, don't
report success.

**Monorepo mode — placement is deterministic.** Append the new component's H2 **after the
last component H2 and immediately before `## Tooling & root config`**. Keep every existing
section in its current order; **never re-sort** — the shipped indexes are ordered
semantically, not alphabetically.

**Monorepo mode — reconcile (the both-endpoints rule, applied).** For **every** sibling
component named in the new component's Cross-component links, open that sibling's `##`
section in the same index and add the matching back-link to **its** Cross-component links
field. Work through them one at a time:

- [ ] Each sibling named by the new component has gained its back-link.
- [ ] Each edge found on the sibling side in Step 3 (a sibling's manifest declaring a dep on
      the new component) also appears in the new component's own field.
- [ ] **Every name already on a sibling's Cross-component links line is still there.** You
      are *extending* that line, never replacing it — dropping a pre-existing edge while
      adding yours is a defect, not a tidy-up.
- [ ] No other field of any existing section was altered. Only the Cross-component links
      field of a component actually incident to the new one may change.

Re-read every section you touched and confirm each edge appears on **both** endpoints
before reporting success.

**Mixed mode — reconcile the parent's shallow list, if and only if it already exists.**
After writing the member index, look at the monorepo-member's `Components:` field in
`<workspace-root>/workspace-index.md`:

- **No `Shallow list:` prefix** → the author chose pure delegation. **Leave the parent
  byte-untouched.** Never create a list.
- **A `Shallow list:` is present** → add `` `<component>` (<role tag>) `` for the new
  component, keeping every existing entry. The list must then name **exactly** the member's
  components — no more, no less.
- **Adding it would exceed the soft cap** (`layer1-index-format.md`) → remove the
  `Shallow list:` clause entirely, dropping to pure delegation, and say so in the report. A
  capped list that silently looks exhaustive is worse than no list.

Nothing else in the parent may change: not the delegation pointer, not the boundary marker,
not any other member's section.

## Step 6 — write the updated index

Write the whole file back to the target(s) resolved in Step 1 — the untouched existing
sections, the sections you back-linked in 5b, and the new repo's/component's section from
5a. Which file(s) that means, and under what conditions, is exactly the Safety boundary's
allowed-targets list above (read first, in this document) — this step does not re-derive
or restate it, only executes it. Do not write, move, or copy any other file: never inside
`wayfinding/`, never inside a member repo, and never `git add` or commit a generated
index.

**Mixed mode — write order is binding.** Write the **member's component index first**, then
the parent `workspace-index.md` (only if its shallow list needed reconciling). The parent
must never reference a member index state that is not yet on disk. Both files sit at the
workspace root on a parent-scoped run; neither is `git add`ed.

## Step 7 — print an onboarding report

After writing the index, report:

- The repo onboarded, and where its section was placed.
- Any CLAUDE.md gaps found for the new repo (Step 2) — report-only, nothing was edited.
- Any sibling-side mentions found on existing repos' docs that fed into the new repo's
  Cross-repo links (Step 2).
- Every existing repo whose section gained a back-link in Step 5b, and what was added.
- The stack-profile match or "Layer-4 baseline only; Layer-3 profile TODO" (Step 4) —
  and, if unprofiled, confirm the same annotation is already sitting on the new repo's
  Stack line in the index you just wrote (Step 4/5a), not only here in the report.
- The path to **every** file written — one in multi-repo and monorepo mode, and in mixed
  mode the member's component index plus, only if it already had a `Shallow list:`, the
  parent index. Name them explicitly rather than saying "the index".
- A reminder that every edge touching the new unit now appears on both endpoints; that the
  files written are exactly those the Safety boundary allows and nothing else; and that
  this skill modified nothing inside any member repo or component directory, and `git
  add`ed nothing.

**Monorepo mode — the report also states:** the component onboarded and its qualified unit
path; the derived candidate set and any subtractions applied; every dropped dependency and
why (registry range, or unresolvable to a component); every sibling section that gained a
back-link; the stack-profile match or the unprofiled marker; the exact file written; and
that nothing inside the monorepo or any component was modified, `git add`ed, or committed.

**Mixed mode — the report also states:** the member resolved and how (path containment, or
a name matched across members); which of the two index locations was used, and any stale
duplicate found at the other; whether the parent's shallow list was updated, left untouched
(no list present), or dropped to pure delegation (cap exceeded); and the gitignore reminder
for every file written.

## Common mistakes to avoid

- Appending the new repo's section and stopping there — the defining failure mode this
  skill exists to prevent: a new repo's Cross-repo links naming an existing repo, with no
  matching back-link added to that existing repo's own section.
- Editing an existing repo's section for anything other than adding the back-link it's
  actually owed (don't refresh unrelated fields — that's `audit`'s job, not `onboard`'s).
- Editing any repo's actual `CLAUDE.md` on disk instead of only the index's copy of the
  edge.
- Onboarding more than one un-indexed repo in a single pass without the user specifying
  which — ambiguous scope, ask instead of guessing.
- Running this skill when no `workspace-index.md` exists yet — that's `bootstrap`.
- Citing a specific file/line instead of the capability it provides.
- Referencing `../..`-style relative paths for shared plugin files instead of
  `${CLAUDE_PLUGIN_ROOT}/...`.
- Inventing a Purpose, Stack, or capability that isn't actually stated in a repo's own
  docs, or fabricating a stack-profile match without checking its "Languages/build tool"
  section actually names the new repo's stack.
- Recording "Layer-4 baseline only; Layer-3 profile TODO" in the report but leaving it
  out of the new repo's own Stack line in `workspace-index.md` — the report is ephemeral,
  the index entry is the durable record; the annotation must land in the index, not just
  be said out loud.
- Adding the unprofiled-stack annotation to a repo whose stack *did* match a profile.
- Hard-wrapping the `Layer-4 baseline only; Layer-3 profile TODO` marker across a newline
  (to fit a column width) so an exact-string search can't find it — keep the phrase on one
  unbroken line.
- **Mixed mode:** writing the parent `workspace-index.md` before the member's own component
  index — the write order is binding (Step 6): member first, always.
- **Mixed mode:** inventing or choosing an in-place member index location instead of using
  the one that already exists — this skill never *creates* an index, so it never chooses a
  location; if neither location has one, stop and point at `bootstrap`.
- **Mixed mode:** deleting a stale duplicate index found at the other location instead of
  reporting it — never delete, only report (same rule `audit` and `bootstrap` apply).
- **Mixed mode:** creating a `Shallow list:` where the parent had none, or leaving it stale
  (missing the new component, or exceeding the soft cap without dropping to pure delegation)
  after a member-scoped run.
- **Mixed mode:** letting a member-scoped run finish without naming the parent's host-at-root
  index and its `Shallow list:` in the report — a member-scoped run cannot reconcile the
  parent itself, so silence there is how the parent goes stale.
