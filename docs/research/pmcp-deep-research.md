# P-MCP Deep Research: Seven Open Design Questions for the Safety-Critical Architecture

**Status.** Final research synthesis, prepared in support of the canonical P-MCP specification.

**Scope.** Seven specific open design questions on: (1) HNN determinism and confidence for safety gating, (2) fail-safe design when the Raft consensus layer fails, (3) physical locality / proof-of-location for robot identity, (4) spatial-overlap lease conflict detection, (5) end-to-end JSON-RPC message authentication, (6) recovery/reconnection handshake after Safe State, (7) SIL ceiling for ML-gated safety functions.

**Convention.** For each question: the concrete mechanism or data structure (not just the concept), 2–3 primary references to read in full, and an explicit **"Settled vs. Open"** verdict flagging where the field genuinely has no settled answer.

---

## Question 1 — HNN / Neural-Network Determinism and Confidence for Safety Gating

### Concrete mechanism

**Confidence schema.** The defensible pattern — drawn from the autonomous-vehicle (AV) perception stacks and the FDA's Predetermined Change Control Plan (PCCP) framework for ML-enabled medical devices — is to *never* emit a bare `{safe: true/false}` from an ML gate. The message shape that has emerged across these domains is a *typed prediction record*:

```json
{
  "prediction": "SAFE_TO_ACTUATE",
  "confidence_score": 0.92,
  "confidence_method": "conformal_prediction",
  "error_bound": {"type": "abstention_set", "coverage": 0.99, "epsilon": 0.03},
  "model_id": {"hash": "sha256:…", "training_data_version": "v3.4.2", "weights_uri": "ipfs://…"},
  "input_range": {"odds_of_motion": [0, 1.5], "tau_max": 12.0, "…": "…"},
  "ood_flag": false,
  "ensemble_disagreement": 0.04,
  "runtime_determinism_token": "deterministic_v1"
}
```

The receiving gate then evaluates a *composite* predicate, not the raw `prediction`:

```
gate_passes  ≡  (prediction == SAFE_TO_ACTUATE)
              ∧ (confidence_score ≥ θ_conf)
              ∧ (ensemble_disagreement ≤ θ_ens)
              ∧ (ood_flag == false)
              ∧ (input is inside input_range)
              ∧ (runtime_determinism_token == expected)
```

**Threshold-setting methodology.** Three positions exist in the literature, in increasing defensibility order:

1. **Fixed threshold** (e.g., `confidence_score ≥ 0.95`). Used in early AV prototypes. Now considered indefensible for safety-critical use because raw softmax scores are *not calibrated* — a model may say 0.95 when its empirical accuracy is 0.70.
2. **Calibrated threshold** via Platt scaling / isotonic regression / temperature scaling. Improves calibration on the validation set but gives no distribution-free guarantee on out-of-distribution (OOD) inputs.
3. **Conformal prediction** (Vovk; Shafer & Vovk 2008). Provides *distribution-free* coverage guarantees: if you ask for 99% coverage, conformal prediction guarantees ≥99% coverage on exchangeable test data, regardless of the underlying model. This is the methodology used in `Sun et al., Conformal Prediction for Uncertainty-Aware Planning with Dynamical Models` (Stanford, 2023) for robotics. For P-MCP's Shadow validation, conformal prediction is the only methodology with a defensible mathematical guarantee. **Use it.**

**Cross-hardware non-determinism.** This is a *real, documented* problem, not a theoretical one. The two root causes are:
- **Floating-point non-associativity under parallel reduction.** `(a+b)+c ≠ a+(b+c)` in IEEE 754, and parallel GPU reductions pick an order based on warp scheduling. Documented in `arXiv:2408.05148` (2024) and the NVIDIA CCCL determinism blog (2026).
- **Concurrency-induced nondeterminism in the kernel scheduler**, not floating-point per se (challenged by Thinking Machines, 2025).

Three defenses, in increasing rigor:
1. **Fixed random seed + deterministic cuDNN algorithms + `torch.use_deterministic_algorithms(True)`** — *necessary but not sufficient*. Still leaves cross-vendor divergence.
2. **Bounded numerical divergence**: document a worst-case `‖output_cpu − output_gpu‖_∞ ≤ ε_max` per model version, established by *test-vector replay* on every supported hardware target, and reject any production output that diverges from a reference CPU run by more than `ε_max`. This is the practical pattern used in production AV stacks.
3. **Runtime determinism token**: a SHA-256 of `(model_hash, hardware_id, driver_version, cuda_version, deterministic_kernel_flag)` embedded in every prediction. The gate refuses to actuate unless the token matches one of the *pre-qualified* token set established at certification time.

P-MCP should require all three: deterministic kernels + bounded divergence + determinism token.

### Settled vs. Open

