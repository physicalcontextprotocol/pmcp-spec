# P-MCP Safety Architecture (v0.7 draft)

**Status:** Draft — supersedes the lease/CRDT design implied by the current
`pmcp/`, `sdk/`, and `v05/` type definitions. Written after two rounds of
research: round 1 into Anthropic MCP, ISO 10218/ISO-TS 15066/IEC 61508,
ROS 2/MAVLink/OPC-UA Safety, CRDT literature, and TLA+/formal methods
practice; round 2 into the seven specific open design questions round 1
surfaced (HNN determinism, consensus-failure fail-safe, proof-of-location,
spatial lease conflicts, message signing, recovery handshake, SIL
ceiling for ML). All four source research reports are archived in
`docs/research/`.

**What changed in this revision (round 2):** three of the "open judgment
calls" flagged in v0.6 now have a concrete, defensible answer, because
two independent research passes converged on the same architecture
(monitor-controller / Simplex pattern for the ML gate) even though they
used different vocabulary to describe it. See §10.

This document is the thing every other artifact in `pmcp-org` should be
checked against: the JSON Schema, the conformance suite, and all three
SDKs. If code and this document disagree, the document wins until it's
formally revised.

---

## 1. Safe State (define this before anything else)

> In any failure, fault, ambiguity, timeout, or unrecognized message,
> the system transitions to **Safe State** within `T_safe` milliseconds.
>
> **Safe State** = all leases held by the affected robot are revoked,
> motion is stopped per **Stop Category 1** (controlled deceleration,
> then power removal — see §4), and an audit log entry is sealed
> recording the trigger.

`T_safe` is not yet numerically fixed — per both research reports, it
must be derived from physics (ISO/TS 15066 biomechanical
speed-and-separation bounds for the specific robot class), not from
"reasonable" network latency. Placeholder until that analysis is done:
`T_safe ≤ 200ms` for collaborative/human-proximate operation,
`T_safe ≤ 500ms` otherwise. **Do not treat these numbers as final** —
they need a real hazard analysis (ISO 12100) per robot class before
they're load-bearing.

## 2. What changed from the current design, and why

| Area | Current (`pmcp`/`sdk`/`v05` types) | Revised | Why |
|---|---|---|---|
| Lease state | Implicit; CRDT-replicated in some paths | **Raft consensus group**, single-writer per zone | CRDTs guarantee eventual, not timely, convergence, and provide no mutual-exclusion guarantee. Two tenants can both believe they hold a lease during a partition. No safety-certified protocol researched uses CRDTs for lease/mutex state. |
| CRDT ledger | Used broadly, including safety-relevant state | **Scoped to non-safety state only**: telemetry, status, audit log, config | Audit log is append-only and eventual convergence is fine there. Lease/actuation-permission state is not. |
| E-Stop | An error code (`ESTOP_ACTIVE`) inside the normal actuation error space; a `Capabilities.estop` flag | **First-class message type, lease-independent, highest priority, bypasses the Lease→Constitution→Shadow gate entirely** | ISO 10218-1 §5.5.2 treats E-stop as mandatory and structurally separate from normal command flow. Modeling it as "just another error" means it inherits the latency and failure modes of the whole gate pipeline it's supposed to override. |
| Heartbeat / watchdog | Not present | **Mandatory heartbeat at a fixed interval; missed heartbeat → Safe State** | Every safety-certified protocol researched (OPC-UA Safety, MAVLink, PROFIsafe-style designs) has this. Lease TTL alone is not a substitute — it only covers lease-holding clients, not general link loss. |
| Gate order | Lease → Constitution → Shadow (already correct, per the earlier spec-order fix) | Unchanged, but now explicitly a **3-vote gate that exceeds 2oo2 (dual-channel) minimums**, with an explicit rule for what happens on any single-channel disagreement | Structurally sound already; it just wasn't stated as a formal safety property before. See §3. |
| Timing | Undefined anywhere in the protocol | **First-class**: every gate, the heartbeat, and Safe State transition get an explicit max-latency bound | IEC 61508 / IEC 61784-3 require bounded response times for anything claiming safety relevance. |
| Physics validation (HNN) | `ShadowStatus` treated as a deterministic-looking enum | **Must carry an explicit confidence/error-bound field**, not just a status enum | Neural network predictions are not deterministic across hardware. A bare `SAFE`/`COLLISION` enum hides that uncertainty from anything consuming it. |

