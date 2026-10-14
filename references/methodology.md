<!-- CANONICAL. This file is the maintained copy of the 4-layer model and has no upstream
     master. It was originally distilled from a navigation-experiment write-up that is not
     part of this plugin and is not shipped with it; do not reintroduce a `source:` pointer
     to a path outside ${CLAUDE_PLUGIN_ROOT}, which by definition cannot resolve after
     install. -->

# Codebase-navigation methodology for AI agents

**Status:** Portable deliverable — written project-agnostic so it can be lifted out
to any project (including a 10+ repo workspace). It contains no specifics of the repo
it was authored in. Empirical tool results for a *particular* stack belong in that
project's own verification report, not here.

## The problem

An AI coding agent working in a large or multi-repo codebase needs the *right* context
at the *right* time: enough orientation to know where things live, without drowning in a
hand-maintained map that drifts out of date the moment code moves. The failure modes at
both extremes are documented:

- **Too little structure** → the agent greps blindly, re-derives layout every session, and
  misses cross-repo relationships entirely.
- **Too much hand-authored structure** → stale file paths send the agent confidently to the
  wrong place, and *auto-generated prose context measurably lowers task success while raising
  cost* (ETH Zurich study: human-curated context beat LLM-generated across all agents tested;
  generated files *reduced* success 0.5–2% and increased inference cost >20%).

The resolution is to **separate slow, hand-authored orientation from fast, dynamic detail** —
and to hand-author *only* the parts that change slowly.

## The 4-layer model

| Layer | What it holds | Authoring | Granularity | Staleness risk |
|---|---|---|---|---|
| **1. Workspace index** ("repo router") | Per-repo purpose / role / entry points / cross-repo links | Hand | Coarse (repo-level) | Low — repos are added/removed rarely |
| **2. Per-repo conventions** | Rules, gotchas, non-inferable decisions (NOT structure dumps) | Hand | Coarse (universal truths) | Low — these are stable facts |
| **3. Dynamic augmentation** | Generated symbol map, exact symbol nav, and/or semantic search | Dynamic | Fine | None — ephemeral, regenerated |
| **4. Baseline navigation** | Live `grep` / glob / file-read / agentic search | Dynamic | Fine | None — always current |

**Layers 1–2 are hand-authored and committed. Layers 3–4 are dynamic and never committed.**
That boundary is the whole methodology.

### Layer 1 — workspace index ("repo router")

A single hand-authored orientation doc listing each repo/package and its role, stack, entry
points, and how it relates to its siblings. This is the layer that does **"which repo?"
routing** — the question that dominates at scale and is absent in a single repo. It is
deliberately coarse: it names capabilities and boundaries, not files.

- Recommended form: a markdown index (the `llms.txt` shape — H1 name, blockquote summary, H2
  sections linking each repo with a one-line note) or the monorepo-root convention of listing
  each package + its stack.
- Keep it at the level of "this repo owns X; it talks to Y over Z." If a line names a specific
  file, it is a candidate for staleness — see the path-existence guard below.

### Layer 2 — per-repo conventions

Each repo carries its own conventions file (`CLAUDE.md` / `AGENTS.md`). Hierarchical loading is
the supported mechanism: a root file sets workspace-wide rules and each repo/subdirectory adds
its own, loaded nearest-first. Starting the agent inside one repo pulls that repo's file plus the
root, excluding siblings — natural context isolation.

This layer holds **what cannot be inferred from the code**: money/precision rules, immutability
invariants, safety guardrails, "this is experimental," deploy boundaries. It explicitly does
**not** hold a structure dump or a file map — those are Layer 3's job and go stale here.

> Note on the "nearest file wins" framing: tools that support per-directory convention files
> generally **concatenate** them from root → cwd; "nearest wins" governs *conflict resolution*,
> not which single file is read. Per-package layering is real; "only the closest file is read"
> is a common misconception.

### Layer 3 — dynamic augmentation

Generated, ephemeral, regenerated on demand — so it *cannot* go stale. Three complementary
primitives (use any or all; they are not substitutes for one another):

