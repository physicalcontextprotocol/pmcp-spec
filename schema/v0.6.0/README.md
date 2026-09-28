# P-MCP canonical schema — v0.6.0

`pmcp.schema.json` is the canonical, language-neutral source of truth
for the P-MCP wire format (JSON Schema 2020-12; see
`docs/SAFETY_ARCHITECTURE.md` §8 for why JSON Schema and not
TypeScript is canonical here).

## Verified, not just written

```bash
pip install jsonschema
python3 verify.py
```

`verify.py` does three things: checks the schema against the JSON Schema
2020-12 meta-schema, validates every `examples/valid/` fixture against
its `$defs[$defRef]`, and confirms every `examples/invalid/` fixture is
rejected.

The third check is stricter than it looks. **A fixture must be rejected
for the reason it claims to probe, not merely rejected at all.** The
script enforces this by requiring that each rejection mentions the
property in `EXPECTED_REJECTION_TERMS`. This is not theoretical
fastidiousness — it has already caught one false-confidence bug:

`invalid/lease_grant_bad_state.json` was being rejected solely because
it omitted the required `fence_token`. It read as proof that
`LeaseState` was enforced, and it was actually proving nothing about
`LeaseState` whatsoever. The fixture now includes `fence_token`, so the
rejection can only come from `"GRANTED"` not being a member of the
`LeaseState` enum.

Three invalid-example checks specifically probe safety-load-bearing
constraints:

- `EStopMessage` with `stop_category != 0` → rejected by the `const: 0`
  constraint (E-Stop is always Stop Category 0, §4)
- `ShadowResult` with only `verdict` and `predicted_trajectory` →
  rejected (§10.2 explicitly forbids the bare-boolean anti-pattern)
- `LeaseGrant` with `state: "GRANTED"` → rejected as an invalid
  `LeaseState` member (`ACTIVE` is correct) — this is the exact kind of
  drift that caused the original four-duplicate-client problem

## Two defects this pass found and fixed

Recording these because the pattern is the point.

**1. `ShadowResult` permitted a bare verdict.** The schema had
`required: ["verdict"]` only, with `confidence`, `monitoring`, and
`determinism` optional and nullable. So
`{"verdict": "PASS", "predicted_trajectory": {}}` validated cleanly —
which is exactly the bare-boolean anti-pattern §10.2 forbids, in a
safety gate. All five keys are now required; the three blocks remain
**nullable**, because a subsystem that is not implemented must say so
explicitly. An absent key is indistinguishable from a verdict nobody
checked, which is why presence is enforced and nullability is not.

**2. The `EStopMessage` "valid" example was itself invalid.** It carried
`"triggered_at": "2026-08-21T04:30:00Z"` while the schema defines that
field as a numeric Unix timestamp. The example was wrong, not the
schema — the schema's description explicitly says "Unix timestamp,
seconds since epoch (matches `time.time()` in all reference SDKs)". The
fixture now uses `1755753000.0`, and the corresponding invalid fixture
was updated to match, so that the `stop_category` rejection cannot be an
accident of a malformed timestamp.

## What this schema resolves from the type-consolidation work

- **`ErrorCode`** — union of `pmcp/types.py`'s 10 codes and `v05`'s 5
  additions (no conflict, just different completeness — kept as one
  superset)
- **`SensorType`** — same pattern, union of the generic and
  robotics-specific vocabularies
- **`ShadowResult`/verdict** — replaces both the old lowercase
  (`pmcp`/`sdk`) and uppercase (`v05`) `ShadowStatus` enums, which
  genuinely conflicted in members and casing. Neither is reused as-is;
  this is the §10.1/§10.2 monitor-controller design instead.
- **`LeaseState`** — based on `v05`'s enum (the only file that had one)
  plus the `PENDING` state the recovery/Raft work required.

## What's NOT in this schema yet

- **No per-message JSON-RPC method registry** — the schema defines the
  types (`$defs`), but not yet the mapping from JSON-RPC `method` names
  to which request/response types apply. That's the natural next
  artifact.
- **`BatchActuationRequest`/`Result`** carried forward from
  `pmcp/types.py` as-is, but §3 invariant 7
  (`SingleActuationPerLease`) isn't yet reconciled with what batching
  actually means — flagged, not resolved, in the schema's description
  field.
- **No Rust-idiomatic generated types yet** — quicktype's Rust output
  tends not to be idiomatic; plan is to hand-author `pmcp-rust`'s types
  against this schema rather than blindly codegen them (see
  `docs/SAFETY_ARCHITECTURE.md` §8's directory layout note).
- Field-level numeric constraints tied to the still-open `T_safe` /
  `T_leader_unknown` / `epsilon_max` values (§11) are documented in
  `description` fields but not yet enforced as JSON Schema
  `minimum`/`maximum` constraints, since the numbers themselves don't
  exist yet.
