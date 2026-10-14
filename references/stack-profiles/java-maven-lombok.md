verified: 2026-06-28, Serena (serena-agent) 1.5.3, jdtls 1.60.0 (optional toolchain reuse), Lombok 1.18.42

## Languages/build tool

Java (project's target version, e.g. Java 25), Maven (`./mvnw`). Lombok-heavy codebases
(`@Getter`/`@Setter`/`@RequiredArgsConstructor` etc. generating synthetic members) are the
motivating case — plain accessor find-references is exactly what grep can't disambiguate
(see Verification command below).

## Layer-3 tool(s)

Layer 3b — exact symbol navigation (LSP). Primary: **Serena** (MCP server wrapping a
bundled or reused jdtls). Secondary/opt-in: Claude Code's native `jdtls-lsp` plugin (see
"Advanced/opt-in: native jdtls-lsp" below) — do not lead with it; its only Lombok fix is
brittle (see Gotchas).

### Why Serena leads

Both paths deliver **exact** Lombok-aware `find-references` once configured (verified:
same 4/4 call sites, same exclusions). The difference is where the Lombok fix lives:

| | Native `jdtls-lsp` (CC plugin) | Serena (MCP) |
|---|---|---|
| Lombok fix location | **global**, per-machine `marketplace.json` patch | **project-local** `.serena/project.local.yml` + one-time `~/.serena` trust entry |
| Survives a Claude Code plugin update | ❌ no — silently dropped | ✅ yes |
| Out-of-the-box Lombok | ❌ needs the patch | ✅ bundled Lombok agent, zero config |
| Lombok in symbol overview | ❌ hidden (synthetic members) | ✅ listed |

Serena is the **less-brittle, project-scoped** option and is what this profile verifies
by default. Reach for native `jdtls-lsp` only if you specifically want the built-in `LSP`
tool and accept the global-patch cost (see below).

## Install (discover paths, never hardcode)

1. **Install Serena** (pinned, stable release — not `uvx --from git+…`, which can pull an
   unreleased `main` and hit dependency-version warnings):
   ```bash
   uv tool install -p 3.13 serena-agent
   ```
   Puts `serena` on `PATH` (discover with `which serena`) in an isolated `uv` venv.

2. **Register the MCP server** at local scope, pointing at the target repo (discover the
   repo path from where you're standing — don't hardcode another machine's path):
   ```bash
   claude mcp add serena -s local -- serena start-mcp-server --context claude-code --project "$(pwd)"
   ```

3. **(Optional) reuse your own toolchain instead of Serena's bundled vscode-java** (~465
   MB, bundled JRE 21, bundled Lombok). Discover the paths at run time — never paste an
   absolute path from one developer's machine into a committed file:
   ```bash
   # newest resolved Lombok jar for this project
   LOMBOK_JAR="$(find ~/.m2/repository/org/projectlombok/lombok -name 'lombok-*.jar' 2>/dev/null | sort -V | tail -1)"

   # a JDK whose version >= the project's target Java version (macOS)
   JAVA_HOME_DISCOVERED="$(/usr/libexec/java_home -v 25 2>/dev/null || /usr/libexec/java_home)"

   # an installed jdtls, if you want Serena to launch it instead of its own bundle
   JDTLS_DIR="$(brew --prefix jdtls 2>/dev/null)/libexec"
   ```
   Any JDK distribution works (Corretto, Temurin, Zulu, Homebrew) as long as its version is
   `>= max(project Java version, jdtls's own runtime minimum, ~17)` — one newer JDK covers
   older projects too.

4. **Restart to pick up the MCP tools** — `claude mcp add` (local/user scope) is **not**
   loaded mid-session; there is no reload for MCP servers. Use `claude --resume` (fresh
   process, transcript preserved) or a full restart.

## Config requirements

- `.serena/` in the target repo should be gitignored — it's local tooling state, not a
  committed artifact.
- To use the discovered toolchain from step 3 above (rather than Serena's bundled
  fallback), write `<repo>/.serena/project.local.yml`:
  ```yaml
  ls_specific_settings:
    java:
      jdtls_path: "$JDTLS_DIR"        # discovered, not hardcoded
      lombok_path: "$LOMBOK_JAR"      # discovered, not hardcoded
      java_home: "$JAVA_HOME_DISCOVERED"
  read_only: true   # Serena is edit-capable; keep nav-only against a real repo
  ```
- **Required for the above to take effect:** add the workspace path to
  `trusted_project_path_patterns` in `~/.serena/serena_config.yml`:
  ```yaml
  trusted_project_path_patterns:
  - /path/to/your/workspace/**
  ```
  Serena **silently ignores** project-local `ls_specific_settings` on an untrusted path (a
  security feature, since those settings launch executables) and falls back to its bundled
  toolchain instead — which still resolves Lombok, just not with your exact jar/JDK.
