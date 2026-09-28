# Contributing to pmcp-spec

The source-of-truth repository for the Physical Model Context Protocol.
Everything else — `pmcp-python`, `pmcp-typescript`, `pmcp-rust`,
`pmcp-conformance` — implements against what is defined here.

The organization-wide contributor policy lives in
[`physicalcontextprotocol/.github`](https://github.com/physicalcontextprotocol/.github/blob/main/CONTRIBUTING.md).
This file covers what is specific to this repository.

## What belongs here

- `docs/PROTOCOL_SPEC.md` — the normative wire protocol.
- `docs/SAFETY_ARCHITECTURE.md` — how the safety pipeline is layered.
- `docs/FOUNDATION_CHARTER.md` — governance.
- `schema/v0.6.0/` — JSON Schema 2020-12 definitions and examples.
- `formal/` — the TLA+ models and their `.cfg` files.
- `LIMITATIONS.md` — what is verified, and what is not.
- `MIGRATION_MAP.md` — how the pre-split monorepo maps onto the
  current multi-repository layout.

Runtime code does **not** belong here. If you are adding an
implementation, it goes in an SDK repository.

## Running the checks

The formal models and the schema are the two things CI checks here.

```bash
# JSON Schema — validate the schema and round-trip the examples
python -m pip install jsonschema
python -c "import json, jsonschema; \
  s=json.load(open('schema/v0.6.0/pmcp.schema.json')); \
  jsonschema.Draft202012Validator.check_schema(s); print('schema OK')"

# TLA+ — model-check both specs (requires the TLA+ toolbox, or tlaplus/tlc)
tlc2.TLC -config formal/PMCPCore.cfg     formal/PMCPCore.tla
tlc2.TLC -config formal/PMCPRecovery.cfg formal/PMCPRecovery.tla
```

`formal/README.md` documents the mutant-testing procedure that verifies
TLC is actually catching injected spec violations, rather than passing
vacuously. If you change a spec, re-run that procedure — a translation
bug once made an invariant check pass for the wrong reason, and that is
exactly the failure mode this repository cares about.

## Changing the protocol

1. **Spec changes and schema changes go in the same PR.** A change to
   `PROTOCOL_SPEC.md` that is not reflected in
   `schema/v0.6.0/pmcp.schema.json` will fail CI's schema check.
2. **Say what is normative.** Distinguish a rule that implementations
   *must* satisfy from a numeric default that is merely a suggested
   value. `CONST-01` through `CONST-08` were recently reclassified this
   way for a reason.
3. **Update the conformance suite in the same PR or a linked one.** A
   spec change with no test that would catch a violation is a change
   nobody can rely on.
4. **Update `LIMITATIONS.md`** if your change closes an open problem, or
   opens a new one.

## Style

- Keep the gate order consistent everywhere. It is
  **E-Stop → Lease → Constitution → Shadow**, and it is normative. §13.3
  once still showed the old Shadow-before-Constitution ordering; that
  class of inconsistency is a bug.
- Prefer a stated assumption over an unstated one. Where something is
  unresolved, write that it is unresolved.

## PR description

Please include which documents you touched, why the change is needed,
and how you verified it — in particular, whether you re-ran the TLA+
model check and the mutant test if you touched `formal/`.
