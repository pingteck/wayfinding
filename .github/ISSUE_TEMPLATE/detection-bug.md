---
name: Detection bug
about: detect-mode.sh classified a repo or workspace wrongly
title: "Detection: <repo or shape> — <one-line summary>"
labels: detection
---

> **⚠️ Public issue — sanitize first.** Strip secrets, customer names, internal hostnames and
> proprietary content. For a public repo, a link is the best repro.

**Repo or workspace** (link if public, otherwise an abstracted description of its layout):

**Command and output:**

```
$ bash scripts/detect-mode.sh <dir>
<paste the full output: mode=, root=, and every unit line>
```

**What it should have said** (mode, and which units are wrong, missing or extra):

**Manifests and workspace configs involved** (paths only, e.g. `go.work`, `apps/*/package.json`,
`settings.gradle.kts`):

**wayfinding version** (`version` in `.claude-plugin/plugin.json`):