- **Settled (go implement):** "ML safety gates must emit a typed prediction record with confidence + error bound + model_id + determinism token, not a bare boolean." Every credible reference agrees on this.
- **Settled (go implement):** "Conformal prediction is the minimum defensible uncertainty quantification methodology for safety-critical ML." Vovk's framework is mature, with implementations in Python (`MAPIE`), R, and growing production adoption.
- **Open research problem (P-MCP must make a documented judgment call):** "What is the right *cross-hardware divergence budget* `ε_max` for a Hamiltonian Neural Network doing physics validation?" There is no published methodology for setting `ε_max` for HNN-style physics-informed networks specifically. P-MCP must establish this empirically per model version and document the methodology.
- **Open research problem (P-MCP must make a documented judgment call):** "How does conformal prediction compose with adversarial inputs?" Conformal prediction assumes exchangeable data; an attacker constructing inputs violates this. There is no settled defense. P-MCP must explicitly bound Shadow validation's threat model to "non-adversarial input distribution" OR layer an adversarial-robustness check before conformal prediction.

### References to read in full

1. **EASA Artificial Intelligence Roadmap 2.0** — `easa.europa.eu/en/domains/research-innovation/ai`. The canonical aviation-AI certification framework. Read the W-shape W-model concept and the Level 1/2/3 AI classification. Read the EASA Concept Paper on Level 1 ML applications.
2. **FAA Roadmap for Artificial Intelligence Safety Assurance** (July 2024) — `faa.gov/aircraft/air_cert/step/roadmap_for_AI_safety_assurance`. U.S. counterpart; complementary perspective on AI trustworthiness and assurance.
3. **FDA, *Predetermined Change Control Plans (PCCP) for AI-Enabled Device Functions*** (final guidance, August 2025) — `fda.gov/regulatory-information/search-fda-guidance-documents/...`. The methodology for managing model-version drift in regulated ML. Directly applicable to P-MCP's `model_id` field and version-management discipline.
4. **Sun, Tomlin, et al. (Stanford, 2023), *Conformal Prediction for Uncertainty-Aware Planning with Dynamical Models*** — `msl.stanford.edu/papers/sun_conformal_2023.pdf`. Concrete application of conformal prediction to robotics dynamics models.
5. **arXiv:2408.05148, *Impacts of floating-point non-associativity on reproducibility*** — the definitive recent treatment of the cross-hardware determinism problem.

---

## Question 2 — Fail-Safe Design When the Consensus Layer Itself Fails

### Concrete mechanism

**The standard Raft behavior is unsafe for P-MCP.** The etcd FAQ states explicitly: *"If quorum is lost through transient network failures (e.g., partitions), etcd automatically and safely resumes once the network recovers."* Note what this says and what it doesn't: it says the *data* is safe (no split-brain), it does **not** say anything about what happens to *in-flight operations* during the quorum-loss window. For a database, "no leader → write blocked → eventually resumes" is fine. For a robotics lease system, "no leader → can't renew lease → lease expires → ??? → robot may already be mid-actuation" is a safety event.

**The pattern that has emerged in safety-critical DCS literature** (industrial Distributed Control Systems from vendors like Siemens, Rockwell, ABB) is the **"default-to-safe-state-on-quorum-loss"** rule, with three concrete mechanisms layered on top of Raft:

1. **Lease TTL << worst-case-quorum-recovery-time.** The lease duration must be *shorter* than the worst-case time the consensus layer could take to elect a new leader (typically 2–10 seconds). This way, if quorum is lost, the lease expires *before* any actuation in progress can complete. The lease is renewed on a *cadence* of TTL/3, and a missed renewal is the safety trigger, not the loss-of-quorum event itself.
2. **Independent watchdog on each robot.** Each robot runs a hardware watchdog (not the consensus client) that physically interrupts motion if it hasn't received a valid lease-renewal signature within TTL + jitter. This is the **OPC-UA Part 15 SCL pattern** (the "black channel" approach): treat the consensus layer as an unreliable channel and put the safety monitoring at the endpoint.
3. **Pre-committed Safe State transition.** When a Raft follower detects `current_leader == None` for more than `T_leader_unknown` (typically 1.5× election timeout), it transitions local state to `SAFE` *immediately and irrevocably* — even if a leader is elected a millisecond later. This is the "fail-safe bias" rule: assume the worst, confirm before resuming.

**The concrete state machine** for a Raft-backed safety system is:

```
state ActivelyLeased:
  on lease_renewal_received within TTL:
    stay
  on lease_renewal_missed OR current_leader == None for T_leader_unknown:
    → transition to Safe (Stop Category 1, motion decelerating)
  on consensus_unreachable:
    → transition to Safe (Stop Category 1)

state Safe:
  // Stuck. Cannot leave without full re-handshake (see Q6).
  on manual_reset_and_full_rehandshake:
    → transition to Unleased

state Unleased:
  on fresh_lease_acquired AND constitution_validated AND shadow_validated:
    → transition to ActivelyLeased
```

The key property: **`Safe` is sticky**. The system does not auto-recover. This is the divergence from "high-availability Raft" thinking and is the single most important safety property of the design.

### Settled vs. Open

