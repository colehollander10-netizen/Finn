# Done

Append-only. Newest at top. Each entry: what shipped, when, and the outcome that mattered.

---

## FINN-006a: Pro entitlement + free-tier gating engine
**Status:** done
**Started:** 2026-05-24
**Completed:** 2026-05-24
**Why:** The `codex/finn-006-pro-entitlements` branch had ~80% of the Pro monetization built but uncommitted: a StoreKit 2 `AppEntitlements`, a `FinnProPaywallView`, and save-time gates. It shipped with a critical hole — the share-extension auto-save path (FINN-016) bypassed the gate entirely, and the limits were scattered magic numbers with no tests.

### What shipped
- Committed Codex's draft as baseline (`0f0f238`), then a hardening pass on top.
- `FreeTierPolicy` (SubscriptionStore package) — single source of truth for the caps (3 active trials, 10 active subscriptions; Pro = unlimited). Replaces hardcoded `>= 3` / `>= 10` in `AddSubscriptionSheet` + `TrialDetailSheet`. 18 unit tests.
- **Closed the share-extension bypass:** `SharedCaptureImporter` now enforces the cap via `FreeTierPolicy.planBatch` (the same unit-tested code path), drops over-cap captures, and reports `skippedAtLimit`.
- Cold-launch + foreground ordering fix in `FinnApp`: entitlements `refresh()` runs before import, so a Pro user is never wrongly capped.
- Upgrade nudge: `ShareLimitToast` in ContentView opens the paywall when captures are dropped ("you already captured these — upgrade to keep them").
- 32 package tests pass; app builds clean (generic iOS) incl. share extension.

### Not in scope (still open as FINN-006)
- Pricing/founding-waitlist *copy* + landing-page decisions (the product half of COL-109). This ticket is the engineering half.
- Real-device StoreKit purchase validation (sandbox) — gate logic is unit-tested but purchase flow needs on-device sandbox testing.

---

## FINN-005: Manual trial entry — paste, share, OCR
**Status:** done
**Started:** 2026-04-22
**Completed:** 2026-05-01

### What shipped
- PR #46 — Paste-from-clipboard on Add Trial
- PR #50/#51 — Share extension for text/HTML, routes shared text into Add Trial via TrialParsingCore
- PR #52 — Screenshot OCR fallback (Apple Vision, on-device, no network) feeding the same applySharedText funnel with source: .screenshot
- Funnel architecture: paste, share, and OCR all converge on `applySharedText(_:source:)` → `PastedTrialExtractor` → `TrialParser.classifyText`. Single parsing path for all three input methods.
- Vision config: .accurate + usesLanguageCorrection=false (protects brand names like Disney+, MUBI, HBO Max from being mangled)
- Verified: simulator walkthrough on iPhone 17 Pro with synthetic Cursor Pro trial confirmation — service, end date, charge amount all extracted and saved correctly

### Successor
FINN-016 closes the gap on having to be inside Finn to use this — share from anywhere on iOS.

---

## FINN-015: Stamp cancelledAt when a trial is cancelled
**Status:** done
**Started:** 2026-04-29
**Completed:** 2026-04-29
**Why:** Cancellation history and future savings/accounting features need a reliable timestamp when a trial is cancelled.

### What shipped
- Merged PR #45 (`codex/finn-015-cancelled-at`).
- `Trial.status = .cancelled` now stamps `cancelledAt` when it was previously nil.
- Explicit existing `cancelledAt` timestamps are preserved.
- Converted the prior `SubscriptionStore` expected-failure coverage into normal passing assertions.

---

## FINN-014: Confirm no Google blocker for launch + decide on backend
**Status:** done
**Started:** 2026-04-29
**Completed:** 2026-04-29
**Why:** Manual-only capture removed the Gmail/Google review dependency; the public privacy story needed to match.

### What shipped
- Confirmed v1 has no Gmail, Google API, bank-link, or app backend dependency for trial/subscription data.
- Merged PR #47 (`codex/finn-privacy-docs-manual-only`) updating README and `legal/privacy.html` to manual-only, local-only data handling.
- Any waitlist/pricing backend decision remains scoped to FINN-006, not core app data.

---

