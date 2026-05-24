# Backlog

Ordered. Top = next. Re-rank by editing this file.

Source of truth: this file + `~/Obsidian/Active/Finn/Finn.md`. Linear is archived as of 2026-04-27 (stale since 2026-04-24 — vault was always the real state).

**v1 ship blockers** at top, then v1.1+ work, then research/polish. v2 design epic (COL-120) is shipped — its remaining children (COL-131 motion, COL-132 fox/Rive, COL-139 Settings polish) are deferred to v1.1 unless reopened.

---

## FINN-006: Launch pricing + founding waitlist offer
**Status:** backlog (narrowed — engineering half shipped as FINN-006a, see done.md)
**Why:** Pricing has to match product psychology — Finn helps avoid unwanted charges, so it cannot feel like an ironic extra bill. Needs to feel obviously smaller than the surprise charge it prevents.

### Acceptance
- [ ] Monthly + annual pricing decided and documented
- [ ] Founding-member waitlist offer defined
- [ ] Launch pricing copy drafted for landing page + onboarding
- [x] StoreKit products configured to match (FinnPro.storekit: $2.99/mo, $24.99/yr, $59 founding lifetime) — shipped in FINN-006a
- [ ] Real-device StoreKit sandbox purchase validation

### Notes
- Linear (archived): COL-109
- The Pro entitlement + free-tier gating *engine* shipped 2026-05-24 as FINN-006a. What remains here is the pricing/copy/waitlist product work + on-device purchase validation.

---

## FINN-007: SwiftData schema migration support before v1 ship (revisit)
**Status:** backlog
**Why:** Diagnosed 2026-04-21 after a 2hr "blank white screen" chase. Lower priority now — a prior session deliberately backed out of `VersionedSchema` during P1 because the app is pre-TestFlight. Becomes warranted once TestFlight data exists.

### Acceptance
- [ ] If/when TestFlight users exist: define `SchemaMigrationPlan` for Trial model
- [ ] Test: install v1 build, change schema, install v2 build, app launches without data loss
- [ ] No silent fallback to in-memory store on production builds

### Notes
- Linear (archived): COL-112
- Partial mitigation shipped 2026-04-22 (commit `d8cd811`) — `FinnApp.modelContainer` no longer falls back silently
- Re-evaluate trigger: first TestFlight build with real users

---

## FINN-008: File real-device bug list from first on-phone test
**Status:** backlog
**Why:** First install on iPhone 16 Pro 2026-04-22 surfaced bugs not visible in sim. Many pre-pivot bugs may be obviated by current architecture — re-walk after FINN-003.

### Acceptance
- [ ] Walk full app on real device after P7 lands
- [ ] Every friction point screenshotted/described
- [ ] Each becomes its own task in this backlog

### Notes
- Linear (archived): COL-114
- Bundle id (current): `com.colehollander.subly` — intentionally preserved after FINN-002 so installed data and App Store linkage survive
- **Consolidates** COL-106 (UI friction audit, same intent — folded in)

---

## FINN-009: v1.1 — v2 design polish remainder (motion + Settings + Rive fox)
**Status:** backlog
**Why:** v2 design epic (COL-120) is shipped — but three children deferred. Bundling them as one v1.1 polish ticket: SettingsView second-pass, motion choreography, and full Rive-based fox upgrade beyond the current static placeholders.

### Acceptance
- [ ] SettingsView polish per DESIGN.md (notifications pill, copy)
- [ ] Motion pass: staged animations 100–200ms each, no one-shot 500ms fades
- [ ] Rive iOS runtime added; FoxView migrated from static PNG to state-machine driven
- [ ] Cole sign-off on full app walkthrough

### Notes
- Linear (archived): consolidates COL-139 (Settings polish), COL-131 (motion), COL-132 (Rive fox)
- All three were children of COL-120 v2 epic; epic itself is DONE
- Ship after v1 launches — these are post-TestFlight polish

---

## FINN-010: Brand logo improvements (post-launch)
**Status:** backlog
**Why:** LogoService is already shipped (Brandfetch-backed, transparent PNGs over `glassFill`). This ticket is leftover from before LogoService landed — keep the ticket as a placeholder for any future logo issues.

### Acceptance
- [ ] Re-evaluate after first TestFlight: are there services where logo fails or looks wrong?
- [ ] Fallback monogram avatar quality check
- [ ] If needed, additional CDN or curated logo bundle

### Notes
- Linear (archived): COL-88
- Already mostly shipped; this is a "review later" placeholder

---

## FINN-011: NotificationEngine review (already shipped — verify)
**Status:** backlog
**Why:** NotificationEngine package exists and has 11 passing tests. This ticket is leftover. Convert to a verification-only pass before v1 ship.

### Acceptance
- [ ] Confirm 3-day-before + day-of alerts fire at 9:00 local (manual test on device)
- [ ] Confirm cancellation/reschedule on edit/remove
- [ ] If everything works, mark dropped

### Notes
- Linear (archived): COL-87
- Likely redundant — engine code is already in repo. Keep until verified on device.

---

## FINN-012: Trial Detection Logic (post-pivot review)
**Status:** backlog
**Why:** Originally about classifying parsed emails as trial / recurring / ignore. Largely obsolete after the manual-only pivot — `TrialParsingCore` handles parsing now and email is gone. Keep as placeholder in case manual entry adds an auto-classify pass.

### Acceptance
- [ ] Decision: drop or repurpose for manual-input classification
- [ ] If repurposed, define new acceptance

### Notes
- Linear (archived): COL-86
- **Drop candidate** — likely superseded by manual pivot + TrialParsingCore

---

## FINN-013: Settings tab — extra fields (deferred)
**Status:** backlog
**Why:** Settings already has notifications + preview data + export/delete + about. Original ticket asked for notification offset preference + manual add entry — both now mostly covered or moved elsewhere.

### Acceptance
- [ ] Decision: are any Settings fields actually missing?
- [ ] If yes, list them and ship as part of FINN-009 (v1.1 polish)
- [ ] If no, drop

### Notes
- Linear (archived): COL-92 (Low priority)
- **Drop candidate** — likely fully covered by current Settings + FINN-009

---
