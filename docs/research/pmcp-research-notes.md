# P-MCP Specification — Pre-Finalization Research Notes

**Scope.** Six research areas supporting the canonical protocol specification for P-MCP (Physical Model Context Protocol): a safety-critical robotics coordination protocol modeled on Anthropic's MCP, but for physical actuation of robots. Five-layer architecture: TEE attestation, Ed25519 robot/client identity, CRDT ledger, Hamiltonian Neural Network (HNN) physics validation, JSON-RPC 2.0 application layer. Safety-critical actuation commands pass through a gated sequence: Lease acquisition → Constitution check → Shadow (physics-simulation) validation → real actuation.

For each area: key concepts to get right, safety/robotics-specific pitfalls, and 2–4 concrete references to read in full.

---

## 1. MCP Schema, Versioning, and Capability Negotiation

### Key concepts to get right

- **TypeScript-first, JSON Schema as derivative.** MCP defines its schema in `schema.ts` (TypeScript) and emits `schema.json` as a derived artifact. The TypeScript file is the source of truth; the JSON Schema exists for non-TS consumers and tooling. This is the opposite of OpenAPI/AsyncAPI, where YAML/JSON *is* the source of truth. For P-MCP, given you want Rust + Python + TS SDKs, you should pick one direction deliberately — see §4.
- **Dated spec versions, not semver.** MCP versions specs by date (`2025-03-26`, `2025-06-18`, `2026-07-28`). Schema/JSON files are tagged to the spec date, not bumped through `MAJOR.MINOR.PATCH`. The implicit contract: breaking changes only happen at date-stamped releases, and any SDK pinning a date-version has a frozen contract.
- **Capability negotiation is a per-peer, bi-directional advertisement.** Both `ClientCapabilities` and `ServerCapabilities` are declared in the `Initialize` request/response. Capabilities are *additive* and *opt-in*: a feature exists in the spec but a peer must advertise it before you can use it. Critically, MCP does **not** negotiate down — there is no "highest common denominator" — each direction advertises independently.
- **Method namespacing with dotted prefixes.** `tools/call`, `resources/read`, `prompts/get`. Reserved prefixes (`resources/`, `prompts/`, `tools/`, `logging/`, `completion/`, `notifications/`) are owned by the spec; custom methods use reverse-DNS or vendor prefixes.
- **JSON-RPC 2.0 as the wire envelope.** Request/response/notification semantics, batch support, error codes reserved in the `-32000` to `-32099` range for protocol errors. MCP layers its own error semantics on top (`McpError` codes).
- **Schema evolution is additive-only across dated versions.** New fields are optional; deprecation is by documentation, not by removal. There is no formal "removed in version X" process yet — fields become deprecated but linger.

### Pitfalls to avoid

- **Treating capability advertisement as a contract.** Advertising `tools` doesn't mean the server implements every method — you still need per-method probing or graceful fallback. For safety-critical actuation, this is unacceptable: you must require *positive capability declaration plus per-method precondition check* before issuing any actuation command.
- **Implicit assumption of bidirectional capability symmetry.** A client advertising `roots` doesn't mean the server can handle `roots/list` — these are separate directions. P-MCP's lease/constitution/shadow gating should declare capabilities on *both* sides explicitly per gate.
- **Version drift between schema.ts and schema.json.** MCP has had releases where the TS and JSON schema briefly diverged. If you mirror their model, your CI must run a generation-and-diff check on every PR.
- **Using date versions without an SDK compatibility matrix.** Users have no way to know "does SDK X support spec Y" without checking docs. P-MCP should publish an explicit capability matrix.

### References to read in full