- **Settled (go implement):** "Treat the consensus layer as a black channel; put the safety watchdog at the robot endpoint, not in the consensus client." This is the OPC-UA Part 15 SCL pattern, certified to SIL 3.
- **Settled (go implement):** "Lease TTL must be shorter than worst-case Raft leader election time, with renewal at TTL/3." This is the standard heartbeat/watchdog pattern, applied to Raft semantics.
- **Settled (go implement):** "Safe State is sticky; do not auto-recover." Every functional-safety standard (IEC 61508, ISO 13849, ISO 10218) requires manual reset after a safety function triggers.
- **Open research problem (P-MCP must make a documented judgment call):** "What is the right value of `T_leader_unknown` for a robotics lease system with sub-second actuation windows?" The Raft literature gives bounds for *database* workloads (150–300ms election timeout), but there is no published methodology for setting this for *physical actuation* where the lease expiration must be derived from physical safety bounds (e.g., robot stopping distance at max velocity). P-MCP must derive `T_leader_unknown` from the worst-case robot stopping time, not from the Raft defaults.
- **Open research problem (P-MCP must make a documented judgment call):** "Byzantine Raft variants (Tangaroa, etc.) are research-stage; should P-MCP mandate a Byzantine-tolerant consensus for multi-tenant environments?" Tangaroa (Copeland & Zhong, Stanford) is the canonical BFT Raft, but it is not deployed at scale in safety-critical contexts. If P-MCP assumes a single trusted operator, vanilla Raft + Ed25519 message signing (Q5) is defensible. If P-MCP must resist a malicious minority of consensus participants, BFT Raft is required but introduces 3× message overhead.

### References to read in full

1. **Ongaro & Ousterhout (2014), *In Search of an Understandable Consensus Algorithm*** — the canonical Raft paper. Read §6 (Safety) and §7 (Membership changes) closely, and the section on leader election timeouts.
2. **Copeland & Zhong (Stanford, 2014), *Tangaroa: a Byzantine Fault Tolerant Raft*** — `scs.stanford.edu/14au-cs244b/labs/projects/copeland_zhong.pdf`. The BFT extension if you need it.
3. **OPC UA Part 15 (Safety Communication Layer)** — `reference.opcfoundation.org/specs/OPC-10000-15/4`. The "black channel + endpoint watchdog" pattern that P-MCP should mirror.
4. **NASA/TM—2014-218497 (Torres-Pomales), *Selecting an Architecture for a Safety-Critical Distributed System*** — short, concrete, directly addresses "what does 'fail-safe' mean for a distributed control system?"

---

## Question 3 — Physical Locality / Proof-of-Location for Robot Identity

### Concrete mechanism

**TEE attestation proves code integrity, not location.** This is a hard ceiling of TEE-based identity. To prove a robot is *physically where it claims to be*, you need a separate *distance-bounding* mechanism layered on top.

**Distance-bounding protocols.** The foundational reference is Brands & Chaum (1993), which introduced the rapid bit-exchange protocol: a verifier sends a challenge bit, the prover responds within a tightly bounded time window, and the round-trip time (multiplied by the speed of light) gives an upper bound on the distance. After `n` rounds (typically 32–64), the probability of a relay attack succeeding is `≤ (3/4)^n`. The Brands-Chaum protocol and its descendants (Hancke & Kuhn 2005; Reid et al. 2007; Kim & Avoine 2010) form the canonical literature.

**Three layers of location assurance, in increasing strength:**

1. **BLE RSSI proximity** — `received_signal_strength ≈ −60 dBm at 1m` is used as a distance proxy. **Known spoofing weaknesses**: a relay attack with a directional antenna can make a far-away attacker appear close. *Insufficient for safety-critical use alone.* Useful as a sanity-check / additional signal.
2. **Visual fiducial (AprilTag) localization with signed identity.** The robot observes an AprilTag at a known physical location, computes its pose relative to the tag, and signs the resulting pose claim with its Ed25519 identity key. The verifier checks the signature, then checks that the tag's ID corresponds to a *registered* physical location in the workspace. Concrete attack surface: an attacker who can fake the camera feed (deepfake video injection) can defeat this. Defense: pair AprilTag with a second modality (UWB or inertial).
3. **UWB distance-bounding** (IEEE 802.15.4z). The only mechanism with a cryptographic distance bound. The 802.15.4z amendment added *scrambled timestamping* and *stretched pulses* to defeat relay attacks. Concrete implementation: the Decawave/Qtvo QM33200 and NXP SR150 chips implement 802.15.4z with sub-30cm distance-bounding precision. The Tippenhauer et al. (ETH, 2015) UWB rapid-bit-exchange implementation is the most-cited academic reference.

**The composite pattern for P-MCP** should be:

```
location_proof ≡ (
    uwb_distance_bound(distance_to_anchor_i ≤ d_max for all i ∈ trusted_anchors)
  ∧ ed25519_signed_pose_report(from_robot_id, at_pose, at_time, observed_fiducial_id)
  ∧ optional: ble_rssi_within_expected_range  // sanity only, not a safety signal
)
```