## 3. Safety invariants (the floor — prose now, TLA+ later)

These are the properties that must hold at every point in the protocol.
They're written in prose here as the minimum bar; a `pmcp-spec/formal/`
PlusCal/TLA+ spec should eventually make these machine-checkable
(tracked as follow-up, not blocking v0.6).

1. **`LeaseHeldBeforeConstitution`** — Constitution check may only be
   entered for a (robot, zone) pair that currently holds an ACTIVE
   lease, granted by the Raft-elected leader for that zone.
2. **`ShadowPassedBeforeActuation`** — an actuation command may only be
   dispatched to hardware if the immediately preceding Shadow validation
   for that exact trajectory returned SAFE with confidence above the
   configured threshold.
3. **`LeaseMonotonicExpiry`** — a lease, once EXPIRED or RELEASED,
   cannot be reactivated; a new lease requires a fresh Raft-arbitrated
   acquisition.
4. **`FailSafeOnDisagreement`** — if Lease, Constitution, or Shadow
   disagree, time out, or one is unreachable, the system transitions to
   Safe State within `T_safe`. There is no "majority wins" fallback for
   the safety gate — any single blocking vote blocks.
5. **`EstopAlwaysReachable`** — an E-Stop message is accepted and acted
   on from every protocol state, including mid-actuation, regardless of
   lease state, Raft leadership, or any in-flight gate check.
6. **`HeartbeatBoundedLoss`** — if no heartbeat is received from a
   leased client within the configured watchdog interval, the robot
   transitions to Safe State and the lease is revoked, independent of
   the lease's stated TTL.
7. **`SingleActuationPerLease`** — at most one in-flight actuation
   command per lease at a time (multiplicity beyond this needs an
   explicit batching design, not implicit concurrency).

## 4. Revised architecture layers

```
Application     Lease Mgmt (Raft) | Actuation | Constitution | E-Stop (bypass) | Config
Validation      Shadow Validation (HNN, w/ confidence bound) | Safety Rule Engine
Safety          Safety Container: CRC, sequence number, watchdog, safety token
State Diss.     CRDT Ledger — non-safety only: telemetry, status, audit log, config
Identity/Attest Ed25519 Identity | TEE Attestation (SGX/SEV/TrustZone/DICE)
Transport       WebSocket (reference) | DDS | QUIC | custom (extensible, "black channel")
```

The Transport layer is treated as a **black channel** (OPC-UA Safety
Part 15 pattern): it's assumed to fail arbitrarily — drop, reorder,
delay, duplicate — and safety guarantees come from the Safety layer
above it, not from trusting the transport.

**Stop Categories** (ISO 10218), and which trigger maps to which:

| Trigger | Stop Category | Behavior |
|---|---|---|
| E-Stop message | Category 0 | Immediate, uncontrolled power removal |
| Watchdog/heartbeat timeout | Category 1 | Controlled deceleration, then power removal |
| Constitution/Shadow gate failure | Category 1 | Controlled deceleration, then power removal |
| Lease expiry mid-actuation | Category 1 | Controlled deceleration, then power removal |
| Graceful `deactivate()` | Category 2 | Controlled stop, power maintained |

## 5. Robot state machine

```
UNCONFIGURED --configure()--> INACTIVE --activate()--> ACTIVE
ACTIVE --actuate() [gate passed]--> ACTUATING --complete()--> ACTIVE
ACTIVE --deactivate()--> INACTIVE                (Stop Cat 2)

From ANY state:
  E-Stop            --> SAFE   (Stop Cat 0, immediate)
  Watchdog timeout   --> SAFE   (Stop Cat 1)
  Gate disagreement  --> SAFE   (Stop Cat 1, during ACTUATING transition attempt)
  Lease expiry (mid-ACTUATING) --> SAFE (Stop Cat 1)

SAFE --recover() [operator-confirmed, fresh lease required]--> INACTIVE
```

## 6. Lease state machine (Raft-backed)

```
FREE --acquire() [Raft leader arbitrates]--> PENDING
PENDING --granted()--> ACTIVE
PENDING --denied()--> DENIED --> FREE

ACTIVE --release()--> FREE
ACTIVE --expire() [TTL elapsed]--> EXPIRED --> FREE
ACTIVE --heartbeat_timeout()--> EXPIRED --> FREE   (independent of stated TTL)
ACTIVE --estop()--> EXPIRED --> FREE               (E-Stop always revokes)

EXPIRED, DENIED are terminal for that acquisition attempt —
no path back to ACTIVE without a fresh acquire() through the leader.
```