1. **MCP spec repository**: `github.com/modelcontextprotocol/modelcontextprotocol` — read `schema/schema.ts`, `schema/schema.json`, `README.md`, and the spec markdown under `/docs`.
2. **MCP Specification (latest, dated)**: `modelcontextprotocol.io/specification/2026-07-28` — and diff against `2025-06-18` to see how a real protocol evolves a schema additively.
3. **JSON-RPC 2.0 specification**: `jsonrpc.org/specification` — read in full; it's short, and every word matters (especially §5.1 on batch and §5.2 on notifications).

---

## 2. Industrial Robot Safety Standards (ISO 10218, ISO/TS 15066, IEC 61508, ANSI/RIA R15.06)

### Key concepts to get right

- **ISO 10218-1:2025 and 10218-2:2025** are the *current* editions (published 2025, third edition). They supersede the 2011 versions and made functional safety requirements *explicit rather than implied*. Part 1 covers the robot itself (partly-completed machinery); Part 2 covers system integration. P-MCP's spec should reference the 2025 editions, not 2011.
- **"Safety-rated" means something specific.** It means a function has been designed, validated, and certified to a Performance Level (PL) per ISO 13849 or SIL per IEC 62061 / IEC 61508. It is **not** a marketing term. A "safety-rated stop" carries a guaranteed response time, a dual-channel architecture, and diagnostic coverage.
- **The dual-channel / 2-out-of-2 (2oo2) or 1-out-of-2 (1oo2) principle.** Safety-rated functions require redundant signal paths with cross-monitoring. For P-MCP, your Lease acquisition + Constitution check + Shadow validation is structurally a 3-vote gate, which exceeds 2oo2 — but you must define what happens when any single channel disagrees (fail-safe → inhibit actuation).
- **Fail-safe default = motion-stopped, power-maintained (or removed depending on category).** ISO 10218 defines Stop Categories 0, 1, 2: Cat 0 = immediate power removal (uncontrolled); Cat 1 = controlled deceleration then power removal; Cat 2 = controlled stop with power maintained. P-MCP must specify which Stop Category each gate-failure triggers.
- **ISO/TS 15066 defines biomechanical force/pressure thresholds.** It enumerates max permissible force/pressure on 29 body regions for collaborative operation. Your Shadow validation layer's physics model must include these thresholds if any collaborative operation is in scope.
- **IEC 61508 is the meta-standard.** It defines Safety Integrity Levels (SIL 1–4), the safety lifecycle, hazard and risk analysis, and the techniques required per SIL. SIL 2 is typical for industrial robot integration; SIL 3 for high-risk functions; SIL 4 almost never seen in robotics. Your Constitution layer should declare the target SIL per command class.
- **ANSI/RIA R15.06 is the U.S. national adoption** of ISO 10218 with deviations. It is essentially equivalent but you must comply with both if operating in the U.S.
- **Safety-rated monitored stop (SMS)** is the gate that brings collaborative robots to a controlled stop *before* a human enters the workspace. P-MCP's lease-expiry behavior should mirror SMS semantics.

### Pitfalls to avoid

- **Treating "stop" as a single concept.** Stop Category 0 vs 1 vs 2 have radically different failure modes and dynamics. A protocol-level "STOP" command that doesn't specify category is indefensible.
- **Implicit assumption that software can be SIL-rated.** IEC 61508 Part 3 explicitly requires hardware-backed diagnostics for SIL 2 and above. Pure-software safety functions top out around SIL 2 with restrictive assumptions. If your HNN physics validation is pure software, your achievable SIL ceiling is bounded.
- **Ignoring the "safety lifecycle" of IEC 61508.** The standard doesn't just require techniques at implementation time — it requires hazard analysis, safety requirements specification, verification, validation, and a *change management process*. Your protocol must produce the artifacts (audit log, hazard list, validation evidence) the lifecycle demands.
- **Conflating "functional safety" with "security."** IEC 61508 is about random and systematic *failures*; security (adversarial attacks) is addressed by IEC 62443. P-MCP must address both — a security compromise can be a systematic safety failure, and the standards increasingly cross-reference.
- **Forgetting that ISO/TS 15066 requires a *speed and separation monitoring (SSM)* architecture**, not just force-limiting. SSM requires deterministic, bounded-cycle response — your lease TTL must be derived from the worst-case SSM response time, not from network latency.
- **Publishing the spec without a hazard analysis.** ISO 12100 (general machine safety risk assessment) is the entry point that 10218, 15066, and 61508 all assume. Your spec should reference ISO 12100 as the framing methodology.