The lease-acquisition step should require this location proof, and the lease should be scoped to the physical zone claimed in the proof.

### Settled vs. Open

- **Settled (go implement):** "UWB distance-bounding (IEEE 802.15.4z) is the only cryptographically-sound location-assurance mechanism." The literature is consistent and the hardware is commodity (~$5/chip).
- **Settled (go implement):** "Brands-Chaum rapid-bit-exchange protocol is the canonical construction, with Hancke-Kuhn as the deployment-friendly simplification." Both have provable security properties.
- **Settled (go implement):** "TEE attestation must be paired with a separate distance-bound proof for any safety claim involving physical location." Every credible architecture agrees.
- **Open research problem (P-MCP must make a documented judgment call):** "How many UWB anchors are required, and what geometric configuration, for a workspace of shape X with safety margin Y?" There is no closed-form methodology; it depends on the workspace geometry. P-MCP should specify the *requirement* (e.g., "at least 3 non-collinear UWB anchors, with line-of-sight to the robot's claimed position") and let deployments choose their geometry.
- **Open research problem (P-MCP must make a documented judgment call):** "How does a robot prove its location when moving (dynamic location claim) vs. when stationary (static location claim)?" Distance-bounding protocols assume a stationary prover at the time of the bit exchange. For a moving robot, the proof is for *position at time t*, and the lease must expire at `t + δ` where `δ` is short enough that the robot cannot have moved outside its declared zone. There is no published standardized pattern for this. P-MCP must define one.

### References to read in full

1. **Brands & Chaum (1993), *Distance-Bounding Protocols*** — EUROCRYPT '93. The foundational paper. Read in full.
2. **Tippenhauer et al. (ETH, 2015), *UWB Rapid-Bit-Exchange System for Distance Bounding*** — `research.scy-phy.net/tippenhauer15uwb.pdf`. The most complete modern UWB implementation reference.
3. **IEEE 802.15.4z-2020 amendment** — the standard that added scrambled timestamping and stretched pulses, defeating the relay attacks that earlier UWB was vulnerable to. Read §15 (Secured Ranging) and Annex A.
4. **Hancke & Kuhn (2005), *An RFID Distance Bounding Protocol*** — the deployment-friendly simplification of Brands-Chaum; widely implemented.

---

## Question 4 — Spatial-Overlap Lease Conflict Detection

### Concrete mechanism

**The data structure is well-known.** The published literature converges on two complementary approaches:

1. **Spatial index (R-tree or R*-tree) over axis-aligned bounding boxes (AABBs)** in 3D, paired with a temporal interval tree. A lease reservation is a `(workspace_aabb, time_interval)` tuple. Conflict detection = spatial-join query: "Does any existing reservation's AABB intersect the new request's AABB, AND do their time intervals overlap?"
2. **Discretized occupancy grid (voxel grid) with time-stamped occupancy**, used in ROS 2 Nav2 costmaps. Easier to implement but has resolution/quantization issues at workspace boundaries.

The published Amazon/Kiva architecture (per the PatSnap 2026 landscape report) uses what they call a *"waypoint-and-timestamp reservation system"* — essentially option (1), where the reservation granularity is a waypoint (not a continuous AABB) plus a time window. This is coarser than AABB-reservation but is the only publicly-documented industrial-scale system.

**The P-MCP-recommended data structure:**

```python
@dataclass
class SpatialLeaseReservation:
    lease_id: UUID
    robot_id: Ed25519PubKey
    workspace: AABB3D  # (xmin, ymin, zmin, xmax, ymax, zmax)
    time_window: Interval[Timestamp]  # [t_start, t_end)
    safety_margin: float  # inflated AABB by this margin before insertion
    priority_class: PriorityClass  # EMERGENCY > NORMAL > TELEMETRY

# Conflict-check algorithm (per-request):
def has_conflict(new: SpatialLeaseReservation,
                 existing_index: RTree) -> Optional[SpatialLeaseReservation]:
    # Inflate new.workspace by new.safety_margin before querying.
    inflated = new.workspace.inflate(new.safety_margin)
    for candidate in existing_index.query_aabb(inflated):
        if candidate.time_window.overlaps(new.time_window):
            # Priority-class exceptions:
            if (new.priority_class == EMERGENCY
                and candidate.priority_class != EMERGENCY):
                # Bump the existing reservation; do not allow.
                return candidate
            return candidate
    return None
```

**The R*-tree (Beckmann et al. 1990) is preferred over the original R-tree (Guttman 1984)** for write-heavy workloads because it considers overlap, enlargement, and area when splitting nodes, yielding ~30% better query performance. The `libspatialindex` C library (used by `rtree` Python package and `rstar` Rust crate) is the reference implementation.