Only the Raft-elected leader for a given zone may grant an ACTIVE
lease for that zone. This is the mechanism that gives
`SingleActuationPerLease`-adjacent mutual exclusion — CRDTs cannot
express "if unheld, claim it" atomically, so this can't live in the
CRDT ledger.

## 7. Versioning policy

**SemVer 2.0.0** for the protocol spec.

| Version component | Triggers | Wire compatibility | Required action |
|---|---|---|---|
| MAJOR (X.0.0) | Remove/rename a field, change a field's type, add a *required* field, remove a message type, change gate order | Breaking | All implementations must update together |
| MINOR (0.X.0) | Add an *optional* field, add a new message type, add a capability flag, relax a constraint | Backward compatible | Older implementations ignore what they don't know |
| PATCH (0.0.X) | Fix spec ambiguity, add examples, clarify docs | No wire change | No implementation change needed |

CI enforcement (for `pmcp-conformance`, once schema-driven): diff the
new JSON Schema against the previous tagged version and reject the PR
if it contains a MAJOR-class change without a MAJOR version bump.

**Deprecation:** a field or message type must be marked deprecated for
at least two MINOR versions before removal in a MAJOR version.

## 8. Schema organization (for `pmcp-spec`)

JSON Schema is canonical (not TypeScript — see rationale in chat/prior
discussion: P-MCP has three peer SDKs, and a language-neutral source
avoids privileging one of them).

```
pmcp-spec/
  schema/
    pmcp.schema.json        # canonical, JSON Schema 2020-12, versioned via $id
  generated/
    python/                 # pydantic models (quicktype or hand-authored)
    typescript/              # TS types (quicktype)
    rust/                    # hand-authored w/ schemars+serde (quicktype Rust
                              #   output is rarely idiomatic — don't auto-generate blindly)
  docs/
    PROTOCOL_SPEC.md
    SAFETY_ARCHITECTURE.md  # this document
    versioning.md
  formal/                   # not yet started
    invariants.tla
    state-machines.scxml
  examples/
    messages/                # example valid + INVALID messages (conformance needs both)
```

## 10. Resolution of the seven open design questions (research round 2)

Two independent research passes (`docs/research/pmcp-deep-research.md`
and `docs/research/P-MCP_Advanced_Safety_Review.md`) converged on the
same underlying architecture for six of the seven questions, despite
using different vocabulary ("advisory/oracular subsystem" vs.
"monitor-controller/Simplex"). Where they genuinely disagree or where
both flag something as unresolved, that's called out explicitly.

### 10.1 Shadow validation: monitor-controller (Simplex), not raw HNN output — **now settled**

This was the single biggest open item in v0.6. It's resolved: **the HNN
is never the safety-authoritative decision-maker.** A separate,
non-ML **monitor** evaluates the HNN's output against hard physical
limits, a calibrated confidence interval, and out-of-distribution/
ensemble-disagreement checks — and the monitor's composite verdict, not
the raw HNN prediction, gates actuation.

```
verdict ∈ {PASS, CONDITIONAL_PASS, FAIL, INDETERMINATE}

FAIL           if any hard physical limit is violated (non-negotiable,
                 doesn't even need the HNN's confidence)
INDETERMINATE  if the conformal interval, OOD score, or ensemble
                 disagreement exceeds its configured threshold
                 (fails SAFE, not FAIL — "I don't know" ≠ "it's fine")
CONDITIONAL_PASS if all checks pass but the interval is wider than nominal
PASS           only if every check passes within normal bounds
```

`INDETERMINATE` and `FAIL` both block actuation; the distinction is for
logging/diagnostics, not for the gate decision. This directly answers
`FailSafeOnDisagreement` (§3, invariant 4) for the ML-specific case.

**SIL consequence:** this monitor/Simplex split is what makes a real
SIL target achievable at all. The composite Shadow gate:

