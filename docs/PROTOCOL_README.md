# P-MCP — Physical Model Context Protocol

> **P-MCP is the USB-C port for robot AI.**  
> An open standard that enables any MCP-compatible AI client to control physical robots safely.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Protocol Version](https://img.shields.io/badge/P--MCP-v0.5-green.svg)]()
[![MCP Compatible](https://img.shields.io/badge/MCP-2024--11--05-orange.svg)](https://modelcontextprotocol.io)
[![ISO 10218](https://img.shields.io/badge/ISO-10218-red.svg)]()

---

## What is P-MCP?

P-MCP (Physical Model Context Protocol) is to robots what Anthropic's [Model Context Protocol](https://modelcontextprotocol.io) is to data sources — a universal integration layer.

**v0.5 is the first version with full MCP wire compatibility:**  
Claude Desktop, Cursor, ChatGPT, and any MCP client can directly connect to P-MCP robot servers.

```
Claude Desktop / Cursor / ChatGPT / Custom LLM
            │
            │  Standard MCP Protocol (JSON-RPC 2.0)
            ▼
    ┌─────────────────────────────────────────┐
    │       P-MCP Server (robot-side)         │
    │                                         │
    │  tools/list    → Robot actuations       │
    │  tools/call    → Safety → Execute       │
    │  resources/*   → Sensor streams         │
    │  prompts/*     → Mission templates      │
    │  shadow/*      → Pre-flight simulation  │
    │  lease/*       → Zone ownership         │
    └──────────────────┬──────────────────────┘
                       │
             Safety Pipeline
       Constitution (ISO 10218) → Shadow → Execute
                       │
              Physical Robot Hardware
         UR5 · TurtleBot · Spot · PLC · AMR
```

---

## v0.5 Quick Start

### Connect Claude Desktop to a robot arm

Add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "robot-arm": {
      "command": "python",
      "args": ["/path/to/P-MCP/v05/robot_servers/arm_server.py"]
    }
  }
}
```

### Run the demo

```bash
python -m v05.main_pmcp_v5             # all demos
python -m v05.main_pmcp_v5 --demo arm  # arm robot only
```

### Build your own server

```python
from v05.pmcp_v5_server import PMCPServer
from v05.pmcp_v5_types  import ActuationResult, SensorReading, SensorType
import asyncio

server = PMCPServer("my-robot", robot_class="arm", model="UR5e")

@server.actuation("move_to", description="Move TCP to XYZ", max_speed_m_s=1.0)
async def move_to(x: float, y: float, z: float, speed: float = 0.3):
    # Call your real hardware here
    return ActuationResult(success=True, output={"x": x, "y": y, "z": z})

asyncio.run(server.run())  # stdio — compatible with Claude Desktop
```

---

## Why P-MCP?

| Problem | P-MCP Solution |
|---------|---------------|
| Every robot has a different API | `tools/list` + `tools/call` (universal MCP) |
| LLMs can't safely command hardware | Mandatory shadow preview before any execution |
| Multiple robots collide | Temporal lease system (zone ownership) |
| Hard safety rules bypassed | TEE-signed safety constitution (ISO 10218) |
| Can't reuse robot integrations | pip-installable SDK + MCP registry |
| LLM client incompatibility | Full MCP 2024-11-05 wire compatibility |

---

## Protocol Versions

| Version | Highlights |
|---------|-----------|
| **v0.1** | Core schemas, shadow validator, digital twin |
| **v0.2** | 4D temporal reservations, Vickrey auction, HIL torque |
| **v0.3** | TEE safety constitution, Metabolic Twin, Ghost Physics, CRDT |
| **v0.4** | ZK safety proofs, DePIN broker, Zenoh P2P transport |
| **v0.5** ✨ | **Full MCP wire compatibility**, clean SDK, registry, 3 robot servers |

---

---

## What This Is

P-MCP is an open protocol for **LLM-to-robot tool calling** — the bridge between
AI reasoning and physical-world actuation. It defines how an AI agent safely
invokes motor commands, with a layered stack of guarantees:

```
LLM Agent
    │  tool_use (JSON schema)
    ▼
PMCPServer  ──→  ShadowValidator  ──→  Digital Twin
    │                │                     │
    │          Ghost Physics (L11)    Metabolic Twin (L10)
    │          Vision Voxels (L14)    CRDT Ledger (L12)
    ▼
TEE Command Gate (L9)  ──→  HardwareToken
    │
    ▼
ROS2 / OPC-UA / Viam / Serial  ──→  Physical Robot
```

---

## The Four Columns of Sovereignty

| Column        | Technology                  | Purpose                                     |
|---------------|-----------------------------|---------------------------------------------|
| **Identity**  | W3C DIDs + Ed25519          | Who is this machine? Can I trust its sig?   |
| **Governance**| TEE Safety Constitution     | What physical laws can't it break?          |
| **Coordination**| Spatiotemporal CRDT Ledger| How to share 4D space without a central boss? |
| **Actuation** | P-MCP Tool Synthesis        | How does a "thought" become motor torque?   |

---

## Quick Start

### Single-File (Recommended)

The entire v0.1→v0.4 stack is in one self-contained file:

```bash
pip install cryptography pybullet anthropic   # all optional
python pmcp_grand_unified.py
```

No imports from other files needed. PyBullet, cryptography, and anthropic are
all optional — the system degrades gracefully with pure-Python fallbacks.

### Individual Modules

```bash
# v0.1/v0.2 — Core protocol
python v02/main_pmcp.py

# v0.3 — Sovereign Infrastructure Layer
python v03/main_pmcp_v3.py
```

---

## Protocol Versions

### v0.1 — Core Protocol
- `PMCPTool` / `PMCPResource` / `ToolCall` / `ToolResult` schemas
- `ShadowValidator` — pre-flight safety check before hardware executes
- `DigitalTwin` — in-memory world model (poses, zones, power budget)
- `PMCPServer` — tool registry + invoke → confirm pipeline
- `RoboticArmAgent` / `AMRAgent` — robot implementations
- `PlanningAgent` / `HarvestOrchestrator` — LLM bridge layer
- Hardware bridges: ROS2, OPC-UA, Serial, Viam

### v0.2 — Production Upgrades
- **4D Temporal Reservations** — space-time zone locking (`SpaceTimeSlot`)
- **AAS Semantic Capability** — robots discoverable by property, not name
- **Vickrey Second-Price Auction** — competing tool calls resolved economically
- **HIL Torque Feedback** — `joint_torque_error_nm` → self-healing physics model
- **Confirm Timeout Gate** — auto-abort if agent goes silent (safety)
- **Market Price Resource** — live energy/carbon spot price stream

### v0.3 — Sovereign Infrastructure Layer
- **Level 9: TEE Safety Constitution** — Ed25519 DID + 6 immutable hardware rules
  + `HardwareToken` (500ms TTL, replay-protected, TEE-signed)
  + `CertificationAuthority` — third-party robot safety certs
- **Level 10: Metabolic Twin** — APSIM-inspired crop growth model
  + Ball-Berry stomatal conductance + Penman-Monteith transpiration
  + `AutonomousSLAEngine` — stomata close → humidifier priority boost
- **Level 11: Physics HIL** — PyBullet ghost robot (geometric fallback)
  + Sub-millisecond pre-flight collision simulation
  + Per-joint `JointPhysicsState` — Bayesian friction/wear update
- **Level 12: Decentralized Ledger** — CRDT G-Set mesh coordination
  + `SpatiotemporalGSet` — conflict-free slot reservation
  + `MeshLedgerNode` — 100+ robots, no central coordinator

### v0.4 — Interoperable Autonomy
- **Level 13: Dynamic Tool Synthesis (MacGyver Layer)**
  + LLM proposes `SyntheticToolBlueprint` from motor primitives
  + `DynamicToolSynthesizer` stress-tests N=100+ simulations
  + TEE certifies with `safety_cert_hash` → `CONST-06` enforces min passes
- **Level 14: Visual Shadow (VLM/SAM Voxel Injection)**
  + `VisionVoxelBridge` converts camera detections → twin dynamic obstacles
  + Human/limb detections expand safety radius automatically
  + 330ms TTL voxels — stale detections auto-expire
  + `VisionSimulator` for testing without real cameras
- **Level 15: ZK-Safety Proofs (Privacy Layer)**
  + `ZKSafetyProver` — commitment scheme over shadow outcomes
  + Proprietary algorithm stays secret; safety is publicly verifiable
  + `ZKSafetyVerifier` — multi-tenant warehouse trust without data sharing
- **Level 16: Machine Economy (DePIN)**
  + `RoboWallet` — DID-backed economic entity
  + `U = Σ(V·P) − (C_energy + C_wear + C_risk)` utility function
  + Robots refuse unprofitable tasks and re-auction to the fleet
  + `DePINFleetManager` — Vickrey auction across economic agents

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         LLM AGENT                               │
│  (Claude / GPT / Local Ollama via RealClaudeAgent)              │
└────────────────────────────┬────────────────────────────────────┘
                             │  invoke(tool_name, **args)
                             │  [+ zk_proof optional L15]
┌────────────────────────────▼────────────────────────────────────┐
│                       PMCP SERVER v0.4                          │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐ │
│  │ Tool Registry│  │ ZK Verifier  │  │  Auction Pool         │ │
│  │ (static +    │  │ (L15)        │  │  (Vickrey v0.2)       │ │
│  │  synthetic)  │  └──────────────┘  └───────────────────────┘ │
│  └──────┬───────┘                                               │
│         │  validate()                                           │
│  ┌──────▼────────────────────────────────────────────────────┐  │
│  │              SHADOW VALIDATOR v0.4                        │  │
│  │  Tube collision · 4D temporal · Human clearance           │  │
│  │  Vision voxels (L14) · Ghost physics (L11) · AAS          │  │
│  └──────┬────────────────────────────────────────────────────┘  │
└─────────│───────────────────────────────────────────────────────┘
          │  ProjectedOutcome (safe / risk / energy / utility)
┌─────────▼───────────────────────────────────────────────────────┐
│                   DIGITAL TWIN v0.4                             │
│  Robot poses · Workspace zones · Temporal reservations          │
│  Plant health · Market prices · Vision voxels                   │
│  ┌─────────────────┐  ┌──────────────────────────────────────┐ │
│  │ MetabolicTwin   │  │ PyBulletGhostSimulator               │ │
│  │ (L10 crop model)│  │ (L11 pre-flight sim)                 │ │
│  └─────────────────┘  └──────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
          │  confirm() → TEE gate (L9)
┌─────────▼───────────────────────────────────────────────────────┐
│                   TEE COMMAND GATE v0.3                         │
│  Ed25519 DID sig · Safety Constitution (6 rules)               │
│  HardwareToken (500ms TTL · one-time · TEE-attested)           │
└─────────┬───────────────────────────────────────────────────────┘
          │  token.consume() → hardware ACK
┌─────────▼───────────────────────────────────────────────────────┐
│              HARDWARE BRIDGE LAYER                              │
│  ROS2 (MoveIt/Nav2) · OPC-UA · Serial/Arduino · Viam          │
│  Zenoh P2P mesh · DID-signed commands                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Map

```
pmcp_grand_unified.py     ← SINGLE FILE: entire v0.1→v0.4 stack (2900+ lines)
│
├── v01/
│   └── pmcp_schemas.py          ← v0.1 data types (Vec3, Pose, ToolCall, ...)
│
├── v02/
│   ├── pmcp_shadow.py           ← Digital twin + ShadowValidator
│   ├── pmcp_server.py           ← PMCPServer (invoke/confirm/auction/HIL)
│   ├── pmcp_llm_bridge.py       ← PlanningAgent, HarvestOrchestrator, RealClaudeAgent
│   ├── robots_agents.py         ← RoboticArmAgent, AMRAgent, HarvesterRobot
│   ├── bridges_hardware.py      ← ROS2, OPCUA, Serial, Viam, Zenoh, DID stubs
│   └── main_pmcp.py             ← v0.2 demo (9 scenarios)
│
├── v03/
│   ├── pmcp_tee.py              ← TEE + Ed25519 DID + Safety Constitution (L9)
│   ├── pmcp_metabolic.py        ← Crop growth model + Autonomous SLA (L10)
│   ├── pmcp_physics_hil.py      ← PyBullet ghost + joint calibration (L11)
│   ├── pmcp_ledger.py           ← CRDT G-Set + MeshLedgerNode (L12)
│   └── main_pmcp_v3.py          ← v0.3 demo (4 sovereign infrastructure layers)
│
├── v04/                         ← Integrated into pmcp_grand_unified.py
│   │   # L13: DynamicToolSynthesizer (MacGyver Layer)
│   │   # L14: VisionVoxelBridge + VisionSimulator
│   │   # L15: ZKSafetyProver + ZKSafetyVerifier
│   │   # L16: RoboWallet + DePINFleetManager
│
├── docs/
│   ├── README.md                ← This file
│   ├── PROTOCOL_SPEC.md         ← Formal protocol specification
│   └── ARCHITECTURE.md          ← System architecture deep-dive
│
├── examples/
│   ├── example_harvest_cycle.py ← Minimal harvest demo
│   ├── example_safety_blocks.py ← Safety and TEE veto examples
│   └── example_multi_robot.py   ← Multi-robot auction + ledger
│
└── requirements.txt             ← All dependencies
```

---

## Dependencies

```bash
# Core (no extras needed — pure Python fallbacks for everything)
python >= 3.9

# Level 9: TEE + DID (highly recommended)
pip install cryptography

# Level 11: Physics HIL (optional — geometric fallback always available)
pip install pybullet pybullet_data

# LLM Bridge (optional)
pip install anthropic

# Hardware bridges (optional — only needed for real robots)
pip install asyncua        # OPC UA (Siemens, Beckhoff, Rockwell)
pip install pyserial       # Arduino/Serial
pip install viam-sdk       # Viam robotics
pip install eclipse-zenoh  # P2P mesh transport
# ROS2: follow ros.org installation for your distro
```

---

## Key Design Decisions

**Why a single file?**  
Zero import friction. Clone the repo, run `python pmcp_grand_unified.py`.
No module path configuration. All optional deps handled with try/except.

**Why geometric fallback over PyBullet-only?**  
Sub-0.5ms capsule-link collision detection is sufficient for most farm
environments. PyBullet drops in transparently when installed.

**Why CRDT over central ledger?**  
Horizontal scaling. Adding robot 101 requires zero server changes —
it joins the mesh, reads existing claims, self-schedules. Works across
network partitions (merge on reconnect).

**Why Vickrey (second-price) auction?**  
Truth-revelation incentive — agents bid their true valuation.
No game-theoretic incentive to underbid. Economic optimum is stable.

**Why Ed25519 over RSA?**  
32-byte keys, 64-byte signatures, fast verify (~0.1ms). Critical for
500ms TEE token TTL. No key generation entropy issues.

---

## Production Notes

1. **TEE**: Replace `TEESimulator` with OP-TEE Trusted Application (ARM TrustZone)
   or Intel SGX enclave. Same Python API surface, different execution boundary.

2. **PyBullet**: Use `p.DIRECT` (headless) mode. Pre-load URDF at startup,
   not per-call, to stay under 10ms per validation.

3. **Zenoh**: Replace `ZenohBridge` stubs with `import zenoh`.
   Key space: `farm/{wing}/{robot_id}/{tool_type}`.

4. **ZK Proofs**: Replace hash-commitment scheme with PLONK/Groth16 circuits
   via Circom + SnarkJS. Shadow validator constraints become arithmetic circuits.

5. **DePIN Token**: Replace USD accounting in `RoboWallet` with ERC-20 on
   Polygon or Solana. TEE signs transactions; smart contract settles.

---

## Phase 3 & 4 Components (v0.5+)

### Plugin Marketplace (`marketplace/`)
A pip-installable REST API for distributing P-MCP plugins:
- SQLite/FTS5 backend with full-text search over plugin descriptions
- SHA-256 archive verification on upload and install
- Review system, category browsing, download stats
- `plugin_sdk.py` — `PluginLoader` for ZIP-based plugin installation + dynamic import
- Runs on port 9000: `pmcp-marketplace`

### DePIN Token Economy (`depin/`)
Off-chain ERC-20-style robot token ledger with staking and auctions:
- `RobotToken` — in-process ledger with mint/transfer/history (Decimal precision)
- `StakeManager` — MIN_STAKE=100 tokens before a robot can bid
- `WorkAuction` — first-price sealed-bid with collateral locking
- `RewardEngine` — quality-score-weighted reward distribution
- Runs on port 9001: `pmcp-depin`

### Dynamic Tool Synthesis v2 (`pmcp/tools/synthesis.py`)
Auto-compose P-MCP tool schemas from intent + robot capability profile:
- `CapabilityProfile` — classifies a robot's available actuations/sensors
- `BUILTIN_TEMPLATES` — pick_and_place, patrol_waypoints, inspect_joints, charge_and_resume
- Python codegen produces a `SynthesisedTool` with full JSON Schema
- Optional LLM backend for unmatched intents

### Federated Physics (`physics-federation/`)
FedAvg over robot experience without sharing raw data:
- `PhysicsModel` — NumPy 2-layer MLP for dynamics prediction
- `ExperienceBuffer` — capacity-10,000 ring buffer per robot
- `Aggregator` — weighted FedAvg aggregation with submission deduplication
- `FederatedNode` — observe → train_local → submit_update → pull_global
- Runs on port 9002

### Human-AI Multisig (`multisig/`)
Approval gate for high-risk commands requiring multi-party sign-off:
- `MultisigPolicy` — quorum check (M-of-N parties)
- `RiskScorer` — heuristic 0.0–1.0 risk scoring based on command + pose magnitude
- 30-second expiry loop rejects stale approvals automatically
- Runs on port 9003: `pmcp-multisig`

### Swarm COO (`swarm/`)
Autonomous Chief Operating Officer for multi-robot fleets:
- Priority task queue (CRITICAL → LOW) backed by `heapq`
- `Dispatcher` — weighted scoring: distance 40%, battery 30%, capability 20%, load 10%
- `Monitor` — heartbeat timeout detection with automatic task requeue
- Full fleet KPI reporting
- Runs on port 9010: `pmcp-swarm-coo`

### ISO/IEC Compliance Harness (`compliance/`)
Automated standard compliance checks against any live P-MCP robot:
- **ISO 10218-1/2** — E-stop cycle, actuation blocking, lease mechanism, metrics
- **IEC 62443-3-3** — Protocol version, robot ID uniqueness, ping latency < 500 ms
- **ISO 13849-1** — Safety controller declaration
- CLI: `pmcp-compliance --url http://robot:8080 --standard all --output report.json`
- Exit code 0 = compliant, 1 = failures found

### Edge Hardening (`edge/`)
Security hardening for resource-constrained edge deployments:
- `InputValidator` — strict allowlist regex + depth-limited parameter validation
- `RateLimiter` — per-peer token bucket (100 req capacity, 10 req/s)
- `TLSConfig` — TLS 1.3-only server/client context builder
- `ResourceGuard` — asyncio.wait_for wrapper enforcing max task time
- `SecureLogger` — redacts sensitive fields (keys, tokens, passwords) from logs
- `EdgeHardeningMiddleware` — drop-in aiohttp middleware combining all layers
- Security headers: HSTS, X-Content-Type-Options, X-Frame-Options, Cache-Control: no-store
- `benchmarks.py` — local throughput benchmarks (100k req/s input validation) + remote latency (P50/P95/P99)

### Reference Implementations (`reference_impl/`)
End-to-end worked examples:
- `hospital_robot.py` — medication delivery robot with RFID verification, occupancy check, lease-gated navigation
- `smart_factory.py` — 4-robot manufacturing cell (UR5 arm + Panda arm + TurtleBot AMR + Vision system)

---

## Roadmap Beyond v0.4

| Level | Name                    | Description                                          |
|-------|-------------------------|------------------------------------------------------|
| 17    | Federated Learning      | Robots share joint physics models without sharing raw data |
| 18    | Swarm Consciousness     | Emergent coordination without explicit messaging     |
| 19    | Biological Integration  | Direct plant-to-robot signal (no camera needed)     |
| 20    | Physical Turing Test    | Can a human distinguish robot-coordinated vs human-run farm? |

---

## License

Apache 2.0 — Build on this. The physical layer of the web should be open.

---

*Built by TIMPS (Trustworthy Interactive Memory Partner System)*  
*GitHub: github.com/physicalcontextprotocol*
