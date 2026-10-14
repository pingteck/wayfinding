# Layer 1 index format

Layer 1 is the **workspace index** ("repo router") from `methodology.md`: a single
hand-authored orientation doc that answers "which repo?" before anything else. It is
produced by the `bootstrap` and `onboard` skills and asserted against by the plugin's
own tests — the shape below is a contract, not a suggestion.

## Shape

- **H1** — the workspace name.
- **Blockquote summary** — one or two lines: what this workspace is, in plain language.
- **One `##` (H2) section per repo** — each repo section contains exactly these fields,
  as their own labeled lines (bold label + colon, or a sub-heading — either is fine, but
  the label text itself must appear verbatim):
  - **Purpose** — what this repo is for, one or two sentences.
  - **Role** — its position in the workspace (e.g. "backend API," "frontend SPA," "shared
    library"). Distinct from Purpose: Purpose is *why it exists*, Role is *how the other
    repos depend on it*.
  - **Entry points** — the capabilities an agent starts from (e.g. "REST API under
    `/api/*`," "CLI entry `npm run dev`"), not a file listing.
  - **Cross-repo links** — every edge to a sibling repo, described as a capability/contract
    (e.g. "calls the backend REST API," "consumes this repo's OpenAPI contract"). **Every
    edge must be listed on both endpoints** — if repo A's Cross-repo links says "calls B,"
    repo B's Cross-repo links must say "called by A." A one-sided edge is a defect.
  - **Stack** — languages, frameworks, key infra (e.g. "Spring Boot 3.5.7, Java 25,
    MyBatis, managed Postgres").

## Capabilities, not paths

Per the methodology's staleness principle: Layer 1 names **what a repo does and how it
connects**, never **which file does it**. Do not include file paths, line numbers, or
directory trees. If a section is tempted to cite a specific file, replace it with the
capability that file provides.

If a file reference is genuinely unavoidable, it **must** satisfy
`${CLAUDE_PLUGIN_ROOT}/scripts/check-doc-paths.sh` (the path-existence guard) — i.e. the referenced path must
actually exist relative to the doc, or use one of the guard's recognized exemptions
(URL, `~`-path, `/UPPER/PLACEHOLDER/` example, in-page `#anchor`). An index with a dead
file link fails the guard and fails review.

## Filled example (2 repos)

This example is itself a valid Layer-1 index — every required field is present on both
repo sections, and both cross-repo edges are listed on both endpoints.

---

# Storefront Workspace

> A small commerce platform, split into a backend API repo and a frontend SPA repo that
> share a managed Postgres database (auth/data) and a payment-provider account (billing).

## catalog-api

- **Purpose:** Owns catalog, customer, and pricing data; issues product documents; handles
  subscription billing.
- **Role:** Backend REST API — the single source of truth for catalog data.
- **Entry points:** REST API under `/api/*`; Spring Boot application entry via the
  Maven Wrapper run target.
- **Cross-repo links:** Serves the REST API that storefront-web calls; shares the managed
  Postgres database (auth + data) and the payment-provider account with storefront-web.
- **Stack:** Spring Boot 3.5.7, Java 25, MyBatis, managed Postgres.

## storefront-web

- **Purpose:** Customer-facing and merchant-facing UI for browsing the catalog, managing
  customers/pricing, and billing.
- **Role:** Frontend SPA — the primary user interface, calls the backend for all data.
- **Entry points:** Vite dev server entry (`npm run dev`); the built static site is the
  production entry point.
- **Cross-repo links:** Calls catalog-api's REST API for all data operations; shares the
  managed Postgres database (auth) and the payment-provider account (checkout/portal)
  with catalog-api.
- **Stack:** Vite 6, React 19, TypeScript, Tailwind v4, shadcn/ui.

---

## Monorepo variant (one repo, many components)

When the target is a **single monorepo** (not a workspace of sibling repos), the index
answers "which **component**?" The shape mirrors the multi-repo one, with these changes:

- **H1** — the monorepo name; **blockquote summary** — one or two lines.
- **One H2 per component** — a deployable unit (an `application`, or a `service`) or a
  shared `library` — each with:
  - **Purpose** — what this component is for.
  - **Role** — its position + the **role tag** in parentheses: `(application)` /
    `(service)` / `(shared library)`.
  - **Entry points** — capabilities an agent starts from (not file listings).
  - **Cross-component links** — edges to sibling components as capabilities/contracts,
    **on both endpoints** (a shared lib's "consumed by X" ↔ X's "consumes it"). Same
    both-endpoints rule as multi-repo; a one-sided edge is a defect.
  - **Stack** — languages/frameworks/infra; the unprofiled `Layer-4 baseline only;
    Layer-3 profile TODO` marker applies unchanged, on its own unbroken line.
- **H2 naming:** `detect-mode.sh` emits container-qualified component paths
  (`unit component apps/api`). The H2 is the path's **last segment** — `## api`, never
  `## apps/api`. The qualified path is how a component is located on disk; the last
  segment is how it is named in the index.
- **A single `## Tooling & root config` note** — one line listing the collapsed
  tooling/infra dirs (`.github/`, `docker/`, `eslint-config-*`, etc.). Not a component H2.
- **A `## No-manifest candidates` note** — real-code dirs with no recognized build
  manifest, listed for human confirmation (per `component-detection.md`), never indexed as
  full components silently.

**Soft-cap grouped shape:** above ~15 components, group entries under a top-level-taxonomy
heading (`apps/`, `services/`, `libs/`) instead of a flat wall of H2s; per-component fields
are unchanged, only a grouping heading is added. Below the cap, use the flat shape.

**Mixed workspaces** — a multi-repo workspace where one member is itself a monorepo — are
handled by **recursive delegation** to that member's own component index, not by folding
every component into the parent document. See the **Mixed variant** section below.

### Filled monorepo example

# Acme Platform

> A polyglot monorepo: a web app and a Python API backed by a Rust ingest service, over a
> shared UI library.

## web

- **Purpose:** Customer-facing single-page app.
- **Role:** Frontend app (application). Calls the API; renders the product UI.
- **Entry points:** Vite dev server; built static bundle.
- **Cross-component links:** Consumes `shared-ui`; calls `api` over REST.
- **Stack:** TypeScript, React, Vite.

## api

- **Purpose:** Business API and persistence.
- **Role:** Backend service (service). Serves `web`; enqueues work for `ingest`.
- **Entry points:** REST API; ASGI app run target.
- **Cross-component links:** Called by `web`; hands ingestion work to `ingest`.
- **Stack:** Python 3.12, FastAPI.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._

## ingest

- **Purpose:** High-throughput event ingestion.
- **Role:** Backend service (service). Consumes work from `api`.
- **Entry points:** Cargo run target for the ingest binary.
- **Cross-component links:** Receives ingestion work from `api`.
- **Stack:** Rust (Cargo workspace).

## shared-ui

- **Purpose:** Reusable UI component library.
- **Role:** Shared library (shared library). Imported by app components.
- **Entry points:** Package import (its published/workspace entry).
- **Cross-component links:** Consumed by `web`.
- **Stack:** TypeScript, React.

## Tooling & root config

- Tooling/infra (not components): `.github/` (CI), `eslint-config-acme` (shared lint config).

## No-manifest candidates

- `docs-site/` — real content, no recognized build manifest; confirm whether to index.

### Blank monorepo template

```markdown
# <Monorepo Name>

> <One or two line summary.>

## <component-name>

- **Purpose:**
- **Role:** <… (application | service | shared library)>
- **Entry points:**
- **Cross-component links:**
- **Stack:**

## Tooling & root config

- <collapsed tooling/infra dirs>

## No-manifest candidates

- <real-code dirs with no recognized manifest, for confirmation>
```

## Mixed variant (a member that is itself a monorepo)

A **mixed workspace** is a multi-repo workspace where **one or more members are
themselves monorepos** (the `monorepo-member` shape from `${CLAUDE_PLUGIN_ROOT}/scripts/detect-mode.sh`,
per `component-detection.md`). The parent workspace index keeps the **multi-repo shape
unchanged** for plain members. A monorepo-member's H2 keeps the usual Purpose / Entry
points / Cross-repo links / Stack fields, and gains:

- **Role** — carries the `(monorepo member)` tag alongside its normal role, e.g.
  "Frontend + API platform (monorepo member)."
- **Components** — a **delegation pointer** to the member's own component index, plus the
  explicit **boundary marker**: *"this member owns its own components; the parent's scope
  ends here."* The member's component index (the existing monorepo variant, verbatim)
  lives at one of two locations — never both:
  - `<workspace-root>/<member>.index.md` — **host-at-root**, the default on a
    parent-scoped run (keeps the plugin's writes out of a repo the user may not own; also
    yields a stable dogfood oracle).
  - `<member>/workspace-index.md` — **in-place**, only when the user explicitly
    **targeted** that member at invocation (the existing monorepo bootstrap run on that
    member's own directory) — never inferred, never offered on a parent-scoped run.
  - **Optional, soft-capped shallow list.** If present it MUST begin with the verbatim
    prefix `Shallow list:` inside the `Components:` field, followed by
    `` `<component>` (<role>) `` entries. That literal prefix is the only signal tools may
    key on — `onboard` maintains an existing list and never creates one, so a list that is
    merely implied by prose does not exist. Past the soft cap — the same **~15 components**
    threshold defined above under "Soft-cap grouped shape" in the Monorepo variant section
    — use pure delegation instead: if adding a component would push the member's component
    count past ~15, drop the `Shallow list:` clause entirely rather than leave a capped list
    looking exhaustive.
- **Who checks the delegation pointer.** The pointer is written as **backtick prose**
  (`` `<member>.index.md` ``), never as a markdown link — and
  `${CLAUDE_PLUGIN_ROOT}/scripts/check-doc-paths.sh` extracts **only** markdown-link
  references (a bracketed label immediately followed by a parenthesised path — the
  literal syntax is not written out here, because the guard would extract it from this
  very sentence). So the guard does **not** check the pointer, in either
  location form. Existence of the member index is validated instead by **`audit`**, whose
  cross-file delegation check resolves each parent pointer to a real member index and
  reports a dangling one (and, in this plugin's own tests, by `grade-mixed-index.sh`).
  Should a pointer ever be written as a markdown link, the guard *does* check it —
  including the in-place `<member>/workspace-index.md` form, which the generalized
  sibling-repo skip used to swallow (every member repo has its own `.git`)
  until an explicit exemption for plugin-authored `workspace-index.md` / `*.index.md`
  targets was added. A pointer to an
  as-yet-unpopulated member index is **valid** (noted "run bootstrap on this member to
  populate"), not a dead ref. On regenerate, the pointer is **reconciled** to whichever
  location currently holds the member index; a stale index left at the other location from
  a prior run is **reported**, not silently ignored.
- **Recursion:** a monorepo-member that is itself mixed nests by the same delegation rule
  (bounded — v1 exercises one nesting level).

### Filled mixed example

# Acme Workspace

> A multi-repo workspace where the platform monorepo (`acme-platform`) sits alongside a
> standalone billing service.

## acme-platform

- **Purpose:** Houses the customer-facing web app, its API, and a shared UI library as a
  single monorepo.
- **Role:** Frontend + API platform (monorepo member).
- **Entry points:** See the member's own component index for per-component entry points.
- **Cross-repo links:** Calls `billing-service`'s REST API for invoicing data.
- **Components:** Delegates to `acme-platform.index.md` (host-at-root) — this member owns
  its own components; the parent's scope ends here. Shallow list: `web` (application),
  `api` (service), `shared-ui` (shared library).
- **Stack:** Polyglot (TypeScript/React, Python/FastAPI) — see the member's own index for
  per-component stacks.

## billing-service

- **Purpose:** Standalone billing and invoicing service.
- **Role:** Backend service.
- **Entry points:** REST API under `/billing/*`.
- **Cross-repo links:** Called by `acme-platform` for invoicing data.
- **Stack:** Go, Postgres.

### Blank mixed template

```markdown
# <Workspace Name>

> <One or two line summary of what this workspace is.>

## <monorepo-member-name>

- **Purpose:**
- **Role:** <... (monorepo member)>
- **Entry points:**
- **Cross-repo links:**
- **Components:** Delegates to `<monorepo-member-name>.index.md` (host-at-root), or
  `<monorepo-member-name>/workspace-index.md` if the user targeted this member directly —
  this member owns its own components; the parent's scope ends here. Shallow list:
  `<component-name>` (<role>), ...   ← optional; if included, keep the `Shallow list:`
  prefix verbatim (it is the only marker tools key on), else omit the clause entirely.
- **Stack:**

## <plain-repo-name>

- **Purpose:**
- **Role:**
- **Entry points:**
- **Cross-repo links:**
- **Stack:**
```

## Blank template

```markdown
# <Workspace Name>

> <One or two line summary of what this workspace is.>

## <repo-name>

- **Purpose:**
- **Role:**
- **Entry points:**
- **Cross-repo links:**
- **Stack:**

## <repo-name>

- **Purpose:**
- **Role:**
- **Entry points:**
- **Cross-repo links:**
- **Stack:**
```

## Checklist before publishing an index

- [ ] Every repo in the workspace has a section.
- [ ] Every section has all five fields: Purpose, Role, Entry points, Cross-repo links,
      Stack.
- [ ] Every cross-repo edge appears on both endpoints.
- [ ] No file paths, line numbers, or directory trees — capabilities only.
- [ ] Any file reference that does appear passes `${CLAUDE_PLUGIN_ROOT}/scripts/check-doc-paths.sh`.
