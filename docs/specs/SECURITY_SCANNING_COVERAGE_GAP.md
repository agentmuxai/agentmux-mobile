# Security scanning — coverage gap (breadcrumb)

## Problem

The org-wide weekly Security Researcher (`a5af/shared-infrastructure`,
`weekly-analysts/scripts/security-researcher/run.py`) audits this repo along with
`agentmux`, `agentmux-cloud`, `dev-tools`, and `agentmux-docs` — but it only knows how
to scan two dependency-manifest types: `package.json` (via `npm audit`) and
`requirements*.txt` (via `pip-audit`). This repo is Flutter/Dart (`pubspec.yaml`) —
neither manifest type exists anywhere in the tree, so the scanner correctly finds
nothing to audit every run.

Until 2026-08-17 this read, in the weekly report, as vague/unremarkable prose
("no audit output"), easy to misread as "clean" rather than "not covered." As of
`docs/analysis/ANALYSIS_SECURITY_RESEARCHER_AUDIT_COVERAGE_GAP_2026_08_18.md` in
shared-infrastructure, the report now explicitly marks this repo's `npm_audit`/
`pip_audit` fields `status: "completed"` with `detail: "no package.json manifests
found"` — i.e. deterministically confirmed as "not applicable," not silently dropped
or ambiguous. **That fixed the reporting; it did not add Dart/pub coverage.**

## Current state

- Secret scanning (`trufflehog`, full git history) — **covered**, same as every
  other repo in the scan list.
- IAM/CDK/dependency-vulnerability scanning via `npm audit`/`pip-audit` —
  **not applicable**, correctly recognized as such.
- Dart/Flutter dependency vulnerability scanning (`pubspec.yaml` / `pubspec.lock`
  against pub.dev advisories) — **not implemented anywhere**. No automated coverage
  exists for this dimension today.

## Scope (in) — if someone picks this up later

- A `run_dart_audit()`-equivalent in the shared security-researcher script,
  following the same `DependencyAuditResult` (`status`/`findings`/`detail`) shape
  `run_npm_audit`/`run_pip_audit`/`run_trufflehog` already use, so it plugs into the
  existing coverage-gap banner + posture-downgrade logic for free.
- Whatever `pub` tooling actually exists for this (`dart pub outdated`,
  `flutter pub deps`, or a pub.dev advisory-database lookup — needs research; unlike
  `npm audit`/`pip-audit`, there's no single well-known "just run this" command as
  of this writing).

## Scope (out) — and why

- **Not doing this now.** This doc exists so the *next* person who wonders "is our
  Flutter dependency tree being checked for known CVEs" finds an answer in under a
  minute instead of re-deriving "oh, the scanner doesn't support this ecosystem"
  from scratch — the exact rediscovery cost that motivated writing it down.
- Adding Dart/pub scanning is a shared-infrastructure change (the scanner is
  centralized, not per-repo), not something to build inside this repo.
