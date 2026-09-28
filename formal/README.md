# P-MCP formal specification (TLA+)

Two PlusCal/TLA+ models, both model-checked with TLC (not just written —
see "self-test" methodology below).

## `PMCPCore.tla` — gate sequence + lease + E-Stop + watchdog

Models the single-robot safety state machine described in
`docs/SAFETY_ARCHITECTURE.md` §§3, 5, 6: lease acquisition, the
Lease → Constitution → Shadow gate sequence, E-Stop (reachable from
every state), heartbeat/watchdog timeout, and a simplified single-step
recovery.

**Verified** (`SafetyInv`, 10 distinct states, exhaustive, no violation):
- `Inv_LeaseHeldBeforeConstitution` (§3 invariant 1)
- `Inv_ShadowPassedBeforeActuation` (§3 invariant 2)
- `Inv_NoActuationOnBadVerdict` (§3 invariant 4, restricted)

## `PMCPRecovery.tla` — the five-phase recovery handshake

Models `docs/SAFETY_ARCHITECTURE.md` §10.7 in full: cause-removed →
manual-reset → self-test → re-attestation → fresh-lease → operator-start.

**Key modeling choice:** manual reset and operator-start confirmation
are actions of a separate `operator` process, not the `robot_sw`
process — a literal, structural encoding of §10.7's requirement that
manual reset "cannot be done remotely via the protocol." No software
action in this model is even capable of setting `manualReset`; it isn't
just omitted; it's a different actor.

**Verified** (`RecoverySafetyInv`, 8 distinct states, exhaustive, no
violation):
- `Inv_CauseBeforeSelftest`, `Inv_ManualResetBeforeAttest`,
  `Inv_SelftestBeforeLease`, `Inv_AttestBeforeInactive` — no phase is
  reachable without every phase before it having actually completed
  (i.e. the five phases are a real sequence, not five independently
  reachable labels).
- `Inv_FreshLeaseOnResume` — formalizes "the old lease is never
  resumed" (§3 invariant 3, `LeaseMonotonicExpiry`, specialized to the
  recovery path).

## How to run either one

```bash
curl -sL -o tla2tools.jar \
  https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
java -cp tla2tools.jar pcal.trans PMCPCore.tla       # or PMCPRecovery.tla
java -cp tla2tools.jar tlc2.TLC -workers auto PMCPCore.tla
```

**Known footgun, worth documenting because it bit us once already:**
`pcal.trans` silently overwrites the `.cfg` file on every retranslation,
including any `INVARIANT`/`PROPERTY` lines you've added by hand. If you
edit the PlusCal `algorithm` block and retranslate, re-check the `.cfg`
file before trusting a "no error found" result — it may mean nothing
was actually checked.

## Self-test methodology (`self-test/`)

Each model has a deliberately-broken sibling in `self-test/` that TLC
correctly flags. This exists to catch exactly the class of mistake
above — if a "real" spec's invariant check passes vacuously (empty
`.cfg`, wrong invariant name, etc.), it's easy to mistake that for a
genuine safety proof. If a self-test mutant ever passes, something is
wrong with the checking setup, not the design.

- `PMCPCore_mutant.tla` — drops the lease-held guard on entering
  `GATE_CONSTITUTION`. TLC finds the violation in 2 steps.
- `PMCPRecovery_mutant.tla` — lets self-test completion jump straight to
  `RECOVERING_LEASE`, skipping TEE re-attestation. TLC finds the
  violation in 4 steps (reaches `INACTIVE` with `attested = FALSE`).

Worth noting honestly: the first mutant attempt for the recovery model
(removing the `causeRemoved` guard on manual reset) was a dud — it
passed because `causeRemoved` gets set atomically in the same
transition that produces `RECOVERING_CAUSE`, so that particular guard
was structurally redundant to begin with. Not every "obviously wrong"
mutation actually tests something; picking a mutant that's guaranteed
to matter takes the same care as writing the invariant itself.

## What's NOT verified (scope of this pass)

- **Multi-robot spatial-overlap conflicts** (`SAFETY_ARCHITECTURE.md`
  §10.5) — both models are single-robot. The R*-tree spatial
  reservation logic isn't modeled here.
- **Liveness/temporal properties** — e.g. "E-Stop is *always* eventually
  actionable" or "a missed heartbeat *always* leads to Safe State within
  bounded time." These need explicit fairness assumptions
  (`WF_vars`/`SF_vars`) and temporal-logic properties, not simple state
  invariants, and aren't attempted in this pass.
- **Numeric timing** (`T_safe`, `T_leader_unknown`, lease TTL) — both
  models treat all transitions as instantaneous/untimed. A timed model
  would be needed to verify the actual millisecond bounds once they're
  derived from the physical hazard analysis §11 calls out as
  still-open.
- **The two models aren't composed** — `PMCPCore.tla`'s simplified
  single-step recovery and `PMCPRecovery.tla`'s five-phase version
  aren't the same model. Composing them (full gate sequence + full
  recovery handshake in one spec) is the natural next step once both
  have been reviewed independently.

## Next steps

1. Compose `PMCPCore.tla` and `PMCPRecovery.tla` into one model.
2. Extend to N robots to check the spatial-lease-conflict logic once
   §10.5's R*-tree design is finalized.
3. Once §11's timing numbers are derived, consider a timed model to
   check the actual bounds, not just the untimed ordering.