### References to read in full

1. **ISO 10218-1:2025 and ISO 10218-2:2025** — `iso.org/standard/73933.html` and `/73934.html`. Read both Parts in full. Also read Hartmann et al., *Comparative analysis of ISO 10218-1/2 (2011 vs. 2025)* (ScienceDirect, 2026) for a structured diff.
2. **ISO/TS 15066:2016** — *Robots and robotic devices — Collaborative robots*. Read Annex A (biomechanical thresholds) in full; it's the most-quoted and least-implemented-correctly part.
3. **IEC 61508 Parts 0–7** — at minimum read Part 1 (general), Part 3 (software requirements), and Part 6 (guidelines). The "techniques table" in Part 7 is essential: it tells you which techniques are mandatory per SIL.
4. **ISO 13849-1** — *Safety of machinery — Safety-related parts of control systems*. This is where Performance Levels (PL a–e) are defined, and is what 10218 actually references for safety-related control functions.

---

## 3. Existing Robotics Protocols: ROS 2/DDS, MAVLink, OPC-UA Safety, TEE-Attested Identity

### ROS 2 / DDS (and DDS-XRCE)

**Key concepts:**

- ROS 2 sits on DDS, which provides 20+ QoS policies (reliability, durability, deadline, lifespan, liveliness, history depth, etc.). QoS is the *primary* mechanism for ensuring safety-relevant delivery semantics.
- Critical QoS pairs: `RELIABLE` + `KEEP_ALL` for commands; `BEST_EFFORT` + `KEEP_LAST(1)` for high-frequency telemetry; `TRANSIENT_LOCAL` durability for late-joining consumers of state.
- DDS Security (the SMI profile) provides authentication (X.509 + PKI), access control (permissions XML), cryptographic protection (AES-GCM), and data tagging — but it is *opt-in* and rarely enabled in production ROS 2 deployments.
- DDS-XRCE (for resource-constrained devices) is a *thin client* protocol on top of DDS, with its own session/reliability layer. It does not inherit DDS Security by default.
- The ROS 2 `lifecycle` node is a managed state machine: `unconfigured → inactive → active → finalized`, with deterministic transitions. This is the closest ROS-native analog to your lease/constitution/shadow gating.

**Pitfalls:**

- Default QoS in ROS 2 (`RELIABLE` + volatile durability + `KEEP_LAST(10)`) is **not** suitable for safety-critical state. You must explicitly opt into `TRANSIENT_LOCAL` durability and bounded history.
- DDS multicast is often blocked on real networks — many "production" ROS 2 deployments silently fall back to unicast discovery, which changes timing semantics.
- The lifecycle node's failure modes are not well-specified; the standard says "transitions to INACTIVE on error" but doesn't define how to atomically cancel in-flight work.

**References:**

1. **DDS specification (OMG)** — formal/22-06-01 or later. Read §7 (QoS Policies) and §9 (DDS Security).
2. **ROS 2 DDS Security plugins docs** — `docs.ros.org/en/rolling/Tutorials/AdvancedTopics/Configure-DDS-Security.html`.
3. **arXiv:2509.03381**, *Dependency Chain Analysis of ROS 2 DDS QoS Policies* (2025) — the most rigorous recent treatment of QoS interactions.

### MAVLink

**Key concepts:**

