# Changelog — pcp-spec

All notable changes to the Physical Context Protocol
specification. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Implementation changes belong in the SDK's own changelog
(`pcp-python`, `pcp-typescript`, `pcp-rust`).

## [0.6.0] — 2026-09-28

First tagged public release of the specification.

Tagged **v0.6.0** to match the JSON Schema it ships, not the wire
protocol version, and this is worth being precise about because the two
numbers differ on purpose. The wire protocol is **0.5** — that is what
`PMCP_VERSION` carries in the reference SDKs and what a client sends in
`initialize`; `docs/PROTOCOL_SPEC.md` §3.2 explains why the schema runs
ahead of it. The release tag follows the schema, because the schema is
the artifact this repository ships and the thing a reader pins.

An earlier draft of this file headed the entry `## [1.0.0]`. That was
wrong twice over: it claimed a spec release that does not exist, and it
contradicted this repository's own README badge, which has said
PCP v0.5 throughout. The SDKs are at 1.0.0. The specification is not.

### Added

- **`LIMITATIONS.md`.** An explicit, maintained list of what is
  verified by an actual run and what is not. The list of open research
  problems is the point of the file: cross-hardware HNN determinism
  budget, conformal-prediction behaviour under adversarial input, and
  UWB anchor geometry for moving robots are all unresolved and need
  physical hardware to close.
- **`SECURITY.md`.** Organization-wide policy, including the
  private-reporting route and a per-repository supported-version table
  that is honest about which components should not face untrusted
  networks.
- **`MIGRATION_MAP.md`.** How the pre-split monorepo maps onto the
  current ten-repository layout, so the history of any given file is
  traceable.
- **`schema/v0.6.0/`** is now populated, validated against the JSON
  Schema 2020-12 meta-schema and round-tripped against
  `examples/valid/` and `examples/invalid/`.
- **`formal/self-test/`** — deliberately mutated copies of both TLA+
  specs, used to prove TLC actually catches a violation rather than
  passing vacuously. The procedure is documented in `formal/README.md`
  so anyone can re-run it.

### Fixed

- **§13.3 gate-order inconsistency.** The LLM Safety Invariant section
  still showed Shadow before Constitution while the rest of the
  specification had already been corrected to
  **E-Stop → Lease → Constitution → Shadow**. A section that
  contradicts the rest of the spec on the one property the spec exists
  to guarantee is the most damaging kind of documentation bug.
- **CONST-01 through CONST-08 reclassified.** The *rule semantics* are
  normative; the *numeric thresholds* (2.0 m/s, 50 000 J, 0.5 m, …) are
  now labelled non-normative reference defaults sized for a small
  collaborative arm. CONST-01 (2.0 m/s cap) was also reconciled against
  the tighter `move_to` inputSchema cap (1.0 m/s) so a reader knows
  both apply.

### Changed

- **The specification moved out of a monorepo into its own
  repository.** This was done to keep the three SDKs looking like peer
  implementations rather than bindings of one reference
  implementation — a single repository would have undercut that claim.

## [0.5.0]

Draft protocol line. Gate ordering, E-Stop latch semantics, and the
lease/mutex coordination model were established here.

## [0.1.0] – [0.4.0]

Development history, preserved as snapshots in the private
`pcp-labs/legacy/` repository.
