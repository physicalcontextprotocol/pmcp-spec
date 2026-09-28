# PMCP: Verified State & Open Research Problems

This document exists so that every claim PMCP makes about itself is
checkable. If something is not listed under "Verified today", treat it
as not yet proven — that is deliberate, not an oversight.

Everything below was **re-run while assembling the v1.0.0 release**, not
carried forward from an earlier draft. Where an earlier draft's number
did not reproduce, it has been corrected here, and the correction is
recorded rather than quietly overwritten.

## Verified today

Each line below is backed by an actual run — a test suite, a schema
validator, or a CI job — not by design intent or code review.

### Test results (re-run 2026-09-28)

| Component | Command | Result |
|---|---|---|
| `pmcp-python` | `pytest -q` on `pip install -e ".[dev,numerics]"`, Python 3.12 | **214 collected, 213 passed, 1 skipped** |
| the one skip | `pytest -q -rs` | `tests/v05/test_hnn_gate.py:208` — *"torch/numpy available — cannot test missing-deps path"*. It is an `importorskip`-style guard for the absent-dependency branch, and it can only run when torch/numpy are **not** installed. |
| `pmcp-rust/pmcp-core` | `cargo test` | **43 passed, 0 failed** |
| `pmcp-conformance` | `pytest -q` | **42 passed** |
| `pmcp-spec` schema | `python schema/v0.6.0/verify.py` | **5 fixtures, 0 failures** — 2 valid accepted, 3 invalid rejected *for the stated reason* |
| `pmcp-typescript` | `npx tsc --noEmit` (typescript installed locally) | **32 compile errors** across 7 files. No test suite exists. |
| `pmcp-rust/pmcp-ledger` | `cargo build` | **19 compile errors** (cargo's own summary: *19 previous errors; 45 warnings*). Not runnable. |

**A note on how to check the TypeScript number, because it bites.** With
no local `node_modules`, `npx tsc --noEmit` prints a decoy banner
("This is not the tsc command you are looking for") and **exits 0**.
Grepping its output for `error TS` returns zero, which looks exactly
like a clean build. Install dev dependencies first
(`npm ci`) or you will "verify" a compile failure into a compile pass.
`pmcp-typescript`'s CI installs before type-checking, so the job itself
is sound — but the local one-liner is a trap, and it is how the previous
"19 errors" figure went stale in the first place.

The single skip is a Gate-4 HNN test guarding the missing-dependency
branch. It is a guard, not a silently passing test — and it is skipped
*because* torch/numpy are installed, which is the healthy case.

### A correction — and this one is worth reading

Earlier drafts claimed **213/213 Python tests passing**. During release
assembly that figure was flagged as unreproducible and rewritten here as
"187 collected, 178 passed, 10 skipped".

**That rewrite was wrong, and the 213 was right.** Re-running `pytest -q`
gives 214 collected, 213 passed, 1 skipped — stable across repeated runs.
The 178/187 figure never corresponded to this tree: 178 passed plus 10
skipped is 188 outcomes, which cannot come from a 187-test collection, so
it was arithmetically impossible on its face and should have been
rejected at the time rather than propagated.

What this illustrates, in the project's own terms: a correction is still
a claim, and a claim still has to survive a re-run. The error here was
not dishonesty but the same class of bug this document exists to catch —
trusting a number because it was written down, in either direction.

`pmcp-python`'s collected total has changed across drafts (187, then
214), so the count is now stated as collected **and** passed **and**
skipped, and the command to reproduce it, in every place it appears.

### Properties, and what backs each

- **E-Stop is a real actuation-blocking latch**, not an advisory flag.
  `pmcp/estop` bypasses the gate sequence entirely at the
  message-handling layer, and this is covered by the conformance suite
  rather than only described in the spec.
- **Fencing tokens** (Kleppmann 2016) are implemented with per-zone
  monotonic counters and staleness rejection, in both Python and Rust.
  `LeaseGrant.fence_token` is a required schema field, so a lease
  response that omits it does not validate.
- **`ShadowResult` cannot be a bare boolean.** All five keys — `verdict`,
  `predicted_trajectory`, `confidence`, `monitoring`, `determinism` —
  are required. The three blocks are nullable, because a subsystem that
  is not implemented must report that explicitly; an absent key is
  indistinguishable from a verdict nobody checked, which is the
  anti-pattern §10.2 forbids.
- **The schema rejects what it should, for the right reason.**
  `verify.py` requires each invalid fixture's rejection to mention the
  property that fixture exists to probe. This caught
  `invalid/lease_grant_bad_state.json` being rejected only for a
  missing `fence_token` — it read as proof that `LeaseState` was
  enforced while proving nothing of the kind.
- **Five defects that static review missed were found by executing
  code**, not by reading it, and are fixed and re-verified: an exception
  hierarchy bug that crashed every safety-block path, a silently
  duplicated middleware definition where the weaker version won, 14
  async tests that were never actually executing, a result-discarding
  bug in the batch actuation path, and — in the Rust crate — a
  duplicate `Cargo.toml` key hiding roughly 60 compiler errors, plus a
  broken async `Clone` that was silently corrupting shared lease state
  across concurrent connections, plus a missing lease-enforcement check
  in the actuation-call path itself.