## FINN-005A: Paste flow uses TrialParsingCore
**Status:** done
**Started:** 2026-04-29
**Completed:** 2026-04-29
**Why:** The parser package existed but Add Trial still used a local one-off paste extractor.

### What shipped
- Merged PR #46 (`codex/finn-005-parser-paste-flow`).
- Add Trial paste-to-prefill now routes through `TrialParser.classifyText(..., source: .pastedText)`.
- Low-confidence parses fill nothing; `"Unknown"` is not written into the service field.
- Remaining FINN-005 work is share sheet text/HTML capture and screenshot OCR.

---

## FINN-011A: Lock notification planning to 9:00 local
**Status:** done
**Started:** 2026-04-29
**Completed:** 2026-04-29
**Why:** Notification timing was documented in engine comments but not locked by tests.

### What shipped
- Merged PR #48 (`codex/finn-011-notification-time-tests`).
- `TrialEngine` tests now verify trial and subscription planned alerts fire at 9:00 in the supplied local calendar.
- Manual on-device delivery testing still belongs to the real-device bug walk before v1.

---

## FINN-004: P10 — Integration + adversarial review + final QA
**Status:** done
**Started:** 2026-04-29
**Completed:** 2026-04-29
**Why:** Pre-App-Store hardening after FINN-002 and FINN-003 merged.

### What shipped
- Package tests passed: TrialEngine 4, NotificationEngine 11, TrialParsingCore 10, SubscriptionStore 12.
- Simulator build/run passed on iPhone 17.
- Walked Home, Add Subscription sheet, Subscriptions, Trials, and Settings.
- Fixed two QA regressions: negative countdown labels now render `PAST DUE` instead of `-1D`; Settings now shows `1.0 (1)` instead of `— (—)`.
- Captured the remaining expected-failure issue as FINN-015 (`cancelledAt` not stamped on cancel).

---

## FINN-003: P7 — HomeView H1 rebuild (sleeping-fox empty state)
**Status:** done
**Started:** 2026-04-24
**Completed:** 2026-04-29
**Why:** Last visible phase of the subscription-pivot epic; makes the Home empty state feel intentional.

### What shipped
- Merged PR #42 (`feat/finn-003-sleeping-fox-empty-state`).
- Added the sleeping-fox Home empty state via `FoxView(.sleeping)`.
- Preserved the no-spend-hero-card decision.

---

## FINN-002: Rename to Finn (mechanical)
**Status:** done
**Started:** 2026-04-24
**Completed:** 2026-04-29
**Why:** Align the product name with the locked Finn brand while preserving data-sensitive identifiers where needed.

### What shipped
- Merged PR #38.
- Display name and app-facing copy use Finn.
- Bundle id intentionally remains `com.colehollander.subly` to preserve on-device SwiftData and App Store linkage.

---

## FINN-CONSOLIDATION: Migration cleanup + Linear archive
**Status:** done
**Started:** 2026-04-27
**Completed:** 2026-04-27
**Why:** Initial Linear → markdown migration carried over 18 tickets, but the vault `Finn.md` showed Linear was 3+ days stale. Cleaned `.tasks/` to reflect actual codebase + vault state, then archived Linear.

### What shipped
- `.tasks/active.md` cleared (no actually-in-progress work — COL-149 P9 is already merged per vault PR #28/#32 timeline)
- `.tasks/backlog.md` rewritten down to 13 tickets (from 19) with overlap consolidation:
  - FINN-005 absorbs COL-101 (share sheet → manual entry)
  - FINN-008 absorbs COL-106 (UI friction audit → real-device walk)
  - FINN-009 absorbs COL-131 + COL-132 + COL-139 (v2 polish remainder)
- v2 design epic (COL-120) marked DONE per `Finn.md` § Outstanding (only P7 + P10 of pivot remain)
- Linear "Finn" project archived

---

## FINN-001: Migrate live Linear tickets into this system
**Status:** done
**Started:** 2026-04-27
**Completed:** 2026-04-27
**Why:** Single source of truth. Anything still in Linear that mattered needed to land here.

### What shipped
- 68 total Linear issues reviewed. 50 already done (43 completed + 7 canceled) — left in Linear's history.
- 18 open issues ported. After consolidation pass (above), reduced to 13 active tickets in backlog.
- Original Linear IDs (COL-XXX) preserved in every Notes section for traceability with old commits/PRs.

---
