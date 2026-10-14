#!/usr/bin/env bash
# Authoritative mechanical detection for wayfinding. Pure bash, no external deps,
# never invokes git. Emits: mode=, root=, and sorted `unit <shape> <relpath>` lines.
set -uo pipefail
shopt -s dotglob nullglob
TARGET="${1:-.}"
[ -d "$TARGET" ] || { echo "mode=ambiguous"; echo "root=$TARGET"; exit 0; }
ROOT="$(cd "$TARGET" && pwd)"

IGNORE_DIRS='node_modules vendor target dist build .venv __pycache__ .git'
# Adding an ecosystem means editing these lists AND references/component-detection.md
# §Supported ecosystems (mirrored in README.md) — they are a matched pair. Until 2026-10-14
# root_ships_code() carried a THIRD hand-copied list, which is how `build.gradle.kts` could be
# missing from all of them unnoticed. It now reads MODULE_MANIFESTS.
MANIFESTS='pyproject.toml setup.py go.mod Cargo.toml pom.xml build.gradle build.gradle.kts package.json'
# Manifests that mean "this directory ships a module of its own". Distinct from MANIFESTS:
# a bare package.json is excluded, because root devDeps + a `workspaces` array is the
# near-universal JS convention and does not mean the root ships code. (Cargo.toml is handled
# separately: only a `[package]` table means a module, a bare `[workspace]` does not.)
MODULE_MANIFESTS='go.mod pom.xml pyproject.toml setup.py build.gradle build.gradle.kts'
WORKSPACE_CONFIGS='pnpm-workspace.yaml go.work nx.json turbo.json lerna.json rush.json'
MAX_DEPTH=6   # ADVISORY/documentation-only: depth is structural (one-level walk), never recursive.

