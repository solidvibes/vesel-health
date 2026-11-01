# Vesel is open source under Apache 2.0

**Date:** 2026-10-31
**Who decided:** mine
**Plan:** docs/plans/2026-10-31-exemplar-polish.md
**Supersedes:** the licence bullet of `2026-10-28-open-source.md` (PolyForm Noncommercial 1.0.0, commercial licences on request)

## Context

Vesel was published source-available under PolyForm Noncommercial 1.0.0. The owner wants it to be a real open-source example people can learn from and build on.

## Decision

- Vesel's own code is licensed under the Apache License 2.0 (`LICENSE`). `NOTICE` holds the copyright line: Stojanov Ventures UG (haftungsbeschränkt), published under its Solid Vibes brand.
- No licence header in each file: `LICENSE` and `NOTICE` cover the repo.
- The Polar BLE SDK is not part of the repo and stays under Polar's licence (`THIRD_PARTY_NOTICES.md`).
- The CLA stays: contributions still transfer to the UG, which may pass them on. For contributions, the CLA applies instead of Apache 2.0 §5.
- The UG stays the owner, as decided on 2026-10-30.

## Why

Apache 2.0 is a well-known open-source licence. It includes a patent grant and a clear way to carry notices, which MIT lacks.

## Alternatives

Keep PolyForm Noncommercial: not open source, and the owner chose to change it. MIT: no patent grant and no `NOTICE` handling.

## What it means

Anyone may use, change and sell copies of Vesel, as long as they keep the licence and `NOTICE`. A version once published under Apache 2.0 stays Apache 2.0 for whoever has it. The UG can still license later versions differently, because the CLA gives it the rights in every contribution.