**For ROS 2 Nav2 specifically**, the costmap-based approach has *no native spatial reservation*. Nav2's `costmap_2d` represents instantaneous occupancy; it does not do time-windowed reservation. Multi-robot coordination in Nav2 typically uses *behavior-tree-level arbitration* (one robot waits while another passes), not structured reservation. This is a known gap in the ROS 2 ecosystem and is one of the reasons Amazon Robotics uses a custom fleet manager rather than vanilla Nav2.

### Settled vs. Open

- **Settled (go implement):** "R*-tree + interval tree over (AABB3D, time_interval) tuples is the canonical data structure for spatial-temporal reservation conflict detection." Guttman 1984, Beckmann 1990, and Agarwal et al. (Box-Trees) provide the foundational theory.
- **Settled (go implement):** "Inflate the requested AABB by a safety_margin before querying." This is the standard practice in collision-avoidance systems; without it, you get into races where two robots' envelopes touch but the AABB query misses the collision.
- **Settled (go implement):** "Priority-class exceptions (E-Stop bypasses normal reservations) should be encoded as a priority order, not as a special-case code path." Otherwise the bypass logic spreads throughout the codebase.
- **Open research problem (P-MCP must make a documented judgment call):** "What is the right safety_margin as a function of robot velocity, sensor latency, and lease-renewal cadence?" No published closed-form methodology. P-MCP should require: `safety_margin ≥ v_max × T_safe + sensor_uncertainty_r`, where `T_safe` is the Safe-State transition time (see Q2) and `sensor_uncertainty_r` is the worst-case position-estimation error.
- **Open research problem (P-MCP must make a documented judgment call):** "Should the reservation granularity be continuous (AABB) or discrete (voxel grid)?" Continuous is more space-efficient but harder to visualize and audit. Discrete is easier to audit but introduces quantization error at boundaries. Industrial practice (Amazon) uses discrete waypoint reservation; aerospace-style safety systems tend to use continuous AABBs. P-MCP should pick one and document the tradeoff.

### References to read in full

1. **Guttman (1984), *R-Trees: A Dynamic Index Structure for Spatial Searching*** — the foundational R-tree paper. Short, foundational.
2. **Beckmann, Kriegel, Schneider, Seeger (1990), *The R*-tree: An Efficient and Robust Access Method for Points and Rectangles*** — SIGMOD '90. The R*-tree variant P-MCP should use.
3. **Agarwal et al., *Box-Trees and R-trees with Near-Optimal Query Time*** — `webdoc.sub.gwdg.de/ebook/serien/ah/UU-CS/2001-10.pdf`. Theoretical worst-case bounds for spatial queries.
4. **Amazon/Kiva warehouse fleet literature** — see the PatSnap 2026 landscape report and the Amazon Science blog posts on multi-agent path finding (MAPF). The published technical detail is limited (Amazon is protective), but the high-level architecture is documented.

---

## Question 5 — End-to-End Message Authentication over JSON-RPC for Safety-Critical Control

### Concrete mechanism

**JWS (JSON Web Signature, RFC 7515) is the standard.** The pattern is: each JSON-RPC request and response is wrapped in a JWS envelope, signed by the sender's Ed25519 key, with the payload either detached (RFC 7797 unencoded payload option, for large messages) or base64url-encoded inline (for smaller messages).

**Concrete envelope shape:**

```json
{
  "jsonrpc": "2.0",
  "id": "req-7f3a...",
  "method": "pmcp/lease/acquire",
  "params": { /* ... */ },
  "auth": {
    "alg": "EdDSA",
    "kid": "robot:abc123#key-1",
    "nonce": "7f3a...-nonce",
    "timestamp": 1734000000,
    "jws_protected": "eyJhbGciOiJFZERTQSIsImtpZCI6InJvYm90OmFiYzEyMyNrZXktMSIsIm5vbmNlIjoiN2YzYS4uLi1ub25jZSIsInRpbWVzdGFtcCI6MTczNDAwMDAwMH0",
    "signature": "base64url-ed25519-signature-over-canonical-json-of-jsonrpc-object"
  }
}
```

**Canonical JSON encoding** is critical — JWS signs bytes, and JSON serialization is not deterministic by default. RFC 8785 (*JSON Canonical Encoding Scheme*, "JCS") is the standard for this. Every JSON-RPC implementation must canonicalize before signing or the signatures won't interoperate.

**Detached payload pattern** (RFC 7715 / RFC 7797): for messages larger than ~4KB, the payload is sent in cleartext and only the signature is included. This matters for telemetry-batch messages but not for command messages.

**Why message-level signing, not just TLS?** Three reasons, each independently sufficient:
1. **Defense in depth.** If TLS is terminated at a load balancer (common), the message travels unencrypted on the internal network. Message-level signing survives this.
2. **Non-repudiation.** TLS provides confidentiality and integrity but *not* non-repudiation — both endpoints share the TLS session keys. Ed25519 signatures are non-repudiable: only the holder of the private key could have produced them.
3. **End-to-end across intermediaries.** In a multi-hop architecture (client → gateway → consensus node → robot), TLS is hop-by-hop. Message-level signatures are end-to-end.

