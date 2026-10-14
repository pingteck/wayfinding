---
name: Skill feedback
about: A wayfinding skill (bootstrap / onboard / audit) fell short
title: "Skill feedback: <skill> — <one-line summary>"
labels: skill-feedback
---

> **⚠️ Public issue — sanitize first.** Strip secrets, credentials, PII, customer names, internal
> hostnames and proprietary content. If you can't describe the gap without them, abstract it.

**File only for an objective gap:** the skill contradicted one of its own instructions, gave no
guidance for a situation you had to handle, or you caught yourself working around one of its
rules. Not for normal use or a preference.

```
skill:       <bootstrap | onboard | audit>
mode:        <the mode= line detect-mode.sh printed>
trigger:     <the situation that surfaced it>
actual:      <what the skill did, or failed to do>
expected:    <what it should have done>
contradicts: <the instruction it broke, OR "no guidance for X">
repro:       <abstracted, sanitized scenario — optional but helps>
severity:    low | medium | high
```
