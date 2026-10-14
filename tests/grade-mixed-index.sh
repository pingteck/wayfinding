#!/usr/bin/env bash
# Mixed-index grader: parent router + cross-file delegation + REAL member-index assertions.
#
# Call shape unchanged: grade-mixed-index.sh <parent-index.md> <member-index-dir> [member]
# [name:tag ...]. Two extras, both opt-in so every existing call site is unaffected:
#   - a `--no-shallow-list` token anywhere among the trailing args asserts the parent's
#     Components: field for $MEMBER carries NO "Shallow list:" marker at all (D2-negative /
#     the D2-cap "dropped to pure delegation" case), instead of the default check that
#     (when a list IS present) it names exactly the member's component set.
#   - a $PROFILED environment variable (space-separated component names, default empty —
#     the mixed fixture has no profiled component) names which member components must
#     carry NO unprofiled marker; every other expected component must carry one (I2).
set -uo pipefail
# NOTE: <member> is positional ($3). --no-shallow-list is only recognised AFTER it, so pass the
# member name explicitly when using the flag: `... <parent> <memdir> web-monorepo --no-shallow-list`.
# Putting the flag in $3 makes it the member NAME — that fails loudly (no such H2), never silently.
PARENT="${1:?usage: grade-mixed-index.sh <parent-index.md> <member-index-dir> [member] [name:tag ...] [--no-shallow-list]}"
MEMDIR="${2:?missing member-index-dir}"
MEMBER="${3:-web-monorepo}"
shift 3 2>/dev/null || shift $#
NO_SHALLOW_LIST=0
ARGS=()
for a in "$@"; do
  if [ "$a" = "--no-shallow-list" ]; then NO_SHALLOW_LIST=1; else ARGS+=("$a"); fi
done
MEM_SPEC=(${ARGS[@]+"${ARGS[@]}"})
[ ${#MEM_SPEC[@]} -gt 0 ] || MEM_SPEC=("admin:(application)" "ui:(shared library)" "web:(application)")
PROFILED="${PROFILED:-}"
fail=0

need(){ grep -qiE "$1" "$PARENT" || { echo "MISS(parent): $2"; fail=1; }; }
need '^## plain-api'    "plain-api H2"
need '^## trap-lib'     "trap-lib H2 (trap stayed a plain member)"
need "^## $MEMBER"      "$MEMBER H2"

# --- member's own H2 section, extracted once and reused everywhere below (both for the
# three member-specific assertions right here and for the shallow-list block further down)
# instead of grep -qiE over the WHOLE parent file. A file-wide scan is satisfied by prose
# ANYWHERE — including this oracle's own "Notes for graders" section, which happens to
# contain "owns its own components" and "web-monorepo.index.md" in free text. That let a
# parent whose real $MEMBER "Components:" field was wiped down to "(none recorded)." still
# report MIXED INDEX OK, because the Notes section satisfied the assertions on the file's
# behalf. Anchoring to the member's own section closes that: the section runs from its
# "## $MEMBER" heading (exclusive) to the next "## " heading (exclusive).
member_section(){
  awk -v m="## $1" '
    /^## / { sec=$0; sub(/[[:space:]]+$/,"",sec); insec=(sec==m); next }
    insec { print }
  ' "$PARENT"
}
MEMBER_SECTION_RAW="$(member_section "$MEMBER")"
# Flattened, whitespace-squeezed copy for phrase checks: fields legitimately wrap (e.g.
# "...this member owns\n  its own components..."), so a literal multi-word regex must not
# be defeated by the line break — join lines and collapse runs of whitespace to one space.
MEMBER_SECTION_FLAT="$(printf '%s\n' "$MEMBER_SECTION_RAW" | tr '\n' ' ' | tr -s '[:space:]' ' ')"
need_in_member(){
  printf '%s' "$MEMBER_SECTION_FLAT" | grep -qiE "$1" || { echo "MISS(parent): $2"; fail=1; }
}
need_in_member 'monorepo member'  "$MEMBER tagged monorepo member (in its own section)"
need_in_member 'owns its own components' "boundary marker present (in $MEMBER's own section)"
need_in_member "$MEMBER\.index\.md" "delegation pointer to member index (in $MEMBER's own section)"

MI="$MEMDIR/$MEMBER.index.md"
[ -f "$MI" ] || { echo "MISS: member index $MI absent (dangling delegation)"; fail=1; echo "MIXED INDEX FAILED"; exit 1; }

# --- member component set: EXACT, with extras-check and anchored headings ---
EXPECTED=""; for s in "${MEM_SPEC[@]}"; do EXPECTED="$EXPECTED ${s%%:*}"; done
EXP_SORTED="$(printf '%s' "$EXPECTED" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed -E 's/ +$//')"
ACTUAL="$(grep -E '^## ' "$MI" | sed -E 's/^## +//; s/[[:space:]]+$//' \
  | grep -viE '^(Tooling & root config|No-manifest candidates|Notes for graders.*)$' \
  | sort -u | tr '\n' ' ' | sed -E 's/ +$//')"
if [ "$ACTUAL" != "$EXP_SORTED" ]; then
  echo "MISS(member): component set mismatch"
  echo "  expected: $EXP_SORTED"
  echo "  actual:   $ACTUAL"
  for c in $EXP_SORTED; do case " $ACTUAL " in *" $c "*) ;; *) echo "  MISSING: $c";; esac; done
  for c in $ACTUAL;     do case " $EXP_SORTED " in *" $c "*) ;; *) echo "  EXTRA:   $c";; esac; done
  fail=1
