# PCP monorepo → pcp-org migration map

This documents how the original single-repo PCP tree was split into
nine independently-versioned repos under `pcp-org/`, mirroring the
`modelcontextprotocol` GitHub organization pattern. It's a **file-copy
restructuring pass** — imports have not been rewritten and no bugs from
the source tree have been fixed as part of this pass (see "Not done in
this pass" below).

## Repo → source directory mapping

| Repo | Source directories/files |
|---|---|
| `pcp-spec` | `docs/PROTOCOL_SPEC.md`, `docs/FOUNDATION_CHARTER.md`, `docs/PROJECT_EXPLANATION.md`, `docs/README.md` |
| `pcp-python` | `pmcp/`, `v05/`, `sdk/`, `pyproject.toml`, `requirements.txt`, `tests/` (minus `tests/conformance/`) |
| `pcp-typescript` | `typescript-sdk/` |
| `pcp-rust` | `rust/pcp-core/`, `ledger/` |
| `pcp-conformance` | `tests/conformance/` |
| `pcp-servers` | `v05/robot_servers/`, `reference_impl/`, `examples/`, `simulator/`, `gateway/`, `ros2-bridge/` |
| `pcp-registry` | `registry/` |
| `pcp-safety` | `safety-loop/`, `tee-attestator/`, `compliance/`, `multisig/`, `edge/` |
| `pcp-labs` | `v01/`, `v02/`, `v03/`, `v04/`, `legacy/`, `community/`, `cloud/`, `depin/`, `physics-federation/`, `swarm/`, `marketplace/`, `pmcp_grand_unified.py`, `docker/`, `docker-compose.yml`, `Dockerfile` |

Org-wide meta files (`README.md`, `CHANGELOG.md`, `.github/workflows/ci.yml`)
were copied to the `pcp-org/` root, since they don't belong to any one
repo. `LICENSE` was duplicated into all nine repos (standard practice
for split orgs — each repo needs its own copy for distribution).

Note: `v05/robot_servers/` is referenced from both `pcp-python` (as
part of the v05 tree) and `pcp-servers` (as the reference servers) —
it's duplicated on purpose. Once `pcp-python`/`v05` and the duplicate
clients are consolidated (see below), `pcp-servers` should depend on
`pcp-python` rather than vendoring a copy of `robot_servers/`.

## Sequencing (per prior architectural decision)

Spec and conformance stabilize first, then SDKs follow, with
`pcp-labs` migrated/quarantined last:

1. `pcp-spec`, `pcp-conformance`
2. `pcp-python` → `pcp-typescript` → `pcp-rust`
3. `pcp-servers`, `pcp-registry`, `pcp-safety`
4. `pcp-labs` (already done here, but treat as unstable)

## Flagged issues (surfaced by this split, not yet fixed)

1. **Four duplicate client implementations** in `pcp-python`:
   `pmcp/client.py`, `pmcp/client_v2.py`, `sdk/client.py`,
   `v05/pmcp_v5_client.py`. No canonical one has been chosen.
2. **`pmcp_grand_unified.py`** (161KB, at former repo root) has no
   clear owner and duplicates functionality now spread across
   `pcp-python`, `pcp-safety`, `pcp-servers`. Parked in `pcp-labs`
   pending a split/deprecate/archive decision.
3. **JSON Schemas** for `pcp-spec` are not populated in this pass —
   they need to be hand-extracted from the canonical Python types once
   the duplicate-client/type question above is resolved (extracting
   schemas from four different type definitions would just encode the
   duplication).
4. **Rust workspace structure**: `pcp-core` and `ledger` are two
   independent crates in `pcp-rust`; whether they should be members of
   one Cargo workspace is undecided.
5. **`docker/` duplication**: `pcp-labs/infra/` has both a `docker/`
   subfolder and root-level `docker-compose.yml`/`Dockerfile` covering
   overlapping ground.

## Not done in this pass

Compared to a prior working session on an earlier snapshot of this
codebase, this pass is **structural only**. It does **not** re-apply
(and hasn't re-verified) these previously-identified fixes, since this
upload is a fresh copy of the monorepo and none of that work is present
in it:

- Protocol spec gate-order correction (Lease→Constitution→Shadow).
- Reclassifying hardcoded thresholds from normative MUSTs to
  non-normative reference defaults in the spec.
- Stripping `|| true` from CI so failures are reportable.
- Adding missing `tests/__init__.py` files.
- The `ShadowPreview`/`ShadowStatus` circular-dependency fix (move to
  `pcp-safety`, re-export from `pcp-python`).
- Converting `pmcp_kinematics`'s hard cross-package import to a soft
  import in `pcp-safety`.
- Converting the registry hard dependency in `main_pmcp_v5.py`'s CLI
  demo to a soft `try/except` import.

These are all good candidates for the next pass, once you confirm
whether to redo them against this fresh copy.