- MAVLink v2 uses a command/acknowledgement pattern: `COMMAND_LONG` → `COMMAND_ACK` with result codes (`MAV_RESULT_ACCEPTED`, `_TEMPORARILY_REJECTED`, `_DENIED`, `_UNSUPPORTED`, `_FAILED`, `_IN_PROGRESS`).
- **Failsafe model is publisher-driven, not protocol-driven.** The autopilot owns the failsafe state machine; the GCS just sends `SET_MODE`. MAVLink's job is to detect loss-of-link via heartbeats and trigger a configured behavior on the autopilot side.
- The `HEARTBEAT` message at 1 Hz is the liveliness signal; loss for >N seconds triggers failsafe. This is conceptually identical to your lease expiration, but the timing bound is autopilot-configured.
- `COMMAND_ACK` carries a `progress` field (0–100) for long-running commands and a `result_param2` for transport-specific reasons — this is a useful pattern for your shadow-validation gate (which may take seconds to compute).

**Pitfalls:**

- MAVLink doesn't enforce that acks come back in order. Implementations must track `command_id`+`target_system` and not assume FIFO.
- The failsafe behavior is configured *on the robot*, not negotiated. A GCS cannot ask "what's your failsafe?" — it must trust the configuration. This is a major divergence from what P-MCP needs.

**References:**

1. **MAVLink v2 spec**: `mavlink.io/en/spec/`. Read §2 (Command Protocol), §4 (Heartbeat / Connection Protocol).
2. **PX4 failsafe docs**: `docs.px4.io/main/config/failsafes.html` — concrete state machine.

### OPC-UA Safety (OPC UA Part 15)

**Key concepts:**

- OPC UA Safety is a *safety communication layer (SCL)* on top of OPC UA. It is the cleanest industry example of a black-channel safety protocol: the underlying OPC UA stack is treated as a "black channel" that may fail arbitrarily, and the SCL provides end-to-end safety via a SIL-rated transmitter and receiver pair.
- **The SCL adds:** sequence numbers, time monitoring (a watchdog), CRCs over the safety payload, and a redundancy mechanism — exactly the kind of belt-and-suspenders your protocol needs.
- **Time monitoring is critical.** The SCL expects round-trip within a *configured* `SPDU_Timeout`. A missed round-trip → safety state. This is what your lease mechanism should look like.
- This is the architecture that has been certified to SIL 3 in production. It is the reference design to mirror.

**Pitfalls:**

- SCL doesn't make OPC UA itself safe — both endpoints must run the SCL stack. You can't "talk safety" to a non-safety OPC UA device.
- The SCL requires explicit configuration of `SPDU_Timeout`, `ack_timeout`, and `receive_timeout`. Getting these wrong can cause either spurious trips (too tight) or undetected failures (too loose).

**References:**

1. **OPC UA Part 15**: `reference.opcfoundation.org/specs/OPC-10000-15/4`. Read the whole spec; it's the most directly applicable reference to your gate-order design.
2. **PROFIBUS/PI OPC UA Safety specification** (free PDF): `profibus.com/download/opc-ua-safety-specification`.

### TEE-attested robot identity in multi-tenant physical environments

**Key concepts:**

- The published architectures (Partee.io's "Trustworthy Real-Time Containers for the Physical AI Era" whitepaper, Robo360's multi-tenant robotics docs) converge on: signed boot measurements + remote attestation + per-tenant RBAC layered on top.
- The pattern is: TEE measures boot state → TEE signs a quote → tenant verifies quote (via DCV-style flow) → tenant issues a short-lived capability token scoped to its tenancy.
- Robot-side TEE options: ARM TrustZone + OP-TEE (most common in embedded robotics), Intel SGX/TDX (rare in robotics), AMD SEV-SNP (server-side controllers), and RISC-V Keystone (emerging).

**Pitfalls:**