# M3: reject any declared/scanned path that escapes the root via .. or an absolute path.
is_contained() { # is_contained <root> <candidate-abs-or-rel>
  case "$2" in /*) return 1;; esac          # absolute -> reject
  case "$2" in *..*) return 1;; esac        # parent-escape -> reject
  return 0
}

# H4: is a directory entry a symlink (not to be followed during any walk)? Strip a
# trailing slash first — `-L` silently reports false on a symlink path with a trailing
# slash because the shell resolves through the link before stat'ing.
is_symlink_entry() { local p="${1%/}"; [ -L "$p" ]; }

# emit collects `unit <shape> <relpath>` lines; printed sorted (deduped) at the end.
UNITS=""
emit() { UNITS="${UNITS}unit $1 $2"$'\n'; }

is_ignored_dir() { case " $IGNORE_DIRS " in *" $1 "*) return 0;; *) return 1;; esac; }

# A dir is an INDEPENDENT repo if it has its own CLAUDE.md and/or .git (file or dir — L1).
is_independent_repo() { [ -e "$1/.git" ]; }

# ---------------------------------------------------------------------------------------
# DECLARED MEMBER SET (findings F3/F4/F5). The declared set is AUTHORITATIVE about which
# paths are members and which are excluded; the one-level scan below is ADDITIVE on top of
# it. Before this, the declared entries were only ever COUNTED as an H1 threshold input and
# then thrown away, while component enumeration globbed for manifests independently — one
# root cause behind three field defects.
# ---------------------------------------------------------------------------------------
DECLARED_MEMBERS=""        # newline-separated root-relative dirs, globs already expanded
DECLARED_NEGATED=""        # newline-separated root-relative dirs to suppress (`!` entries)
DECLARED_ROOT_MEMBER=0     # 1 iff `.` is declared a member (F5)

path_has_ignored_segment() {
  local seg IFS=/
  for seg in $1; do is_ignored_dir "$seg" && return 0; done
  return 1
}

# go.work `use` directives, BOTH forms: single-line `use ./x` and the block
# `use ( ... )`. The old one-line sed captured the literal `(` from the opening line and
# nothing else, so a 5-member go.work counted as 1 and fell below the >=2 threshold.
go_work_entries() {
  local file="$1" line lt rest tok inblock=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%//*}"                              # drop // comments
    lt="${line#"${line%%[![:space:]]*}"}"            # ltrim
    if [ "$inblock" = 1 ]; then
      case "$lt" in ')'*) inblock=0; continue;; esac
      for tok in $lt; do printf '%s\n' "$tok"; done
      continue
    fi
    case "$lt" in
      use[[:space:]]*'('*|use'('*)                   # block form (possibly closed same line)
        rest="${lt#*(}"; inblock=1
        case "$rest" in *')'*) rest="${rest%%)*}"; inblock=0;; esac
        for tok in $rest; do printf '%s\n' "$tok"; done ;;
      use[[:space:]]*)                               # single-line form
        rest="${lt#use}"
        for tok in $rest; do printf '%s\n' "$tok"; done ;;
    esac
  done < "$file"
}

# Cargo `[workspace]`: `members` entries as-is, `exclude` entries prefixed `!` so they
# SUBTRACT exactly like pnpm negations. Only those two keys are read. The previous parser took
# every quoted string in the table, so `exclude` paths became members — and `resolver = "2"`
# became a member entry too, harmless only because no directory is called `2`. Arrays may
# span lines; `#` comments are dropped (Cargo paths do not contain `#`).
cargo_workspace_entries() {
  awk '
    /^[[:space:]]*\[/ { inws = ($0 ~ /^[[:space:]]*\[workspace\][[:space:]]*(#.*)?$/); key=""; inarr=0; next }
    !inws { next }
    { sub(/#.*/, "") }
    !inarr && /^[[:space:]]*[A-Za-z_-]+[[:space:]]*=/ {
      key=$0; sub(/^[[:space:]]*/, "", key); sub(/[[:space:]]*=.*/, "", key)
      val=$0; sub(/^[^=]*=/, "", val)
      inarr = (val ~ /\[/ && val !~ /\]/)
      emit(val); next
    }
    inarr { if ($0 ~ /\]/) inarr=0; emit($0) }
    function emit(s,   m) {
      if (key != "members" && key != "exclude") return
      while (match(s, /"[^"]+"/)) {
        m = substr(s, RSTART+1, RLENGTH-2)
        print (key == "exclude" ? "!" : "") m
        s = substr(s, RSTART+RLENGTH)
      }
    }
  ' "$1"
}

# Emit one line per declared entry as `+<path>` or `-<path>` (negated). Raw and unexpanded:
# quote-stripped and `./`-normalised only. Containment and glob expansion happen in
# declared_resolve, so every ecosystem gets the same validation.
declared_entries_raw() {
  local d="$1" e sign w
  {
    if [ -f "$d/pnpm-workspace.yaml" ]; then
      sed -nE 's/^[[:space:]]*-[[:space:]]*//p' "$d/pnpm-workspace.yaml" 2>/dev/null \
        | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
    fi
    if [ -f "$d/package.json" ] && grep -q '"workspaces"' "$d/package.json" 2>/dev/null; then
      # entries inside the workspaces array (best-effort, single or array form)
      w=$(tr -d '\n' < "$d/package.json" | sed -nE 's/.*"workspaces"[^][]*\[([^]]*)\].*/\1/p')
      printf '%s' "$w" | grep -oE '"[^"]+"' | sed -E 's/^"(.*)"$/\1/'
    fi
    if [ -f "$d/Cargo.toml" ] && grep -q '^\[workspace\]' "$d/Cargo.toml" 2>/dev/null; then
      cargo_workspace_entries "$d/Cargo.toml"
    fi
    [ -f "$d/go.work" ] && go_work_entries "$d/go.work"
  } | while IFS= read -r e; do
        sign=+
        case "$e" in '!'*) sign=-; e="${e#!}";; esac
        e="${e#./}"; e="${e%/}"
        [ -n "$e" ] || continue
        printf '%s%s\n' "$sign" "$e"
      done
}

