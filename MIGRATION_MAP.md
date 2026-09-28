# P-MCP monorepo → pmcp-org migration map

This documents how the original single-repo P-MCP tree was split into
nine independently-versioned repos under `pmcp-org/`, mirroring the
`modelcontextprotocol` GitHub organization pattern. It's a **file-copy
restructuring pass** — imports have not been rewritten and no bugs from
the source tree have been fixed as part of this pass (see "Not done in
this pass" below).

## Repo → source directory mapping

| Repo | Source directories/files |
|---|---|
| `pmcp-spec` | `docs/PROTOCOL_SPEC.md`, `docs/FOUNDATION_CHARTER.md`, `docs/PROJECT_EXPLANATION.md`, `docs/README.md` |
| `pmcp-python` | `pmcp/`, `v05/`, `sdk/`, `pyproject.toml`, `requirements.txt`, `tests/` (minus `tests/conformance/`) |
| `pmcp-typescript` | `typescript-sdk/` |
| `pmcp-rust` | `rust/pmcp-core/`, `ledger/` |
| `pmcp-conformance` | `tests/conformance/` |
| `pmcp-servers` | `v05/robot_servers/`, `reference_impl/`, `examples/`, `simulator/`, `gateway/`, `ros2-bridge/` |
| `pmcp-registry` | `registry/` |
| `pmcp-safety` | `safety-loop/`, `tee-attestator/`, `compliance/`, `multisig/`, `edge/` |
| `pmcp-labs` | `v01/`, `v02/`, `v03/`, `v04/`, `legacy/`, `community/`, `cloud/`, `depin/`, `physics-federation/`, `swarm/`, `marketplace/`, `pmcp_grand_unified.py`, `docker/`, `docker-compose.yml`, `Dockerfile` |

Org-wide meta files (`README.md`, `CHANGELOG.md`, `.github/workflows/ci.yml`)
were copied to the `pmcp-org/` root, since they don't belong to any one
repo. `LICENSE` was duplicated into all nine repos (standard practice
for split orgs — each repo needs its own copy for distribution).

Note: `v05/robot_servers/` is referenced from both `pmcp-python` (as
part of the v05 tree) and `pmcp-servers` (as the reference servers) —
it's duplicated on purpose. Once `pmcp-python`/`v05` and the duplicate
clients are consolidated (see below), `pmcp-servers` should depend on
`pmcp-python` rather than vendoring a copy of `robot_servers/`.

## Sequencing (per prior architectural decision)

Spec and conformance stabilize first, then SDKs follow, with
`pmcp-labs` migrated/quarantined last:

1. `pmcp-spec`, `pmcp-conformance`
2. `pmcp-python` → `pmcp-typescript` → `pmcp-rust`
3. `pmcp-servers`, `pmcp-registry`, `pmcp-safety`
4. `pmcp-labs` (already done here, but treat as unstable)

## Flagged issues (surfaced by this split, not yet fixed)

1. **Four duplicate client implementations** in `pmcp-python`:
   `pmcp/client.py`, `pmcp/client_v2.py`, `sdk/client.py`,
   `v05/pmcp_v5_client.py`. No canonical one has been chosen.
2. **`pmcp_grand_unified.py`** (161KB, at former repo root) has no
   clear owner and duplicates functionality now spread across
   `pmcp-python`, `pmcp-safety`, `pmcp-servers`. Parked in `pmcp-labs`
   pending a split/deprecate/archive decision.
3. **JSON Schemas** for `pmcp-spec` are not populated in this pass —
   they need to be hand-extracted from the canonical Python types once
   the duplicate-client/type question above is resolved (extracting
   schemas from four different type definitions would just encode the
   duplication).
4. **Rust workspace structure**: `pmcp-core` and `ledger` are two
   independent crates in `pmcp-rust`; whether they should be members of
   one Cargo workspace is undecided.
5. **`docker/` duplication**: `pmcp-labs/infra/` has both a `docker/`
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
  `pmcp-safety`, re-export from `pmcp-python`).
- Converting `pmcp_kinematics`'s hard cross-package import to a soft
  import in `pmcp-safety`.
- Converting the registry hard dependency in `main_pmcp_v5.py`'s CLI
  demo to a soft `try/except` import.

These are all good candidates for the next pass, once you confirm
whether to redo them against this fresh copy.