- TEE attestation only proves "the right code is running" — it doesn't prove "the robot is physically where it claims to be." You need a separate physical-locality proof (UWB distance bounding, BLE with RSSI, or visual fiducials).
- Multi-tenant doesn't compose cleanly with safety: if Tenant A's lease and Tenant B's lease would interfere (overlapping physical workspace), the protocol must refuse both, not serialize. Your lease layer must include spatial/temporal non-overlap predicates.
- TEEs are not necessarily real-time-capable. SGX has been shown to have variable exit-cost; OP-TEE can be configured RT but it's not default. If your lease handshake goes through the TEE, you must characterize its worst-case execution time.

**References:**

1. **"Trustworthy Real-Time Containers for the Physical AI Era"** (Partee Systems whitepaper, Feb 2026) — `partee.systems/assets/whitepaper-feb-2026.pdf`.
2. **OP-TEE documentation**: `optee.readthedocs.io` — the de-facto embedded TEE spec.
3. **Confidential Computing Consortium attestation specs**: `github.com/confidential-containers/attestation` — for the verifier-side patterns.

---

## 4. Versioned JSON Schema as the Single Source of Truth

### Key concepts to get right

- **Pick the source of truth deliberately.** Two viable patterns:
  - **OpenAPI/AsyncAPI pattern**: YAML/JSON is the source of truth; language SDKs are generated *from* the spec.
  - **MCP pattern**: TypeScript types are source of truth; JSON Schema is generated *from* TS.

  For P-MCP with three SDKs (Python/TS/Rust), I recommend the **schema-first** (JSON Schema as source of truth) pattern, because:
  - JSON Schema is language-agnostic and parseable by all three SDKs' codegen tools.
  - It composes with JSON-RPC 2.0 natively.
  - It avoids implying TypeScript is "more equal" than the others.

- **Use JSON Schema 2020-12, not draft-07.** 2020-12 is the current standard, has cleaner `$ref` semantics, and is supported by the modern toolchain.
- **quicktype is the dominant codegen tool for multi-language output from JSON Schema.** It generates Rust, Python, TypeScript, Go, Kotlin, Swift, C#, C++, Java. Use `quicktype-core` (npm) or the `quicktype` CLI.
- **For Rust specifically, use `schemars` + `serde` and generate JSON Schema *from* Rust types if you want a Rust-first approach, OR use `quicktype` to generate Rust types *from* JSON Schema. Don't mix — pick one.
- **Encode enums and state machines in JSON Schema using `enum` + `$comment` annotations** for documentation, and `oneOf` discriminated unions for state transitions. For conformance-test machine-checkability, generate a separate state-machine spec (see §6).
- **Version the schema with `$id` URIs that include the spec version date.** Example: `https://pmcp.org/schemas/2026-08-16/lease.schema.json`. This lets the JSON Schema validator refuse schema mixing.
- **Capability negotiation should itself be schema-described.** MCP does this; your `Initialize` response should include a JSON-Schema-validated `capabilities` object, not ad-hoc fields.

### Pitfalls to avoid

- **Using `oneOf` where you mean `discriminated union`.** JSON Schema `oneOf` validates that exactly one subschema matches, which is expensive and ambiguous when subschemas overlap. Use `allOf` with a `discriminator` property (or, in 2020-12, `prefixItems` with `const` for the discriminator).
- **Schema validation at runtime without compile-time validation.** Your SDKs should validate at the SDK boundary, not just at message send. A Rust SDK that hands you an unvalidated `LeaseRequest` struct has failed the user.
- **Not versioning the schema and the codegen output independently.** Generated SDK code should embed the schema version it was generated from. Otherwise drift is invisible.
- **Trusting codegen to produce idiomatic code.** `quicktype` Rust output is correct but not always idiomatic (uses `Box<T>` aggressively). Plan a thin wrapper layer that adapts codegen output to language idioms.
- **Missing negative tests.** Your conformance suite must include *invalid* messages that should be rejected — most schema-test suites only test the happy path.

### References to read in full