**Pitfall: replay attacks.** The `nonce` + `timestamp` fields in the protected header are *mandatory*. The verifier must reject any message where `timestamp` is older than `T_replay_window` (e.g., 30 seconds) or where the `(kid, nonce)` pair has been seen before. Without this, an attacker who captures a valid command can replay it indefinitely.

**Prior art in industrial/financial contexts:** Visa's API platform uses JWS-over-JSON for exactly this purpose (`developer.visaacceptance.com` documents the pattern in detail). W3C's Verifiable Credentials Data Integrity Proofs (2020) defines a JWS-based proof format for verifiable credentials.

### Settled vs. Open

- **Settled (go implement):** "JWS (RFC 7515) + EdDSA (RFC 8037) over canonical JSON (RFC 8785) is the standard pattern for per-message JSON-RPC authentication." The standards are mature and interoperable.
- **Settled (go implement):** "Nonce + timestamp + replay-window rejection is mandatory for safety-critical commands." Without it, replay attacks are trivial.
- **Settled (go implement):** "Detached payload (RFC 7797) for messages >4KB." Necessary for telemetry-batch messages; the inline pattern bloats wire size.
- **Open research problem (P-MCP must make a documented judgment call):** "Key rotation in a multi-tenant robotics fleet." The `kid` (key ID) header allows multiple keys per identity, but the *policy* — how often to rotate, what happens to in-flight messages during rotation, how to revoke a compromised key across all robots — has no settled standard for physical robotics. Visa's pattern (key rotation every 90 days with 24-hour overlap) is a starting point but may be too slow for robotics threat models.
- **Open research problem (P-MCP must make a documented judgment call):** "Should the consensus layer (Raft) itself use JWS-signed messages, or rely on TLS-only protection for the consensus transport?" Consensus messages are high-frequency; per-message signing adds ~1ms per message (Ed25519 is fast but not free). Most production Raft deployments use TLS-only. P-MCP must decide based on its threat model — if a Raft node can be compromised despite TEE attestation, message-level signing is necessary.

### References to read in full

1. **RFC 7515, *JSON Web Signature (JWS)*** — `datatracker.ietf.org/doc/html/rfc7515`. The canonical spec.
2. **RFC 8785, *JSON Canonical Encoding Scheme*** — `datatracker.ietf.org/doc/html/rfc8785`. Required for deterministic signing.
3. **RFC 8037, *CFRG Elliptic Curve Diffie-Hellman (ECDH) and Signatures in JSON Object Signing and Encryption (JOSE)*** — defines EdDSA in JWS.
4. **RFC 7797, *JSON Web Signature (JWS) Unencoded Payload Option*** — for detached payloads.
5. **W3C, *JSON Web Signatures for Data Integrity Proofs*** (2024) — `w3.org/TR/vc-jws-2020`. Higher-level proof pattern built on JWS, useful for the auditable-log aspect.

---

## Question 6 — Recovery/Reconnection Handshake After a Safe-State Event

### Concrete mechanism

**ISO 10218-1:2025 renamed "safety-rated monitored stop" to "monitored standstill."** This is not just a name change: the 2025 revision clarified the recovery sequence, which was ambiguous in 2011.

**The required restart sequence, drawn from ISO 10218-1:2025 §5.4 (Stopping Functions) and ISO 13849-1 (Manual Reset as a Safety Function), is:**

1. **Cause of stop has been removed.** The protective stop was triggered by condition X (e.g., human in workspace); X must no longer be true. Verified by independent sensor (not the same one that triggered the stop).
2. **Manual reset.** A human operator must *physically* press a reset button on the robot's safety circuit. **This cannot be done remotely via the protocol.** ISO 13849-1 requires that the reset function be hard-wired (or implemented in safety-rated logic, e.g., via a safety PLC). The reset button is a Category-0 / Category-1 safety device.
3. **Self-test.** The robot runs a self-test sequence: (a) joint encoders report expected positions, (b) safety-rated inputs report their expected states, (c) emergency-stop circuit is closed, (d) [if applicable] the HNN physics model can be loaded and produces a valid output on a known test vector.
4. **Re-attestation.** The robot's TEE re-attests its boot state and signed code measurements, and the verifier (the consensus cluster or the client) confirms attestation freshness.
5. **Lease re-acquisition.** A new lease must be acquired from scratch, through the full Lease → Constitution → Shadow sequence. The previous lease is *not* resumed.
6. **Operator confirmation to start.** After the system is in the `Ready` state, the operator must *explicitly* command "start" — typically by pressing the start button, which is separate from the reset button. This two-button pattern (reset, then start) is mandatory under ISO 13849-1.

**Key invariants for P-MCP:**
- The protocol layer **must not** allow restart without positive operator confirmation. A "soft restart" via API would violate ISO 13849-1.
- The recovery handshake **must produce a new lease**, not resume the old one. This is required by the principle of *monotonicity* (the old lease is dead; its expiry is final).
- The self-test **must include a Shadow validation test** on a known-good test vector, to verify the HNN is still functioning correctly.

