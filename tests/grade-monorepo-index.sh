#!/usr/bin/env bash
set -uo pipefail
IDX="${1:?usage: grade-monorepo-index.sh <generated-index.md> [expected-component-set] [profiled-set]}"
PROFILED="${3:-web}"
fail=0

# --- expected component set (the five real components; everything else must NOT be an H2) ---
EXPECTED="${2:-api ingest nested-ws shared-ui web}"

# Collect actual component H2 headings, excluding the two note sections.
ACTUAL="$(grep -E '^## ' "$IDX" \
  | sed -E 's/^## +//; s/[[:space:]]+$//' \
  | grep -viE '^(Tooling & root config|No-manifest candidates)$' \
  | tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' ' ' | sed -E 's/ +$//')"

EXP_SORTED="$(echo "$EXPECTED" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed -E 's/ +$//')"

if [ "$ACTUAL" != "$EXP_SORTED" ]; then
  echo "MISS: component set mismatch"
  echo "  expected: $EXP_SORTED"
  echo "  actual:   $ACTUAL"
  # name the specific extras/missing for a readable failure
  for c in $EXP_SORTED; do case " $ACTUAL " in *" $c "*) ;; *) echo "  MISSING: $c";; esac; done
  for c in $ACTUAL;     do case " $EXP_SORTED " in *" $c "*) ;; *) echo "  EXTRA:   $c";; esac; done
  fail=1
fi

# a duplicated section is invisible to the sort -u'd set comparison above
for c in $EXPECTED; do
  n="$(grep -cE "^## ${c}[[:space:]]*$" "$IDX")"
  [ "$n" = 1 ] || { echo "MISS: '## $c' appears $n time(s), expected exactly 1"; fail=1; }
done

need() { grep -qiE "$1" "$IDX" || { echo "MISS: $2"; fail=1; }; }

# --- per-component role tags: the RIGHT tag on the RIGHT component (catches a swap) ---
role_ok() { # role_ok <component> <exact-tag-substring>
  awk -v comp="$1" -v tag="$2" '
    $0 ~ "^## "comp"[[:space:]]*$" {inseg=1; next}
    /^## / {inseg=0}
    inseg && /Role:/ && index($0,tag)>0 {ok=1}
    END{exit !ok}
  ' "$IDX"
}
check_role() { role_ok "$1" "$2" || { echo "MISS: $1 should carry role tag $2"; fail=1; }; }
check_role web "(application)"
check_role api "(service)"
check_role ingest "(service)"
check_role shared-ui "(shared library)"
check_role nested-ws "(shared library)"
need "^## Tooling & root config" "tooling note present"
need "^## No-manifest candidates" "no-manifest candidates note present"
need "docs-site" "docs-site listed as a candidate"

# --- the two trap dirs must NOT appear as component H2s ---
grep -E '^## ' "$IDX" | grep -qiE '^## (leftpad|packages|eslint-config)' \
  && { echo "EXTRA: a trap dir (leftpad/packages/eslint-config) indexed as a component"; fail=1; }

# --- unprofiled marker SELECTIVITY: on every unprofiled component, on NONE that is profiled ---
# marker_in <component> -> exit 0 if the single-unbroken-line marker sits inside that component's H2 section
marker_in() {
  awk -v comp="$1" '
    $0 ~ "^## "comp"[[:space:]]*$" {inseg=1; next}
    /^## / {inseg=0}
    inseg && index($0,"Layer-4 baseline only; Layer-3 profile TODO")>0 {found=1}
    END{exit !found}
  ' "$IDX"
}
# profiled components MUST carry no marker; every other expected component MUST carry one
for c in $EXPECTED; do
  case " $PROFILED " in
    *" $c "*) marker_in "$c" && { echo "MISS: $c matches a bundled profile — it must carry NO unprofiled marker"; fail=1; } ;;
    *)        marker_in "$c" || { echo "MISS: $c is unprofiled — should carry the 'Layer-4 baseline only; Layer-3 profile TODO' marker"; fail=1; } ;;
  esac
done

# --- both-endpoints: shared-ui is consumed by TWO components; each edge on both sides ---
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
# so e.g. "webpack" in a Stack: field can't satisfy a check for "web", and "shared-ui" can't
# be satisfied by a bare "ui" token — restoring the single-line restriction to scan the
# whole section would reopen that hole.
# Backticks are not required — they're just another non-name delimiter character.
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
  ' "$IDX"
}
check_edge() { edge_both "$1" "$2" || { echo "MISS: $1<->$2 edge not on both endpoints"; fail=1; }; }
check_edge web shared-ui
check_edge nested-ws shared-ui

[ "$fail" = 0 ] && echo "MONO INDEX OK" || echo "MONO INDEX FAILED"
exit $fail