# Resolve a dir's declared entries into DECLARED_MEMBERS / DECLARED_NEGATED /
# DECLARED_ROOT_MEMBER. Globs expand against the real tree; `*` therefore yields the actual
# member dirs instead of counting as one entry. M3: is_contained runs on the RAW entry, so a
# hostile `../../../etc/*` is dropped before expansion and can neither inflate the count nor
# reach the output; each expanded path is re-checked belt-and-braces.
declared_resolve() {
  local d="$1" line sign entry p rel
  DECLARED_MEMBERS=""; DECLARED_NEGATED=""; DECLARED_ROOT_MEMBER=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    sign="${line%"${line#?}"}"; entry="${line#?}"
    is_contained "$d" "$entry" || continue
    if [ "$entry" = "." ]; then
      [ "$sign" = "+" ] && DECLARED_ROOT_MEMBER=1
      continue
    fi
    for p in "$d"/$entry/; do
      [ -d "$p" ] || continue
      is_symlink_entry "$p" && continue
      rel="${p#"$d"/}"; rel="${rel%/}"
      case "$rel" in /*|*..*) continue;; esac
      path_has_ignored_segment "$rel" && continue
      if [ "$sign" = "-" ]; then DECLARED_NEGATED="${DECLARED_NEGATED}${rel}"$'\n'
      else DECLARED_MEMBERS="${DECLARED_MEMBERS}${rel}"$'\n'; fi
    done
  done < <(declared_entries_raw "$d")
}

# WHOLE-PATH membership test against the negated list. The newline delimiters on BOTH sides
# are load-bearing: a substring test would let `!packages/turbo` also suppress
# `packages/turbo-extra`. Substring-vs-whole-token is this project's dominant defect class.
is_negated() { case $'\n'"$DECLARED_NEGATED" in *$'\n'"$1"$'\n'*) return 0;; esac; return 1; }

# F5: does the root itself ship code? True iff it is a declared member (`.`), or it carries a
# manifest that is more than a workspace container. A bare root `package.json` does NOT count
# — holding devDeps/`workspaces` at the root is the near-universal JS convention and does not
# mean the root ships a module. A root `go.mod` DOES: Go's one-module-per-repo model is
# exactly what floods the no-manifest-candidate list (F3). Requires declared_resolve first.
root_ships_code() {
  local d="$1"
  [ "$DECLARED_ROOT_MEMBER" = 1 ] && return 0
  local m
  for m in $MODULE_MANIFESTS; do [ -f "$d/$m" ] && return 0; done
  [ -f "$d/Cargo.toml" ] && grep -q '^\[package\]' "$d/Cargo.toml" 2>/dev/null && return 0
  return 1
}

# H1 threshold input: how many members does this dir DECLARE? Counts expanded, contained,
# non-negated members, plus `.` when declared.
declared_member_count() {
  local d="$1" n=0 m
  declared_resolve "$d"
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    is_negated "$m" || n=$((n + 1))
  done <<< "$DECLARED_MEMBERS"
  [ "$DECLARED_ROOT_MEMBER" = 1 ] && n=$((n + 1))
  printf '%s' "$n"
}

has_workspace_config() {
  local d="$1" c
  for c in $WORKSPACE_CONFIGS; do [ -f "$d/$c" ] && return 0; done
  [ -f "$d/package.json" ] && grep -q '"workspaces"' "$d/package.json" 2>/dev/null && return 0
  [ -f "$d/Cargo.toml" ] && grep -q '^\[workspace\]' "$d/Cargo.toml" 2>/dev/null && return 0
  return 1
}

# tooling test: known infra dir names OR a manifest matching a tooling pattern.
is_tooling_dir() {
  local rel="$1" base; base="$(basename "$rel")"
  case "$base" in .github|docker|bin|scripts|tools) return 0;; esac
  case "$base" in eslint-config-*|prettier-*) return 0;; esac
  case "$base" in *) return 1;; esac
}

# Does a dir (its own top level only — no recursion) contain a recognized manifest?
dir_has_manifest() {
  local d="$1" m
  for m in $MANIFESTS; do [ -f "$d/$m" ] && return 0; done
  return 1
}

# Enumerate top-level components of a monorepo root.
#
# PASS 1 — the DECLARED set is authoritative. Each expanded, non-negated declared member is
# emitted at its declared depth, however deep (`documentation/examples/remote_storage` is a
# real go.work member). `.` becomes `root-component .` when the root ships code.
#
# PASS 2 — an ADDITIVE one-level scan, so an undeclared-but-manifested dir is still found.
# For each immediate child of root:
#   - negated by the declared set     -> skipped entirely (authoritative exclusion)
#   - tooling name pattern            -> emit tooling <basename>
#   - own manifest at that level      -> emit component <basename>  (roll-up: never descend
#                                        further — a Cargo/pnpm workspace nested inside an
#                                        already-manifested dir stays ONE component)
#   - neither (a bare container, e.g. apps/ packages/ services/) -> descend exactly one level:
#       - tooling child   -> emit tooling <parent>/<child>   (path keeps the container parent)
#       - manifested child -> emit component <parent>/<child> (rolled up the same way)
#       - if the container yields NO recognized child at all -> the container itself is a
#         no-manifest-candidate (e.g. a docs-site/ with only prose, no subdirs) — UNLESS the
#         root ships code, in which case the dir is a package of the root module and is
#         therefore explained, not a candidate (F3: this is what emitted ~18 phantom
#         candidates for one plain Go repo).
enumerate_components() {
  local root="$1" child rel g gbase grel found m
  declared_resolve "$root"

  # PASS 1: declared members (authoritative).
  # `root-component` is deliberately its own shape, not `component .`: a heading of `.` is
  # nonsense, and a silently-mishandled new state is the defect class this fix exists to kill.
  # It also must not be counted by is_monorepo_member's `^unit component ` grep — the shape
  # name differing at the START of the token is what keeps that anchored match honest.
  root_ships_code "$root" && emit root-component .
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    is_negated "$m" && continue
    if is_tooling_dir "$m"; then emit tooling "$m"; else emit component "$m"; fi
  done <<< "$DECLARED_MEMBERS"

  # PASS 2: additive scan.
  for child in "$root"/*/; do
    [ -d "$child" ] || continue
    is_symlink_entry "$child" && continue   # H4: never follow a symlinked entry
    rel="$(basename "$child")"
    is_ignored_dir "$rel" && continue
    is_negated "$rel" && continue            # F4: declared `!` exclusion wins over discovery

    if is_tooling_dir "$rel"; then
      emit tooling "$rel"
      continue
    fi
    if dir_has_manifest "$child"; then
      emit component "$rel"
      continue
    fi

    # bare container: no manifest of its own, not tooling -> descend one level
    found=0
    for g in "$child"*/; do
      [ -d "$g" ] || continue
      is_symlink_entry "$g" && continue     # H4: never follow a symlinked entry
      gbase="$(basename "$g")"
      is_ignored_dir "$gbase" && continue
      grel="$rel/$gbase"
      is_negated "$grel" && continue          # F4: `!packages/turbo` must survive the descent
      if is_tooling_dir "$gbase"; then
        emit tooling "$grel"
        found=1
      elif dir_has_manifest "$g"; then
        emit component "$grel"
        found=1
      fi
    done
    # F5/F3: when the root ships code, an unmanifested dir is a package of the root module —
    # explained, so not a candidate. Only an unexplained dir is worth flagging to the user.
    [ "$found" = 0 ] && ! root_ships_code "$root" && emit no-manifest-candidate "$rel"
  done
}

# H4: if cwd is INSIDE a member (itself a repo, no independent-repo children) and its parent
# is a managed workspace root, resolve up ONE level. Mechanical membership-validation only
# (existence/config checks — never git, never more than one level).
resolve_root() {
  local start="$1" parent has_indep_child=0 child
  for child in "$start"/*/; do
    [ -d "$child" ] || continue
    is_symlink_entry "$child" && continue
    is_independent_repo "$child" && has_indep_child=1
  done
  # cwd already contains repos, or has a workspace config -> it is the root
  if [ "$has_indep_child" = 1 ] || has_workspace_config "$start"; then printf '%s' "$start"; return; fi
  # cwd is itself a repo? and parent has a cross-repo CLAUDE.md (the only walk-up signal;
  # fail-closed: no cross-repo CLAUDE.md at the parent -> stay put, never guess from sibling
  # count alone, or a cwd inside any generic multi-repo folder would get silently bundled).
  if is_independent_repo "$start"; then
    parent="$(cd "$start/.." && pwd)"
    if [ -f "$parent/CLAUDE.md" ]; then printf '%s' "$parent"; return; fi
  fi
  printf '%s' "$start"
}


# Same-ecosystem veto. Answers: is the root a module whose manifested children are a
# DIFFERENT ecosystem (satellites), or the same one (siblings)?
#   root go.mod  over JS package.json children -> satellites -> VETO
#   root pom.xml over pom.xml children         -> aggregator over siblings -> no veto
#
# Two things here are load-bearing and were established the hard way:
#
# 1. It consults EMITTED component units, never a raw manifest scan. A Go service with a JS
#    UI typically also has `internal/tools/go.mod`; a raw scan reads that as a same-ecosystem
#    sibling and skips the veto, inverting the motivating case. enumerate_components
#    classifies it as TOOLING, so it is correctly absent from the component set.
# 2. It is deliberately NOT root_ships_code(). That function answers a different question —
#    "is an unmanifested subdir explained by the root module?" — and reusing it here demotes
#    EVERY Maven/Gradle/Python monorepo, because declared_entries_raw has no parser for those
#    ecosystems (so their declared count is structurally 0) while their root manifests are in
#    its file list. Validated on a 25-repo ecosystem corpus: 1 veto, zero false vetoes.
veto_discovered() { # veto_discovered <dir> <newline-separated component relpaths>
  local d="$1" comps="$2" c m rooteco=""
  for m in $MODULE_MANIFESTS; do [ -f "$d/$m" ] && rooteco="$rooteco $(manifest_ecosystem "$m")"; done
  [ -f "$d/Cargo.toml" ] && grep -q '^\[package\]' "$d/Cargo.toml" 2>/dev/null && rooteco="$rooteco cargo"
  [ -n "$rooteco" ] || return 1            # root ships no module -> nothing to veto
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    for m in $MODULE_MANIFESTS Cargo.toml; do
      [ -f "$d/$c/$m" ] || continue
      # a component shares the root's ECOSYSTEM -> siblings, not satellites
      case " $rooteco " in *" $(manifest_ecosystem "$m") "*) return 1;; esac
    done
  done <<< "$comps"
  return 0                                  # all satellites -> veto
}

# "Same ecosystem" is a property of the BUILD TOOL, not of the manifest filename. The veto
# compared exact filenames until 2026-10-14, so a root `build.gradle.kts` over `build.gradle`
# children (legal, and the normal state of a Gradle DSL migration) — or a root
# `pyproject.toml` over `setup.py` packages — read as two ecosystems and the whole monorepo
# was vetoed down to a plain repo. Fixtures: classify/gradle-mixed-dsl, py-mixed-manifests.
manifest_ecosystem() {
  case "$1" in
    build.gradle|build.gradle.kts) echo gradle ;;
    pyproject.toml|setup.py)       echo python ;;
    Cargo.toml)                    echo cargo ;;
    *)                             echo "$1" ;;
  esac
}

# THE shared monorepo predicate — called by BOTH the parent's member test and the target's
# own classification, so the two can no longer answer this question differently. (Note this
# does not make disagreement impossible: resolve_root may walk up one level BEFORE
# classification, so a scoped member run can still resolve to its parent. The skills carry a
# defensive branch for that; see the findings doc, R3.)
#
# Clause order is deliberate:
#   1. declared >= 2      — the repo's own explicit grouping, authoritative
#   2. same-ecosystem veto — a module root with only satellites is not a monorepo
#   3. workspace config    — nx/turbo/lerna/rush have no parser, so this is the ONLY signal
#                            they ever contribute; dropping it made deeply-nested Nx repos
#                            classify as plain repos with zero units
#   4. discovered >= 2     — the polyglot fallback
is_monorepo() {
  local d="$1" comps n dc=0 m
  declared_resolve "$d"     # in-shell, NOT via $(declared_member_count) — a command
                            # substitution would strand DECLARED_ROOT_MEMBER in a subshell
                            # and silently disable the `.`-declared branch below.
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    is_negated "$m" || dc=$((dc + 1))
  done <<< "$DECLARED_MEMBERS"
  [ "$DECLARED_ROOT_MEMBER" = 1 ] && dc=$((dc + 1))
  [ "$dc" -ge 2 ] && return 0

  # `sort -u` before counting is REQUIRED, not cosmetic: enumerate_components legitimately
  # emits the same unit twice when a path is both declared AND found by the additive scan.
  # Without dedup a repo with ONE real component counts 2 and is wrongly promoted.
  comps=$(UNITS=""; enumerate_components "$d" >/dev/null; printf '%s' "$UNITS" \
          | grep -E '^unit component ' | sed 's/^unit component //' | sort -u)
  n=$(printf '%s' "$comps" | grep -c '^')

  [ "$n" -ge 2 ] && veto_discovered "$d" "$comps" && return 1
  has_workspace_config "$d" && return 0
  [ "$n" -ge 2 ]
}

classify_and_emit() {
  local root="$1" child rel indep=0 had_mono=0
  # multi-repo iff >=1 immediate child is an independent repo
  for child in "$root"/*/; do
    [ -d "$child" ] || continue
    is_symlink_entry "$child" && continue   # H4: never follow a symlinked entry
    rel="$(basename "$child")"; is_ignored_dir "$rel" && continue
    if is_independent_repo "$child"; then indep=1; fi
  done
  if [ "$indep" = 1 ]; then
    for child in "$root"/*/; do
      [ -d "$child" ] || continue
      is_symlink_entry "$child" && continue   # H4: never follow a symlinked entry
      rel="$(basename "$child")"; is_ignored_dir "$rel" && continue
      if is_independent_repo "$child"; then
        if is_monorepo "$child"; then emit monorepo-member "$rel"; had_mono=1
        else emit repo "$rel"; fi
      fi
    done
    if [ "$had_mono" = 1 ]; then echo "mode=mixed"; else echo "mode=multi-repo"; fi
    echo "root=$root"
  elif is_monorepo "$root"; then
    echo "mode=monorepo"; echo "root=$root"
    enumerate_components "$root"
  else
    # Not a monorepo and not a multi-repo parent: ONE unit, nothing to route between.
    # Distinct from `ambiguous` ("could not decide — a human must"), which now survives only
    # for a target that is not a directory at all. Emits no `unit` lines: the single unit IS
    # `root=`. Consumers must treat this as a confident classification, not a failure.
    echo "mode=plain-repo"; echo "root=$root"
  fi
  printf '%s' "$UNITS" | grep -E '^unit ' | sort -u
  return 0
}
ROOT="$(resolve_root "$ROOT")"
classify_and_emit "$ROOT"
# Exit status is NOT a classification signal. Without this, the trailing `grep` finding no
# `unit` lines makes the script exit 1 under `pipefail` — which used to be a rare `ambiguous`
# curiosity but would now be the status for every ordinary single-repo target.
exit 0
