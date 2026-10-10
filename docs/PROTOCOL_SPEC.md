# PCP Protocol Specification

**Version:** 0.5  
**Spec Date:** 2026-05-21  
**Status:** Draft Standard  
**License:** Apache 2.0  
**MCP Alignment:** 2024-11-05  

---

## Abstract

The **Physical Context Protocol (PCP)** is an open protocol that standardizes how AI/LLM applications communicate with physical robot systems. PCP is to robots what the Model Context Protocol (MCP) is to data sources: a universal integration layer that eliminates the need for custom one-off robot drivers in every AI application.

PCP extends JSON-RPC 2.0 with **five physical primitives** and a mandatory **three-layer safety pipeline**. Any compliant PCP server (robot) can be connected to any compliant PCP client (LLM application) without modification.

> **PCP is the USB-C port for robot AI. Standardize once, connect everything.**

---

## Table of Contents

1. [Motivation](#1-motivation)
2. [Architecture Overview](#2-architecture-overview)
3. [Protocol Foundation](#3-protocol-foundation)
4. [Lifecycle](#4-lifecycle)
5. [Physical Primitives](#5-physical-primitives)
6. [Safety Pipeline](#6-safety-pipeline)
7. [JSON-RPC Methods](#7-json-rpc-methods)
8. [Error Codes](#8-error-codes)
9. [Transport](#9-transport)
10. [Security](#10-security)
11. [Conformance](#11-conformance)
12. [MCP Wire Compatibility (v0.5)](#12-mcp-wire-compatibility-v05)
13. [LLM Integration (Grok / Claude / GPT)](#13-llm-integration)

---

## 1. Motivation

Modern AI agents can reason and plan, but have no standardized way to act in the physical world. Every robotics team builds custom robot drivers, custom LLM prompts, custom safety shims, and custom simulation harnesses — duplicated across the industry.

| Problem | PCP Solution |
|---------|---------------|
| Every robot has a different API | `actuations/list` + `actuations/call` (universal) |
| LLMs can't safely command hardware | Mandatory shadow preview before execution |
| Multiple robots collide | Temporal lease system (zone ownership) |
| Hard safety rules can be bypassed | TEE-signed safety constitution |
| Can't reuse robot integrations | pip-installable SDK + driver registry |

---

## 2. Architecture Overview

```
 LLM / AI Application  (Claude, GPT-4, Gemini, custom)
           |
           |  PCP Protocol (JSON-RPC 2.0)
           |
     PMCPClient SDK             pip install physicalcontextprotocol
       list_actuations()
       shadow_preview()         <- safety-first API
       request_lease()
       call_actuation()
           |
           |  stdio / HTTP transport
           |
     PMCPServer SDK             pip install physicalcontextprotocol
       @server.actuation()
       @server.sensor()
       SafetyMiddleware
           |
    Robot Hardware    Shadow Simulator     Safety Constitution
    (UR5, Arduino,    (PyBullet/MuJoCo/    (TEE-signed
     PLC, mobile)      Isaac Sim)           ISO rules)
```

| Component | Role |
|-----------|------|
| **PMCPClient** | LLM-side: discovers, previews, leases, calls |
| **PMCPServer** | Robot-side: hosts actuations + sensors |
| **SafetyMiddleware** | Lease + constitution + shadow pipeline (plus e-stop latch checked first) |
| **Shadow Simulator** | Pre-flight 3D simulation (pluggable) |
| **Safety Constitution** | TEE-signed hard rules (ISO 10218 / IEC 62443) |
| **Lease Manager** | Temporal zone ownership (Vickrey auction) |

---

## 3. Protocol Foundation

### 3.1 JSON-RPC 2.0

PCP uses JSON-RPC 2.0 as the base message format, identical to MCP.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": "a1b2c3d4",
  "method": "actuations/call",
  "params": { "name": "move_to", "arguments": { "x": 0.3, "y": 0, "z": 0.5 } }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "a1b2c3d4",
  "result": { "content": [{ "type": "actuation", "data": { "success": true } }] }
}
```

**Error Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "a1b2c3d4",
  "error": { "code": -33001, "message": "Shadow preview blocked: Z below floor" }
}
```

**Notification** (no id, no response expected):
```json
{ "jsonrpc": "2.0", "method": "notifications/initialized", "params": {} }
```

### 3.2 Protocol Version

Current: `"0.5"` (matches `PMCP_VERSION` in all three reference SDKs --
`pcp-python`, `pcp-rust` -- exactly; confirmed by direct inspection, not
just asserted). Clients MUST send `protocolVersion` in `initialize`.
Servers MUST respond with the version they will use.

Note this is distinct from the JSON Schema file version
(`pcp-spec/schema/v0.6.0/pmcp.schema.json`), which versions the schema
document itself and may run ahead of the wire protocol version as new
message fields are specified before every SDK implements them (e.g.
`fence_token`, added in schema v0.6.0). The two version numbers are not
required to match.

---

## 4. Lifecycle

```
Client                                   Server
  |-- initialize ----------------------->|
  |<-- {protocolVersion, capabilities} --|
  |-- notifications/initialized -------->|
  |                                      |
  |-- actuations/list ------------------>|
  |<-- {actuations: [...]} --------------|
  |                                      |
  |-- shadow/preview ------------------->|   <- safety first
  |<-- {preview: {safe: true}} ----------|
  |                                      |
  |-- lease/request -------------------->|   <- claim zone
  |<-- {lease: {granted: true}} ---------|
  |                                      |
  |-- actuations/call ------------------>|   <- hardware moves
  |<-- {content: [{data: ...}]} ---------|
  |                                      |
  |-- lease/release -------------------->|   <- free zone
  |<-- {released: true} -----------------|
```

### 4.1 Capability Negotiation

```json
{
  "capabilities": {
    "actuations":   { "listChanged": true },
    "sensors":      { "streaming": false },
    "shadow":       {},
    "constitution": {},
    "leases":       {}
  }
}
```

Clients MUST NOT call methods for undeclared capabilities.

---

## 5. Physical Primitives

PCP defines five physical primitives:

| # | Primitive | MCP Equivalent | Purpose |
|---|-----------|---------------|---------|
| 1 | **Actuations** | Tools | Physical movement commands |
| 2 | **Sensors** | Resources | Physical data streams |
| 3 | **Prompts** | Prompts | Safety/interaction templates |
| 4 | **Shadow Preview** | _(new)_ | Pre-flight ghost simulation |
| 5 | **Temporal Leases** | _(new)_ | Zone ownership tokens |

### 5.1 Actuations

```json
{
  "name": "move_to",
  "description": "Move TCP to absolute XYZ position",
  "inputSchema": {
    "type": "object",
    "properties": {
      "x":     { "type": "number", "x-unit": "m" },
      "y":     { "type": "number", "x-unit": "m" },
      "z":     { "type": "number", "x-unit": "m", "minimum": 0.01 },
      "speed": { "type": "number", "default": 0.3, "maximum": 1.0, "x-unit": "m/s" }
    },
    "required": ["x", "y", "z"]
  },
  "physical": {
    "maxSpeed": 1.0,
    "requiresLease": true,
    "shadowRequired": true,
    "robotClass": "arm",
    "safetyCategory": "motion"
  }
}
```

If `shadowRequired: true`, the server MUST run shadow preview before hardware execution.

### 5.2 Sensors

URI format: `pmcp://sensor/{name}`

```json
{
  "name": "joint_angles",
  "uri": "pmcp://sensor/joint_angles",
  "description": "Current joint positions (6 DOF)",
  "mimeType": "application/pmcp-sensor",
  "physical": {
    "sensorType": "position",
    "unit": "rad",
    "sampleRateHz": 100.0,
    "streaming": false
  }
}
```

**Sensor reading:**
```json
{
  "sensorName": "joint_angles",
  "value": [0.1, -0.2, 0.5, 0.0, 1.1, 0.0],
  "unit": "rad",
  "timestamp": 1714832400.123,
  "quality": 1.0
}
```

### 5.3 Prompts

Identical to MCP Prompts — reusable templates for safety workflows and operator interactions.

### 5.4 Shadow Preview

Ghost simulation of full trajectory before any hardware moves.

**Request:**
```json
{
  "method": "shadow/preview",
  "params": {
    "actuationName": "move_to",
    "robotId": "arm-01",
    "arguments": { "x": 0.3, "y": 0, "z": 0.5, "speed": 0.3 }
  }
}
```

**Response (safe):**
```json
{
  "preview": {
    "status": "safe",
    "safe": true,
    "predictedPose": { "x": 0.3, "y": 0.0, "z": 0.5 },
    "durationS": 1.67,
    "energyJ": 124.5,
    "collisions": [],
    "violations": [],
    "shadowToken": "a1b2c3d4e5f6g7h8"
  }
}
```

**Response (blocked):**
```json
{
  "preview": {
    "status": "floor_guard",
    "safe": false,
    "violations": ["Z=-0.05 below floor plane (z=0)"],
    "collisions": ["floor"]
  }
}
```

### 5.5 Temporal Leases

Prevent concurrent zone occupancy via Vickrey auction allocation.

**Request:**
```json
{
  "method": "lease/request",
  "params": { "robotId": "arm-01", "zoneId": "workspace-A",
              "durationMs": 10000, "bidEnergyJ": 200.0 }
}
```

**Response (granted):**
```json
{
  "lease": { "leaseId": "wsa-a1b2c3d4", "granted": true, "expiresAt": 1714832410.0 }
}
```

---

## 6. Safety Pipeline

Every `actuations/call` MUST pass all three layers before hardware moves.
Actual gate order (matches the reference SDK implementations in
`pcp-python`/`pcp-rust` exactly -- this diagram previously showed
Constitution -> Shadow -> Lease, which was a real spec/code mismatch,
confirmed and corrected):

```
actuations/call received
        |
        v
[0. E-STOP LATCH]   Checked first, unconditionally. Bypasses everything
        |            below -- see section 6.1. Not part of the numbered
        |            gate sequence since it isn't a per-actuation check.
        v
[1. LEASE CHECK]    Zone ownership + fencing token. Anti-collision guarantee.
        | valid?
        v
[2. CONSTITUTION]   TEE-signed hard rules. Cannot be overridden by client.
        | cleared?
        v
[3. SHADOW PREVIEW] Ghost simulation. Runs full trajectory before hardware moves.
        | safe?
        v
   HARDWARE EXECUTES
```

### Built-in Constitution Rules

The reference SDK ships eight named rules. The **rule identities and check
semantics** below are normative; the **numeric thresholds** are non-normative
reference defaults sized for a small collaborative arm in a lab cell. Real
deployments MUST re-derive these from the robot's ISO 10218-2 / ISO/TS 15066
risk assessment, and the constitution fingerprint returned by
`pmcp/constitution` MUST change whenever any threshold changes.

| Rule ID | Semantics (normative) | Reference default (non-normative) |
|---------|-----------------------|-----------------------------------|
| CONST-01 | Commanded/executed speed bounded above by a per-robot limit | 2.0 m/s |
| CONST-02 | Target Z bounded below (floor guard) | 0.0 m |
| CONST-03 | Estimated kinetic-plus-payload energy bounded above | 50,000 J |
| CONST-04 | Shadow-preview freshness bound (max age accepted at gate time) | 2 s |
| CONST-05 | Peak commanded/measured force bounded above | 500 N |
| CONST-06 | E-Stop latch MUST be clear before any actuation is admitted | — (boolean) |
| CONST-07 | Human-proximity minimum standoff (via workspace sensor) | 0.5 m |
| CONST-08 | Actuation call ID length bound (correlation-id hygiene) | 8 characters |

Servers MAY add custom rules. CONST-01, CONST-02, CONST-06 MUST NOT be removed
without explicit operator override + audit log. When a server changes a
reference default, it SHOULD advertise both the rule ID and the concrete
threshold in the response of `pmcp/constitution` so clients can reason about
what is enforced without guessing.

> Note on internal consistency: the `move_to` example inputSchema in §5.1
> pins `speed.maximum: 1.0` m/s. That is a per-tool inputSchema bound (a
> tighter contract advertised for that specific tool), not the global
> constitution bound in CONST-01 (2.0 m/s). Both bounds apply; the server
> MUST reject a call that exceeds either.

### 6.1 E-Stop

`pmcp/estop` is a first-class message type, not an error code, precisely
so it cannot inherit the gate pipeline's latency or failure modes. When
active, it MUST block every actuation call for the affected robot before
any other check runs (lease, constitution, shadow, or rate limit) --
reference SDK implementations check it as an unconditional latch at the
very top of the actuation-call handler. `stop_category` on an
`EStopMessage` is always `0` (IEC 60204-1 Category 0: immediate,
uncontrolled power removal); controlled-deceleration (1) and graceful (2)
stops are represented by other, non-E-Stop mechanisms.

An active E-Stop MUST NOT clear implicitly -- not on lease expiry, not on
a new lease/actuation request, not on reconnect. Clearing it requires an
explicit `pmcp/estop_reset` call, which reference SDKs log as a distinct
audit event so the reset itself is attributable.

Because every millisecond matters in a real emergency, `pmcp/estop` is
available both as a JSON-RPC request (with a confirmation response) and
as a notification (fire-and-forget, no round trip required).

---

## 7. JSON-RPC Methods

| Method | Direction | Description |
|--------|-----------|-------------|
| `initialize` | C→S | Handshake |
| `notifications/initialized` | C→S | Client ready |
| `ping` | C→S | Health check |
| `actuations/list` | C→S | List actuations |
| `actuations/call` | C→S | Execute actuation |
| `sensors/list` | C→S | List sensors |
| `sensors/read` | C→S | Read sensor value |
| `prompts/list` | C→S | List prompts |
| `prompts/get` | C→S | Get rendered prompt |
| `shadow/preview` | C→S | Ghost simulation |
| `constitution/check` | C→S | Evaluate against rules |
| `lease/request` | C→S | Request zone lease |
| `lease/release` | C→S | Release lease |
| `pmcp/estop` | C→S | Emergency stop. First-class, lease-independent -- bypasses the Lease/Constitution/Shadow pipeline entirely (see section 6). Available as both a request and a notification for lowest possible latency. |
| `pmcp/estop_reset` | C→S | Clear an active E-Stop latch. Always a distinct, explicit, auditable call -- never implicit via a new lease or actuation request. |

---

## 8. Error Codes

### Standard JSON-RPC 2.0

| Code | Name |
|------|------|
| -32700 | Parse Error |
| -32600 | Invalid Request |
| -32601 | Method Not Found |
| -32602 | Invalid Params |
| -32603 | Internal Error |

### PCP Physical Safety (-33xxx)

| Code | Name | Meaning |
|------|------|---------|
| -33001 | SHADOW_BLOCKED | Trajectory unsafe |
| -33002 | CONSTITUTION_BLOCKED | Safety rule violated |
| -33003 | LEASE_REQUIRED | No valid zone lease |
| -33004 | LEASE_EXPIRED | Lease expired |
| -33005 | ESTOP_ACTIVE | Emergency stop active |
| -33006 | FLOOR_GUARD | Z below floor |
| -33007 | SPEED_LIMIT | Speed exceeded |
| -33008 | ENERGY_BUDGET | Budget exhausted |
| -33009 | HUMAN_PROXIMITY | Human too close |
| -33010 | ZK_PROOF_INVALID | ZK proof failed |

---

## 9. Transport

### stdio (Primary)

Newline-delimited JSON-RPC over stdin/stdout. Identical to MCP stdio transport.

```bash
python my_robot_server.py   # reads stdin, writes stdout
```

### HTTP

POST /pmcp — Content-Type: application/json

```bash
curl -X POST http://arm-01.local:8080/pmcp \
  -d '{"jsonrpc":"2.0","id":"1","method":"actuations/list","params":{}}'
```

### Zenoh P2P (Optional)

For multi-robot mesh networks. Topic: `pmcp/{farm_id}/{node_id}/rpc`

---

## 10. Security

- Safety constitutions MUST be signed with Ed25519 keys stored in a TEE
- HTTP transport MUST use TLS in production
- Lease tokens SHOULD be cryptographically signed
- ZK safety proofs available for high-assurance deployments (v04 module)

---

## 11. Conformance

| Level | Name | Requirements |
|-------|------|-------------|
| **L1** | Basic | `initialize`, `actuations/list`, `actuations/call`, CONST-01 + CONST-02 |
| **L2** | Safe | L1 + `shadow/preview`, `lease/request/release`, all 8 CONST rules |
| **L3** | Full | L2 + `sensors/*`, physics engine shadow, TEE constitution, ZK proofs |

---

## Reference Implementation

```bash
pip install physicalcontextprotocol
```

```python
from pmcp.server import PMCPServer
from pmcp.safety import SafetyMiddleware
from pmcp.types  import ActuationResult, SensorReading, SensorType

safety = SafetyMiddleware.default(robot_id="arm-01")
server = PMCPServer("ur5-arm", safety_middleware=safety)

@server.actuation("move_to", description="Move TCP to XYZ", max_speed_m_s=1.0)
async def move_to(x: float, y: float, z: float, speed: float = 0.3):
    return ActuationResult(success=True, final_pose={"x": x, "y": y, "z": z})

@server.sensor("joint_angles", sensor_type=SensorType.POSITION, unit="rad")
async def read_joints():
    return SensorReading(value=[0.0, -1.57, 1.57, 0.0, 0.0, 0.0], unit="rad")

if __name__ == "__main__":
    import asyncio
    asyncio.run(server.run())
```

**Source:** https://github.com/physicalcontextprotocol/pcp-spec  
**License:** Apache 2.0

---

## 12. MCP Wire Compatibility (v0.5)

PCP v0.5 achieves full **MCP 2024-11-05 wire compatibility**. A PCP server is a valid MCP server — any MCP client (Claude Desktop, Cursor, Cline, custom apps) can connect without modification.

### 12.1 Mapping

| PCP Concept | MCP Primitive | Wire Method |
|---------------|---------------|-------------|
| Actuation | Tool | `tools/list`, `tools/call` |
| Sensor | Resource | `resources/list`, `resources/read` |
| Mission | Prompt | `prompts/list`, `prompts/get` |
| Shadow Preview | Tool call (internal) | `shadow/preview` (PCP extension) |
| Lease | Tool call (internal) | `lease/request`, `lease/release` |
| Identity | Resource | `identity/get` |
| Constitution | Resource | `constitution/get` |

### 12.2 Tool Schema Generation

PCP automatically generates MCP-compatible tool schemas from actuation decorators:

```python
@server.actuation("move_to", description="Move TCP to XYZ", max_speed_m_s=1.0)
async def move_to(x: float, y: float, z: float, speed: float = 0.3):
    ...
```

Becomes the MCP tool schema:

```json
{
  "name": "move_to",
  "description": "Move TCP to XYZ",
  "inputSchema": {
    "type": "object",
    "properties": {
      "x":     {"type": "number"},
      "y":     {"type": "number"},
      "z":     {"type": "number"},
      "speed": {"type": "number", "default": 0.3}
    },
    "required": ["x", "y", "z"]
  },
  "x-pmcp": {
    "category":       "motion",
    "max_speed_m_s":  1.0,
    "safety_checked": true
  }
}
```

The `x-pmcp` extension namespace carries PCP-specific metadata; MCP clients that don't understand it ignore it safely.

### 12.3 Transport

| Transport | How to use |
|-----------|-----------|
| **stdio** | `asyncio.run(server.run())` — connects to Claude Desktop, Cursor via config |
| **HTTP** | `asyncio.run(server.run("http", port=8080))` — REST + SSE |
| **WebSocket** | `asyncio.run(server.run("ws", port=8080))` — streaming sensors |

### 12.4 Claude Desktop Quick Connect

```json
{
  "mcpServers": {
    "factory-arm": {
      "command": "python",
      "args": ["/path/to/PCP/v05/robot_servers/arm_server.py"]
    },
    "warehouse-mobile": {
      "command": "python",
      "args": ["/path/to/PCP/v05/robot_servers/mobile_server.py"]
    }
  }
}
```

---

## 13. LLM Integration

PCP is LLM-agnostic. Any model with tool-calling / function-calling support can act as the planner.

### 13.1 Supported LLM Planners

| LLM | API | Notes |
|-----|-----|-------|
| **Grok (xAI)** | OpenAI-compatible | `base_url="https://api.x.ai/v1"`, models: `grok-3`, `grok-2` |
| **Claude (Anthropic)** | Anthropic SDK | `tool_use` format; native MCP client |
| **GPT-4o (OpenAI)** | OpenAI SDK | `function_calling` → `tool_calls` |
| **Gemini (Google)** | Google SDK | `function_declarations` |
| **Local (Ollama)** | OpenAI-compatible | Any model with tool support (Llama 3.1, Mistral) |

### 13.2 Grok Integration Pattern

Grok (xAI) uses the OpenAI-compatible API format, making PCP tool schemas directly usable:

```python
import openai, os

client = openai.AsyncOpenAI(
    api_key=os.environ["XAI_API_KEY"],
    base_url="https://api.x.ai/v1",
)

# PCP tools/list → OpenAI function format
openai_tools = [
    {
        "type": "function",
        "function": {
            "name":        t["name"],
            "description": t["description"],
            "parameters":  t["inputSchema"],
        },
    }
    for t in pmcp_tools
]

response = await client.chat.completions.create(
    model="grok-3",
    messages=[{"role": "user", "content": mission}],
    tools=openai_tools,
    tool_choice="auto",
)
```

See [`examples/example_grok_agent.py`](../examples/example_grok_agent.py) for the complete implementation.

### 13.3 Safety Invariant (LLM-agnostic)

Regardless of which LLM is used as planner, the PCP safety pipeline is enforced **server-side** before any physical execution. The gate order matches §6 (Lease → Constitution → Shadow, plus an unconditional E-Stop pre-check):

```
LLM plans  →  E-Stop pre-check  →  Lease check  →  Constitution check  →  Shadow preview (3D sim)  →  TEE gate  →  Hardware
                                                     ↑ blocked here if unsafe — LLM cannot bypass this
```

The LLM never has direct hardware access. It proposes tool calls; PCP validates them. A compromised or hallucinating LLM cannot cause unsafe physical motion.

---

*Physical Context Protocol — Making every robot AI-ready.*
