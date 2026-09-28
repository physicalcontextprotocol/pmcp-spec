# pmcp-spec

**The Physical Model Context Protocol (P-MCP) specification.** This is
the source-of-truth repository. Every SDK (`pmcp-python`,
`pmcp-typescript`, `pmcp-rust`) and the conformance suite
(`pmcp-conformance`) implements against what is defined here, and none
of them is the reference implementation.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Protocol Version](https://img.shields.io/badge/P--MCP-v0.5-brightgreen.svg)](docs/PROTOCOL_SPEC.md)
[![MCP Compatible](https://img.shields.io/badge/MCP-2024--11--05-orange.svg)](https://modelcontextprotocol.io)

> **Before you rely on this: read [`LIMITATIONS.md`](LIMITATIONS.md).**
> It lists what is verified by an actual run, and — more importantly —
> what is not, including the open problems that need physical hardware
> to close. A safety protocol that will not tell you what it has not
> proven is not one you should trust.

## What P-MCP does

P-MCP is a thin protocol layer that lets any MCP-compatible AI client
— Claude, GPT, Grok, Gemini, a local Ollama — command physical robots
through the standard MCP `tools/call` interface. The safety pipeline
lives on the robot side of the wire, not in the model's good
intentions:

```
Any LLM (Claude · GPT · Grok · Gemini · Ollama)
              │  Standard MCP JSON-RPC 2.0
              ▼
    ┌──────────────────────────────────────────────────┐
    │           P-MCP Server (robot-side)              │
    │                                                  │
    │  tools/list   → Robot actuations                 │
    │  tools/call   → E-Stop → Lease → Constitution →  │
    │                  Shadow → Execute                │
    │  resources/*  → Live sensor streams              │
    │  shadow/*     → Pre-flight simulation            │
    │  lease/*      → Zone ownership                   │
    └──────────────┬───────────────────────────────────┘
                   │  Safety Pipeline
       E-Stop (latch) → Lease → Constitution → Shadow → Execute
                   │
          Physical Robot Hardware
```

The gate order is **normative**: **E-Stop → Lease → Constitution →
Shadow**, defined in
[`docs/PROTOCOL_SPEC.md §6`](docs/PROTOCOL_SPEC.md). E-Stop is a real
actuation-blocking latch, not an advisory flag that another gate has to
remember to check.

## Contents

| Path | What it is |
|---|---|
| `docs/PROTOCOL_SPEC.md` | The wire protocol: five-layer architecture (TEE, Ed25519 identity, CRDT ledger, HNN physics validation, application layer), gate ordering, message types |
| `docs/SAFETY_ARCHITECTURE.md` | The safety pipeline in detail, including the §10.1 monitor-controller design and the §10.2 confidence schema |
| `docs/FOUNDATION_CHARTER.md` | Project charter and governance |
| `docs/PROJECT_EXPLANATION.md` | Narrative overview |
| `docs/PROTOCOL_README.md` | Original protocol README |
| `schema/v0.6.0/` | JSON Schema 2020-12 source of truth, plus `verify.py` and the example fixtures |
| `formal/` | Two TLA+ models, their `.cfg` files, and a `self-test/` directory of deliberately mutated specs |
| `LIMITATIONS.md` | What is verified, and what is not |
| `SECURITY.md` | **Canonical org-wide security policy** |
| `MIGRATION_MAP.md` | How the pre-split monorepo maps onto the current repository layout |

## Verified

```bash
pip install jsonschema
python schema/v0.6.0/verify.py
```

The schema is a valid JSON Schema 2020-12 document, every
`examples/valid/` fixture validates, and every `examples/invalid/`
fixture is rejected **for the reason it claims to probe** — not merely
rejected. That last property is enforced by `verify.py`, and it has
already caught one instance of false confidence:
`invalid/lease_grant_bad_state.json` used to be rejected only because
it omitted the required `fence_token`, so it read as proof that
`LeaseState` was enforced while proving nothing of the sort.

### The TLA+ models, and why the mutants matter

[`formal/`](formal/) holds two model-checked specs — `PMCPCore.tla` and
`PMCPRecovery.tla`. A model checker that passes a *wrong* spec is
worse than no model checker, because it manufactures confidence. That
failure is not hypothetical: a translation bug in the checking
tooling (`pcal.trans` silently overwriting `.cfg` on retranslation)
once made an invariant check pass vacuously.

So `formal/self-test/` contains deliberately mutated copies of both
specs, and the procedure is documented in `formal/README.md` for
anyone who does not want to take our word for it. The model-checking
CI job is **currently disabled** pending a self-hosted TLC runner — see
the job's own comment, and the note in `LIMITATIONS.md`.

## Known open items

- **No per-method JSON-RPC schema registry.** The schema defines the
  types under `$defs`, but not yet the mapping from JSON-RPC `method`
  names to request/response types. See `schema/v0.6.0/README.md`.
- **`ShadowResult`'s confidence, monitoring, and determinism blocks are
  required but nullable.** §10.2 forbids a bare-boolean verdict, so
  the keys must be present; a subsystem that is not implemented must say
  so with an explicit `null` rather than omit the key.
- **Field-level numeric constraints are not enforced as
  `minimum`/`maximum`.** The values they would encode (`T_safe`,
  `T_leader_unknown`, `epsilon_max`) are still open in §11, so they are
  documented in `description` fields instead of being invented.

## The wider project

| Repository | What it is |
|---|---|
| [`pmcp-python`](https://github.com/physicalcontextprotocol/pmcp-python) | Python SDK — 187 tests collected, 178 pass / 10 skip by default |
| [`pmcp-typescript`](https://github.com/physicalcontextprotocol/pmcp-typescript) | TypeScript SDK — skeleton, does not compile yet, no tests |
| [`pmcp-rust`](https://github.com/physicalcontextprotocol/pmcp-rust) | Rust crates — `pmcp-core` builds with 43 tests; `pmcp-ledger` does not compile |
| [`pmcp-conformance`](https://github.com/physicalcontextprotocol/pmcp-conformance) | 42 tests any implementation must pass |
| [`pmcp-safety`](https://github.com/physicalcontextprotocol/pmcp-safety) | Safety loop, TEE attestator, multisig gate, edge hardening |
| [`pmcp-servers`](https://github.com/physicalcontextprotocol/pmcp-servers) | Illustrative robot servers |
| [`pmcp-registry`](https://github.com/physicalcontextprotocol/pmcp-registry) | Experimental — **do not expose to an untrusted network** |

Organization overview and per-repository maturity:
[`physicalcontextprotocol`](https://github.com/physicalcontextprotocol).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). The short version: spec
changes and schema changes go in the same PR, and a spec change with no
test that would catch a violation is a change nobody can rely on.

## License

Apache 2.0 (see [`LICENSE`](LICENSE)).
