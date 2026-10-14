#!/usr/bin/env bash
# Proves the graders for the onboard-skim and doc-precedence dogfood checks can FAIL, before any
# agent is spent on them (tests/dogfood.md → Checks 20–21). Mechanical; runs in run-all.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
green() { if "$@" >/dev/null 2>&1; then printf '  PASS  %s\n' "$LABEL"; else printf '  FAIL  %s (rejected a CORRECT result)\n' "$LABEL"; "$@" 2>&1 | sed 's/^/          /' | head -8; fail=1; fi; }
red()   { if "$@" >/dev/null 2>&1; then printf '  FAIL  %s — stayed GREEN on a broken result\n' "$LABEL"; fail=1; else printf '  PASS  %s\n' "$LABEL"; fi; }

echo "onboard-skim — siblings document an edge the new repo's own docs never state"
export LINKS_FIELD='Cross-repo links:'
SEED="$HERE/seeds/onboard-skim.md"
printf 'component=pager-svc\ntouched=hub-svc feed-svc\n' > "$TMP/allowed"
pager() { printf '\n## pager-svc\n\n- **Purpose:** Paging service. Delivers notifications to on-call engineers.\n- **Role:** Delivery service.\n- **Entry points:** The `pagerd` binary.\n- **Cross-repo links:** %s\n- **Stack:** Go 1.25.\n  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._\n' "$1"; }
backlink() { sed -e '/^## hub-svc/,/^## /s/^- \*\*Cross-repo links:\*\* None recorded yet\./- **Cross-repo links:** Pushes routed alerts to `pager-svc`./' \
                 -e '/^## feed-svc/,/^## /s/^- \*\*Cross-repo links:\*\* None recorded yet\./- **Cross-repo links:** Reads the delivery archive `pager-svc` writes./' "$1"; }
{ cat "$SEED"; pager 'Receives routed alerts from `hub-svc`; its delivery archive is read by `feed-svc`.'; } > "$TMP/s"; backlink "$TMP/s" > "$TMP/good"
{ cat "$SEED"; pager 'None documented.'; } > "$TMP/literal"
LABEL="control: both edges found and back-linked — gate1"
green bash "$HERE/grade-onboard-component.sh" gate1 "$SEED" "$TMP/good" "$TMP/allowed"
LABEL="control: — structural grader (reciprocity)"
green bash "$HERE/grade-multirepo-index.sh" "$TMP/good" hub-svc feed-svc pager-svc --unprofiled hub-svc,feed-svc,pager-svc
LABEL="the LITERAL skim result (no sibling doc read, no edge) fails gate1"
red bash "$HERE/grade-onboard-component.sh" gate1 "$SEED" "$TMP/literal" "$TMP/allowed"
LABEL="edges named on the new section but siblings NOT back-linked fails gate1"
red bash "$HERE/grade-onboard-component.sh" gate1 "$SEED" "$TMP/s" "$TMP/allowed"
LABEL="only the AGENTS.md sibling found (README-tier sibling missed) fails gate1"
{ cat "$SEED"; pager 'Receives routed alerts from `hub-svc`.'; } | sed '/^## hub-svc/,/^## /s/^- \*\*Cross-repo links:\*\* None recorded yet\./- **Cross-repo links:** Pushes routed alerts to `pager-svc`./' > "$TMP/half"
red bash "$HERE/grade-onboard-component.sh" gate1 "$SEED" "$TMP/half" "$TMP/allowed"

echo "doc-precedence — two of tide-svc's own docs each name a different CURRENT entry point"
G="$HERE/grade-doc-precedence.sh"
idx() { printf '# Harborline Workspace\n\n> Two services.\n\n## tide-svc\n\n- **Purpose:** Tide prediction.\n- **Entry points:** %s\n- **Stack:** Go 1.25.\n' "$1" > "$TMP/p"; }
idx 'Conflicting: CLAUDE.md names `cmd/tidewater`, README.md names `cmd/ebbtide`; neither is marked stale.'
LABEL="both named, conflict stated -> PASS";              green bash "$G" "$TMP/p"
idx 'Not established — the repo'"'"'s two docs disagree on the entry point.'
LABEL="neither named, conflict stated -> PASS";           green bash "$G" "$TMP/p"
idx 'The `tidewater` binary.'
LABEL="coin toss: CLAUDE.md's answer alone -> FAIL";      red bash "$G" "$TMP/p"
idx 'The `ebbtide` binary, started with `--serve`.'
LABEL="coin toss: README's answer alone -> FAIL";         red bash "$G" "$TMP/p"
idx 'The `tidewater` and `ebbtide` binaries.'
LABEL="both named as if both true, no conflict -> FAIL";  red bash "$G" "$TMP/p"
idx 'The service binary.'
LABEL="neither named, no conflict stated -> FAIL";        red bash "$G" "$TMP/p"
printf '# W\n\n> x\n\n## tide-svc\n\n- **Entry points:** The `tidewater` binary;\n  see the README, which disagrees.\n' > "$TMP/p"
LABEL="wrapped field is read whole (1 named + 'disagrees' on line 2 still FAILS as a coin toss)"; red bash "$G" "$TMP/p"

echo
[ "$fail" = 0 ] && echo "AGENT-CHECK GRADERS OK" || echo "AGENT-CHECK GRADERS FAILED"
exit $fail