fi

# --- exactly one heading per component (a duplicate is invisible to the sort -u above) ---
for c in $EXP_SORTED; do
  n="$(grep -cE "^## ${c}[[:space:]]*$" "$MI")"
  [ "$n" = 1 ] || { echo "MISS(member): '## $c' appears $n time(s), expected exactly 1"; fail=1; }
done

# --- per-component role tag: the RIGHT tag on the RIGHT component (catches a swap) ---
role_ok() {
  awk -v comp="$1" -v tag="$2" '
    $0 ~ "^## "comp"[[:space:]]*$" {inseg=1; next}
    /^## / {inseg=0}
    inseg && /Role:/ && index($0,tag)>0 {ok=1}
    END{exit !ok}
  ' "$MI"
}
for s in "${MEM_SPEC[@]}"; do
  c="${s%%:*}"; tag="${s#*:}"
  role_ok "$c" "$tag" || { echo "MISS(member): $c should carry role tag $tag"; fail=1; }
done

# --- unprofiled marker SELECTIVITY (I2): on every unprofiled member component, on NONE
# that is profiled — mirrors grade-monorepo-index.sh:59-75. Deleting every marker line
# from the member index must fail this, not slide through as before (previously nothing
# in this grader ever looked for "Layer-4" at all).
marker_in() {
  awk -v comp="$1" '
    $0 ~ "^## "comp"[[:space:]]*$" {inseg=1; next}
    /^## / {inseg=0}
    inseg && index($0,"Layer-4 baseline only; Layer-3 profile TODO")>0 {found=1}
    END{exit !found}
  ' "$MI"
}
for c in $EXP_SORTED; do
  case " $PROFILED " in
    *" $c "*) marker_in "$c" && { echo "MISS(member): $c matches a bundled profile — it must carry NO unprofiled marker"; fail=1; } ;;
    *)        marker_in "$c" || { echo "MISS(member): $c is unprofiled — should carry the 'Layer-4 baseline only; Layer-3 profile TODO' marker"; fail=1; } ;;
  esac
done

# --- both-endpoints, exact-section anchored ---
# edge_both <A> <B>: A's Cross-component links: FIELD must name B (as a whole token) AND
# B's Cross-component links: FIELD must name A. "Field" means the whole bullet, accumulated
# from its "- **Cross-component links:**" line through every continuation line, stopping at
# the FIRST of: a blank line, the next "- **" bullet, or the next "## " heading — not just
# the one physical line the field's bullet starts on, which false-fails a correct edge
# whenever the field legitimately wraps (e.g. a shared library consumed by several
# components). The blank-line stop matters because free-text prose can follow a field after
# a blank line before the next bullet/heading; without it that prose gets swept into the
# field and can false-satisfy a destroyed edge merely by mentioning the sibling's name
# (a genuinely wrapped field never contains a blank line mid-field, so this doesn't
# reopen the wrap false-failure). Matching is still token-anchored (not index()/substring),
# so a decoy word elsewhere in the section that merely contains the name as a substring
# (e.g. "build" containing "ui") can't satisfy the check — restoring the single-line
# restriction to scan the whole section would reopen that hole. Backticks are not
# required — they're just another non-name delimiter character, so an index that names
# components without backticks still passes.
edge_both() {
  awk -v a="## $1" -v b="## $2" -v an="$1" -v bn="$2" '
    function has_token(line, name,    tmp, n, i, arr) {
      tmp = line
      gsub(/[^A-Za-z0-9_-]/, " ", tmp)
      n = split(tmp, arr, " ")
      for (i = 1; i <= n; i++) if (arr[i] == name) return 1
      return 0
    }
    /^## / {
      sec=$0; sub(/[[:space:]]+$/,"",sec)
      cur = (sec==a) ? "a" : (sec==b) ? "b" : ""
      infield=0
      next
    }
    # M1: a decoy ###+ heading right after the field must also stop accumulation, or its
    # text gets swept in as if it were still field content.
    /^#{3,}[[:space:]]/ { infield=0; next }
    cur!="" && /^- \*\*/ {
      infield = ($0 ~ /Cross-component links:/) ? 1 : 0
      if (infield) { if (cur=="a") afield=$0; else bfield=$0 }
      next
    }
    cur!="" && infield && /^[[:space:]]*$/ {
      infield=0
      next
    }
    cur!="" && infield {
      if (cur=="a") afield = afield " " $0; else bfield = bfield " " $0
      next
    }
    END{
      ab = has_token(afield, bn)
      ba = has_token(bfield, an)
      exit !(ab&&ba)
    }
  ' "$MI"
}
for s in "${MEM_SPEC[@]}"; do
  c="${s%%:*}"; tag="${s#*:}"
  case "$tag" in *"shared library"*) LIB="$c";; esac