| Component | SIL | Why |
|---|---|---|
| Monitor (hard limits + conformal-interval + OOD/ensemble check) | **SIL 2** | Conventional logic, no ML in the decision path itself |
| Raw HNN prediction | **SIL 1**, advisory-only | Feeds the monitor; never directly authorizes actuation |
| Lease gate (Raft + Ed25519 + TEE) | **SIL 2–3** | No ML |
| Constitution gate (rule engine) | **SIL 3** | Pure logic |
| E-Stop (hardware) | **SIL 3–4** | No ML, no consensus, no network dependency |

**Target for the composite system: SIL 2.** This supersedes the SIL 1
ceiling implied by treating the HNN as authoritative in v0.6.

### 10.2 Confidence schema for Shadow validation responses — **now settled**

Every Shadow validation response must be a typed record, not a bare
boolean, minimally including: verdict (as above), the predicted
trajectory/forces/energy, a conformal-prediction confidence block
(method, alpha, calibration date, interval widths), a monitoring block
(ensemble disagreement, OOD score, in-distribution flag), and a
determinism block (input/output hashes, model version, hardware
fingerprint — device/driver/cuDNN/precision). This becomes the shape of
the `ShadowResult` type in the eventual schema — see
`docs/research/P-MCP_Advanced_Safety_Review.md` §1.3 for the full
worked JSON example.

### 10.3 Consensus-layer fail-safe — **settled, with one number left open**

**Settled:** treat Raft as a black channel (OPC-UA Part 15 pattern);
put the watchdog at the robot endpoint, not in the consensus client.
Lease TTL must be shorter than worst-case Raft leader-election time,
renewed at TTL/3. **Safe State is sticky — no auto-recovery, ever**,
confirmed independently by both reports as a hard requirement across
every relevant standard (IEC 61508, ISO 13849, ISO 10218).

Revised lease state machine (adds the missing `T_leader_unknown` trigger
to §6):

```
ACTIVE --lease_renewal_missed()--> SAFE  (Stop Cat 1)
ACTIVE --current_leader_none() [> T_leader_unknown]--> SAFE  (Stop Cat 1,
                                    even if a leader is elected moments later)
ACTIVE --consensus_unreachable()--> SAFE  (Stop Cat 1)
```

**Still genuinely open:** the numeric value of `T_leader_unknown` and
the lease TTL. Both reports agree these must be *derived from physical
stopping-distance/SSM bounds per robot class* (ISO/TS 15066), not from
Raft's database-workload defaults (150–300ms). This is empirical work
per deployed robot type — the spec can define the *formula*, not the
number:

```
T_leader_unknown  ≤  robot_worst_case_stopping_time(v_max)
lease_TTL         =  T_leader_unknown / 3   (renewal cadence)
```

### 10.4 Physical location / proof-of-location — **settled mechanism, deployment-specific parameters open**

**Settled:** TEE attestation proves code integrity, not location — a
separate distance-bounding layer is required. IEEE 802.15.4z UWB secure
ranging is the recommended mechanism (commodity hardware, sub-30cm
precision). BLE RSSI is explicitly **not** sufficient for safety-critical
use (spoofable via directional-antenna relay attack) — sanity-check
signal only. One nuance the second report adds: even 802.15.4z doesn't
achieve *pure* Brands-Chaum mafia-fraud-resistance in commercial
implementations — so UWB location attestation should be treated as
"strong, not perfect," and paired with a signed pose report:

```
location_proof ≡ uwb_distance_bound(all trusted anchors within d_max)
                ∧ ed25519_signed_pose_report(robot_id, pose, time, fiducial_id)
                ∧ (optional) ble_rssi_sanity_check   // never load-bearing
```

**Open, deployment-specific:** UWB anchor count/geometry per workspace
shape, and how a *moving* robot's location claim expires (both reports
flag this as unresolved in the literature — P-MCP has to define its own
pattern: bound the claim's validity window tightly enough that the
robot can't have exited its declared zone before the claim expires).

### 10.5 Spatial-overlap lease conflict detection — **settled**

R*-tree (not the original R-tree — better split behavior for
write-heavy workloads) over `(AABB3D, time_interval)` reservation
tuples, with the query AABB inflated by a `safety_margin` before
checking for intersection. Concrete formula for the margin, tying
back into §1's `T_safe`:

```
safety_margin ≥ v_max × T_safe + sensor_uncertainty_r
```

Priority-class exceptions (E-Stop overrides any existing reservation)
are encoded as an explicit priority order in the conflict-check
function, not as special-case branches scattered through the codebase.

