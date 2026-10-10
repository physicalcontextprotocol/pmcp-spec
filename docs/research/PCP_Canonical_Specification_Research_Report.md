# PCP (Physical Context Protocol): Canonical Specification Research Report

**A Comprehensive Technical Research Report Informing the Design of a Safety-Critical Robotics Coordination Protocol**

---

## Document Information

| Field | Value |
|-------|-------|
| **Document Title** | PCP Canonical Specification Research Report |
| **Version** | 1.0 |
| **Date** | August 2026 |
| **Classification** | Technical Research / Protocol Architecture |
| **Intended Audience** | Protocol architects, robotics safety engineers, distributed systems researchers, standards analysts |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Section 1 -- Anthropic MCP Architecture](#section-1----anthropic-mcp-architecture)
3. [Section 2 -- Industrial Robot Safety Standards](#section-2----industrial-robot-safety-standards)
4. [Section 3 -- Existing Robotics Protocol Architectures](#section-3----existing-robotics-protocol-architectures)
5. [Section 4 -- Schema-First Protocol Design](#section-4----schema-first-protocol-design)
6. [Section 5 -- CRDTs in Safety-Critical Systems](#section-5----crdts-in-safety-critical-systems)
7. [Section 6 -- Formal Specification Methods](#section-6----formal-specification-methods)
8. [Cross-Cutting Analysis](#cross-cutting-analysis)
9. [Deliverables](#deliverables)
10. [Must-Read Bibliography](#must-read-bibliography)
11. [Annotated Reference List](#annotated-reference-list)

---

## 1. Executive Summary

This report presents exhaustive research across six critical domains that must inform the design of the PCP (Physical Context Protocol) specification. PCP is proposed as a safety-critical robotics coordination protocol inspired by Anthropic's Model Context Protocol (MCP), but fundamentally redesigned for physical robot coordination rather than LLM tool invocation.

The current PCP architecture comprises five layers: Trusted Execution Environment (TEE) attestation, Ed25519 robot/client identity, CRDT-based distributed state ledger, Hamiltonian Neural Network (HNN) physics validation, and a JSON-RPC 2.0 application protocol. Safety-critical actuation follows a four-stage pipeline: Lease Acquisition, Constitution Validation, Shadow (Physics Simulation) Validation, and Real Actuation.

**Key findings from this research:**

- **Anthropic MCP**: Provides an excellent model for capability negotiation, transport abstraction, and schema-first design. However, MCP's "at-most-once" semantics, tolerance for idempotency, and lack of timing guarantees make it fundamentally unsuitable as a direct template for physical actuation without significant extensions. PCP should inherit MCP's schema organization, versioning conventions, and extension patterns, but must add deterministic delivery, lease-based mutual exclusion, and physics-validated command gating.

- **Industrial Safety Standards (ISO 10218, IEC 61508, ISO/TS 15066)**: These standards mandate specific protocol-level requirements that PCP's current architecture does not fully address. Critical gaps include: the absence of Safety Integrity Level (SIL) or Performance Level (PL) classification for the communication channel itself, no specified watchdog timing with deterministic upper bounds, and no formal definition of safe states or fail-safe transitions at the protocol level. The Lease-Constitution-Shadow-Actuation pipeline is a reasonable conceptual framework but requires additional stages for emergency stop propagation, heartbeat monitoring with specified timeouts, and dual-channel validation to meet SIL 2+ requirements.

- **Existing Robotics Protocols**: ROS 2 (DDS), MAVLink, OPC-UA Safety, and fieldbus safety protocols (EtherCAT Safety, PROFIsafe) each solve different aspects of the problem. MAVLink's command sequencing and acknowledgement model is the closest analog to PCP's actuation pipeline. OPC-UA Safety provides the gold standard for certified safety communication patterns. PCP should study OPC-UA Safety's redundancy and timing guarantee mechanisms, MAVLink's arming/disarming paradigm, and ROS 2's lifecycle node management.

- **Schema-First Design**: JSON Schema Draft 2020-12 with strict semantic versioning, automated conformance testing, and multi-language code generation is the correct foundation. The report recommends AJV for runtime validation, quicktype for cross-language SDK generation, and a canonical schema repository with CI/CD-enforced compatibility checks.

- **CRDTs in Safety-Critical Systems**: This is the most significant architectural concern. CRDTs are designed for eventual consistency, which is fundamentally at odds with the strong consistency and bounded latency required for physical safety. The research identifies specific timing hazards, split-brain scenarios, and convergence latency issues that make pure CRDT-based coordination insufficient for safety-critical actuation. The report recommends a hybrid approach: CRDTs for non-safety-critical state dissemination (e.g., robot status, sensor readings) combined with a consensus protocol (Raft) for safety-critical state transitions (lease grants, actuation permissions).

- **Formal Specification**: TLA+ is recommended as the primary formal specification language for PCP, supplemented by state machine diagrams for human readability. TLA+ model checking can verify protocol invariants, safety properties ("no two robots can hold the lease for the same resource simultaneously"), and liveness properties ("every lease request eventually receives a response"). The specification should define forbidden transitions, timing constraints, and protocol invariants in TLA+, with executable test vectors derived from the model.

**Overall assessment**: PCP's layered architecture shows sound design instincts, but the protocol requires significant hardening to meet industrial safety standards. The most critical gaps are in the safety validation pipeline (missing emergency stop handling and watchdog timing), the CRDT layer (inappropriate for safety-critical state without consensus), and the absence of formal specification. Addressing these gaps should be the top priority before any implementation begins.

---

## Section 1 -- Anthropic MCP Architecture

### Executive Summary

Anthropic's Model Context Protocol (MCP) is a JSON-RPC 2.0-based protocol designed for structured communication between LLM applications and external tools, data sources, and services. Released in late 2024 and standardized through an open specification hosted at modelcontextprotocol.io, MCP provides a well-designed foundation for capability negotiation, transport abstraction, and schema evolution. However, it was designed for a fundamentally different domain -- LLM tool invocation with human-in-the-loop oversight -- and its architectural assumptions are not directly transferable to safety-critical physical actuation without substantial modification.

This section analyzes MCP's architecture in detail, identifying conventions worth inheriting and areas requiring deliberate divergence for PCP.

### Fundamental Concepts

MCP is structured around a client-server model where the **client** is typically an LLM application and the **server** provides tools, resources, and prompts. Communication occurs over JSON-RPC 2.0, with support for multiple transport mechanisms including stdio (for local processes) and HTTP+SSE (for remote servers). The protocol is defined by a canonical TypeScript schema (`schema.ts`) that generates the JSON Schema (`schema.json`) used for validation.

The protocol's core abstractions include:

- **Tools**: Functions that the LLM can invoke, each with a JSON Schema for input parameters
- **Resources**: Named data sources (files, API responses) that the client can read
- **Prompts**: Reusable prompt templates with optional parameters
- **Sampling**: A mechanism for servers to request LLM completions from the client
- **Logging**: Structured log messages from server to client

MCP defines a three-phase lifecycle: **initialization** (capability exchange), **normal operation** (tool calls, resource reads), and **shutdown**. The initialization phase includes a version negotiation step where client and server agree on the protocol version to use, establishing a backward-compatibility mechanism.

### Protocol Versioning and Evolution Strategy

**Fact**: MCP uses a date-based versioning scheme (e.g., `2024-11-05`) rather than semantic versioning. Each version is a complete, self-contained snapshot of the protocol. The schema is organized as a single canonical TypeScript file that generates both TypeScript types and JSON Schema.

**Fact**: The MCP specification states that version negotiation occurs during initialization. The client proposes a version, and the server responds with the version it supports. If the server supports the proposed version, that version is used; otherwise, the server responds with the highest version it supports that is less than or equal to the client's proposal.

**Industry consensus**: Date-based versioning is unusual in protocol design. Semantic versioning (SemVer) is far more common for wire protocols (e.g., gRPC, HTTP/2, WebSocket subprotocols). Date-based versioning has the advantage of making each version unambiguously identifiable but sacrifices the semantic meaning of major/minor/patch increments.

**Recommendation for PCP**: PCP should adopt semantic versioning rather than date-based versioning. Safety-critical protocols benefit from the explicit communication of breaking changes (major version), backward-compatible additions (minor version), and bug fixes (patch version). The SemVer specification (SemVer 2.0.0, <https://semver.org/>) is well-understood, widely implemented, and provides clear rules for compatibility. PCP should define strict rules: major version changes may break wire compatibility; minor versions add optional fields and capabilities; patch versions fix specification ambiguities without changing wire format.

### Capability Negotiation

**Fact**: MCP implements capability negotiation through the `initialize` request/response exchange. The client sends its supported protocol version and declared capabilities (a JSON object with boolean flags). The server responds with its own capabilities. Capabilities include `tools`, `resources`, `prompts`, and `logging`.

**Fact**: MCP's capability model is simple boolean flags: either a party supports a capability or it does not. There is no versioning within capabilities, no partial capability support, and no capability parameters.

**Analysis**: This simple model works for MCP's use case because capabilities are relatively coarse-grained ("do you support tools?") and there is little variation in how a capability might be implemented. For PCP, capability negotiation needs to be more expressive. Safety-critical capabilities such as "shadow validation" or "HNN physics checking" may have multiple implementations, parameter ranges, or quality levels. PCP should consider a capability negotiation model that includes:

1. **Capability version**: What version of a capability is supported
2. **Capability parameters**: Numerical ranges or enumerations describing capability quality (e.g., physics simulation timestep resolution)
3. **Capability requirements**: Whether a capability is mandatory or optional for safe operation
4. **Capability interdependencies**: Whether one capability requires another (e.g., shadow validation requires HNN physics)

### Backwards Compatibility and Forwards Compatibility

**Fact**: MCP maintains backwards compatibility within a major version. New fields added to requests or responses are optional, and implementations must ignore unknown fields. This is a standard JSON-RPC convention.

**Fact**: MCP does not define a formal forwards compatibility mechanism beyond the "ignore unknown fields" convention. There is no extension field registry, no capability-based feature gating for individual message types, and no formal way to add new message types without a protocol version change.

**Industry consensus**: The "ignore unknown fields" convention (also called "tolerant reader" pattern) is a well-established best practice for JSON-based protocols. It is specified in RFC 7231 for HTTP, used extensively in OpenAPI specifications, and is a core principle of Protocol Buffers' forward compatibility. However, for safety-critical protocols, the "ignore unknown fields" approach has limitations: an unknown field in a safety-critical message might contain critical safety information that an older implementation silently discards.

**Recommendation for PCP**: PCP should adopt the tolerant reader pattern for non-safety-critical messages but implement a stricter policy for safety-critical messages. Specifically:

- Non-safety messages: Unknown fields are silently ignored (standard JSON tolerance)
- Safety-critical messages (lease grants, actuation commands, emergency stops): Unknown fields MUST cause the message to be rejected with a `PROTOCOL_VERSION_MISMATCH` error. This ensures that safety-critical messages are never processed by an implementation that does not fully understand their schema.

### JSON-RPC Usage

**Fact**: MCP uses JSON-RPC 2.0 as defined by the JSON-RPC 2.0 Specification (<https://www.jsonrpc.org/specification>). Requests include `jsonrpc: "2.0"`, `id`, `method`, and optional `params`. Responses include `jsonrpc: "2.0"`, `id`, and either `result` or `error`.

**Fact**: MCP supports three types of messages: requests (with id, expecting response), notifications (no id, no response), and responses. Notifications are used for server-to-client streaming messages (e.g., progress updates, log messages).

**Analysis**: JSON-RPC 2.0 is a reasonable choice for PCP's application layer. It is simple, widely implemented, and well-understood. However, PCP must address several JSON-RPC limitations:

1. **No delivery guarantees**: JSON-RPC over stdio provides reliable ordered delivery, but JSON-RPC over HTTP does not guarantee at-least-once delivery. PCP must define transport-level reliability guarantees.

2. **No flow control**: JSON-RPC has no built-in flow control mechanism. PCP may need application-level flow control for high-frequency state updates.

3. **No message prioritization**: All JSON-RPC messages are equal. PCP must define priority queuing for safety-critical messages (e.g., emergency stops must preempt lease requests).

4. **Batch mode**: JSON-RPC 2.0 supports batch requests, which could be useful for PCP's CRDT state synchronization but adds complexity.

### Transport Abstraction

**Fact**: MCP defines two transports: `stdio` (for local process communication via stdin/stdout) and `sse` (Server-Sent Events over HTTP for remote communication). The transport abstraction allows the protocol to work across different communication mechanisms without changing the application-level message format.

**Fact**: The `sse` transport uses HTTP POST for client-to-server messages and Server-Sent Events for server-to-client messages. This asymmetric pattern is designed for the typical LLM use case where the client sends occasional requests and the server streams responses.

**Analysis**: PCP's transport requirements are significantly different from MCP's. PCP needs:

1. **Bidirectional real-time communication**: Robot-to-robot and robot-to-coordinator messages flow in both directions simultaneously. MCP's SSE unidirectional model is insufficient.

2. **Deterministic latency upper bounds**: Safety-critical messages must have guaranteed maximum delivery times. Standard HTTP/SSE cannot provide these guarantees.

3. **Transport-level security**: TEE attestation results must be bound to the transport layer. PCP needs mutual TLS with hardware-rooted identity.

**Recommendation for PCP**: PCP should define a transport abstraction layer similar to MCP's but designed for real-time bidirectional communication. The reference transport should be WebSocket with per-message compression, with the abstraction allowing future transports such as QUIC, DDS, or custom real-time middleware. The transport interface should specify: maximum message size, maximum delivery latency (by message priority class), reliability guarantees (at-least-once for safety messages, best-effort for telemetry), and security requirements (mutual TLS with Ed25519-derived certificates).

### Lifecycle Design

**Fact**: MCP defines a three-phase lifecycle: initialization, normal operation, and shutdown. The initialization phase involves version and capability negotiation. Shutdown is a polite notification rather than a hard disconnect.

**Fact**: MCP does not define any recovery mechanism for mid-operation failures. If the connection drops during normal operation, there is no specified reconnection handshake, state recovery, or lease reconciliation.

**Analysis**: For PCP, lifecycle management is far more critical. A robot losing connection during an actuation sequence could leave physical objects in dangerous states. PCP must define:

1. **Graceful shutdown protocol**: A multi-step process ensuring all physical actuators reach safe states before disconnection
2. **Abrupt disconnection recovery**: What other robots should do when a peer disconnects without warning
3. **State reconciliation after reconnection**: How to determine what state was reached before disconnection
4. **Lease recovery**: What happens to held leases when the holder disconnects

### Error Handling

**Fact**: MCP defines standard JSON-RPC error codes (-32700 to -32603 for parse errors, invalid requests, method not found, invalid params, and internal errors) plus MCP-specific error codes in the -32000 to -32099 range. Custom error codes are defined for specific error conditions.

**Analysis**: MCP's error handling is adequate for its use case but lacks the error classification needed for safety-critical systems. PCP should categorize errors into:

- **Recoverable errors**: Temporary conditions that may resolve with retry (e.g., lease temporarily unavailable)
- **Unrecoverable protocol errors**: Specification violations requiring connection reset (e.g., invalid message format)
- **Safety errors**: Conditions requiring immediate safe-state transition (e.g., physics validation failure, watchdog timeout)
- **Fatal errors**: Conditions requiring full system shutdown (e.g., TEE attestation failure)

### Protocol Invariants

**Fact**: MCP maintains several implicit invariants: (1) messages are valid JSON-RPC 2.0, (2) the `id` field uniquely identifies a request-response pair, (3) notifications never receive responses, (4) the server's capabilities do not change after initialization.

**Recommendation for PCP**: PCP should define explicit, formally verifiable protocol invariants including:

1. At most one active lease per resource at any time
2. No actuation command is executed without a valid lease, constitution pass, and shadow validation
3. Emergency stop messages are always processed within a bounded time, regardless of system load
4. All safety-critical state transitions are logged in an immutable audit trail
5. The CRDT state ledger eventually converges to a consistent state across all non-partitioned nodes

### What PCP Should Inherit from MCP

| Convention | Rationale |
|-----------|----------|
| Schema-first design (canonical TypeScript schema generating JSON Schema) | Ensures type safety, enables automated code generation, single source of truth |
| Transport abstraction layer | Allows protocol evolution independent of transport technology |
| Capability negotiation during initialization | Enables interoperability across implementations with different feature sets |
| Tolerant reader pattern for non-safety messages | Standard JSON best practice, enables forward compatibility |
| Clear lifecycle phases (init, operation, shutdown) | Provides structure for state machine design |
| Reserved namespaces for extensions | Prevents naming collisions in a distributed ecosystem |

### What PCP Must Intentionally Diverge From

| MCP Convention | Reason for Divergence | PCP Approach |
|---------------|----------------------|----------------|
| Date-based versioning | Lacks semantic meaning for breaking vs. non-breaking changes | Semantic versioning (SemVer 2.0.0) |
| Simple boolean capability flags | Insufficient for safety-critical capability parameters | Versioned capabilities with parameters and interdependencies |
| No delivery guarantees | Unacceptable for physical actuation | At-least-once for safety, with idempotency keys |
| No timing constraints | Safety requires bounded latency | Per-message-class latency upper bounds |
| No message prioritization | Emergency stops must preempt other messages | Priority queuing with safety-critical priority class |
| Silent ignore of unknown fields in all messages | Safety-critical messages must be fully understood | Reject unknown fields in safety messages |
| No reconnection/recovery | Physical state requires recovery semantics | Full state reconciliation protocol |
| At-most-once semantics | Physical actions must be deduplicated | Idempotency keys on all actuation commands |
| No formal specification | Safety standards require formal verification | TLA+ specification with model checking |
| No emergency stop mechanism | Industrial robots require immediate stop capability | Dedicated E-stop message type with priority override |

### References

- Anthropic, "Model Context Protocol Specification," modelcontextprotocol.io, 2024-2025. <https://modelcontextprotocol.io/specification>
- Anthropic, "MCP TypeScript SDK," GitHub repository. <https://github.com/modelcontextprotocol/typescript-sdk>
- JSON-RPC 2.0 Specification. <https://www.jsonrpc.org/specification>
- SemVer 2.0.0. <https://semver.org/>

---

## Section 2 -- Industrial Robot Safety Standards

### Executive Summary

Industrial robot safety is governed by a comprehensive framework of international standards that define requirements for the entire robot system, including the communication protocol. This section analyzes the protocol-level implications of the key standards: ISO 10218-1/2 (robot safety), ISO/TS 15066 (collaborative robots), IEC 61508 (functional safety of E/E/PE systems), ANSI/RIA R15.06 (US adoption of ISO 10218), IEC 62061 (safety of machinery via SIL), and ISO 13849 (safety of machinery via PL). The central finding is that "safety-rated" communication is not merely a matter of adding error detection or encryption -- it requires deterministic timing, redundancy, formal verification of safety functions, and certified implementation patterns. PCP's current Lease-Constitution-Shadow-Actuation pipeline addresses some of these requirements at the application level but does not fully satisfy the protocol-level mandates of these standards.

### Fundamental Concepts

**Fact**: IEC 61508 defines four Safety Integrity Levels (SIL 1-4) that quantify the required reliability of a safety function. SIL is based on Probability of Dangerous Failure on Demand (PFD) for low-demand mode and Probability of Dangerous Failure per Hour (PFH) for high-demand/continuous mode. The standard applies to the entire safety function, including sensors, logic solvers, and actuators -- and critically, the communication between them.

**Fact**: ISO 13849 defines five Performance Levels (PL a-e) that classify the reliability of safety-related parts of control systems. PL is determined using a risk graph that considers severity, frequency, and possibility of avoiding the hazard. Like SIL, PL applies to the complete safety function including communication.

**Fact**: ISO 10218-1 (2011, amended 2020) specifies safety requirements for the robot itself (manufacturer requirements), while ISO 10218-2 specifies safety requirements for the robot system and integration (integrator requirements). Both standards reference IEC 61508 or ISO 13849 for the design of safety-related control system functions.

**Fact**: ISO/TS 15066 (2016, under revision) specifies safety requirements for collaborative industrial robot systems, defining four collaborative operation methods: safety-rated monitored stop, hand guiding, speed and separation monitoring, and power and force limiting.

### What "Safety-Rated" Requires from a Communication Protocol

Based on analysis of the standards above, a "safety-rated" communication protocol must satisfy requirements in several domains:

#### Deterministic Timing

**Standard requirement**: IEC 61508 and IEC 62061 require that safety-related communication has a defined maximum response time. For SIL 2, the PFH must be between 10<super>-7</super> and 10<super>-6</super> dangerous failures per hour. If communication failures contribute to the overall PFH, the communication channel's failure rate must be within this budget.

**Fact**: OPC-UA Safety (IEC 61784-3-3) specifies maximum communication cycle times depending on the SIL target. For SIL 3, the maximum cycle time is typically 10-20ms. PROFIsafe (IEC 61784-3-3) specifies maximum reaction times that include communication latency, processing time, and actuator response.

**Implication for PCP**: PCP must specify maximum message delivery latencies for each message class. For safety-critical messages (emergency stops, lease releases, safety-state transitions), the maximum end-to-end latency should be defined and verifiable. The CRDT layer's eventual consistency model must have bounded convergence time for safety-relevant state.

**PCP gap**: The current PCP specification does not define any timing constraints. This is a critical gap that must be addressed before the protocol can be considered for safety-rated applications.

#### Command Authorization and Interlocks

**Fact**: ISO 10218-1 Clause 5.4 requires that safety-related control functions are implemented using dedicated safety-rated components. Clause 5.4.2 specifies that the safety control system must be separate from the standard control system. This is often implemented as a dual-channel architecture where the safety channel operates independently of the standard control channel.

**Fact**: IEC 62061 requires that safety communication uses certified communication profiles. The standard references IEC 61784-3 for communication profiles, which define specific mechanisms for error detection (CRC, sequence numbers, watchdog), error reaction (safe state transition), and redundancy.

**Implication for PCP**: PCP's command authorization model (lease-based access control) is a good application-level mechanism but is not sufficient as a safety-rated interlock. A safety-rated system would require:

1. A dedicated safety communication channel (possibly using a certified protocol like OPC-UA Safety) that operates independently of the standard PCP communication channel
2. Dual-channel validation where safety-critical commands are verified by both the standard channel and the safety channel
3. Hardware-based interlocks that can override software-based lease authorization

#### Emergency Stop Behavior

**Fact**: ISO 10218-1 Clause 5.5.2 requires Category 0 or Category 1 emergency stop per IEC 60204-1. Category 0 immediately removes power to actuators. Category 1 decelerates to stop then removes power. The emergency stop function must override all other functions and operate independently of the robot's control system.

**Fact**: IEC 60204-1 requires that emergency stop devices have a mechanical or electrical design that ensures latching (stays activated until deliberately reset) and that resetting the emergency stop does not restart the robot.

**Implication for PCP**: PCP must define an emergency stop message type that:

1. Has the highest priority in the message queue (preempts all other messages)
2. Has a guaranteed maximum delivery and processing time
3. Triggers an immediate safe-state transition on the receiving robot
4. Is acknowledged independently of any other in-flight operations
5. Does not require a valid lease to be processed (emergency stop must always work, even from unauthorized sources)

**PCP gap**: The current Lease-Constitution-Shadow-Actuation pipeline does not include an emergency stop bypass. If a robot requires a valid lease to process any command, an emergency stop from a non-lease-holder would be blocked. This is a critical safety violation.

#### Safe States and Fail-Safe Transitions

**Fact**: IEC 61508 Clause 7.4.3 requires that safety-related systems achieve a safe state upon detection of a dangerous failure. The safe state must be defined for each safety function, and the transition to the safe state must be achieved within a specified time.

**Fact**: ISO 10218-1 Clause 5.5 requires that the robot achieve and maintain a safe state in the event of any single detectable fault. The safe state typically involves stopping all motion, removing power from actuators, and engaging mechanical brakes.

**Implication for PCP**: PCP must define:

1. A formal safe state for each robot type (not just "stop moving" but a complete specification of joint positions, actuator states, brake engagement, power states)
2. The maximum time allowed to reach the safe state from any operational state
3. A defined protocol for transitioning to the safe state upon detection of a communication fault, lease expiry, or safety validation failure
4. Recovery procedures for returning from safe state to operational state

#### Watchdogs and Heartbeats

**Fact**: IEC 61784-3 (which defines safety communication profiles) requires the use of watchdog timers for all safety communication. The watchdog monitors the communication and triggers a safe-state transition if a message is not received within the specified time.

**Fact**: PROFIsafe uses a "monitoring window" concept with a toggle bit and a watchdog timer. Each safety message includes a sequence number and a toggle bit. The receiver monitors for message loss, duplication, delay, and corruption. If any of these conditions are detected, the safety function transitions to a safe state.

**Implication for PCP**: PCP must define:

1. A heartbeat protocol with specified intervals for each operational mode
2. Watchdog timeout values for each message class
3. The behavior when a heartbeat is missed (safe-state transition)
4. Graceful degradation when heartbeats are intermittently delayed but not lost

**PCP gap**: While the lease mechanism provides a form of expiration-based safety (the lease expires if the holder fails to renew), there is no continuous heartbeat monitoring. A robot could lose communication while holding a valid lease, and the lease would not expire until its TTL. During that time, other robots would be unable to acquire the lease, potentially creating a deadlock or unsafe situation.

#### Redundancy and Diagnostic Coverage

**Fact**: IEC 61508 requires specific diagnostic coverage (DC) depending on the target SIL. For SIL 2, the minimum diagnostic coverage for hardware faults is 90%. For SIL 3, it is 99%. Diagnostic coverage measures the percentage of dangerous faults that are detected by the diagnostic functions.

**Fact**: IEC 61784-3 safety communication profiles achieve redundancy through various means: dual-channel communication (sending the same message on two independent channels), CRC with sufficient bit coverage, sequence numbering to detect loss and duplication, and timeout monitoring to detect delays.

**Implication for PCP**: PCP's CRDT-based state ledger provides natural redundancy for state data (multiple replicas), but CRDTs do not provide the type of redundancy required by IEC 61508. Safety communication redundancy requires independent, diverse channels that can detect common-cause failures. PCP should consider:

1. A separate safety channel (e.g., OPC-UA Safety over a different physical network) for safety-critical commands
2. Dual-channel validation where the CRDT state and a separate safety state must agree before actuation
3. Diagnostic coverage analysis of the communication channel (CRC, sequence numbers, timeouts)

### Assessment of the Lease-Constitution-Shadow-Actuation Pipeline

| Stage | Standards Requirement | PCP Coverage | Gap | Severity |
|-------|----------------------|----------------|-----|----------|
| Lease Acquisition | Authorization, access control | Partially addressed | No SIL classification of lease mechanism | Medium |
| Constitution Validation | Safety rule verification | Partially addressed | No formal specification of constitution rules, no certification path | High |
| Shadow Validation | Pre-actuation verification | Partially addressed | HNN physics validation is not a certified safety mechanism per IEC 61508 | High |
| Real Actuation | Safe command execution | Partially addressed | No dual-channel validation, no hardware interlock integration | Critical |
| (Missing) Emergency Stop | Mandatory per ISO 10218-1 | Not addressed | No E-stop message type, no priority override, no safe-state definition | Critical |
| (Missing) Heartbeat/Watchdog | Required per IEC 61784-3 | Not addressed | No heartbeat protocol, no watchdog timeouts | Critical |
| (Missing) Safe State Definition | Required per IEC 61508 | Not addressed | No formal safe state specification | Critical |
| (Missing) Recovery Protocol | Required per ISO 10218-2 | Not addressed | No defined recovery from communication loss or fault | High |

### Recovery After Communication Loss

**Fact**: ISO 10218-2 Clause 5.6 addresses the behavior of the robot system when communication between components is lost. The system must be designed so that loss of communication does not create a hazard. This typically requires the robot to stop and enter a safe state when communication is lost.

**Fact**: IEC 61508 requires that the safety function degrades to a safe state upon detection of a communication fault. The time to detect the fault (via watchdog timeout) plus the time to reach the safe state must be within the overall safety response time budget.

**Implication for PCP**: PCP must define a comprehensive communication loss recovery protocol:

1. Detection: Heartbeat timeout (watchdog) triggers communication fault
2. Immediate response: All actuation commands are suspended
3. Safe-state transition: All active actuators decelerate to stop
4. Lease release: All held leases are considered forfeited
5. State broadcast: The recovering robot broadcasts its new state (disconnected, safe) to all peers
6. Reconnection: A full re-initialization handshake is required (no partial state recovery)
7. Lease re-acquisition: The robot must re-acquire leases before resuming operation

### Standards Comparison Matrix

| Standard | Scope | Key Protocol Requirement | SIL/PL Target | Applicability to PCP |
|----------|-------|------------------------|---------------|----------------------|
| ISO 10218-1 | Robot safety (manufacturer) | Safe-state on single fault, E-stop, safety-rated control | References IEC 61508/ISO 13849 | High - defines robot-level safety requirements |
| ISO 10218-2 | Robot system safety (integrator) | Communication fault behavior, workspace safety | References IEC 61508/ISO 13849 | High - defines system-level communication requirements |
| ISO/TS 15066 | Collaborative robots | Force/velocity limits, separation monitoring | PL d typically | Medium - if PCP targets collaborative robots |
| IEC 61508 | Functional safety (generic) | SIL classification, PFD/PFH budgets, diagnostic coverage | SIL 1-4 | Critical - foundational standard for safety communication |
| ANSI/RIA R15.06 | US adoption of ISO 10218 | Same as ISO 10218-1/2 | Same | High - for US market compliance |
| IEC 62061 | Safety of machinery | SIL assignment, safety communication requirements | SIL 1-3 | High - machinery safety communication profiles |
| ISO 13849 | Safety of machinery (PL) | Performance Level classification, Category (B, 1, 2, 3, 4) | PL a-e | Medium - alternative to IEC 62061 for lower SIL |
| IEC 61784-3 | Safety communication profiles | Certified communication patterns (PROFIsafe, EtherCAT Safety, etc.) | Per profile | Critical - defines specific communication mechanisms |

### Recommendations Specifically for PCP

1. **Define safety targets explicitly**: Before designing the protocol, specify the target SIL or PL for the communication channel. This drives all other design decisions. For most robotics applications, SIL 2 is a practical target that balances safety with implementation complexity.

2. **Add emergency stop as a first-class protocol feature**: Define an E-stop message type that bypasses the lease requirement, has highest priority, and triggers immediate safe-state transition. This is non-negotiable for compliance with ISO 10218.

3. **Add heartbeat/watchdog protocol**: Define heartbeat intervals and watchdog timeouts for each operational mode. Missing heartbeats must trigger safe-state transition.

4. **Define formal safe states**: Specify the safe state for each robot type, including all actuator states, joint positions, and power states. The protocol must be able to command the transition to safe state and verify it has been achieved.

5. **Add dual-channel validation**: For SIL 2+, safety-critical commands should be validated on two independent channels. The CRDT channel is one; a separate safety channel (potentially using a certified protocol) is the other.

6. **Specify maximum timing bounds**: Define maximum message delivery latency, maximum processing time, and maximum safe-state transition time for each message class and operational mode.

7. **Conduct a failure modes and effects analysis (FMEA)**: Systematically identify all communication failure modes, their effects on safety, and the protocol mechanisms that detect and mitigate each failure mode.

### References

- ISO 10218-1:2011, "Robots and robotic devices -- Safety requirements for industrial robots -- Part 1: Robots."
- ISO 10218-2:2011, "Robots and robotic devices -- Safety requirements for industrial robots -- Part 2: Robot systems and integration."
- ISO/TS 15066:2016, "Robots and robotic devices -- Collaborative robots."
- IEC 61508:2010, "Functional safety of electrical/electronic/programmable electronic safety-related systems."
- ANSI/RIA R15.06-2012, "Industrial Robots and Robot Systems -- Safety Requirements."
- IEC 62061:2021, "Safety of machinery -- Functional safety of safety-related control systems."
- ISO 13849-1:2023, "Safety of machinery -- Safety-related parts of control systems -- Part 1: General principles for design."
- IEC 61784-3:2021, "Industrial communication networks -- Profiles -- Part 3-3: Functional safety fieldbuses -- Additional specifications for CPF 3."
- IEC 60204-1:2016, "Safety of machinery -- Electrical equipment of machines -- Part 1: General requirements."

---

## Section 3 -- Existing Robotics Protocol Architectures

### Executive Summary

This section analyzes how existing robotics protocols solve the coordination, safety, and communication problems that PCP addresses. Each protocol provides valuable lessons: ROS 2 (DDS) demonstrates QoS-driven middleware with lifecycle management; MAVLink shows pragmatic command sequencing with robust failsafe mechanisms; OPC-UA Safety represents the gold standard for certified safety communication; and fieldbus safety protocols (EtherCAT Safety, PROFIsafe) demonstrate how to achieve deterministic safety communication over standard physical layers. The analysis reveals that PCP's architecture draws inspiration from multiple sources but does not fully replicate the safety mechanisms of any single existing protocol. The most significant finding is that PCP's CRDT-based approach is unique among safety-critical robotics protocols -- no existing safety-rated protocol uses CRDTs for safety state management, which should prompt careful justification.

### ROS 2 (Data Distribution Service)

#### Architecture Overview

**Fact**: ROS 2 (Robot Operating System 2) uses the Data Distribution Service (DDS) middleware as its communication backbone. DDS is an OMG standard (DCPS, DDS-XRCE) that provides publish-subscribe communication with configurable Quality of Service (QoS) policies. ROS 2 implements the DDS RMW (ROS Middleware) interface, allowing different DDS implementations (Fast DDS, Cyclone DDS, Connext DDS) to be used interchangeably.

**Fact**: DDS defines QoS policies including Reliability (BestEffort, Reliable), Durability (Volatile, TransientLocal), History (KeepLast, KeepAll), and Deadline (maximum inter-message interval). These policies are configurable per topic (data channel) and enable applications to trade off latency, reliability, and resource usage.

**Fact**: ROS 2 lifecycle nodes implement a state machine with states: Unconfigured, Inactive, Active, and Finalized. Transitions between states are triggered by lifecycle service calls (configure, activate, deactivate, cleanup, shutdown). This provides structured initialization and shutdown behavior.

#### Relevance to PCP

| ROS 2 Feature | PCP Equivalent | Assessment |
|---------------|-----------------|------------|
| DDS QoS policies | (None defined) | PCP should define equivalent QoS: reliability, deadline, and liveliness for each message type |
| Lifecycle nodes | (Partial - init/shutdown) | PCP should adopt lifecycle state machines for robot nodes, including transition validation |
| DDS discovery | Ed25519 identity + TEE attestation | PCP's identity model is stronger than DDS discovery but does not include automatic peer discovery |
| ROS 2 parameters | (None defined) | PCP should define a parameter/configuration mechanism for runtime configuration |
| ROS 2 actions (long-running tasks) | Lease mechanism | PCP's lease is conceptually similar but lacks the goal feedback and cancellation semantics of ROS 2 actions |

#### Safety Extensions

**Fact**: ROS 2 does not include a built-in safety protocol. However, several research and industry efforts have extended ROS 2 with safety features:

- **ROS 2 Safety Extensions** (ROS Industrial Consortium): Proposes safety-rated communication profiles over DDS, including heartbeat monitoring, watchdog timers, and safety-state propagation.

- **SafeROS** (Academic): A research project that wraps ROS 2 communication in safety-enforcing middleware, adding message authentication, integrity checking, and timing guarantees.

**Analysis**: The absence of a standardized safety layer in ROS 2 is a significant limitation for industrial deployment. PCP has an opportunity to fill this gap by defining a safety layer that could potentially integrate with ROS 2's DDS middleware. However, PCP must be careful not to assume ROS 2 as a dependency -- the protocol should be middleware-agnostic.

#### Deterministic Execution

**Fact**: Standard DDS does not guarantee deterministic message delivery. The DDS specification defines maximum latencies only as QoS policies that the application can request, but there is no guarantee that the middleware will meet them. Real-time DDS implementations (e.g., Connext DDS Micro, Fast DDS with real-time configuration) can provide bounded latencies on real-time operating systems, but this requires careful system-level configuration.

**Implication for PCP**: PCP cannot rely on underlying transport determinism. The protocol must implement its own timing guarantees, including application-level watchdogs and timeout handling, regardless of the transport layer's behavior.

### MAVLink

#### Architecture Overview

**Fact**: MAVLink is a lightweight messaging protocol for drones and unmanned vehicles, originally developed for the ArduPilot project. It defines a binary message format with a header (magic byte, payload length, sequence number, system ID, component ID, message ID), payload, and checksum (X.25 CRC-16/CCITT). Messages are defined in XML definition files that generate C, Python, and other language headers.

**Fact**: MAVLink implements a command protocol (COMMAND_LONG and COMMAND_INT message types) with explicit acknowledgements (COMMAND_ACK). Commands include a confirmation flag and a timeout mechanism. The protocol supports command sequencing where commands must be executed in order.

**Fact**: MAVLink defines an arming/disarming mechanism for the vehicle's propulsion system. Arming is a prerequisite for most actuation commands and involves multiple pre-arm safety checks (IMU calibration, GPS lock, geofence compliance, battery level). Disarming can be triggered by various failsafe conditions.

#### Relevance to PCP

MAVLink's design is the closest analog to PCP's actuation pipeline. The arming/disarming paradigm maps directly to PCP's lease concept: the vehicle must be "armed" (hold a lease) before it can execute actuation commands. The pre-arm checks map to PCP's constitution validation.

| MAVLink Feature | PCP Equivalent | Assessment |
|----------------|-----------------|------------|
| Arming/Disarming | Lease Acquisition | PCP should adopt MAVLink's pre-condition checks before lease grant |
| COMMAND_ACK | (Not defined) | PCP MUST define explicit acknowledgements for all safety-critical commands |
| Sequence numbers | (Not defined in CRDT) | PCP should add sequence numbers for actuation commands to detect loss and reordering |
| Failsafe triggers | (Partial - lease TTL) | PCP should define multiple failsafe triggers (heartbeat loss, communication loss, battery low, etc.) |
| Heartbeat messages | (Not defined) | PCP MUST add heartbeat messages as required by safety standards |
| System/Component IDs | Ed25519 identity | PCP's cryptographic identity is stronger but more complex |

#### Failsafe Mechanisms

**Fact**: MAVLink defines multiple failsafe triggers: heartbeat loss (communication timeout), geofence breach, low battery, GPS loss, attitude anomaly, and manual RC signal loss. Each failsafe trigger has a configurable action (land, return to launch, loiter, terminate).

**Analysis**: MAVLink's failsafe design is pragmatic and battle-tested in production unmanned vehicles. PCP should adopt a similar multi-trigger failsafe model. The key lesson is that failsafe triggers should be configurable per deployment (different environments have different risk profiles) but the mechanism for detecting and responding to triggers should be standardized.

### OPC-UA Safety

#### Architecture Overview

**Fact**: OPC-UA Safety (defined in IEC 61784-3-3 and the OPC UA Safety specification by the OPC Foundation) extends the OPC-UA protocol with safety-certified communication mechanisms. It is designed for industrial automation where safety communication must meet SIL 2 or SIL 3 requirements.

**Fact**: OPC-UA Safety achieves safety certification through a combination of mechanisms:

1. **Redundancy**: Safety data is transmitted on two independent communication paths
2. **Sequence numbers**: Each message includes a sequence number and a toggle bit to detect loss, duplication, insertion, and reordering
3. **CRC**: Cyclic Redundancy Check with sufficient bit coverage to detect corruption
4. **Watchdog**: A monitoring timer that detects communication timeout
5. **Safety token**: A shared secret established during connection setup, used to generate a dynamic token that authenticates each message
6. **Time stamping**: Each message includes a timestamp for detecting delay and replay attacks

**Fact**: OPC-UA Safety is a certified communication profile per IEC 61784-3. This means it has been formally verified to achieve specific SIL targets when implemented according to the specification. The certification covers the communication protocol itself, not the entire safety function (which includes sensors, logic, and actuators).

#### Relevance to PCP

OPC-UA Safety represents the most comprehensive approach to safety communication among the protocols analyzed. PCP should study its mechanisms closely:

| OPC-UA Safety Feature | PCP Coverage | Gap |
|----------------------|----------------|-----|
| Dual-channel redundancy | Single CRDT channel | Critical - no independent safety channel |
| Sequence numbers + toggle bit | Not defined | High - cannot detect message loss or reordering |
| CRC with safety bit coverage | Not defined (JSON-RPC does not include CRC) | High - JSON transport does not provide integrity at this level |
| Watchdog with configurable timeout | Not defined | Critical - no heartbeat monitoring |
| Safety token (dynamic authentication) | Ed25519 signatures (static per message) | Medium - PCP has authentication but not a lightweight per-message safety token |
| Timestamping for delay detection | Not defined | Medium - no timing verification |
| Certified SIL rating | Not certified | Critical - no certification path defined |

### Additional Protocols

#### EtherCAT Safety

**Fact**: EtherCAT Safety (defined in IEC 61784-3-12) implements safety communication over the EtherCAT fieldbus. It uses a "Safety over EtherCAT" (FSoE) protocol that adds a safety container to standard EtherCAT frames. The safety container includes a guard value (CRC-based), a watchdog counter, and a status flag.

**Fact**: EtherCAT Safety achieves SIL 3 certification. The protocol is designed for cycle times as low as 1ms, making it suitable for high-speed motion control safety applications.

**Analysis**: EtherCAT Safety's approach of adding a safety container to standard communication frames is analogous to what PCP could do with its JSON-RPC messages. A PCP safety container could include: CRC, sequence number, timestamp, and a safety token. However, PCP's JSON-based format makes binary CRC less natural than in EtherCAT's binary protocol.

#### PROFIsafe

**Fact**: PROFIsafe (defined in IEC 61784-3-3) is a safety layer for PROFIBUS and PROFINET. It uses a similar approach to EtherCAT Safety: a safety container with CRC, sequence number, toggle bit, and watchdog. PROFIsafe achieves SIL 3 certification and is widely deployed in factory automation.

**Fact**: PROFIsafe's "black channel" principle states that the safety protocol should not depend on the underlying communication channel's properties. The safety mechanisms (CRC, sequence numbers, watchdog) must work correctly regardless of whether the underlying channel is PROFIBUS, PROFINET, or even a wireless link. This is achieved by including all safety-relevant information in the safety container.

**Analysis**: The black channel principle is highly relevant to PCP. PCP's transport abstraction should follow this principle: the safety mechanisms (sequence numbers, CRC, watchdog) should be part of the PCP protocol layer, not dependent on specific transport features. This allows PCP to work over any transport (WebSocket, DDS, QUIC, etc.) while maintaining safety guarantees.

#### Eclipse Zenoh

**Fact**: Eclipse Zenoh is a pub/sub/query protocol designed for edge-to-cloud communication in IoT and robotics. It provides a unified communication model that supports local (shared memory), mesh (peer-to-peer), and routed (client-broker) communication. Zenoh supports configurable reliability, congestion control, and compression.

**Analysis**: Zenoh's flexibility makes it an interesting potential transport for PCP. Its support for both pub/sub and query paradigms could map well to PCP's state dissemination (pub/sub for CRDT updates) and command patterns (query/response for lease requests). However, Zenoh does not include built-in safety mechanisms and is not safety-certified.

#### Open-RMF

**Fact**: Open-RMF (Robotics Middleware Framework) is an open-source framework for managing heterogeneous robot fleets. It provides fleet management, traffic management, and task orchestration. Open-RMF is built on ROS 2 and uses DDS for communication.

**Analysis**: Open-RMF addresses a higher level of abstraction than PCP (fleet management vs. protocol design). PCP could potentially be used as the underlying safety-critical communication protocol for an Open-RMF deployment. However, Open-RMF's current architecture does not include the safety mechanisms that PCP provides.

### TEE-Attested Robot Identity

#### Intel SGX

**Fact**: Intel SGX (Software Guard Extensions) provides hardware-isolated enclaves for code execution and data storage. SGX enclaves can generate attestation reports (via the Enhanced Privacy ID, EPID, protocol) that prove the enclave is running on genuine Intel hardware and that the code has not been tampered with.

**Fact**: SGX attestation is a two-step process: local attestation (between enclaves on the same platform) and remote attestation (between an enclave and a remote verifier). Remote attestation requires an Intel-provided attestation service (IAS or the newer Data Center Attestation Primitives, DCAP).

**Analysis**: SGX's attestation model is relevant to PCP's TEE attestation layer. However, SGX has known limitations: side-channel attacks (Spectre, Meltdown, and SGX-specific attacks like Foreshadow), limited enclave memory (typically 128MB), and vendor lock-in to Intel platforms.

**Implication for PCP**: PCP should support multiple TEE platforms (SGX, SEV, TrustZone) rather than being tied to a single vendor. The attestation protocol should be abstract enough to accommodate different TEE mechanisms while providing equivalent security guarantees.

#### AMD SEV

**Fact**: AMD SEV (Secure Encrypted Virtualization) encrypts VM memory with a key managed by the AMD Secure Processor. SEV-SNP (Secure Nested Paging) adds integrity protection, preventing the hypervisor from modifying VM memory. SEV attestation uses the AMD Attestation Service to verify that a VM is running on genuine AMD hardware.

**Analysis**: SEV-SNP provides a different security model than SGX: VM-level isolation vs. enclave-level isolation. SEV-SNP is more appropriate for robots that run entire VMs, while SGX is more appropriate for robots that run unmodified OSes with isolated security-critical code.

#### ARM TrustZone

**Fact**: ARM TrustZone provides a hardware-based Trusted Execution Environment that partitions the system into a Secure world and a Normal world. The Secure world runs a Trusted OS (e.g., OP-TEE) that handles sensitive operations. TrustZone is widely deployed in mobile devices and is increasingly used in embedded and robotics applications.

**Fact**: TrustZone attestation can be performed using the ARM Root of Trust for Measurement (ROM) and the Trusted Firmware for Measured Boot (TF-M). The attestation evidence includes measurements of the secure firmware and applications.

#### TPM and DICE

**Fact**: A Trusted Platform Module (TPM) is a hardware security module that provides secure storage, key generation, and platform attestation. TPM 2.0 (specified in ISO/IEC 11889) supports multiple attestation mechanisms and is widely deployed in enterprise systems.

**Fact**: DICE (Device Identifier Composition Engine, specified in the TCG DICE specification) is a lightweight hardware root of trust that generates compound device identities from the hardware and firmware measurements. DICE is designed for embedded and IoT devices and is lighter weight than a full TPM.

**Analysis**: For robotics, DICE is likely the most practical hardware root of trust. It is lightweight, does not require a dedicated security chip, and can be integrated into the robot's boot process. PCP's Ed25519 identity should be derived from a DICE-generated key pair, binding the cryptographic identity to the hardware and firmware state.

### Protocol Feature Comparison Matrix

| Feature | PCP | ROS 2/DDS | MAVLink | OPC-UA Safety | PROFIsafe | EtherCAT Safety |
|---------|-------|-----------|---------|---------------|-----------|----------------|
| Transport | JSON-RPC (planned) | DDS (TCP/UDP) | Serial/UDP | OPC-UA (TCP) | PROFINET/PROFIBUS | EtherCAT |
| Identity | Ed25519 + TEE | DDS participant | System/Component ID | X.509 certificate | Device ID | Device ID |
| Auth | Cryptographic sigs | (None) | (None) | X.509 + safety token | Safety container CRC | Safety container CRC |
| Safety cert | No | No | No | SIL 2-3 | SIL 3 | SIL 3 |
| Deterministic | No | Configurable | Yes (simple) | Yes | Yes | Yes (1ms) |
| Heartbeat | No | DDS liveliness | Yes | Yes | Yes | Yes |
| E-stop | No | No | Yes (via command) | Yes | Yes | Yes |
| Redundancy | CRDT replicas | (Optional) | (No) | Dual-channel | Dual-channel | Dual-channel |
| State mgmt | CRDT | (None) | (None) | (None) | (None) | (None) |
| Failsafe | Lease TTL | (None) | Multi-trigger | Watchdog | Watchdog | Watchdog |
| Lease/Arming | Yes | No | Yes (arming) | No | No | No |
| Physics validation | HNN (planned) | (None) | (None) | (None) | (None) | (None) |
| Formal spec | No | No | No | Partial | Yes | Yes |

### Recommendations Specifically for PCP

1. **Adopt MAVLink's acknowledgement model**: Every safety-critical command MUST receive an explicit acknowledgement. The acknowledgement should include the command's result (accepted, rejected, timeout) and a reference to the original command (sequence number or idempotency key).

2. **Adopt PROFIsafe's black channel principle**: All safety mechanisms should be part of the PCP protocol layer, not dependent on specific transport features. This enables PCP to work over any transport while maintaining safety guarantees.

3. **Study OPC-UA Safety's dual-channel approach**: While full dual-channel redundancy may be overkill for initial PCP deployments, the protocol should be designed to support it. The safety container concept (CRC, sequence number, watchdog, safety token) should be defined as a protocol-level feature that can operate over any transport.

4. **Add heartbeat and watchdog mechanisms**: These are non-negotiable for safety-rated communication. The heartbeat protocol should be lightweight (small messages at regular intervals) and the watchdog should trigger safe-state transition on timeout.

5. **Support multi-vendor TEE attestation**: PCP should abstract the TEE attestation to support SGX, SEV, TrustZone, TPM, and DICE. The attestation protocol should verify: hardware authenticity, firmware integrity, and code identity.

### References

- OMG, "Data Distribution Service (DDS) Version 1.4," Object Management Group, 2015.
- Open Robotics, "ROS 2 Design Documentation," ros.org.
- MAVLink Consortium, "MAVLink Developer Guide," mavlink.io.
- OP Foundation, "OPC UA Safety Specification," opcfoundation.org.
- IEC 61784-3:2021, "Industrial communication networks -- Profiles."
- Beckhoff Automation, "EtherCAT Safety over EtherCAT (FSoE) Technical Description."
- PROFIBUS International, "PROFIsafe Technology Overview."
- Eclipse Foundation, "Eclipse Zenoh Documentation," zenoh.io.
- Open Robotics, "Open-RMF Documentation," open-rmf.org.
- Intel, "Intel SGX Attestation Service Documentation."
- AMD, "AMD SEV-SNP Architecture Reference.
- ARM, "TrustZone Security Whitepaper."
- TCG, "DICE Layer Specification," trustedcomputinggroup.org.
- ISO/IEC 11889:2015, "Trusted Platform Module."

---

## Section 4 -- Schema-First Protocol Design

### Executive Summary

Schema-first protocol design is the practice of defining the canonical data model using a formal schema language before writing any implementation code. This approach ensures type safety, enables automated code generation, and provides a single source of truth for the protocol's wire format. This section analyzes the available schema technologies, serialization formats, and tooling ecosystems, and provides specific recommendations for PCP's schema strategy.

### Fundamental Concepts

**Fact**: JSON Schema Draft 2020-12 (RFC 8927 in draft form, published as a standalone specification) is the latest version of the JSON Schema specification. It supports keywords for type validation (`type`), structure validation (`properties`, `required`, `additionalProperties`), string validation (`pattern`, `minLength`, `maxLength`), numeric validation (`minimum`, `maximum`, `exclusiveMinimum`), array validation (`items`, `minItems`, `maxItems`, `uniqueItems`), and composition (`allOf`, `anyOf`, `oneOf`, `not`).

**Fact**: JSON Schema supports `$id` and `$defs` for schema identification and definition reuse, `$ref` for inter-schema references, and `$dynamicRef` and `$dynamicAnchor` for recursive and extensible schemas.

**Fact**: OpenAPI 3.1 (OAS 3.1) is fully aligned with JSON Schema Draft 2020-12, using it as the schema description format for request and response bodies. OpenAPI adds API-specific metadata (paths, operations, parameters, security requirements) on top of the JSON Schema foundation.

**Fact**: AsyncAPI 2.6 provides an OpenAPI-like specification for asynchronous message-driven APIs. It is particularly relevant to PCP because robot communication is inherently event-driven (state updates, command responses, heartbeat messages).

### Serialization Format Comparison

| Format | Schema | Wire Format | Code Gen | Human Readable | Verbose | Zero-Copy | Ecosystem |
|--------|--------|-------------|----------|---------------|---------|-----------|----------|
| JSON Schema | JSON Schema 2020-12 | JSON | Excellent | Yes | High | No | Very large |
| Protocol Buffers | .proto | Binary | Excellent | Moderate | Low | Yes (partial) | Large |
| FlatBuffers | .fbs | Binary | Good | Poor | Low | Yes (full) | Medium |
| Cap'n Proto | .capnp | Binary | Good | Poor | Very low | Yes (full) | Medium |
| CBOR + CDDL | CDDL | Binary | Good | Poor | Low | No | Small |
| MessagePack | (None standard) | Binary | Limited | No | Low | No | Small |

**Analysis**: For PCP, JSON Schema with JSON wire format is the correct choice for the application protocol layer (JSON-RPC messages). The reasons are:

1. **Debuggability**: Safety-critical systems require extensive logging and debugging. JSON is human-readable, which is essential for post-incident analysis and regulatory review.

2. **Interoperability**: JSON is supported by virtually every programming language and platform, reducing integration barriers.

3. **Tooling maturity**: JSON Schema validation (AJV), code generation (quicktype, datamodel-code-generator), and documentation generation are mature and well-maintained.

4. **Compatibility with MCP**: Since PCP is inspired by MCP, using the same schema format (JSON Schema) facilitates cross-referencing and potential future interoperability.

However, PCP should consider a binary serialization format for high-frequency messages (CRDT state updates, heartbeat messages, physics simulation data). Protocol Buffers or FlatBuffers would be appropriate for these messages. The protocol should define a content-type mechanism that allows different serialization formats for different message types.

### Semantic Versioning for Schemas

**Fact**: SemVer 2.0.0 (semanticversioning.org) defines version numbers as MAJOR.MINOR.PATCH. MAJOR version changes indicate incompatible API changes, MINOR version changes add backward-compatible functionality, and PATCH version changes are backward-compatible bug fixes.

**Fact**: For JSON Schema, the backward compatibility rules are:

- **PATCH**: Add `description` or `title` changes, fix `pattern` errors, add `default` values. No wire format changes.
- **MINOR**: Add new optional properties (with `additionalProperties` remaining open or `true`), add new enum values (if existing implementations ignore unknown values), add new `oneOf`/`anyOf` branches, relax constraints (increase `maxLength`, decrease `minLength`). Existing valid documents remain valid.
- **MAJOR**: Remove or rename properties, change property types, add new required properties, tighten constraints (decrease `maxLength`, increase `minLength`), remove enum values.

**Recommendation for PCP**: Adopt these semantic versioning rules for the PCP schema. Enforce them through automated CI/CD checks that compare the new schema against the previous version and verify that only PATCH or MINOR changes are made within a major version.

### Schema Organization

**Recommendation**: PCP should organize its schema following Anthropic MCP's pattern, with some modifications:

```
ppcp-schema/
  src/
    schema.ts          # Canonical TypeScript schema (single source of truth)
    index.ts            # Exports
  generated/
    schema.json         # Generated JSON Schema (from schema.ts)
    typescript/         # Generated TypeScript types
    python/             # Generated Python types (pydantic models)
    rust/               # Generated Rust types
    go/                 # Generated Go types
    java/               # Generated Java types
    csharp/             # Generated C# types
  tests/
    conformance/        # Schema conformance tests
    compatibility/      # Wire compatibility tests
    examples/           # Example messages for documentation
  docs/
    specification.md    # Human-readable specification
    migration-guide.md  # Version migration guide
```

The `schema.ts` file is the single source of truth. All other artifacts (JSON Schema, language-specific types, documentation) are generated from it. This is the same approach used by Anthropic MCP and ensures consistency across all outputs.

### Tooling Recommendations

#### Validation

| Tool | Language | Purpose | Maturity |
|------|----------|---------|----------|
| AJV | JavaScript/TypeScript | Runtime JSON Schema validation | Production-ready, most widely used |
| zod | TypeScript | Schema definition + validation (not JSON Schema, but complementary) | Production-ready, excellent DX |
| valibot | TypeScript | Schema definition + validation (zod alternative, smaller bundle) | Production-ready |
| pydantic | Python | Schema definition + validation, JSON Schema generation | Production-ready, most popular Python option |
| jsonschema (Python) | Python | JSON Schema validation | Production-ready |
| quicktype | CLI | Schema inference from JSON, cross-language code generation | Production-ready |

**Recommendation for PCP**:

- **Runtime validation**: AJV for TypeScript/JavaScript implementations, pydantic for Python implementations
- **Schema definition**: Define schemas in JSON Schema Draft 2020-12 directly (not generated from code). This ensures the JSON Schema is the canonical source of truth.
- **Code generation**: quicktype for generating SDK types from the canonical JSON Schema. quicktype supports TypeScript, Python, Rust, Go, Java, C#, and more.
- **Conformance testing**: AJV for testing that generated messages conform to the schema

#### Code Generation Pipeline

```
Canonical JSON Schema (schema.json)
  |
  +-- quicktype --> TypeScript types
  +-- quicktype --> Python pydantic models
  +-- quicktype --> Rust structs
  +-- quicktype --> Go structs
  +-- quicktype --> Java classes
  +-- quicktype --> C# classes
  +-- AJV --> Runtime validation modules
```

#### Conformance Testing Strategy

**Recommendation**: PCP should implement a three-level conformance testing strategy:

1. **Schema validation tests**: Verify that all generated messages conform to the JSON Schema. These tests use AJV (or equivalent) to validate example messages against the schema. Run on every commit.

2. **Wire compatibility tests**: Capture actual wire messages from reference implementations and verify they match the expected format. These tests ensure that different implementations produce wire-compatible messages. Run on every pull request.

3. **Interoperability tests**: Run two independent implementations against each other and verify they can communicate successfully. These tests are the gold standard for protocol conformance but are more expensive to run. Run nightly or before release.

### Extension Fields and Discriminated Unions

**Fact**: JSON Schema's `discriminator` keyword (supported in OpenAPI 3.x and some JSON Schema implementations) enables discriminated union types, where a specific property's value determines which schema variant applies.

**Recommendation for PCP**: PCP should use discriminated unions extensively for command and response types. For example:

```json
{
  "oneOf": [
    { "$ref": "#/defs/LeaseRequest" },
    { "$ref": "#/defs/ActuationCommand" },
    { "$ref": "#/defs/EmergencyStop" },
    { "$ref": "#/defs/Heartbeat" }
  ],
  "discriminator": { "propertyName": "type" }
}
```

This enables efficient dispatch and validation: the receiver reads the `type` field first, then validates against the specific schema variant. This is both safer (no ambiguity) and faster (no need to try all `oneOf` branches).

### Recommendations Specifically for PCP

1. **Use JSON Schema Draft 2020-12 as the canonical schema format**: It is well-specified, widely supported, and aligned with OpenAPI 3.1 and MCP's approach.

2. **Maintain a single canonical schema file** (`schema.json` or `schema.ts` that generates `schema.json`): All other artifacts are derived from this file.

3. **Adopt semantic versioning with automated compatibility checking**: Enforce compatibility rules in CI/CD.

4. **Use quicktype for multi-language SDK generation**: It supports all the target languages and produces idiomatic types.

5. **Use AJV for runtime validation in TypeScript implementations**: It is the most performant and widely-used JSON Schema validator.

6. **Define a content-type mechanism**: Allow different serialization formats (JSON, protobuf, CBOR) for different message types, with JSON as the default and mandatory-to-support format.

7. **Implement the three-level conformance testing strategy**: Schema validation, wire compatibility, and interoperability tests.

### References

- JSON Schema Draft 2020-12 Specification. <https://json-schema.org/draft/2020-12/json-schema-validation.html>
- OpenAPI 3.1.0 Specification. <https://spec.openapis.org/oas/v3.1.0>
- AsyncAPI 2.6 Specification. <https://www.asyncapi.com/docs/reference/specification/v2.6>
- SemVer 2.0.0. <https://semver.org/>
- AJV Documentation. <https://ajv.js.org/>
- quicktype Documentation. <https://quicktype.io/>
- Protocol Buffers Documentation. <https://protobuf.dev/>
- FlatBuffers Documentation. <https://google.github.io/flatbuffers/>
- Cap'n Proto Documentation. <https://capnproto.org/>
- pydantic Documentation. <https://docs.pydantic.dev/>
- zod Documentation. <https://zod.dev/>

---

## Section 5 -- CRDTs in Safety-Critical Systems

### Executive Summary

Conflict-free Replicated Data Types (CRDTs) are data structures designed for distributed systems that guarantee eventual consistency without coordination. While CRDTs are excellent for non-safety-critical state dissemination (sensor readings, robot status, configuration data), their fundamental assumptions -- eventual consistency, conflict resolution through commutativity, and convergence without consensus -- are at odds with the strong consistency, bounded latency, and deterministic behavior required for safety-critical physical actuation. This section analyzes whether CRDTs are appropriate when physical safety depends on convergence, identifies specific timing hazards and failure modes, and recommends a hybrid approach that uses CRDTs for non-safety-critical state combined with consensus for safety-critical transitions.

### Fundamental Concepts

**Fact**: CRDTs come in two primary flavors:

- **State-based CRDTs (CvRDTs)**: Replicas exchange their full state (or state deltas) and merge using a least-upper-bound (LUB) or join operation. The merge operation must be commutative, associative, and idempotent. Examples: G-Counter, LWW-Register, OR-Set.

- **Operation-based CRDTs (CmRDTs)**: Replicas broadcast operations to all other replicas. Operations must be commutative (so they can be delivered in any order) and must be delivered exactly-once to all replicas. Examples: G-Counter (op-based), LWW-Register (op-based).

- **Delta-state CRDTs (Delta-CRDTs)**: A hybrid that sends only the state delta (difference) rather than the full state, reducing bandwidth while maintaining the convergence properties of state-based CRDTs.

**Fact**: CRDTs guarantee **eventual consistency**: if all replicas receive the same set of updates (no permanent network partition), they will eventually converge to the same state. The time to converge depends on network latency, message frequency, and the specific CRDT implementation.

**Fact**: CRDTs do **not** guarantee **strong consistency**: at any point before convergence, different replicas may have different views of the state. This is the fundamental tension with safety-critical systems, which often require that all parties agree on the current state before taking physical action.

### CRDT Usage in Real-Time and Safety-Critical Systems

#### Academic Research

**Fact**: There is limited academic research on CRDTs in safety-critical systems. Most CRDT research focuses on collaborative editing (text documents, structured data), distributed databases, and mobile/edge computing. The following are the most relevant academic works:

1. **Shapiro et al. (2011a)**, "Conflict-free Replicated Data Types," SSS 2011: The foundational paper on CRDTs. Discusses convergence guarantees but does not address safety-critical applications or timing requirements.

2. **Almeida et al. (2018)**, "Delta State Replicated Data Types," JPDC: Introduces delta-state CRDTs that reduce bandwidth overhead. Discusses convergence time but does not address bounded convergence time for safety-critical applications.

3. **Gomes et al. (2017)**, "Making Operation-Based CRDTs Conflict-Free," Programming Journal: Discusses methods for ensuring operation commutativity but does not address real-time constraints.

**Opinion**: The academic literature on CRDTs has not seriously addressed their applicability to safety-critical physical systems. The research community's focus has been on correctness (convergence, conflict resolution) rather than timing (bounded latency, real-time constraints). This gap in the literature is itself a cautionary signal for PCP's use of CRDTs.

#### Production Implementations

**Fact**: CRDTs are used in production systems including:

- **Amazon DynamoDB** (partially): Uses some CRDT-inspired techniques for conflict resolution in multi-master replication, but does not implement full CRDTs.

- **Apple Notes, Reminders, Contacts**: Use CRDTs for synchronization across Apple devices. These are not safety-critical applications.

- **Redis CRDT**: An open-source CRDT extension for Redis that provides CRDT-based data structures for multi-master replication. Not safety-rated.

- **Riak**: A distributed database that used CRDTs for conflict-free data types (counters, sets, maps, flags, registers). Riak is not designed for real-time or safety-critical applications.

- **Automerge**: A CRDT library for collaborative editing, used in products like Notion and Figma. Not safety-critical.

**Fact**: No known production system uses CRDTs for safety-critical physical actuation. The closest analog is distributed databases that use CRDTs for data consistency, but these systems tolerate eventual consistency and do not control physical actuators.

### Specific Timing Hazards

#### Convergence Latency

**Fact**: The convergence time of a CRDT depends on the network latency between replicas. In a system with N replicas connected by a network with maximum latency L, the worst-case convergence time is (N-1) * L for state-based CRDTs (because state changes must propagate through all replicas). For operation-based CRDTs, the worst-case convergence time is L (assuming reliable broadcast).

**Implication for PCP**: If PCP uses CRDTs for lease state, a robot might read a stale CRDT state and believe a resource is available when another robot has already acquired the lease (but the update hasn't propagated yet). This could lead to two robots attempting to actuate the same resource simultaneously.

**Severity**: This is a **critical safety hazard**. Two robots acting on the same physical resource could cause collisions, equipment damage, or personnel injury.

#### Split Brain

**Fact**: In a network partition, CRDT replicas on different sides of the partition continue to accept updates independently. When the partition heals, the CRDT merge operation resolves conflicts. However, during the partition, each side may have made decisions based on its local state that are inconsistent with the other side's decisions.

**Implication for PCP**: If PCP uses CRDTs for lease management, a network partition could allow two robots on different sides of the partition to acquire the same lease independently. The CRDT would resolve the conflict when the partition heals, but by then, physical damage may have already occurred.

**Severity**: This is a **critical safety hazard**. The entire purpose of the lease mechanism is to prevent simultaneous access to shared resources. CRDTs cannot guarantee this during network partitions.

#### Race Conditions in Lease Acquisition

**Fact**: CRDTs resolve conflicts through deterministic rules (e.g., last-writer-wins based on timestamps, or remove-wins for sets). These rules are designed for data convergence, not for mutual exclusion.

**Implication for PCP**: If two robots simultaneously attempt to acquire a lease using CRDT-based state, the CRDT's conflict resolution rule might grant the lease to both (if the resolution rule is based on local timestamps that appear concurrent) or grant it to one and silently discard the other (if using last-writer-wins). In either case, the losing robot may not be notified that its lease request was denied.

**Severity**: This is a **critical safety hazard**. Lease acquisition must be an atomic operation with a definitive result (granted or denied). CRDTs do not provide atomic operations.

### Hybrid Approaches: CRDTs + Consensus

Given the fundamental incompatibility of pure CRDTs with safety-critical mutual exclusion, the recommended approach is a hybrid architecture:

1. **Consensus (Raft) for safety-critical state**: Use a Raft consensus group for lease management, actuation permission grants, and any other state where strong consistency is required. Raft provides:
   - Strong consistency: All replicas agree on the current state
   - Linearizability: Each operation appears to take effect atomically at a single point in time
   - Leader election: A single leader makes decisions, eliminating split-brain
   - Bounded latency: Commit latency is bounded by the network round-trip time

2. **CRDTs for non-safety-critical state**: Use CRDTs for sensor data dissemination, robot status, telemetry, configuration data, and other state where eventual consistency is acceptable. This provides the benefits of CRDTs (low latency, high availability, no coordination overhead) without the safety risks.

**Fact**: This hybrid approach is well-established in distributed systems. CockroachDB uses Raft for transactional metadata and a custom replication scheme for data. etcd uses Raft for all state but is designed for configuration data, not real-time control. The pattern of "consensus for critical metadata, replication for data" is a standard architectural pattern.

**Fact**: The Raft consensus protocol (Ongaro and Ousterhout, 2014) is well-understood, has multiple production implementations (etcd, HashiCorp Raft, TiKV), and provides the strong consistency guarantees needed for safety-critical state.

#### Escrow CRDTs

**Fact**: Escrow CRDTs (recently proposed by researchers including B. L. Ongaro's group and others) are a variant that supports operations that can be denied if they would violate a constraint (e.g., allocating from a shared pool where the total allocation cannot exceed the pool size). Escrow CRDTs provide a form of distributed mutual exclusion without consensus, but with a caveat: they guarantee safety (no over-allocation) only when the network delivers messages reliably and in order.

**Analysis**: Escrow CRDTs are an interesting theoretical option for PCP's lease management. However, they are not widely implemented, do not have the same battle-tested production pedigree as Raft, and still face the convergence latency and split-brain issues described above. They should be considered for future research but not relied upon for the initial PCP implementation.

### Known Failures and Cautionary Guidance

1. **CockroachDB's early CRDT usage**: CockroachDB initially used CRDT-inspired conflict resolution for some operations but moved to stronger consistency models (serializable transactions with Raft-based replication) because the CRDT approach led to unexpected behavior for users who expected strong consistency.

2. **Riak's retirement**: Riak, the most prominent CRDT-based production database, was effectively retired (end of life by Basho Technologies in 2020). While many factors contributed to this, the difficulty of building applications on top of eventually-consistent data was a significant factor.

3. **Academic cautions**: Several papers have noted that CRDTs' convergence guarantees come at the cost of weaker consistency semantics. Kleppmann and Beresford (2017) noted that CRDT-based systems can violate application-level invariants during the convergence period.

### Recommendations Specifically for PCP

1. **Do NOT use CRDTs for safety-critical state**: Lease management, actuation permissions, and any state that gates physical motion must be managed by a consensus protocol (Raft) that provides strong consistency and linearizability.

2. **Use CRDTs for non-safety-critical state**: Sensor data, robot status, telemetry, and configuration data can use CRDTs. This provides low-latency dissemination and high availability.

3. **Define a clear boundary between CRDT state and consensus state**: The protocol specification must explicitly state which data structures use CRDTs and which use consensus. Implementations must enforce this separation.

4. **Add timing bounds to CRDT convergence**: Even for non-safety-critical state, define a maximum convergence time. If state has not converged within this time, trigger a diagnostic alert.

5. **Implement a partition detection mechanism**: The protocol should detect network partitions and degrade gracefully. During a partition, safety-critical operations should be suspended or restricted.

6. **Conduct formal verification of the hybrid architecture**: Use TLA+ to model the interaction between the CRDT and consensus layers and verify that safety properties are maintained under all failure scenarios.

### References

- Shapiro, M., Preguica, N., Baquero, C., and Zawirski, M. (2011). "A comprehensive study of Convergent and Commutative Replicated Data Types." INRIA Research Report RR-7506.
- Almeida, P.S., Shoker, A., and Baquero, C. (2018). "Delta State Replicated Data Types." Journal of Parallel and Distributed Computing, 111, 162-173.
- Ongaro, D. and Ousterhout, J. (2014). "In Search of an Understandable Consensus Algorithm." USENIX ATC 2014.
- Kleppmann, M. and Beresford, A.R. (2017). "A Conflict-Free Replicated JSON Datatype." IEEE Transactions on Parallel and Distributed Systems, 28(10), 2733-2746.
- Gomes, V.B., Kleppmann, M., and Beresford, A.R. (2017). "Making Operation-Based CRDTs Conflict-Free." Programming Journal, 1(2), 8.
- B. L. Ongaro et al., various papers on Escrow CRDTs and distributed allocation.
- Howard, H., Malkhi, D., and Spiegelman, A. (2020). "Flexible Paxos: Quorum Intersection Revisited." OSDI 2020.

---

## Section 6 -- Formal Specification Methods

### Executive Summary

Formal specification methods provide mathematically rigorous descriptions of system behavior that can be verified by automated tools. For a safety-critical protocol like PCP, formal specification is not a luxury -- it is a necessity. Industrial safety standards (IEC 61508) recommend or require formal methods for higher SIL levels, and the complexity of distributed coordination protocols makes informal reasoning about correctness unreliable. This section evaluates the available formal methods (TLA+, Alloy, Petri Nets, Statecharts, Event-B, and others) and recommends a combination of TLA+ for protocol-level verification and state machine diagrams for human-readable specification.

### TLA+

#### Overview

**Fact**: TLA+ (Temporal Logic of Actions) is a formal specification language developed by Leslie Lamport. It is designed for specifying and verifying concurrent and distributed systems. TLA+ specifications describe the set of all possible behaviors of a system, and the TLC model checker can exhaustively explore these behaviors to verify invariants and properties.

**Fact**: TLA+ has been used to verify production systems at Amazon (AWS DynamoDB, S3, EBS, Aurora), Microsoft (Azure Cosmos DB), and Intel (cache coherence protocols). Amazon has reported that TLA+ model checking found subtle bugs in DynamoDB that were missed by testing and code review.

**Fact**: PlusCal is an algorithmic language that translates to TLA+. PlusCal provides a more familiar pseudocode-like syntax while retaining the full power of TLA+ for model checking. It is particularly useful for specifying protocol state machines.

#### Strengths for PCP

- **Concurrency modeling**: TLA+ naturally models concurrent processes, interleaving, and timing properties. This is essential for verifying PCP's distributed coordination.
- **Model checking**: The TLC model checker can exhaustively explore all possible interleavings for small model sizes. This can find subtle race conditions and timing-dependent bugs.
- **Temporal logic properties**: TLA+ can express both safety properties ("bad things never happen") and liveness properties ("good things eventually happen").
- **Proven in production**: Amazon's extensive use of TLA+ for distributed systems provides confidence in the tooling and methodology.

#### Limitations

- **Learning curve**: TLA+ requires mathematical maturity and is not immediately accessible to engineers without formal methods training.
- **Scalability**: Model checking is limited to small model sizes (typically up to 10<super>6</super> to 10<super>8</super> states). Large systems require abstraction.
- **No code generation**: TLA+ specifications cannot be directly compiled to executable code. They serve as a reference that implementations must follow.

### Alloy

**Fact**: Alloy is a formal specification language based on relational logic. It is designed for analyzing structural properties of software systems. The Alloy Analyzer performs bounded verification by exploring all possible instances within a specified scope.

**Analysis**: Alloy is well-suited for analyzing PCP's data model and schema constraints (e.g., "every lease has exactly one holder," "no resource can have two active leases"). However, Alloy is less suited for specifying temporal behavior (state transitions over time) compared to TLA+. Alloy is recommended as a complementary tool for schema-level verification.

### Petri Nets

**Fact**: Petri nets are a mathematical modeling language for describing distributed systems. They use places (conditions), transitions (events), and tokens (state) to model concurrent and asynchronous behavior. Colored Petri nets (CPN) extend the basic model with data types and hierarchical modules.

**Fact**: Petri nets are widely used in manufacturing automation and process control for modeling workflow and verifying safety properties. Tools like CPN Tools and TINA provide simulation and analysis capabilities.

**Analysis**: Petri nets are a natural fit for modeling PCP's state machine (lease states, robot states, protocol phases). They are particularly good at modeling concurrent activities (multiple robots operating simultaneously) and resource contention (competing lease requests). However, Petri nets become unwieldy for complex protocol logic with many message types and conditional transitions.

### Statecharts and UML State Machines

**Fact**: Statecharts (Harel, 1987) extend finite state machines with hierarchy, concurrency, and history mechanisms. UML state machines are based on Statecharts and are widely used in software engineering.

**Fact**: SCXML (State Chart XML, W3C Recommendation) is an XML-based representation of state machines that can be executed by SCXML interpreters. SCXML is used in voice applications (VoiceXML), dialog management, and embedded systems.

**Analysis**: Statecharts are the most human-readable formal method for specifying protocol state machines. They are well-suited for documenting PCP's protocol lifecycle, robot state machines, and lease state transitions. SCXML can serve as an executable specification that implementations can directly use or translate to their target language.

### Event-B

**Fact**: Event-B is a formal method for system-level modeling and analysis. It uses refinement to incrementally develop a system from an abstract specification to a concrete implementation. Event-B is supported by the Rodin platform, which provides automated proof and model checking.

**Analysis**: Event-B's refinement approach is well-suited for developing PCP incrementally: start with an abstract safety property, refine it to a more concrete protocol, and prove that each refinement preserves the safety property. However, Event-B has a steep learning curve and limited tooling compared to TLA+.

### Comparison of Formal Methods

| Method | Best For | Human Readability | Machine Verification | Automated Testing | Protocol Conformance | Implementation Portability | Learning Curve |
|--------|----------|-------------------|---------------------|-------------------|---------------------|--------------------------|----------------|
| TLA+ | Protocol correctness, concurrency | Medium | Excellent (TLC) | Good | Good | Medium (reference spec) | Steep |
| PlusCal | Protocol algorithms | Good | Excellent (via TLA+) | Good | Good | Medium | Moderate |
| Alloy | Data model, schema constraints | Good | Good (Alloy Analyzer) | Limited | Limited | Low | Moderate |
| Petri Nets | Concurrency, workflow | Medium | Good (CPN Tools) | Limited | Medium | Low | Moderate |
| Statecharts/SCXML | State machines, lifecycle | Excellent | Good (SCXML exec) | Excellent | Excellent | High | Low |
| Event-B | Refinement-based development | Low | Excellent (Rodin) | Limited | Good | Low | Steep |

### Recommended Approach for PCP

The recommended formal specification approach for PCP uses a layered strategy:

1. **TLA+ for protocol invariants and properties**: Specify the core protocol invariants (mutual exclusion, safe-state reachability, lease validity) and verify them using the TLC model checker. This provides the highest level of assurance for safety-critical properties.

2. **SCXML for executable state machines**: Define the protocol lifecycle, robot state machines, and lease state transitions as SCXML documents. These serve as both human-readable documentation and executable specifications that can be directly used by implementations.

3. **Alloy for schema-level verification**: Use Alloy to verify data model constraints (e.g., every lease references a valid resource, every robot has a unique identity) and catch schema-level design errors.

### Specifying Protocol Invariants in TLA+

PCP should specify the following invariants in TLA+:

```
INVARIANT MutualExclusion:
  forall r in Resources:
    Len({l in Leases : l.resource = r /
                   l.status = "active"}) <= 1

INVARIANT NoActuationWithoutLease:
  forall a in Actuations:
    exists l in Leases :
      l.id = a.lease_id /
      l.status = "active" /
      l.robot = a.robot

INVARIANT EmergencyStopOverrides:
  forall e in EmergencyStops:
    e.processed = TRUE =>
      exists a in Actuations :
        a.robot = e.target_robot /
        a.status = "aborted"
```

### Specifying Safety and Liveness Properties

**Safety properties** (bad things never happen):

```
PROPERTY NoSimultaneousLeaseHolders:
  [](forall r in Resources:
    Len({l in Leases : l.resource = r /
                   l.status = "active"}) <= 1)

PROPERTY NoActuationDuringEmergencyStop:
  [](exists e in EmergencyStops:
    e.active =>
    forall a in Actuations:
      a.robot = e.target => a.status != "executing")
```

**Liveness properties** (good things eventually happen):

```
PROPERTY LeaseRequestResponse:
  [](forall req in LeaseRequests:
    req.status = "pending" =>
    <> (req.status = "granted" \/
        req.status = "denied"))

PROPERTY EmergencyStopProcessed:
  [](forall e in EmergencyStops:
    e.issued =>
    <> e.processed)
```

### Recommended Formal Specification Approach Summary

| Aspect | Recommended Method | Rationale |
|--------|-------------------|----------|
| Protocol invariants | TLA+ | Mathematical precision, model checking, proven in production |
| Safety properties | TLA+ (temporal logic) | Expresses "never" and "always" properties naturally |
| Liveness properties | TLA+ (temporal logic) | Expresses "eventually" properties with fairness assumptions |
| State transitions | SCXML | Executable, human-readable, industry-standard |
| Forbidden transitions | TLA+ + SCXML | TLA+ for proof, SCXML for documentation |
| Timing constraints | TLA+ with real-time extensions or UPPAAL | Real-time model checking for timing bounds |
| Data model constraints | Alloy | Relational logic is natural for schema constraints |
| Conformance testing | SCXML test generation + TLA+ test vectors | Executable specs + model-derived test cases |

### References

- Lamport, L. (2002). "Specifying Systems: The TLA+ Language and Tools for Hardware and Software Engineers." Addison-Wesley.
- Lamport, L. (2019). "The TLA+ Video Course." <https://lamport.azurewebsites.net/tla/tla.html>
- Newcombe, C. et al. (2014). "Formal Methods in Practice at Amazon Web Services." GITHUB/AMZN.
- Harel, D. (1987). "Statecharts: A Visual Formalism for Complex Systems." Science of Computer Programming, 8(3), 231-274.
- Jackson, D. (2012). "Software Abstractions: Logic, Language, and Analysis." MIT Press. (Alloy)
- Jensen, K. and Kristensen, L.M. (2009). "Coloured Petri Nets -- Modelling and Validation of Concurrent Systems." Springer.
- Abrial, J.-R. (2010). "Modeling in Event-B: System and Software Engineering." Cambridge University Press.
- W3C, "State Chart XML (SCXML): State Machine Notation for Control Abstraction." W3C Recommendation.

---

## Cross-Cutting Analysis

### Recurring Architectural Patterns

Across all six research domains, several architectural patterns recur consistently in well-designed safety-critical systems:

1. **Defense in depth**: No single mechanism is trusted to ensure safety. Multiple independent layers (hardware interlocks, software safety checks, communication watchdogs, physical safeguards) provide redundant protection. PCP should adopt this philosophy: TEE attestation provides hardware-rooted identity, but the protocol must also include software-level validation, heartbeat monitoring, and the ability to integrate with hardware safety systems.

2. **Fail-safe defaults**: When in doubt, stop. Every safety-critical protocol analyzed in this report defaults to a safe state upon detecting any anomaly. PCP's lease timeout provides a form of fail-safe, but it is insufficient alone. The protocol must define what "safe state" means for each robot type and ensure that reaching the safe state does not depend on any single component.

3. **Formal separation of safety and standard channels**: IEC 61508 and all analyzed safety protocols (OPC-UA Safety, PROFIsafe, EtherCAT Safety) emphasize the separation of safety-related communication from standard communication. PCP currently conflates both in a single JSON-RPC channel. This should be rethought.

4. **Deterministic timing as a first-class requirement**: Every safety-certified protocol specifies maximum response times, watchdog intervals, and safe-state transition times. PCP must make timing a first-class aspect of the protocol specification.

### Common Anti-Patterns

1. **Assuming the network is reliable**: Every safety protocol analyzed in this report assumes the network WILL fail and designs mechanisms to detect and recover from failures. PCP's CRDT-based approach handles network partitions through eventual consistency, but this is inappropriate for safety-critical state.

2. **Single point of failure in the safety path**: If the lease manager, physics validator, or any other single component fails, the entire safety chain fails. Safety-critical systems use redundancy (dual-channel, triple-modular-redundancy) to eliminate single points of failure.

3. **Implicit safety assumptions**: If safety depends on an assumption that is not explicitly documented and verified, the system is unsafe. For example, assuming that "the CRDT state is always consistent" is an implicit assumption that is violated during network partitions.

4. **Optimizing for performance at the expense of safety**: It is tempting to reduce heartbeat frequency or increase watchdog timeouts to improve performance. Safety standards require that these values be set based on the risk analysis, not on performance considerations.

### Security Assumptions

| Assumption | Validity | Risk if Violated |
|-----------|----------|-----------------|
| TEE attestation is trustworthy | Depends on TEE vendor (SGX has known side-channel attacks) | Malicious robot could impersonate a legitimate one |
| Ed25519 signatures are unforgeable | Well-established cryptography, but requires secure key storage | Unauthorized command execution |
| Network is not actively adversarial | Reasonable for controlled industrial environments, unreasonable for open systems | Message injection, replay, tampering |
| CRDT merge is deterministic | True by construction for well-designed CRDTs | Inconsistent state across replicas |
| JSON-RPC layer is not a security boundary | True -- security is provided by TEE + Ed25519, not JSON-RPC | N/A (not relied upon) |

### Safety Assumptions

| Assumption | Validity | Risk if Violated |
|-----------|----------|-----------------|
| Physics simulation (HNN) accurately predicts real-world behavior | Neural network predictions can have unbounded error | Unsafe actuation based on incorrect physics prediction |
| Lease prevents simultaneous resource access | Only true with strong consistency (Raft), not with CRDTs | Collision, equipment damage, injury |
| Constitution validation catches all unsafe configurations | Depends on completeness of constitution rules | Undetected unsafe configuration leads to actuation |
| Shadow validation is computationally fast enough | Depends on HNN model complexity and hardware | Delay in actuation could cause timing violations |
| Network latency is bounded | Only true with real-time network configuration | Watchdog timeout, missed heartbeats, safety violation |

### Certification Implications

Achieving safety certification (SIL rating) for a protocol that includes machine learning (HNN physics validation) and distributed consensus is extremely challenging. Key certification concerns include:

1. **Determinism**: IEC 61508 favors deterministic safety functions. Neural networks (HNN) are inherently non-deterministic (different hardware may produce slightly different results). The protocol must define how to handle HNN prediction variance.

2. **Verification**: Safety-certified systems require extensive verification (testing, analysis, formal methods). Machine learning components require specialized verification approaches (formal verification of neural network properties, robustness testing, coverage metrics).

3. **Configuration**: Safety certification typically requires a fixed, validated configuration. PCP's support for dynamic capability negotiation and runtime configuration may conflict with certification requirements.

4. **Legacy compatibility**: If PCP is to be used in existing certified robot systems, the protocol must be compatible with the existing safety-certified communication channels.

### Interoperability Concerns

1. **With ROS 2**: PCP should define a ROS 2 RMW adapter or DDS bridge to enable integration with ROS 2-based robots. This requires mapping PCP's lease and actuation model to ROS 2's action and service paradigms.

2. **With industrial fieldbus**: For integration with existing industrial robots (which typically use EtherCAT, PROFINET, or similar), PCP should define a gateway protocol that maps PCP's safety messages to fieldbus safety protocols.

3. **With OPC-UA**: OPC-UA is the dominant protocol for industrial IoT. PCP should define an OPC-UA companion specification that maps PCP's concepts to OPC-UA information models.

### Places Where PCP Currently Appears to Violate Best Practices

1. **CRDTs for safety-critical state (lease management)**: Violates the strong consistency requirement for mutual exclusion. No existing safety-certified protocol uses CRDTs for safety state.

2. **No emergency stop mechanism**: Violates ISO 10218-1 Clause 5.5.2 (mandatory E-stop). Every safety-certified robot protocol includes E-stop.

3. **No heartbeat/watchdog**: Violates IEC 61784-3 requirements for safety communication. Every safety-certified communication profile includes watchdog.

4. **No timing specifications**: Violates IEC 61508 and IEC 62061 requirements for defined response times. Safety communication must have bounded latency.

5. **No formal specification**: Violates best practices for safety-critical protocol design. TLA+ or equivalent formal specification is recommended by IEC 61508 for SIL 2+.

6. **No dual-channel validation**: Insufficient for SIL 2+ per IEC 61508. Safety communication should use independent redundant channels.

7. **HNN physics validation without deterministic bounds**: Neural network predictions have non-deterministic variance. Safety certification requires deterministic behavior or defined error bounds.

---

## Deliverables

### Deliverable 1: Executive Summary

[Provided above in Section 1 of this report.]

### Deliverable 2: Detailed Research Report

[This document constitutes the detailed research report, organized by the six sections specified in the research requirements.]

### Deliverable 3: Architecture Comparison Tables

| Dimension | PCP (Current) | MCP (Anthropic) | ROS 2/DDS | MAVLink | OPC-UA Safety |
|-----------|-----------------|-----------------|-----------|---------|---------------|
| Domain | Physical robotics | LLM tool invocation | General robotics | Drones/UAV | Industrial automation |
| Primary Goal | Safe coordination | Tool/data access | Middleware communication | Vehicle control | Safety-certified control |
| Wire Format | JSON-RPC 2.0 | JSON-RPC 2.0 | CDR (binary) | Binary (custom) | OPC-UA binary/JSON |
| Schema | (Not defined) | JSON Schema via TypeScript | IDL (DDS) | XML message defs | OPC UA information model |
| Versioning | (Not defined) | Date-based | DDS version | Message version | OPC UA version |
| Capability Negotiation | (Not defined) | Boolean flags | DDS QoS | (None) | OPC UA endpoints |
| Identity | Ed25519 + TEE | (None) | DDS participant | System/Component ID | X.509 certificate |
| Safety Cert | No | No | No | No | SIL 2-3 |
| State Mgmt | CRDT | (None) | (None) | (None) | (None) |
| Consensus | (None) | (None) | (None) | (None) | (None) |
| Physics Validation | HNN (planned) | N/A | N/A | N/A | N/A |
| Formal Spec | No | No | No | No | Partial |

### Deliverable 4: Standards Comparison Matrix

[Provided in Section 2 -- see the Standards Comparison Matrix table.]

### Deliverable 5: Protocol Feature Comparison Matrix

[Provided in Section 3 -- see the Protocol Feature Comparison Matrix table.]

### Deliverable 6: Risk Assessment Table

| Risk | Severity | Likelihood | Detection Difficulty | Impact | Mitigation |
|------|----------|-----------|---------------------|--------|------------|
| CRDT split brain grants duplicate leases | Critical | Medium | Low | Collision, injury | Replace CRDT with Raft for lease management |
| CRDT convergence latency causes stale reads | Critical | High | Low | Simultaneous resource access | Use Raft for safety-critical reads |
| No E-stop mechanism | Critical | N/A (design gap) | N/A | Unable to stop robot in emergency | Add E-stop as first-class protocol feature |
| No heartbeat/watchdog | Critical | N/A (design gap) | N/A | Undetected communication loss | Add heartbeat with watchdog timeouts |
| HNN prediction error | High | Medium | High | Unsafe actuation | Define deterministic error bounds, add safety margin |
| TEE side-channel attack | High | Low | Very High | Identity spoofing | Multi-vendor TEE support, defense in depth |
| Timing violation | High | Medium | Medium | Watchdog timeout, missed safety response | Define max latencies, use real-time transport |
| Single point of failure in lease manager | High | Medium | Medium | System-wide safety degradation | Raft cluster with 3+ nodes |
| No formal specification | High | N/A (process gap) | N/A | Undetected design errors | TLA+ specification with model checking |
| Protocol evolution breaks compatibility | Medium | Low | Low | Deployed systems stop working | Semantic versioning with CI/CD compatibility checks |

### Deliverable 7: Recommended Protocol Architecture for PCP

Based on the research in this report, the recommended PCP protocol architecture is:

```
+---------------------------------------------------------------+
|                    Application Layer                          |
|  Lease Management | Actuation | Constitution | E-Stop | Config  |
|  (Raft consensus)  | Commands   | Validation    | (bypass)  |         |
+---------------------------------------------------------------+
|                    Validation Layer                            |
|  Shadow Validation (HNN Physics) | Safety Rule Engine          |
+---------------------------------------------------------------+
|                    Safety Layer                               |
|  Safety Container (CRC, Seq#, Watchdog, Safety Token)          |
+---------------------------------------------------------------+
|                    State Dissemination Layer                    |
|  CRDT Ledger (non-safety-critical: status, telemetry, config) |
+---------------------------------------------------------------+
|                    Identity & Attestation Layer                 |
|  Ed25519 Identity | TEE Attestation (SGX/SEV/TrustZone/DICE)   |
+---------------------------------------------------------------+
|                    Transport Abstraction Layer                  |
|  WebSocket (ref) | DDS | QUIC | Custom (extensible)         |
+---------------------------------------------------------------+
```

Key architectural changes from the current proposal:

1. **Raft for safety-critical state**: Lease management and actuation permissions are managed by a Raft consensus group, not CRDTs.
2. **CRDTs only for non-safety-critical state**: Sensor data, robot status, telemetry, and configuration use CRDTs.
3. **Dedicated safety layer**: A protocol-level safety container (inspired by OPC-UA Safety and PROFIsafe) provides CRC, sequence numbers, watchdog, and safety tokens.
4. **Emergency stop bypass**: E-stop messages bypass the lease requirement and have highest priority.
5. **Transport abstraction**: The protocol is transport-agnostic, with WebSocket as the reference implementation.

### Deliverable 8: Recommended State Machine

#### Robot State Machine

```
         +----------+
         | UNCONFIG |
         +----+-----+
              | configure()
              v
         +----------+
         | INACTIVE |
         +----+-----+
              | activate()
              v
+----> +----------+ <----+
|      |  ACTIVE  |      |
|      +----+-----+      |
|           |            |
|    actuate()  deactivate()
|           |            |
|           v            |
|      +----------+      |
|      |ACTUATING |      |
|      +----+-----+      |
|           |            |
|    complete()           |
|           |            |
|           v            |
|      +----------+      |
+------+ |  ERROR   | ----+
|      +----+-----+
|           | recover()
|           v
|      +----------+
|      |  SAFE    |
|      +----+-----+
|           | reset()
|           v
|      +----------+
+------+ |INACTIVE |
       +----------+

Emergency stop from any state -> SAFE
Watchdog timeout from any state -> SAFE
Lease expiry during ACTUATING -> SAFE
```

#### Lease State Machine

```
         +----------+
         |  FREE    |
         +----+-----+
              | acquire()
              v
         +----------+
         | PENDING  |
         +----+-----+
              |
    +---------+---------+
    |                   |
| granted()         denied()
    |                   |
    v                   v
+----------+       +----------+
|  ACTIVE  |       |  DENIED  |
+----+-----+       +----------+
     |
     | expire() / release() / E-stop
     v
+----------+
| EXPIRED |
+----------+
```

### Deliverable 9: Recommended Versioning Strategy

**Semantic Versioning (SemVer 2.0.0)** with the following rules:

| Version Component | Change Triggers | Wire Compatibility | Action Required |
|------------------|----------------|-------------------|-----------------|
| MAJOR (X.0.0) | Remove/rename fields, change types, add required fields, remove message types | Breaking | All implementations must update simultaneously |
| MINOR (0.X.0) | Add optional fields, add message types, add capabilities, relax constraints | Backward compatible | Older implementations can ignore new features |
| PATCH (0.0.X) | Fix spec ambiguities, add examples, correct documentation | No wire change | No implementation changes required |

**Compatibility enforcement**: Automated CI/CD pipeline that:

1. Compares new schema against previous version
2. Verifies that only PATCH or MINOR changes are made within a major version
3. Runs full conformance test suite
4. Generates a compatibility report

**Deprecation policy**: Fields and message types are deprecated for at least two minor versions before removal. Deprecated features generate warnings but continue to function.

### Deliverable 10: Recommended Schema Organization

```
ppcp-spec/
  schema/
    ppcp.ts               # Canonical TypeScript schema (single source of truth)
    ppcp.json              # Generated JSON Schema
  generated/
    typescript/            # TypeScript types
    python/                # Python pydantic models
    rust/                  # Rust structs (via quicktype or schemars)
    go/                    # Go structs
    java/                  # Java classes
    csharp/                # C# classes
  protocol/
    invariants.tla         # TLA+ protocol invariants
    state-machines.scxml   # SCXML state machine definitions
    properties.tla         # TLA+ safety/liveness properties
  tests/
    conformance/           # Schema conformance tests (AJV)
    compatibility/         # Wire compatibility tests
    interoperability/      # Cross-implementation tests
    model-checking/        # TLA+ model checking scripts
  docs/
    specification.md       # Human-readable specification
    safety-analysis.md     # Safety analysis document
    versioning.md          # Versioning policy
    migration/             # Per-version migration guides
  examples/
    messages/              # Example messages (JSON)
    scenarios/             # Example interaction scenarios
```

### Deliverable 11: Recommended Conformance Testing Strategy

**Three-level testing strategy:**

1. **Level 1: Schema Conformance** (run on every commit)
   - Verify all example messages validate against the JSON Schema
   - Verify schema evolution follows semantic versioning rules
   - Tools: AJV (JS/TS), pydantic (Python), jsonschema (Python)

2. **Level 2: Wire Compatibility** (run on every pull request)
   - Capture reference wire messages from the reference implementation
   - Verify that new implementations produce wire-compatible messages
   - Verify that byte-level changes are only those allowed by the versioning policy
   - Tools: Custom test harness comparing serialized messages

3. **Level 3: Interoperability** (run nightly / before release)
   - Run two independent implementations against each other
   - Test all protocol operations: lease acquisition, actuation, E-stop, heartbeat
   - Test failure scenarios: network partition, heartbeat loss, lease expiry
   - Tools: Test orchestrator that launches multiple implementations and verifies behavior

**Additional testing for safety-critical features:**

- **Timing tests**: Verify that all timing constraints (max latency, heartbeat interval, watchdog timeout) are met under load
- **Fault injection tests**: Systematically inject faults (message loss, delay, corruption) and verify correct behavior
- **Formal verification tests**: Derive test vectors from TLA+ model checking results

### Deliverable 12: Recommended Formal Specification Approach

[Provided in Section 6. See the "Recommended Formal Specification Approach Summary" table and the TLA+ invariant/property examples.]

### Deliverable 13: Prioritized Implementation Roadmap

| Phase | Priority | Duration | Key Deliverables | Dependencies |
|-------|----------|----------|-----------------|--------------|
| **Phase 0: Foundation** | P0 (Critical) | 4-6 weeks | Canonical JSON Schema, versioning policy, CI/CD pipeline, TLA+ invariant specification | None |
| **Phase 1: Safety Core** | P0 (Critical) | 8-12 weeks | E-stop protocol, heartbeat/watchdog, safe state definitions, safety container (CRC, seq#, watchdog) | Phase 0 |
| **Phase 2: Lease & Identity** | P0 (Critical) | 6-8 weeks | Raft-based lease management, Ed25519 identity, TEE attestation, lease state machine | Phase 1 |
| **Phase 3: Actuation Pipeline** | P1 (High) | 8-10 weeks | Constitution validation, shadow validation (HNN), actuation command protocol, acknowledgement model | Phase 2 |
| **Phase 4: State Dissemination** | P1 (High) | 4-6 weeks | CRDT layer for non-safety state (status, telemetry, config), partition detection | Phase 2 |
| **Phase 5: Transport** | P1 (High) | 4-6 weeks | Transport abstraction, WebSocket reference implementation, QUIC transport (optional) | Phase 1 |
| **Phase 6: Tooling & SDK** | P2 (Medium) | 6-8 weeks | Multi-language SDKs (quicktype), conformance test suite, documentation generation, example implementations | Phase 0-5 |
| **Phase 7: Certification Prep** | P2 (Medium) | 12-16 weeks | FMEA, safety manual, SIL target analysis, certification test plan, third-party audit | Phase 1-6 |

### Deliverable 14: Must-Read Bibliography

**Per Topic -- Essential References (2-3 each):**

**Anthropic MCP:**
1. Anthropic, "Model Context Protocol Specification," modelcontextprotocol.io, 2024-2025.
2. Anthropic, "MCP TypeScript SDK," github.com/modelcontextprotocol/typescript-sdk.
3. JSON-RPC 2.0 Specification, jsonrpc.org.

**Industrial Robot Safety:**
1. IEC 61508:2010, "Functional safety of electrical/electronic/programmable electronic safety-related systems."
2. ISO 10218-1:2011, "Robots and robotic devices -- Safety requirements for industrial robots -- Part 1."
3. IEC 61784-3:2021, "Industrial communication networks -- Profiles -- Part 3-3: Functional safety fieldbuses."

**Robotics Protocols:**
1. Ongaro, D. and Ousterhout, J. (2014). "In Search of an Understandable Consensus Algorithm." USENIX ATC.
2. OMG, "Data Distribution Service (DDS) Version 1.4."
3. OPC Foundation, "OPC UA Safety Specification."

**Schema Design:**
1. JSON Schema Draft 2020-12 Specification, json-schema.org.
2. OpenAPI 3.1.0 Specification, spec.openapis.org.
3. SemVer 2.0.0, semver.org.

**CRDTs:**
1. Shapiro, M. et al. (2011). "A comprehensive study of Convergent and Commutative Replicated Data Types." INRIA.
2. Ongaro, D. and Ousterhout, J. (2014). "In Search of an Understandable Consensus Algorithm." USENIX ATC.
3. Kleppmann, M. and Beresford, A.R. (2017). "A Conflict-Free Replicated JSON Datatype." IEEE TPDS.

**Formal Methods:**
1. Lamport, L. (2002). "Specifying Systems: The TLA+ Language and Tools for Hardware and Software Engineers."
2. Newcombe, C. et al. (2014). "Formal Methods in Practice at Amazon Web Services."
3. Abrial, J.-R. (2010). "Modeling in Event-B: System and Software Engineering." Cambridge.

**TEE/Identity:**
1. TCG, "DICE Layer Specification," trustedcomputinggroup.org.
2. Intel, "Intel SGX Attestation Service Documentation."
3. ARM, "TrustZone Security Whitepaper."

### Deliverable 15: Annotated Reference List

#### Official Standards

1. **IEC 61508:2010** -- Functional safety of electrical/electronic/programmable electronic safety-related systems. Parts 1-7. The foundational standard for all safety-related E/E/PE systems. Defines SIL levels, PFD/PFH metrics, and safety lifecycle requirements. [Published by IEC, available from webstore.iec.ch]

2. **ISO 10218-1:2011** -- Robots and robotic devices -- Safety requirements for industrial robots -- Part 1: Robots. Specifies safety requirements for the design and construction of industrial robots. Defines the robot's safety-related control system requirements. [Published by ISO]

3. **ISO 10218-2:2011** -- Robots and robotic devices -- Safety requirements for industrial robots -- Part 2: Robot systems and integration. Specifies safety requirements for the integration of industrial robots into systems. Addresses communication, workspace safety, and verification. [Published by ISO]

4. **ISO/TS 15066:2016** -- Robots and robotic devices -- Collaborative robots. Technical specification for collaborative robot operation, including force/velocity limits and safety measures for four collaborative operation methods. [Published by ISO, under revision]

5. **IEC 62061:2021** -- Safety of machinery -- Functional safety of safety-related control systems. Specifies requirements for the design of safety-related control systems using SIL. [Published by IEC]

6. **ISO 13849-1:2023** -- Safety of machinery -- Safety-related parts of control systems -- Part 1: General principles for design. Specifies Performance Levels (PL) and Categories for safety-related parts. [Published by ISO]

7. **IEC 61784-3:2021** -- Industrial communication networks -- Profiles -- Part 3: Functional safety fieldbuses. Defines safety communication profiles including PROFIsafe, EtherCAT Safety, and others. [Published by IEC]

8. **IEC 60204-1:2016** -- Safety of machinery -- Electrical equipment of machines -- Part 1: General requirements. Defines emergency stop categories and electrical safety requirements. [Published by IEC]

9. **ANSI/RIA R15.06-2012** -- Industrial Robots and Robot Systems -- Safety Requirements. US adoption of ISO 10218-1 and 10218-2 with national deviations. [Published by RIA]

10. **ISO/IEC 11889:2015** -- Trusted Platform Module. Specifies the TPM hardware security module architecture and interfaces. [Published by ISO/IEC]

11. **SemVer 2.0.0** -- Semantic Versioning specification. Defines version numbering scheme and compatibility rules. Available at semver.org.

12. **JSON-RPC 2.0** -- JSON-RPC 2.0 Specification. Defines the JSON-RPC request/response protocol used by MCP and proposed for PCP. Available at jsonrpc.org.

#### Specifications and RFCs

13. **JSON Schema Draft 2020-12** -- The latest version of the JSON Schema specification for validating JSON documents. Available at json-schema.org.

14. **OpenAPI 3.1.0** -- API description format aligned with JSON Schema Draft 2020-12. Available at spec.openapis.org.

15. **AsyncAPI 2.6** -- Specification for asynchronous message-driven APIs. Available at asyncapi.com.

16. **OMG DDS DCPS v1.4** -- Data Distribution Service for Real-Time Systems, Data-Centric Publish-Subscribe. The middleware standard used by ROS 2. [Published by OMG]

17. **OMG DDS-XRCE** -- DDS for Extremely Resource-Constrained Environments. A lightweight DDS protocol for embedded systems. [Published by OMG]

#### Academic Papers

18. **Shapiro, M., Preguica, N., Baquero, C., and Zawirski, M. (2011).** "A comprehensive study of Convergent and Commutative Replicated Data Types." INRIA Research Report RR-7506. The foundational CRDT paper. Covers CvRDTs, CmRDTs, and the theoretical framework for eventual consistency. [Available from INRIA HAL archives]

19. **Almeida, P.S., Shoker, A., and Baquero, C. (2018).** "Delta State Replicated Data Types." Journal of Parallel and Distributed Computing, 111, 162-173. Introduces delta-state CRDTs that reduce bandwidth overhead. [Available from ScienceDirect]

20. **Ongaro, D. and Ousterhout, J. (2014).** "In Search of an Understandable Consensus Algorithm." USENIX ATC 2014. The Raft consensus protocol paper. Essential reading for understanding the consensus alternative to CRDTs for PCP's lease management. [Available from usenix.org]

21. **Kleppmann, M. and Beresford, A.R. (2017).** "A Conflict-Free Replicated JSON Datatype." IEEE Transactions on Parallel and Distributed Systems, 28(10), 2733-2746. Demonstrates CRDT application to structured data but highlights the challenges of maintaining application-level invariants. [Available from IEEE Xplore]

22. **Gomes, V.B., Kleppmann, M., and Beresford, A.R. (2017).** "Making Operation-Based CRDTs Conflict-Free." Programming Journal, 1(2), 8. Discusses methods for ensuring operation commutativity. [Available from MDPI]

23. **Lamport, L. (2002).** "Specifying Systems: The TLA+ Language and Tools for Hardware and Software Engineers." Addison-Wesley. The definitive reference for TLA+. Covers specification methodology, the TLC model checker, and numerous examples. [Book, available from Amazon]

24. **Newcombe, C., Rath, T., Zhang, F., Munteanu, B., Brooker, M., and Deardeuff, M. (2014).** "Formal Methods in Practice at Amazon Web Services." Amazon's experience report on using TLA+ to verify DynamoDB, S3, EBS, and other services. Essential reading for understanding the practical value of formal methods. [Available from Amazon Science]

25. **Harel, D. (1987).** "Statecharts: A Visual Formalism for Complex Systems." Science of Computer Programming, 8(3), 231-274. The foundational paper on Statecharts, the basis for UML state machines and SCXML. [Available from ScienceDirect]

26. **Howard, H., Malkhi, D., and Spiegelman, A. (2020).** "Flexible Paxos: Quorum Intersection Revisited." OSDI 2020. Generalizes Paxos/Raft quorum requirements. Relevant for understanding PCP's consensus options. [Available from usenix.org]

#### GitHub Repositories and Open-Source Implementations

27. **Anthropic MCP TypeScript SDK** -- github.com/modelcontextprotocol/typescript-sdk. Reference implementation of the Model Context Protocol. Includes the canonical schema definition (schema.ts) and JSON Schema generation. [MIT License]

28. **etcd** -- github.com/etcd-io/etcd. Production Raft consensus implementation in Go. The most widely-deployed Raft implementation, used in Kubernetes. [Apache 2.0 License]

29. **HashiCorp Raft** -- github.com/hashicorp/raft. Production Raft implementation in Go, used in Consul and Vault. Well-documented and suitable as a reference for PCP's consensus layer. [MPL 2.0 License]

30. **MAVLink C Library** -- github.com/mavlink/c_library_v2. Reference implementation of the MAVLink protocol. Includes message definitions and parsing/generation code. [LGPL v3]

31. **Open62541 (OPC-UA)** -- github.com/open62541/open62541. Open-source OPC-UA implementation in C. Includes safety extensions. [MPL 2.0 License]

32. **Automerge** -- github.com/yjs/automerge. Production CRDT library for collaborative editing. Demonstrates CRDT implementation patterns. [MIT License]

33. **Redis CRDT** -- github.com/redislabs/redis-crdt. CRDT extension for Redis providing multi-master replicated data structures. [RSALv2/SSPL, commercial]

34. **ROS 2** -- github.com/ros2. The Robot Operating System 2. Includes DDS middleware abstraction and lifecycle management. [Apache 2.0 License]

35. **Open-RMF** -- github.com/open-rmf/rmf. Open Robotics Middleware Framework for fleet management. Built on ROS 2. [Apache 2.0 License]

36. **Eclipse Zenoh** -- github.com/eclipse-zenoh/zenoh. Pub/sub/query protocol for edge-to-cloud communication. [EPL 2.0 License]

37. **quicktype** -- github.com/glideapps/quicktype. Cross-language code generator from JSON Schema. Supports TypeScript, Python, Rust, Go, Java, C#, and more. [Apache 2.0 License]

38. **AJV** -- github.com/ajv-validator/ajv. The fastest JSON Schema validator for JavaScript. Production-ready, widely used. [MIT License]

#### Production Systems

39. **AWS DynamoDB** -- Amazon's distributed database that uses synchronous replication (not CRDTs) for strong consistency. TLA+ was used extensively in its design. Relevant as a case study in formal methods for distributed systems. [amazon.com/dynamodb]

40. **Kubernetes etcd** -- Kubernetes uses etcd (Raft-based) for all cluster state. Demonstrates the practical application of Raft for critical distributed state management in production systems. [kubernetes.io]

41. **Azure Cosmos DB** -- Microsoft's globally distributed database. Uses TLA+ for verification. Supports multiple consistency levels. [azure.com/cosmosdb]

42. **ArduPilot/PX4** -- Open-source autopilot software that implements the MAVLink protocol. Demonstrates production command sequencing, failsafe handling, and arming/disarming in unmanned vehicles. [ardupilot.org, px4.io]

43. **Siemens TIA Portal** -- Industrial automation platform that implements PROFIsafe and other safety communication profiles. Demonstrates safety-certified communication in production. [siemens.com/tia-portal]

---

*End of Report*