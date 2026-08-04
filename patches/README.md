# Build-time source patches

Every `*.patch` file in this directory is applied to a clean checkout by the
`Apply Source Patches` step of `.github/workflows/build.yml`, in filename order,
with `git apply -p1 --3way`.

The source tree in `master` therefore stays as close to upstream as possible,
which keeps the automated `Daily Upstream Sync` workflow conflict-free. Fork
specific behaviour changes live here instead of as commits on top of upstream.

## Conventions

- Name files `NNNN-short-description.patch` so the apply order is explicit.
- Generate them from a clean tree with `git diff -U5 -- <paths> > patches/NNNN-....patch`.
- Keep each patch as small as possible. A one-hunk patch survives upstream
  refactors far better than a patch that also carries comment rewording.
- Verify locally with `git apply --check patches/NNNN-....patch` before pushing.

## Current patches

### `0001-allow-any-x-version-for-compatibility-login.patch`

Upstream restricts Compatibility Sign-in to X `12.9` by comparing
`CFBundleShortVersionString`. This patch removes that version gate in two
places:

- `src/Login/BHTCompatibilityLogin.m` — `BHTCompatibilityVersionIsSupported()`
  returns `YES` unconditionally.
- `src/Hooks/CompatibilityLogin.x` — the `%ctor` initialises the hook groups
  whenever `T1HostViewController` exists rather than only on 12.9.

It also flips the matching assertion in `branding/source_smoke_test.py`, which
otherwise fails the `Test Twitter Branding` step because it requires the version
comparison to be present.

The exact class, selector and ABI guards that surround every call site are left
untouched, so an incompatible host runtime is still rejected by those checks
instead of by the version string alone.
