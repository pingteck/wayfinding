verified: 2026-06-28, typescript-language-server 5.3.0

## Languages/build tool

TypeScript, Vite build tool (`npm run dev` / `npm run build`). Verified against a Vite +
React frontend.

## Layer-3 tool(s)

Layer 3b — exact symbol navigation (LSP). Tool: Claude Code's native `LSP` tool via the
`typescript-lsp` code-intelligence plugin, backed by `typescript-language-server`.

## Install (discover paths, never hardcode)

1. **Language server binary on `PATH`:**
   ```bash
   brew install typescript-language-server
   which typescript-language-server   # discover, confirm it's on PATH
   ```
   Installing the Claude Code plugin alone is **not** enough — without the binary on
   `PATH` you get "Executable not found in $PATH" even with the plugin installed.
2. **Install + load the Claude Code plugin:** install `typescript-lsp` from
   `claude-plugins-official`, then `/reload-plugins` (or restart) so the server spawns.

That's the entire setup — unlike the Java/Lombok profile, there is no further
project-import or agent-injection step for TypeScript.

## Config requirements

None beyond the install above — no project-import step, no agent injection, no trust
file. The server spawns and resolves forward navigation and diagnostics for the current
file plus its direct imports on its own.

## Verification command + expected result

Run `goToDefinition` (Claude Code `LSP` tool) on a call site that constructs/uses an
imported symbol.

**Verified example:** `goToDefinition` on a `new <Class>(...)` call site, in a factory
module that imports that class from a sibling module.

**Expected result:** resolves exactly to the class definition and its constructor, in the
defining module. Also confirm `documentSymbol` on the target file returns a full outline
(classes, methods, properties) — both are reliable out of the box.

**Do NOT treat `findReferences` as verified here** (see Verified envelope) — running it on
that same class *at its definition* returns **empty**, even though `grep` shows real
cross-file references (the factory module imports and instantiates it). This is the
expected, verified behavior, not a misconfiguration — see Gotchas.

## Verified envelope

**Strong — use LSP for:**
- **Go-to-definition (forward navigation)** — verified exact.
- **Diagnostics** (semantic errors/warnings on the current file) — verified working.

**Blind spot — Layer 4 wins here, explicitly:**
- **`findReferences` (reverse navigation / find-callers) under-returns in headless use**
  and must **not** be relied on for this stack. `typescript-language-server` lazily loads
  files: it resolves the queried file plus its imports, but not files that import *it* —
  reverse references need the referencing files to already be indexed, which doesn't
  happen in a one-off, on-demand headless invocation. **Use Layer-4 grep** (e.g.
  `grep -rn '<ClassName>' --include='*.ts*'` or the Explore agent) to find callers on this
  stack instead.

This envelope is **not symmetric** with the Java/Lombok profile, where `find-references`
is the strong, LSP-favored case once configured. On TypeScript, find-callers stays a
Layer-4 job; only go-to-definition and diagnostics graduate to Layer 3b here.

## Gotchas

- **`findReferences` under-returns vs grep — verified, not a fluke of one run.** Treat any
  "find all callers of X" task on this stack as a grep/Explore task, not an LSP task.
  Re-verify (don't assume) if a future `typescript-language-server` version changes this.
- **Plugin installed ≠ working.** The `typescript-lsp` Claude Code plugin and the
  `typescript-language-server` binary are two separate installs; missing the binary on
  `PATH` fails silently until first use ("Executable not found in $PATH"), so verify with
  `which typescript-language-server` before trusting any LSP result on this stack.
- No Lombok-style synthetic-member trap on this stack — plain TS/JS symbols always have a
  source location, so go-to-definition results are straightforward once the server is up.