- **Four more defects were found during release assembly**, by running
  the CI definitions locally rather than trusting them:
  - `pmcp-conformance`'s `pip install -e .` failed outright — setuptools
    flat-layout discovery aborts on a repository that is a test suite
    with no importable package. CI would have been red on arrival.
  - `pmcp-rust/pmcp-ledger` requested the redis feature `scripting`,
    which does not exist in redis 0.25 (it is `script`), so Cargo
    could not resolve the dependency at all.
  - The `EStopMessage` "valid" schema example carried an ISO-8601
    string where the schema defines a numeric Unix timestamp, so the
    valid fixture was itself invalid.
  - `ShadowResult` had `required: ["verdict"]` only, which is the bare
    -boolean hole described above.

### Not verified by a run in this pass

Stated explicitly so nothing here is over-read:

- **The TLA+ models check clean, over a very small state space.** This
  pass *did* re-run the model check — TLC 2026.09.25 (tla2tools 1.8.0) —
  and it is now re-run on every CI run rather than sitting disabled.
  But read the numbers before the word "verified":

  | Model | Result | States (distinct) | Depth |
  |---|---|---|---|
  | `PMCPCore.tla` | no error found | **10** | 6 |
  | `PMCPRecovery.tla` | no error found | **8** | — |
  | `self-test/PMCPCore_mutant.tla` | `SafetyInv` violated | — | — |
  | `self-test/PMCPRecovery_mutant.tla` | `RecoverySafetyInv` violated | — | — |

  The two mutants being caught is the part that carries weight: it shows
  TLC is not passing vacuously, which was the live risk given the
  `pcal.trans` `.cfg`-overwrite failure mode. The clean runs show the
  models are self-consistent — not that they represent a real robot.
  Ten distinct states is a small model. It does not explore clock skew,
  partial actuation, sensor noise, or any of the physical problems listed
  above. Read "formally checked" as "the spec is not self-contradictory
  and the checker works", never as "the behaviour of a real system is
  proved".

  Reproduce with `./formal/check.sh`, which fetches a checksum-verified
  tla2tools, runs all four models, and exits non-zero if TLC ever
  accepts a mutant.
- **`pmcp-typescript` has no test suite and does not compile.** Any
  "three peer SDKs" claim is currently a claim about two SDKs plus a
  skeleton. The TypeScript build being non-blocking in CI is a declared
  failure, not a passing check.
- **`pmcp-rust/pmcp-ledger` does not compile.** Its CI job is
  non-blocking, which means nothing about it has been verified.
- **CI has not yet run on GitHub.** The figures in the table are from
  local runs on the release machine. The Actions runs are the next step,
  and if they differ, this table is what needs correcting.

## Open research problems (not yet resolved)

These require physical hardware to close and are not solvable by more
code review, more unit tests, or more model-checking on their own.
Naming them here is the point — a coordination protocol that claims
safety without saying what is still open is not one you should trust.

1. **Cross-hardware HNN determinism budget.** The Shadow-validation
   layer (monitor-controller / Simplex pattern) relies on neural-network
   behaviour being predictable enough to gate on. How much timing and
   numerical variance exists across different hardware backends, and
   what tolerance budget that leaves for the safety gate, is an
   empirical question we have not measured across real hardware.
2. **Conformal prediction behaviour under adversarial input.** The
   statistical guarantees conformal prediction gives assume inputs drawn
   from the calibration distribution. What happens under adversarial or
   out-of-distribution input — and what that means for the safety gate
   that depends on it — is unresolved.
3. **UWB anchor geometry for moving robots.** The physical-location
   proof layer (UWB-based) has geometry assumptions that were validated
   for the configurations tested so far. Anchor placement and accuracy
   for robots in motion, as opposed to fixed reference frames, needs
   further empirical work.

## Known engineering gaps (disclosed, not safety research)

These are ordinary unfinished work, listed so nobody mistakes them for
solved:

- `pmcp-python` ships at least **four** client implementations side by
  side (`pmcp/client.py`, `pmcp/client_v2.py`, `sdk/client.py`,
  `v05/pmcp_v5_client.py`) and three parallel server packages. Picking a
  canonical one is the highest-value open contribution in that repo.
- `pmcp-typescript` has **two** competing `PMCPServer`
  implementations (`src/server.ts` and `src/server_impl.ts`), re-exported
  simultaneously from `src/index.ts`.
- `pmcp-registry` has no authentication, `CORS *` on `POST`/`DELETE`, no
  request-body size limit, no host/port allowlist on `register` (an SSRF
  pivot), and directory listing on the static mount. **Do not expose it
  to an untrusted network.**
- `pmcp-safety`'s TEE attestator returns `MOCK_QUOTE` with hardcoded
  enclave keys, and its safety loop defaults to `--simulator mock`.
  **Neither is a security boundary.**
- `pmcp-labs/infra/` Dockerfiles and compose files reference pre-split
  paths and do not build.
- Five `pmcp-servers/examples/` files import `pmcp_grand_unified` from
  the private `pmcp-labs` repository, so they cannot run without access
  to it.

## What this means in practice

- If you are evaluating PMCP for a system where Shadow validation,
  conformal prediction, or UWB localization is load-bearing for safety,
  **do your own hardware validation of those specific components**
  before relying on them. The lease/mutex coordination, gate ordering,
  and the E-Stop latch are the parts we can currently stand behind
  unconditionally.
- Do not treat this document as a complete list of what is unfinished.
  It is a list of what we have *checked*. A repository's own CHANGELOG
  carries the rest.
- We will update this file as these problems close, as new ones surface,
  and as CI numbers come in. Verification is ongoing, not a one-time
  event before launch.
- Found something we are overclaiming, or a gap this list does not
  cover? Open an issue against the repository it concerns — there is an
  issue template for exactly that. That is the fastest way to make this
  document more trustworthy, not a problem for us.