### Settled vs. Open

- **Settled (go implement):** "Recovery requires: cause-removed AND manual-reset AND self-test AND re-attestation AND new-lease AND operator-start." Every credible standard agrees; the ordering is fixed.
- **Settled (go implement):** "Manual reset must be a hardware (or safety-rated-logic) function, not a protocol message." This is a hard requirement from ISO 13849-1; a pure-software reset is non-conformant.
- **Settled (go implement):** "The new lease is fresh; the old lease is never resumed." This is required by lease monotonicity and matches the "sticky Safe State" pattern from Q2.
- **Open research problem (P-MCP must make a documented judgment call):** "What is the minimum self-test vector suite for the HNN physics validator?" There is no published methodology for designing self-test vectors for HNNs specifically. P-MCP should require: (a) at least one vector with known-safe physics output, (b) at least one vector with known-unsafe physics output (to verify the HNN doesn't always return "safe"), (c) a vector that triggers each of the HNN's failure modes (e.g., out-of-input-range, NaN, infinite output).
- **Open research problem (P-MCP must make a documented judgment call):** "For multi-robot systems, can recovery of robot A proceed while robot B is still in Safe State?" The standards are written for single-robot cells. For multi-robot fleets, P-MCP must decide whether recovery is per-robot (allowing partial recovery) or fleet-wide (requiring all robots in Safe State before any can recover). Per-robot recovery is more operationally flexible but more complex to verify.

### References to read in full

1. **ISO 10218-1:2025, §5.4 (Stopping Functions)** — `iso.org/standard/73933.html`. The current canonical requirements for protective stop, monitored standstill, and emergency stop.
2. **ISO 13849-1:2023, §5.5.3 (Manual reset)** — defines manual reset as a safety function, including the requirement for hard-wired or safety-rated-logic implementation.
3. **Hartmann et al. (2026), *Comparative analysis of ISO 10218-1/2 (2011 vs. 2025)*** — ScienceDirect. Documents the 2025 changes including the "monitored standstill" renaming.
4. **OSHA Technical Manual, Section IV Chapter 4** — `osha.gov/otm/section-4-safety-hazards/chapter-4`. U.S. regulatory perspective on robot safety, including the requirements around restart after a protective stop.

---

## Question 7 — Achievable SIL/Certification Ceiling for ML-Gated Safety Functions

### Concrete mechanism

**The current (2025-2026) regulatory position is restrictive.** IEC 61508 does *not* explicitly forbid ML in safety functions, but its technique tables (Part 3, Annex A) effectively rule out ML above SIL 1 because ML training does not produce the artifacts (formal specifications, traceable requirements, complete test coverage) that the technique tables demand at SIL 2 and above.

**The published position (consolidated from ISO/IEC TR 5469:2024 and recent industry commentary):**

- **SIL 1 is achievable** for ML components, with restrictive assumptions: deterministic execution, complete test coverage of the input domain (or formally-bounded OOD detection), version pinning (PCCP discipline per FDA), and the ML component is *not* the sole safety function — there must be a non-ML safety layer beneath it.
- **SIL 2 is achievable** only if the ML component is *advisory* (inform-and-inhibit), not *authoritative*. The ML says "this is unsafe" → the system stops; the ML is never the *only* thing that can stop the system. This pattern is what Ladkin (2024) calls an *"oracular subsystem"* — the ML is consulted as an oracle, but the safety function is implemented in conventional logic.
- **SIL 3 and above is not currently achievable** with ML in the safety loop. No published technique, no precedent certifications, no consensus on how to bound ML failure modes tightly enough.
- **SIL 4 is structurally out of reach** — IEC 61508 Part 3's technique requirements are incompatible with current ML practice.

**The AI-SIL proposal (Diemert, Critical Systems Labs, 2023)** is an extension to IEC 61508 specifically for AI components, using a "Level of Rigour" (LoR) methodology. It is a *proposal*, not a standard. It is not yet recognized by any certification body.

**What this means for P-MCP concretely:**

| Gate | SIL ceiling | Reason |
|------|-------------|--------|
| Lease acquisition (Raft + Ed25519 + TEE) | **SIL 3** | No ML; conventional consensus + crypto + TEE attestation. OPC-UA Part 15 has set this precedent. |
| Constitution check (rule evaluation) | **SIL 3** | Pure logic; no ML. |
| Shadow validation (HNN physics) | **SIL 1** as authoritative gate; **SIL 2** as advisory gate | ML is in the safety loop. To exceed SIL 1, the HNN must be *advisory only* — i.e., the HNN can veto an actuation, but a separate non-ML safety function must also be present and must be the one that physically interrupts motion. |
| E-Stop (hardware) | **SIL 3 / SIL 4** | Hardware-only, no ML, no consensus. The highest-assurance function in the system. |

**The defensible P-MCP target is therefore:**
- Non-ML gates target SIL 3.
- Shadow validation (HNN) targets SIL 1 as authoritative, OR SIL 2 as advisory.
- E-Stop targets SIL 3 (or SIL 4 if the deployment warrants it).
- The *composite* safety function (all gates together) is bounded by the lowest-SIL component in the chain — currently, that's the HNN at SIL 1. **This is the hard ceiling for the current P-MCP design unless the HNN is made advisory-only.**

### Settled vs. Open

- **Settled (go implement):** "ML in a safety function tops out at SIL 1 (authoritative) or SIL 2 (advisory only), per current IEC 61508 interpretation and ISO/IEC TR 5469:2024." This is the published regulatory position; it is not ambiguous.
- **Settled (go implement):** "ISO/IEC TR 5469:2024 is the bridge document for AI in functional safety. It is a Technical Report (not a standard), so it provides guidance but is not normative. P-MCP should cite it as the basis for its AI-safety argumentation."
- **Settled (go implement):** "The 'oracular subsystem' pattern (Ladkin 2024) is the defensible way to incorporate an ML gate at SIL 2. The ML can only *add* safety (veto), never *remove* it (authorize)."
- **Open research problem (P-MCP must make a documented judgment call):** "Is P-MCP's Shadow validation authoritative (SIL 1, full gate) or advisory (SIL 2, veto-only)?" This is the central architectural decision. The tradeoff: authoritative is simpler (no second safety layer needed) but caps the whole system at SIL 1; advisory allows SIL 2 but requires a parallel non-ML safety function (e.g., geometric envelope check, force-torque monitoring). P-MCP should pick *advisory* and document the parallel non-ML safety function.
- **Open research problem (P-MCP must make a documented judgment call):** "Will AI-SIL or a successor standard be formalized in the 2026–2028 IEC 61508 revision cycle?" The IEC working groups are actively discussing this but no formal timeline exists. P-MCP should design for current-state (SIL 1/2 ceiling) and monitor for regulatory evolution.
- **Open research problem (P-MCP must make a documented judgment call):** "For the HNN specifically — a physics-informed neural network with provable conservation properties — does the *physics-informed* nature lift the SIL ceiling?" This is genuinely unsettled. HNNs (Greydanus et al. 2019) have stronger guarantees than vanilla MLPs (Hamiltonian conservation is provable in the limit), but no certification body has ruled on whether this is sufficient to lift the SIL ceiling. P-MCP should not assume it does; if anything, treat HNNs as still-SIL-1-bounded and document the HNN's conservation properties as part of the safety case.

### References to read in full

1. **ISO/IEC TR 5469:2024, *Artificial intelligence — Functional safety and AI systems*** — `iso.org/standard/81283.html`. The bridge document. Read in full; it is the most important single reference for P-MCP's SIL argumentation. Clause 5 (functional safety overview), Clause 6 (AI technology), and the annexes on neural-network robustness assessment.
2. **Ladkin (2024), *Functional Safety and Oracular Subsystems: An Observation on ISO/IEC TR 5469*** — SCSC Journal, `scsc.uk/journal/index.php/scsj/article/view/32`. Short, foundational paper introducing the "oracular subsystem" pattern.
3. **Diemert et al. (Critical Systems Labs, 2023), *Safety Integrity Levels for Artificial Intelligence (AI-SIL)*** — `criticalsystemslabs.com/resources-hub/2023WAISEDiemertAbstract.pdf`. The proposed extension to IEC 61508 for AI components.
4. **Klüver et al. (2024), *A requirements model for AI algorithms in functional safety*** — `sands.edpsciences.org/articles/sands/full_html/2024/01/sands20240024/sands20240024.html`. Survey of the AI-SIL proposal and its relationship to IEC 61508.
5. **IEC 61508-3:2010, Annex A (Techniques table)** — read the tables for SIL 2 and SIL 3 carefully. This is where the "ML cannot satisfy" requirements come from.

---

## Synthesis: Three Decisions P-MCP Must Make Before Finalizing the Spec

The research converges on three architectural decisions that are *open research problems* but that P-MCP must commit to:

1. **Shadow validation: authoritative (SIL 1) or advisory (SIL 2)?** The recommended answer is *advisory*. This lifts the system-wide SIL ceiling from 1 to 2 by introducing a parallel non-ML safety function (geometric envelope + force-torque monitoring) as the authoritative gate, with the HNN as an additional veto layer. Document this explicitly in the spec.

2. **Cross-hardware HNN determinism budget `ε_max`:** P-MCP must establish this empirically per model version (test-vector replay on every supported hardware target) and document the methodology. There is no published shortcut. The `runtime_determinism_token` field is the wire-level mechanism.

3. **Lease TTL and `T_leader_unknown`:** P-MCP must derive these from physical safety bounds (robot stopping distance at max velocity, worst-case SSM response time per ISO/TS 15066), not from Raft defaults. This is a documented judgment call; the spec should include the derivation formula in an annex.

These three are the places where P-MCP cannot defer to a settled answer in the field — the field genuinely does not have one yet. Everything else in this document has a defensible, settled answer that P-MCP can implement directly.
