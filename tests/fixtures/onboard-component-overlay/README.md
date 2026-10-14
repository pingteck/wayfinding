# onboard-component overlays

Copied OVER a scratch copy of a base fixture — never applied to the committed fixture:

    cp -R tests/fixtures/monorepo/. "$T/mono/"
    cp -R tests/fixtures/onboard-component-overlay/monorepo/. "$T/mono/"

The base fixtures stay the single master (their frozen oracles and `expected-sets`
entries must not move). Each overlay adds exactly one new component plus the manifests
needed to exercise edge resolution:

- `monorepo/` — adds `apps/billing` (forward `workspace:*` dep on `shared-ui`, plus a
  registry dep `left-pad` that must NOT become an edge) and OVERWRITES
  `packages/shared-ui/package.json` to declare a dep ON `billing`, so an implementation
  that skips the reverse scan fails.
- `mixed/web-monorepo/` — adds `apps/reporting` declaring the SCOPED `@acme/ui`
  (must resolve to the `ui` component by its declared manifest name, not by basename)
  and a registry dep `admin` (a real component name, but not a workspace protocol —
  must NOT become an edge). Overwrites `packages/ui` and `apps/web` manifests to make
  the scoped names real.

The fixture root `CLAUDE.md` files are deliberately NOT updated: the new components are
undocumented, which is exactly what forces the manifest-derived edge path.
