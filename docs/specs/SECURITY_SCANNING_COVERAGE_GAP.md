# Security scanning — coverage gap (breadcrumb)

## Problem

The organization's internal weekly security scan covers this repo, but its
dependency-vulnerability check only understands npm and pip manifests. This repo is
Flutter/Dart (`pubspec.yaml`), so that check has nothing to audit here. The scan
reports this repo as "not applicable" for dependency auditing rather than "clean";
that is accurate reporting, not Dart/pub coverage.

## Current state

- Secret scanning (`trufflehog`, full git history) — **covered**, same as every
  other repo the scan covers.
- IAM/CDK/dependency-vulnerability scanning via `npm audit`/`pip-audit` —
  **not applicable**, correctly recognized as such.
- Dart/Flutter dependency vulnerability scanning (`pubspec.yaml` / `pubspec.lock`
  against pub.dev advisories) — **not implemented anywhere**. No automated coverage
  exists for this dimension today.

## Scope (in) — if someone picks this up later

- A Dart/pub dependency check in the internal security scanner, reporting results
  in the same shape as its existing npm/pip checks.
- Whatever `pub` tooling actually exists for this (`dart pub outdated`,
  `flutter pub deps`, or a pub.dev advisory-database lookup — needs research; unlike
  `npm audit`/`pip-audit`, there's no single well-known "just run this" command as
  of this writing).

## Scope (out) — and why

- **Not doing this now.** This doc exists so the *next* person who wonders "is our
  Flutter dependency tree being checked for known CVEs" finds an answer in under a
  minute instead of re-deriving "oh, the scanner doesn't support this ecosystem"
  from scratch — the exact rediscovery cost that motivated writing it down.
- Adding Dart/pub scanning is a change to the centralized internal scanner, not
  something to build inside this repo.