1. **JSON Schema 2020-12 spec**: `json-schema.org/draft/2020-12/release-notes`.
2. **quicktype docs**: `quicktype.io` and `github.com/glideapps/quicktype`. Look at the `--no-rendering` flag for splitting generation from rendering.
3. **OpenAPI 3.1 spec** (which aligns with JSON Schema 2020-12): `spec.openapis.org/oas/v3.1.0`. Even if you don't use OpenAPI, the section on `components/schemas` and discriminators is the cleanest treatment.
4. **AsyncAPI spec**: `asyncapi.com/docs/specifications/v2.6.0` — particularly useful if your protocol includes pub/sub or streaming primitives (which P-MCP's CRDT ledger does).

---

## 5. CRDTs in Safety-Critical / Real-Time Distributed Systems

### Key concepts to get right

- **CRDTs guarantee *eventual* convergence, not timely convergence.** This is the central tension with safety-critical use. CRDTs were designed for offline-capable eventually-consistent apps (Figma, Riak); using them for state where physical safety depends on convergence is structurally risky.
- **There are two main CRDT families:** state-based (CvRDT, "convergent") and operation-based (CmRDT, "commutative"). CmRDTs require a reliable causal broadcast; CvRDTs only require eventual delivery. For a safety-critical ledger, **CvRDTs are the safer choice** because they tolerate message loss without ordering dependencies.
- **Known safe CRDT designs:** MV-Register (multi-value register, lets conflicts surface as a set the application resolves), G-Counter/PN-Counter (monotonic counters), OR-Set (observed-remove set), LWW-Register (last-writer-wins with wall-clock or vector-clock tiebreak).
- **For your ledger specifically**, the right design is almost certainly a *sequence CRDT* (e.g., a Logoot/Woot-derived text CRDT or a Treedoc-style ordered list) for the audit log, combined with an LWW-Register or MV-Register for *current* robot state. Mixing these is fine but each layer must be analyzed independently for convergence bounds.
- **The fundamental safety property CRDTs do NOT provide:** mutual exclusion or single-writer guarantees. If two tenants both believe they hold a lease on the same robot, the CRDT will eventually converge — but during the divergence window, both may issue actuation commands. **Your protocol must layer a deterministic conflict-resolution rule on top of the CRDT**, not rely on CRDT semantics to enforce safety invariants.

### Pitfalls specific to safety-critical/robotics

- **Treating CRDT convergence as "good enough" without a time bound.** "Eventually consistent" is meaningless for safety. You must define a *convergence deadline* (e.g., "state converges within 500 ms of last write across all replicas in healthy network conditions") and treat missed deadlines as a safety event.
- **LWW-Register with wall-clock timestamps is dangerous.** Clock skew between TEEs can cause stale-writes-wins. Use vector clocks or hybrid logical clocks (HLCs, per Kulkarni 2014) — or a Lamport-style monotonic counter scoped per robot.
- **Operation-based CRDTs (CmRDTs) over an unreliable transport.** CmRDTs require causal delivery; if your transport doesn't guarantee it (DDS doesn't by default, MQTT doesn't), your CRDT will silently corrupt state. Use a CvRDT or layer a causal-broadcast shim.
- **CRDT state anti-entropy doesn't compose with limited memory.** CvRDTs grow monotonically — your state needs a *pruning* strategy (tombstone GC, snapshotting). Pruning correctness is subtle: pruning too early resurrects deleted state.
- **MV-Register conflicts surface as sets, not as decisions.** When two lease claims arrive simultaneously, the MV-Register will hold both, and your application must decide. This decision logic is where most "CRDT-based safety system" bugs live.
- **No CRDT can express a conditional write atomically.** "If lease is unheld, claim it" cannot be expressed as a CRDT operation — it requires a consensus round. Either use Paxos/Raft for lease acquisition (and CRDTs only for state replication), or accept that your "lease" is best-effort and require re-validation at actuation time.
- **The HNN physics validation result cannot itself be a CRDT** if it must be deterministic — physics validation is a *pure function* of inputs, not a commutative merge. Replicate the *inputs* via CRDT, compute the validation locally, and broadcast the result as a separate state stream.

### References to read in full

1. **Shapiro, Preguiça, Baquero, Zawirski (2011)**, *A comprehensive study of Convergent and Commutative Replicated Data Types* — INRIA RR-7506. The canonical reference; read in full.
2. **Kulkarni, Demirbas, Madappa, Avva, Leone (2014)**, *Logical Physical Clocks* (HLC paper). Essential for any CRDT-based system that needs time bounds.
3. **NASA/TM—2014-218497** (Torres-Pomales), *Selecting an Architecture for a Safety-Critical Distributed System* — `ntrs.nasa.gov/api/citations/20140004053/downloads/20140004053.pdf`. Directly addresses the "is eventually-consistent enough for safety?" question.
4. **CMU SEI, *Detecting Architecture Traps and Pitfalls in Safety-Critical Software*** — short but actionable catalog of distributed-architecture mistakes.

---

## 6. Formal Methods for Safety-Critical Protocol State Machines

### Key concepts to get right

- **TLA+ is the de facto industry standard for protocol specification.** AWS uses it for S3, DynamoDB, and other distributed systems; it has been used for ISO 26262 ASIL-D safety work. It produces machine-checkable specs with the TLC model checker and provides an interactive proof system (TLAPS).
- **PlusCal is TLA+'s algorithmic-syntax frontend.** It looks more like pseudocode and compiles to TLA+. For specifying your gate-order state machine, PlusCal is more approachable than raw TLA+.
- **The hierarchy of formal rigor, from light to heavy:**
  1. **Documented invariant list** (informal but precise English prose: "After Lease acquisition, Constitution check must be the next successful state transition; otherwise the state machine resets to Unleased.")
  2. **State machine diagrams** (UML state diagrams, ASCII art, Mermaid stateDiagram) — human-readable but not machine-checkable.
  3. **Property-based test invariants** (QuickCheck, Hypothesis, proptest) — machine-checkable against the implementation, but not the spec.
  4. **Alloy** — a lightweight formal specification language with an analyzer that does bounded model checking. Sweet spot between formal rigor and accessibility.
  5. **TLA+/PlusCal + TLC** — full formal specification with model checking.
  6. **Coq/Lean/Isabelle** — theorem proving with full mathematical proofs. Only worth it for the highest-assurance components.
- **For your spec, the right combination is:** UML state diagrams + prose invariants *in the spec doc*, PlusCal/TLA+ specs *in a `/formal/` directory* with TLC-checked properties, and property-based tests in each SDK that mirror the TLA+ invariants.
- **The invariants you must specify explicitly** for the Lease → Constitution → Shadow gate:
  - `LeaseHeldBeforeConstitution`: ∀ state transitions, ConstitutionChecked → LeaseHeld.
  - `ShadowPassedBeforeActuation`: ∀ state transitions, Actuated → ShadowValidated.
  - `LeaseMonotonicExpiry`: A lease, once expired, cannot be "re-resurrected" without a fresh handshake.
  - `FailSafeOnAnyChannelDisagreement`: If any gate fails or times out, the system transitions to a `Safe` state (motion-stopped) within `T_safe` ms.
  - `SingleActuationPerLease`: At most one actuation command per lease acquisition (or your spec defines the multiplicity rule).
- **Petri nets are useful for modeling concurrent safety properties** (mutual exclusion, deadlock freedom) and have a long history in industrial automation. They're less popular now than TLA+ but are well-supported in tools like Tapaal. Use them if you need to model concurrent multi-robot workflows where multiple leases interact.

### Pitfalls specific to safety-critical/robotics

- **Specifying only the happy path.** TLA+ specs that only model successful transitions are useless. You must model faults: lease expiry, gate timeout, partial failure, network partition, attacker sending spoofed acks.
- **Assuming time = logical steps.** TLA+ is untimed. For real-time bounds (your `T_safe` deadline), you need the *Real-Time TLA+* extension (RTLA+) or a timed automaton model in UPPAAL. Untimed TLA+ can prove liveness but not "responds within 50ms".
- **Not validating the spec against the implementation.** A TLA+ spec that's not connected to the implementation will drift. Use `Apalache` (TLA+ to TypeScript) or write property-based tests that mirror the TLA+ invariants.
- **Treating UML state diagrams as formal specs.** UML is informal — the same diagram can be interpreted differently. If you use UML, also write the invariants in prose and at least one formal notation.
- **Conflating safety properties with liveness properties.** Safety = "bad thing never happens" (no actuation without shadow validation). Liveness = "good thing eventually happens" (every request gets a response). For safety-critical protocols, **safety properties are mandatory, liveness properties are optional** — and liveness often must be sacrificed (a stuck-safe system is acceptable; an eventually-actuating-but-maybe-unsafe system is not).
- **Forgetting the halting principle**: in safety-critical contexts, **the ability to halt safely is more important than the ability to make progress.** Your state machine should make `Halt` reachable from every state, with bounded transition time.

### References to read in full

1. **Leslie Lamport, *Specifying Systems*** (book, free PDF: `lamport.azurewebsites.net/tla/book-02-08-08.pdf`). The canonical TLA+ reference; read at least chapters 1–4.
2. **Newcombe et al. (AWS), *Use of Formal Methods at Amazon Web Services*** — `lamport.azurewebsites.net/tla/formal-methods-amazon.pdf`. Short paper that justifies the engineering value.
3. **Resch et al., *Using TLA+ in the Development of a Safety-Critical Fault-Tolerant Module*** (IEEE ISSREW 2017, `computer.org/csdl/proceedings-article/issrew/2017/2387a146/12OmNrNh0PL`). Closest published case study to your problem domain.
4. **Alloy documentation and tutorial**: `alloytools.org`. Worth reading even if you adopt TLA+ — the bounded-model-checking approach is a useful complement to TLA+'s unbounded checking.

---

## Cross-cutting recommendations

A few things emerged across all six areas that I want to flag separately:

1. **Define your "Safe State" first, before any other spec work.** Every standard (ISO 10218, IEC 61508, OPC-UA Safety) and every protocol (MAVLink, ROS 2 lifecycle) starts from a defined fail-safe state. P-MCP's spec doc should open with: "In any failure, fault, ambiguity, or timeout, the system transitions to Safe State within `T_safe` milliseconds. Safe State is defined as: leases revoked, motion stopped per Stop Category 1, audit log sealed."

2. **Mirror OPC-UA Part 15's "black channel" pattern.** Treat JSON-RPC 2.0, the transport, and even the TEE as a black channel that may fail arbitrarily. Your safety guarantees come from an end-to-end safety layer above them, not from trusting any single component.

3. **Get the timing bounds from physics, not from network latency.** ISO/TS 15066's SSM response time bounds come from human biomechanics (how fast a person can move into the workspace). Your `T_safe`, your lease TTL, and your CRDT convergence deadline should all derive from physical constants, not from "typical" network performance.

4. **The CRDT ledger is the most likely place for a subtle safety bug.** Strongly consider using Raft/Paxos for the lease/state machine (single-writer, deterministic) and CRDTs only for the audit log (which is append-only and where eventual convergence is acceptable). Pure-CRDT lease management is structurally hard to defend in a safety case.

5. **For the schema codegen toolchain, the most defensible modern stack is:** JSON Schema 2020-12 as source → `quicktype` for TS/Python → `schemars`/`serde` hand-authored for Rust (because Rust codegen output is rarely idiomatic). This is the pattern used by several production multi-language SDKs (e.g., the Stripe SDK).