- No Maven-project "import" step is needed for Serena the way it is for native jdtls —
  Serena's onboarding/indexing handles this itself.

## Verification command + expected result

Against a Lombok-heavy Java file with a `@Getter`-generated accessor with several call
sites across the codebase, plus unrelated same-named accessors on other types and one
commented-out call — run Serena's `find_referencing_symbols` on the getter.

**Verified example:** `find_referencing_symbols` on a Lombok `@Getter`-generated accessor
of a domain row type — a getter with no explicit method body anywhere in source, whose
name is also declared on several unrelated types in the same codebase.

**Expected result:** exactly the real call sites (verified: 4), each a genuine live call —
**excluding** any commented-out call on the same symbol, and **not** matching same-named
accessors on unrelated types (verified: Serena excluded ~26 other same-named accessor
calls that a plain `grep` for the accessor returns indiscriminately). If the tool instead returns
0 references or the full unfiltered grep-sized set, the Lombok agent isn't loaded or the
project isn't trusted — recheck Config requirements above.

## Verified envelope

**Strong — use Serena for:**
- **`find_referencing_symbols` (reverse refs) on Lombok-generated members** — exact and
  type-aware; this is where it demonstrably beats grep (disambiguates same-named accessors
  across types, skips commented-out code).
- **`get_diagnostics_for_file`** — clean/empty on files whose Lombok accessors resolve
  correctly; a fast way to confirm the toolchain is working before trusting other results.
- **`get_symbols_overview`** — lists Lombok-generated accessors explicitly (an advantage
  over native jdtls, whose `documentSymbol` hides synthetic members).
- **Go-to-definition, where it's strong:** ordinary (non-synthetic) Java symbols — regular
  methods, fields, classes — resolve normally.

**Blind spot — Layer 4 still wins here:**
- Go-to-definition **on the Lombok-generated member itself** has no source line to land
  on (Lombok generates it at compile time; there's no hand-written getter/setter in the
  file). Use `find_referencing_symbols` or diagnostics to confirm resolution instead of
  expecting a jump target.

## Advanced/opt-in: native `jdtls-lsp`

Claude Code's built-in `LSP` tool (via the `jdtls-lsp` plugin) reaches the **same** exact
find-references result on Lombok members once configured — but only after installing
`brew install jdtls`, importing the Maven project, and loading a Lombok javaagent. That
Lombok fix is **not** something upstream lets you configure per-project: the only
injection point is a hand-patch to the **global**, per-machine
`~/.claude/plugins/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json`,
adding a `--jvm-arg=-javaagent:<lombok-jar>` entry under `lspServers.jdtls.args`.

**This is why it's opt-in, not the lead path:**
- The patch is **global and per-machine** — it can't be committed, doesn't travel with the
  repo, and has to be reapplied on every machine that wants it.
- **Claude Code overwrites this file on plugin update**, silently dropping the patch.
- Upstream has **not** shipped a supported way to pass jdtls JVM args:
  [claude-plugins-official#1000](https://github.com/anthropics/claude-plugins-official/issues/1000)
  is still **open**, and
  [claude-code#47561](https://github.com/anthropics/claude-code/issues/47561) is
  **closed as NOT_PLANNED** (checked live via `gh issue view`, 2026-07-11) — i.e. upstream
  does not currently intend to fix this.

If you still want it: reapply the patch after every plugin update — worth scripting
idempotently, since the marketplace file is rewritten wholesale and the patch must be
re-injected rather than merged — then `/reload-plugins` (no full restart needed —
verified). Prefer Serena above for anything beyond a one-off, single-machine check.

## Gotchas

- **Don't run the Serena CLI (e.g. its own indexing/health-check commands) while the MCP
  server for the same project is live** — concurrent access to Serena's index can corrupt
  it. Stick to one access path (the MCP tools via Claude Code, or the CLI) per project at
  a time.
- **MCP tools load only at Claude Code startup.** Adding the server with `claude mcp add`
  mid-session does not make its tools available in that session — use `claude --resume`
  (or a full restart) before expecting `find_referencing_symbols` etc. to appear.
- **Lombok-generated members are synthetic** — they have no hand-written source location.
  Don't judge Lombok resolution by go-to-definition (nothing to jump to) or by
  `documentSymbol`/`get_symbols_overview` alone if using native jdtls (which hides them);
  **confirm via `find_referencing_symbols`** (or, for native jdtls, `hover`), which works
  even on synthetic members once the agent/toolchain is loaded.
- If `trusted_project_path_patterns` isn't set for the workspace, project-local toolchain
  reuse silently falls back to Serena's bundled toolchain (still correct, just not your
  pinned jar/JDK) — no error is raised, so verify with `get_current_config` if the exact
  version matters.
