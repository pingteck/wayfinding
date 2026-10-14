# Stack profile format

A **stack profile** is a Layer-3 (dynamic augmentation) verification report for one
stack (one language/build-tool combination). It answers, empirically, "does a Layer-3
tool actually work here, and for what?" — per the methodology's rule that Layer-3 claims
must be verified on the actual stack before being trusted, never assumed from a tool's
general reputation.

Adding support for a new stack to this plugin means **authoring one file to this
contract** — nothing else in the plugin needs to change.

## Required sections

A stack profile must contain each of the following as a headed section, in this order.
The labels below must appear verbatim (as a heading or a bold label line) so they can be
mechanically checked.

### `verified:` header

The very first content in the file: a line starting with `verified:` giving the date the
verification was performed and the exact tool version(s) used. Example:

```
verified: 2026-07-11, jdtls 1.42.0, Serena 0.8.2
```

A stack profile with no `verified:` header is a claim, not a verification, and must not
be trusted.

### Languages/build tool

Which language(s) and build tool this profile covers (e.g. "Java 25, Maven via
`./mvnw`"). Scopes the rest of the profile to a concrete, checkable target.

### Layer-3 tool(s)

Which Layer-3 primitive(s) (3a symbol map / 3b LSP / 3c semantic search — see
`methodology.md`) this profile verifies, and the specific tool(s) used.

### Install (discover paths, never hardcode)

How to install/locate the tool **on the machine it's run on** — commands that discover
paths at run time (e.g. `which`, package-manager queries, searching under a project-local
tool dir), never a hardcoded absolute path from the verifying machine. A profile that
hardcodes a path from one developer's machine breaks on the next machine.

### Config requirements

Any project-local configuration the tool needs before it will resolve anything correctly
(e.g. "requires the Maven project to be imported/built once before jdtls can resolve
cross-file references"; "requires a `.serena/project.yml` per project"). Per the
methodology's caveat: several LSP-class tools return nothing useful until this step is
done — this section exists specifically to prevent that trap from recurring silently.

### Verification command + expected result

The **exact command** run to verify the tool, and the **exact expected result** — concrete
enough that re-running it either reproduces the verified claim or reveals it has rotted.
Not "it works" — the actual invocation and actual output/count/behavior observed.

### Verified envelope

Which navigation operations this tool is empirically good for on this stack, **and**
where its blind spots are — i.e. where Layer 4 (careful grep) wins instead. Per the
methodology, a Layer-3 tool only earns its place where it demonstrably beats grep; this
section states the boundary explicitly rather than implying blanket superiority.

### Gotchas

Stack-specific traps found during verification that don't fit the sections above (e.g.
under-returned references in headless mode, timeouts on first index, version-specific
breakage).

## Note

Adding a new stack to this plugin = authoring one file to this contract. No skill code,
no scripts, and no other reference file need to change — `bootstrap`/`onboard`/`audit`
consume whichever stack profiles exist by reading their `verified:` header and required
sections.

## Blank template

```markdown
verified: <YYYY-MM-DD>, <tool> <version>[, <tool2> <version>]

## Languages/build tool

## Layer-3 tool(s)

## Install (discover paths, never hardcode)

## Config requirements

## Verification command + expected result

## Verified envelope

## Gotchas
```