### 10.6 End-to-end message signing over JSON-RPC — **settled**

JWS (RFC 7515) with EdDSA (RFC 8037), signing over **canonical JSON**
(RFC 8785 — mandatory, since JSON serialization isn't deterministic and
JWS signs bytes). Every safety-critical message's protected header must
include `nonce` + `timestamp`, and the verifier must reject anything
outside a replay window or with a reused `(kid, nonce)` pair — without
this, a captured command is trivially replayable. Detached-payload mode
(RFC 7797) for telemetry batches over ~4KB.

**Open:** key-rotation policy for a multi-tenant robot fleet (no settled
robotics-specific standard exists — Visa's 90-day/24-hour-overlap
pattern is a starting reference point, likely too slow for this threat
model), and whether Raft's own consensus traffic needs per-message
signing or can rely on TLS alone (depends on your threat model — do you
assume a Raft node itself could be compromised despite TEE attestation?).

### 10.7 Recovery handshake after Safe State — **settled**

Five phases, all mandatory, all in order — this replaces the single
`recover()` transition in §5 with an explicit sub-state-machine:

```
SAFE --cause_removed_and_verified()--> RECOVERING_CAUSE
RECOVERING_CAUSE --manual_reset() [hardware/safety-rated-logic only,
                     NOT a protocol message]--> RECOVERING_SELFTEST
RECOVERING_SELFTEST --selftest_passed() [joints, safety inputs, e-stop
                     circuit closed, HNN test-vector check]--> RECOVERING_ATTEST
RECOVERING_ATTEST --tee_reattested_and_verified()--> RECOVERING_LEASE
RECOVERING_LEASE --fresh_lease_acquired() [full Lease→Constitution→
                     Shadow sequence; the old lease is never resumed]--> INACTIVE
INACTIVE --operator_start_confirmed() [separate button from reset]--> ACTIVE
```

Two invariants worth naming explicitly: **manual reset cannot happen
over the protocol** — it must be hardware or safety-rated logic, so a
compromised or buggy client can never soft-restart a stopped robot —
and **the new lease is never a resumption of the old one**, consistent
with `LeaseMonotonicExpiry` (§3, invariant 3).

**Open:** the minimum self-test vector suite for the HNN specifically
(no published methodology — the spec should require at least one
known-safe vector, one known-unsafe vector, and one vector per known
failure mode: out-of-range input, NaN, infinite output), and whether
multi-robot fleets recover per-robot or fleet-wide (operationally
flexible vs. simpler to verify — undecided, needs a call once you have
a concrete multi-robot deployment to reason about).

### 10.8 What's still genuinely open, fleet-wide

Everything else in the seven questions has a defensible, citable
answer now. These three do not, and both reports agree they're where
the field itself has no settled answer — not just gaps in the research:

1. **Cross-hardware HNN determinism budget (`ε_max`)** — must be
   established empirically per model version, via test-vector replay
   on every supported hardware target. No published shortcut exists.
2. **Composition of conformal prediction with adversarial input** —
   conformal prediction assumes exchangeable (non-adversarial) data.
   P-MCP needs to either explicitly scope Shadow validation's threat
   model to non-adversarial input, or add an adversarial-robustness
   check upstream of it.
3. **UWB anchor geometry and moving-robot location-claim expiry** — no
   closed-form methodology exists; these are per-deployment decisions.

## 11. Open items (not resolved by this document)

- `T_safe`, lease-TTL, and `T_leader_unknown` are still placeholders in
  formula-only form — need a real ISO 12100 hazard analysis per robot
  class to become numbers.
- The three items in §10.8 are open research problems, not just
  undocumented — P-MCP has to make its own documented judgment call on
  each, they won't be "found" by more research.
- Raft cluster sizing/deployment model for lease management is not yet
  specified (research recommends 3+ nodes minimum).
- Formal TLA+ spec for §3's invariants is not started — prose-only for
  now, tracked as follow-up.
- The four duplicate Python type files still need consolidating against
  *this* architecture, not just against each other — the `LeaseState`
  enum in `v05` needs a `PENDING` state added (Raft arbitration takes
  time) and the `ShadowStatus` enum needs to be replaced by the
  `verdict` schema in §10.2, not merged with either existing version.
- Key-rotation policy (§10.6) and per-robot self-test vectors (§10.7)
  are unwritten.