- **3a — Generated symbol map** (e.g. tree-sitter + PageRank, the aider repo-map approach):
  parses source into a ranked symbol list per file ("which files matter"), not a raw file tree.
  Regenerated per request within a token budget.
- **3b — Exact symbol navigation** (LSP / code-intelligence): jump-to-definition,
  find-references, type errors — *exact*, resolved from a language server rather than text
  matching. First-party code-intelligence plugins exist for several languages.
- **3c — Semantic search** (embeddings): chunk → embed → nearest-neighbor recall for
  "where is the thing that does X" when you don't know the symbol name. *Approximate.* Kept
  fresh by re-indexing only changed files (hash/Merkle diff).

**3b is exact; 3c is approximate — they are complementary, not interchangeable.** Exact nav
answers "every caller of this symbol"; semantic search answers "roughly where is this concept."
A generated symbol map (3a) orients before either.

> Caveat carried from verification work: the "LSP finds every caller, always beats grep" premise
> does **not** hold universally out of the box — language servers can under-return references in
> headless/on-demand use, and some need explicit project import before they resolve anything.
> **Verify the tool on the actual stack before relying on it; do not trust the premise.** Until a
> tool demonstrably resolves references reliably, Layer 4 is the baseline it must beat.

### Layer 4 — baseline navigation

Live `grep` / glob / file-read / agentic search. Always current, zero maintenance, no setup. This
is the floor every other layer must justify itself against — and on small repos it is often
sufficient on its own. Layer 3 earns its place only where Layer 4's blind spots bite (scale,
cross-file reference chains, semantic recall without a known symbol).

## The staleness principle

> **Hand-author only the coarse, slow-changing layers (1–2). Everything fine-grained is dynamic
> (3–4) — regenerated or searched live, never committed.**

Corollaries, each grounded in the literature:

1. **Describe capabilities, not paths.** The most dangerous staleness is a hardcoded file path:
   when code moves, the agent "confidently looks in the wrong place." Layers 1–2 name *what a
   repo does*, not *which line does it*.
2. **Guard the few file references that remain.** Where a coarse layer must name a file, add a
   **path-existence check** (CI doc-drift linting — e.g. extract every doc reference and fail the
   build if a referenced path no longer exists). This keeps Layers 1–2 honest cheaply.
3. **Never hand-maintain generated structure.** Auto-generated prose maps hurt; generated symbol
   maps and embeddings stay correct precisely because they are *regenerated, not stored*. If a
   thing can be generated, generate it at Layer 3 — don't commit a snapshot of it.
4. **Coarse + dynamic beats fine + static.** A coarse hand map that rarely changes plus
   just-in-time dynamic detail outperforms a detailed hand map that is always slightly wrong.

## Applying it to a new project

1. **Write Layer 1** — one repo-router doc: every repo, its role, entry points, cross-repo edges.
   Coarse. No file-level detail.
2. **Write/curate Layer 2** — per-repo conventions: only non-inferable rules, gotchas, guardrails.
   Delete any structure dumps; those move to Layer 3.
3. **Stand up Layer 3 as needed** — pick the primitive(s) the work calls for (symbol map for
   orientation, LSP for exact refs, embeddings for semantic recall). **Run a verification gate
   first:** confirm the tool actually resolves the stack's dominant patterns before trusting it;
   record what it can't do as a finding.
4. **Keep Layer 4 as the baseline** — and measure new Layer-3 tooling against it, not against
   nothing. If a tool doesn't beat careful grep on the stack, it isn't pulling its weight yet.
5. **Add the path-existence guard** — CI check over Layers 1–2 so the few committed file
   references can't rot silently.

## Scope and validation

This model maps each layer to an independently proven approach (generated symbol maps; LSP
code-intelligence; embeddings; hierarchical hand-authored conventions; CI drift-checking). The
*model* is well-supported by the literature. What remains project-specific is **which Layer-3
tool actually works on a given stack** — that is an empirical question answered per project by a
verification gate, not by this document. A small testbed can verify *tooling*; it cannot validate
the methodology's payoff *at scale* — the Layer-1 "which repo?" routing problem only bites once
there are many repos. Treat scale validation as deferred to a genuinely multi-repo project.

## References

Grounded in the wayfinding experiment; see the source repo for the literature review.