done
if [ -n "${LIB:-}" ]; then
  for s in "${MEM_SPEC[@]}"; do
    c="${s%%:*}"; [ "$c" = "$LIB" ] && continue
    case "${s#*:}" in *application*|*service*)
      edge_both "$c" "$LIB" || { echo "MISS(member): $c<->$LIB edge not on both endpoints"; fail=1; } ;;
    esac
  done
fi

# --- parent shallow list (I3 / D2-negative, D2-cap) ---
# Capture the WHOLE "- **Components:**" field, from its bullet through every continuation
# line, stopping at the next "- **" bullet, the next "## " heading, or a deeper ###+
# heading (M1) — not a fixed grep -A<n> lookahead, which only survives by coincidence on
# however many lines the oracle happens to wrap onto today (a longer shallow list, e.g.
# more member components, would wrap further and get truncated by a fixed line count).
SHALLOW="$(printf '%s\n' "$MEMBER_SECTION_RAW" | awk '
  /^#{3,}[[:space:]]/ { incomp=0; next }
  /^- \*\*Components:\*\*/ { incomp=1; print; next }
  incomp && /^- \*\*/ { incomp=0 }
  incomp { print }
' | tr '\n' ' ')"
HAS_SHALLOW=0
printf '%s' "$SHALLOW" | grep -q 'Shallow list:' && HAS_SHALLOW=1

if [ "$NO_SHALLOW_LIST" = 1 ]; then
  # D2-negative / the D2-cap "dropped to pure delegation" result: this parent must NOT
  # carry a Shallow list: at all — previously ungated, since the whole block below was
  # skipped by construction whenever no list was present, so a parent that *wrongly
  # gained* one (or kept a stale one after the cap) still passed.
  [ "$HAS_SHALLOW" = 1 ] && { echo "MISS(parent): a Shallow list: is present but must NOT be (pure delegation expected)"; fail=1; }
else
  # Default: if a shallow list IS present it must name EXACTLY the member's components —
  # no more, no fewer (D2-cap's positive half). The D2-cap "dropped to pure delegation"
  # case is asserted via --no-shallow-list above instead, since a dropped list has nothing
  # left here to check names against.
  if [ "$HAS_SHALLOW" = 1 ]; then
    # Only the text AFTER the "Shallow list:" marker is the list itself — the Components:
    # field also legitimately backtick-quotes the delegation pointer (e.g. `web-monorepo.
    # index.md`) earlier in the same field, which must not be mistaken for a component name.
    LIST="$(printf '%s' "$SHALLOW" | sed -E 's/^.*Shallow list:[[:space:]]*//')"
    for c in $EXP_SORTED; do
      printf '%s' "$LIST" | grep -q "\`$c\`" \
        || { echo "MISS(parent): shallow list omits \`$c\`"; fail=1; }
    done
    for n in $(printf '%s' "$LIST" | grep -oE '`[^`]+`' | tr -d '`'); do
      case " $EXP_SORTED " in *" $n "*) ;; *) echo "MISS(parent): shallow list names \`$n\`, not a component"; fail=1;; esac
    done
  fi
fi

[ "$fail" = 0 ] && echo "MIXED INDEX OK" || echo "MIXED INDEX FAILED"
exit $fail
