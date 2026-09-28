# P-MCP Project Explanation

This document provides a comprehensive explanation of P-MCP (Physical Model Context Protocol) from the ground up. Whether you're a developer, researcher, or simply curious about what this project does, this guide will walk you through everything you need to know.

---

## Table of Contents

1. [What is P-MCP?](#what-is-p-mcp)
2. [The Problem It Solves](#the-problem-it-solves)
3. [How P-MCP Works - Architecture Overview](#how-p-mcp-works---architecture-overview)
4. [Protocol Versions and Evolution](#protocol-versions-and-evolution)
5. [Core Concepts](#core-concepts)
6. [The Four Columns of Sovereignty](#the-four-columns-of-sovereignty)
7. [Getting Started](#getting-started)
8. [Code Structure and Files](#code-structure-and-files)
9. [Safety and Security](#safety-and-security)
10. [Supported Hardware](#supported-hardware)
11. [Future Roadmap](#future-roadmap)
12. [License and Contributing](#license-and-contributing)

---

## What is P-MCP?

**P-MCP (Physical Model Context Protocol)** is an open standard that enables any MCP-compatible AI client (like Claude Desktop, Cursor, ChatGPT, or custom LLM applications) to control physical robots safely.

Think of it as the "USB-C port for robot AI" - just as USB-C provides a universal connection between your computer and devices, P-MCP provides a universal connection between AI agents and physical robots.

### Key Highlights

- **Universal Integration**: Connect any AI assistant to any robot using the standard Model Context Protocol (MCP)
- **Safety First**: Mandatory "shadow preview" checks every command before execution
- **Production-Ready**: Version 0.5 has full MCP wire compatibility
- **Open Standard**: Apache 2.0 licensed - anyone can use and build upon it
- **Multi-Robot Support**: Coordinate fleets of robots without central control

---

## The Problem It Solves

Before P-MCP, connecting AI to robots was difficult and risky:

| Problem | Description | P-MCP Solution |
|---------|-------------|----------------|
| **API Fragmentation** | Every robot brand has a different API | Universal MCP tool calling |
| **Safety Risks** | LLMs can issue dangerous commands to hardware | Mandatory shadow validation before execution |
| **Collision Issues** | Multiple robots can crash into each other | Temporal lease system for zone ownership |
| **Bypassed Safety** | Hard safety rules can be ignored | TEE-signed safety constitution (ISO 10218 compliant) |
| **Integration Difficulty** | Hard to reuse robot integrations | pip-installable SDK + MCP registry |
| **Client Incompatibility** | Different AI clients work differently | Full MCP 2024-11-05 wire compatibility |

---

## How P-MCP Works - Architecture Overview

Here's how an AI assistant controls a robot using P-MCP:

```
┌─────────────────────────────────────────────────────────────────┐
│                    LLM AGENT (AI Assistant)                    │
│              (Claude / GPT / Ollama / Custom LLM)              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │  Standard MCP Protocol (JSON-RPC 2.0)
                             │  tool_use (JSON schema)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                       P-MCP SERVER (v0.5)                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Tool Registry (MCP tools)                  │   │
│  │   - move_to, grip, arm_move, navigation, etc.            │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │                                     │
│                     validate()                                   │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              SHADOW VALIDATOR (Pre-flight Check)         │   │
│  │   - Collision detection                                   │   │
│  │   - Safety envelope verification                         │   │
│  │   - Human clearance check                                │   │
│  │   - Energy cost estimation                               │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │                                     │
│              ProjectedOutcome (safe / risk / blocked)          │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   DIGITAL TWIN                           │   │
│  │   - Robot poses and workspaces                           │   │
│  │   - Temporal reservations                                │   │
│  │   - Sensor streams (resources)                          │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │                                     │
│                       confirm() → TEE gate                      │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   TEE COMMAND GATE (v0.3)                │   │
│  │   - Ed25519 DID signature verification                  │   │
│  │   - Safety Constitution enforcement (6 rules)            │   │
│  │   - HardwareToken (500ms TTL, replay-protected)         │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │                                     │
│                      token.consume()                            │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                HARDWARE BRIDGE LAYER                     │   │
│  │   ROS2 / OPC-UA / Serial / Viam / Custom                │   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
                    ┌───────────────┐
                    │   Physical    │
                    │     Robot     │
                    │  UR5/TurtleBot│
                    │   Spot/AMR    │
                    └───────────────┘
```

### The Flow in Plain English

1. **AI Request**: The AI assistant wants the robot to move to a specific position
2. **Tool Call**: The request comes through as a standard MCP tool call
3. **Shadow Validation**: The P-MCP server runs a "shadow" simulation to check if the move is safe
4. **Digital Twin**: The virtual representation of the robot verifies the move
5. **Safety Check**: The TEE (Trusted Execution Environment) gate verifies the command meets safety rules
6. **Hardware Execution**: The safe command is sent to the actual robot

---

## Protocol Versions and Evolution

P-MCP has evolved through multiple versions, each adding important capabilities:

| Version | Name | Key Features |
|---------|------|---------------|
| **v0.1** | Core Protocol | Basic schemas, shadow validator, digital twin, PMCPServer |
| **v0.2** | Production Upgrades | 4D temporal reservations, Vickrey auction, HIL torque feedback |
| **v0.3** | Sovereign Infrastructure | TEE safety constitution, Metabolic Twin, CRDT ledger |
| **v0.4** | Interoperable Autonomy | Dynamic tool synthesis, Visual shadow, ZK safety proofs, DePIN economy |
| **v0.5** | **Current** | Full MCP wire compatibility, clean SDK, registry, 3 robot servers |

### v0.5 - The Current Version

Version 0.5 is the first version with **full MCP wire compatibility**. This means:
- Claude Desktop can directly connect to P-MCP robot servers
- Cursor, ChatGPT, and any MCP client can control robots
- Clean, simple SDK for building your own robot servers
- Pre-built servers for: Arm robots, Mobile robots, Agricultural robots

---

## Core Concepts

### 1. MCP Tools (Actuations)

In P-MCP, robot actions are exposed as **MCP Tools**. Examples:

- `move_to` - Move robot to X, Y, Z position
- `gripper_open` / `gripper_close` - Control gripper
- `navigation` - Move mobile robot to waypoint
- `harvest` - Harvest crop

Each tool has:
- **Name**: Unique identifier
- **Description**: What the tool does
- **Parameters**: JSON schema for arguments
- **Constraints**: Safety limits (max speed, force, etc.)

### 2. Shadow Preview

Before any command reaches the physical robot, it goes through a **shadow validator** that:
- Simulates the motion in a digital twin
- Checks for collisions with obstacles
- Verifies the move stays within safety boundaries
- Calculates energy requirements

Only if the shadow check passes does the command proceed.

### 3. Digital Twin

The **digital twin** is a virtual representation of the physical world:
- Robot poses and configurations
- Workspace zones and boundaries
- Sensor readings and timestamps
- Temporal reservations for scheduling

### 4. Temporal Leases

When multiple robots need to work in the same area, **temporal leases** ensure they don't collide:
- Robots "lease" a zone for a specific time
- Competing robots can bid (Vickrey auction)
- Higher bids can take over the zone
- Expired leases are automatically released

### 5. Safety Constitution

The **Safety Constitution** is a set of immutable rules that cannot be violated:
- Based on ISO 10218 (industrial robot safety)
- Signed by TEE (Trusted Execution Environment)
- Enforced before every command execution

### 6. Resources (Sensor Streams)

P-MCP exposes robot data as **MCP Resources**:
- Joint angles, positions, velocities
- Camera feeds, depth maps
- Battery levels, temperature
- Custom sensor data

### 7. Prompts (Mission Templates)

Reusable prompt templates for common missions:
- "Pick and place sequence"
- "Patrol route"
- "Harvest workflow"

---

## The Four Columns of Sovereignty

P-MCP is built on four foundational pillars:

| Column | Technology | Purpose |
|--------|------------|---------|
| **Identity** | W3C DIDs + Ed25519 | Who is this machine? Can I trust its signature? |
| **Governance** | TEE Safety Constitution | What physical laws can't it break? |
| **Coordination** | Spatiotemporal CRDT Ledger | How to share 4D space without a central boss? |
| **Actuation** | P-MCP Tool Synthesis | How does a "thought" become motor torque? |

### Identity (W3C DIDs + Ed25519)

Every robot has a Decentralized Identifier (DID) and cryptographic keys for:
- Authentication - proving who the robot is
- Authorization - proving the robot has permission
- Non-repudiation - ensuring commands can't be denied later

### Governance (TEE Safety Constitution)

The Safety Constitution defines what robots **cannot** do:
1. Never exceed max speed in human presence
2. Never exceed max force thresholds
3. Never enter forbidden zones
4. Always maintain safe distance from humans
5. Emergency stop always succeeds
6. Never bypass safety sensors

These rules are signed by the TEE and cannot be modified or bypassed.

### Coordination (CRDT Ledger)

P-MCP uses Conflict-free Replicated Data Types (CRDTs) for:
- Zone reservations without central coordinator
- Fault-tolerant coordination across network partitions
- Horizontal scaling to 100+ robots

### Actuation (Tool Synthesis)

The "MacGyver Layer" can create new tools on-the-fly:
- LLM proposes a new tool from motor primitives
- Stress-test in 100+ simulations
- TEE certifies the tool as safe
- Tool becomes available to all robots

---

## Getting Started

### Quick Start (Single File)

The entire v0.1-v0.4 stack is in one self-contained file:

```bash
# Install dependencies
pip install cryptography pybullet anthropic

# Run the demo
python pmcp_grand_unified.py
```

### Using v0.5 (Recommended)

Connect Claude Desktop to a robot arm by adding this to your `claude_desktop_config.json`:

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

Run the demo:
```bash
python -m v05.main_pmcp_v5             # All demos
python -m v05.main_pmcp_v5 --demo arm  # Arm robot only
```

### Building Your Own Server

```python
from v05.pmcp_v5_server import PMCPServer
from v05.pmcp_v5_types  import ActuationResult, SensorReading, SensorType
import asyncio

server = PMCPServer("my-robot", robot_class="arm", model="UR5e")

@server.actuation("move_to", description="Move TCP to XYZ", max_speed_m_s=1.0)
async def move_to(x: float, y: float, z: float, speed: float = 0.3):
    # Call your real hardware here
    return ActuationResult(success=True, output={"x": x, "y": y, "z": z})

asyncio.run(server.run())  # stdio - compatible with Claude Desktop
```

---

## Code Structure and Files

```
P-MCP/
├── pmcp_grand_unified.py    # Single file: entire v0.1→v0.4 stack (2900+ lines)
│
├── v01/                      # v0.1 - Core schemas
│   └── pmcp_schemas.py       # Vec3, Pose, ToolCall, ToolResult, etc.
│
├── v02/                      # v0.2 - Production features
│   ├── pmcp_shadow.py        # Digital twin + ShadowValidator
│   ├── pmcp_server.py        # PMCPServer (invoke/confirm/auction)
│   ├── pmcp_llm_bridge.py    # PlanningAgent, HarvestOrchestrator
│   ├── robots_agents.py      # RoboticArmAgent, AMRAgent
│   ├── bridges_hardware.py   # ROS2, OPCUA, Serial, Viam, Zenoh
│   └── main_pmcp.py          # v0.2 demo (9 scenarios)
│
├── v03/                      # v0.3 - Sovereign infrastructure
│   ├── pmcp_tee.py           # TEE + DID + Safety Constitution
│   ├── pmcp_metabolic.py     # Crop growth model + Autonomous SLA
│   ├── pmcp_physics_hil.py   # PyBullet ghost + joint calibration
│   ├── pmcp_ledger.py        # CRDT G-Set + MeshLedgerNode
│   └── main_pmcp_v3.py       # v0.3 demo
│
├── v04/                      # v0.4 - Integrated into grand_unified
│   │                         # L13: DynamicToolSynthesizer
│   │                         # L14: VisionVoxelBridge
│   │                         # L15: ZKSafetyProver
│   │                         # L16: RoboWallet + DePIN
│
├── v05/                      # v0.5 - Current stable version
│   ├── pmcp_v5_server.py     # MCP-wire-compatible server
│   ├── pmcp_v5_types.py     # v0.5 type definitions
│   ├── pmcp_v5_client.py     # Client for connecting to servers
│   ├── pmcp_safety_v5.py     # Safety middleware and constitution
│   ├── pmcp_registry.py      # Service registry
│   ├── main_pmcp_v5.py       # Demo launcher
│   └── robot_servers/        # Pre-built robot servers
│       ├── arm_server.py     # Robot arm server (UR5, etc.)
│       ├── mobile_server.py  # Mobile robot server (TurtleBot, etc.)
│       └── agricultural_server.py  # Agricultural robot server
│
├── pmcp/                     # Core SDK package
│   ├── __init__.py
│   ├── client.py            # Base client
│   ├── server.py            # Base server
│   ├── types.py             # Type definitions
│   └── safety.py            # Safety utilities
│
├── examples/                 # Example implementations
│   ├── example_harvest_cycle.py
│   ├── example_safety_blocks.py
│   ├── example_multi_robot.py
│   └── generate_examples.py
│
├── docs/                    # Documentation
│   ├── README.md            # Main documentation
│   ├── PROTOCOL_SPEC.md     # Formal protocol specification
│   └── PROJECT_EXPLANATION.md  # This file
│
├── docker/                  # Docker configuration
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── mosquitto.conf
│
├── requirements.txt         # Python dependencies
└── pyproject.toml          # Project configuration
```

---

## Safety and Security

### Safety Layers

P-MCP implements multiple safety layers:

1. **Shadow Validator**: Simulates every command before execution
2. **Safety Constitution**: Immutable rules enforced by TEE
3. **Hardware Token**: 500ms TTL, one-time use, TEE-attested
4. **Emergency Stop**: Always succeeds, cannot be blocked
5. **Human Clearance**: Robots maintain safe distance from humans

### Security Features

- **Ed25519 Signatures**: Fast, secure cryptographic signatures
- **DID Authentication**: Decentralized identity for every robot
- **TEE Attestation**: Hardware-backed security guarantees
- **ZK Safety Proofs**: Verify safety without revealing proprietary data

### Compliance

- **ISO 10218**: Industrial robot safety standard
- **IEC 62443**: Industrial cybersecurity standard

---

## Supported Hardware

### Robots

- **Arm Robots**: Universal Robots (UR5, UR10, UR20), Franka Emika Panda
- **Mobile Robots**: TurtleBot, Spot, AMR (Autonomous Mobile Robots)
- **Agricultural Robots**: Harvesting robots, monitoring platforms

### Communication Protocols

- **ROS2**: MoveIt/Nav2 integration
- **OPC-UA**: Siemens, Beckhoff, Rockwell PLCs
- **Serial**: Arduino and custom serial devices
- **Viam**: Viam robotics platform
- **Zenoh**: P2P mesh transport

### Software Clients

- **Claude Desktop**: Native MCP support
- **Cursor**: AI-powered code editor
- **ChatGPT**: OpenAI's assistant
- **Ollama**: Local LLM deployment

---

## Future Roadmap

| Level | Name | Description |
|-------|------|-------------|
| 17 | Federated Learning | Robots share physics models without sharing raw data |
| 18 | Swarm Consciousness | Emergent coordination without explicit messaging |
| 19 | Biological Integration | Direct plant-to-robot signal (no camera needed) |
| 20 | Physical Turing Test | Can humans distinguish robot-coordinated vs human-run farms? |

---

## License and Contributing

### License

P-MCP is licensed under **Apache 2.0** - the same license used by many open-source projects including Kubernetes, Spark, and Swift. This means you can:

- Use it in commercial products
- Modify and distribute the code
- Use it privately
- Use it in patented products

### Contributing

The project welcomes contributions! Key areas for contribution:

- New robot server implementations
- Hardware bridge drivers
- Safety validators
- Documentation improvements
- Bug fixes and feature additions

### Resources

- **GitHub**: https://github.com/physicalcontextprotocol/pmcp-spec
- **Documentation**: https://github.com/physicalcontextprotocol/pmcp-spec/blob/main/docs/PROTOCOL_README.md
- **Protocol Spec**: https://github.com/physicalcontextprotocol/pmcp-spec/blob/main/docs/PROTOCOL_SPEC.md

---

## Quick Reference

### Installation

```bash
# Core (minimal)
pip install cryptography

# Full installation
pip install pmcp[full]

# Development
pip install pmcp[dev]
```

### Running a Robot Server

```python
from v05.pmcp_v5_server import PMCPServer
import asyncio

server = PMCPServer("my-robot")
# Add your actuations and sensors
asyncio.run(server.run())
```

### Connecting an AI Assistant

Add to your MCP client config:
```json
{
  "mcpServers": {
    "my-robot": {
      "command": "python",
      "args": ["path/to/robot_server.py"]
    }
  }
}
```

---

*Built by TIMPS (Trustworthy Interactive Memory Partner System)*
*Version: 0.5.0*
*License: Apache 2.0*