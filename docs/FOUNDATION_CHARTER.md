# PCP Foundation Governance Charter

> **Version:** 1.0  
> **Effective Date:** May 2026  
> **License:** Apache 2.0

---

## Preamble

This document establishes the governance framework for the PCP (Physical Context Protocol) open standard. The Foundation is dedicated to creating a universal protocol that enables any MCP-compatible AI client to safely control physical robots, fostering interoperability, safety, and innovation in robotics and industrial automation.

The protocol described in this charter aims to be the "USB-C port for robot AI"—a standardized interface that bridges AI reasoning systems with physical actuation across diverse robotic platforms and industrial environments.

---

## 1. Mission and Vision

### 1.1 Mission

The PCP Foundation exists to:

1. **Standardize** the interface between AI systems and physical robots through an open, vendor-neutral protocol
2. **Promote** safety-first design in all AI-to-robot interactions
3. **Accelerate** adoption of AI-driven robotics across industries
4. **Ensure** interoperability across robot manufacturers, AI providers, and deployment environments

### 1.2 Vision

Our vision is a world where:
- Any AI assistant can control any robot safely
- Robot integrations are reusable across applications
- Multi-robot coordination is standardized
- Safety is built into the protocol, not added as an afterthought

---

## 2. Core Principles

The Foundation operates according to these principles:

### 2.1 openness

- The protocol specification is publicly available
- Implementations may be developed in any language
- No proprietary extensions are required for compliance

### 2.2 Safety-First

- The protocol mandates safety validation before execution
- Safety boundaries are non-negotiable
- Human oversight is preserved

### 2.3 Interoperability

- Support for diverse robot types (arms, mobile, agricultural, etc.)
- Transport flexibility (stdio, HTTP, WebSocket, etc.)
- Backward compatibility across versions

### 2.4 Community-Driven

- Technical decisions are made by contributors
- Diversity of perspectives is valued
- Governance is transparent and accountable

### 2.5 Neutrality

- The Foundation does not favor any vendor
- Patent policies ensure royalty-free implementation
- Governance structures prevent capture by any entity

---

## 3. Organizational Structure

### 3.1 Board of Directors

The Board provides strategic direction and ensures the Foundation's mission is served.

**Composition:**
- 5 elected directors from the Technical Community
- 1 appointed by Major Sponsor (if any)
- 1 from Academia/Open Source Projects

**Responsibilities:**
- Approve annual budget
- Set strategic priorities
- Approve policy changes
- Ensure legal and financial compliance

**Term:** 2 years, staggered elections

### 3.2 Technical Steering Committee (TSC)

The TSC leads technical direction and protocol development.

**Composition:**
- 7 members elected from the Technical Community
- Representation should include: robotics, AI/ML, safety engineering, industrial automation

**Responsibilities:**
- Define protocol roadmap
- Review and approve specifications
- Manage working groups
- Ensure technical quality

**Term:** 2 years, elections each year for 3-4 seats

### 3.3 Working Groups

Working groups address specific technical or domain areas.

**Initial Working Groups:**
1. **Protocol Working Group** - Core protocol specification
2. **Safety Working Group** - Safety validation and compliance
3. **Transport Working Group** - Transport layer implementations
4. **Integration Working Group** - Robot and AI provider integrations
5. **Testing Working Group** - Compliance testing and certification

**Governance:**
- Each WG has a charter and lead
- WGs report to TSC
- Open participation from Community Members

### 3.4 Executive Director

The Executive Director manages day-to-day operations.

**Responsibilities:**
- Execute Board decisions
- Manage staff and contractors
- Represent Foundation externally
- Report to Board

---

## 4. Membership

### 4.1 Membership Tiers

| Tier | Requirements | Benefits |
|------|-------------|----------|
| **Individual** | Personal contribution | Discussion forums, voting for TSC |
| **Contributor** | Code/documentation contribution | All Individual + Issue tracker access |
| **Organization** | Annual dues (sliding scale) | All Contributor + Voting for Board,TSC |
| **Sponsor** | Major financial contribution | All Organization + Board seat |

### 4.2 Dues Schedule

- **Individual:** Free
- **Small Org (<10 employees):** $1,000/year
- **Medium Org (10-100):** $10,000/year
- **Large Org (100+):** $50,000/year
- **Platinum Sponsor:** $500,000/year

### 4.3 Rights and Responsibilities

All members agree to:
- Follow the Code of Conduct
- Contribute constructively
- Respect the governance process
- License contributions under Apache 2.0

---

## 5. Specification Process

### 5.1 Specification Types

1. **Core Specification** - Protocol definitions required for compliance
2. **Extension Specification** - Optional capabilities
3. **Implementation Guide** - Best practices for implementations

### 5.2 Specification Lifecycle

```
Proposal → Draft → Review → Ratification → Published → Deprecated
```

**Proposal:** Anyone can submit via GitHub issue  
**Draft:** Working group develops  
**Review:** 30-day public comment period  
**Ratification:** TSC vote (2/3 majority)  
**Published:** Official release  
**Deprecated:** After 2 major versions

### 5.3 Backward Compatibility

- Core specifications are immutable once ratified
- New versions must maintain backward compatibility
- Migration paths must be documented

---

## 6. Intellectual Property

### 6.1 Licensing

- All specifications: Apache 2.0
- All code: Apache 2.0 (or MIT)
- Trademarks: Policy for use of PCP marks

### 6.2 Patents

- Royalty-free license to all necessary patents
- Patent holders must disclose relevant patents
- No defensive patents against the protocol

### 6.3 Contribution Licensing

- All contributions require CLA (Developer Certificate of Origin)
- CLA grants license to Foundation and re-users

---

## 7. Safety and Compliance

### 7.1 Safety Requirements

All compliant implementations must:

1. **Shadow Validation:** Validate commands before execution
2. **Constitution Enforcement:** Enforce immutable safety rules
3. **Emergency Stop:** Support immediate halt capability
4. **Human Clearance:** Maintain safe distances
5. **Audit Logging:** Record all commands and responses

### 7.2 Compliance Program

- **Conformance Testing:** Automated test suites
- **Certification Badges:** "PCP Compliant" certification
- **Compliance Registry:** Public list of certified implementations

### 7.3 Standards Alignment

The protocol aligns with:
- ISO 10218 (Industrial Robot Safety)
- IEC 62443 (Industrial Cybersecurity)
- MCP 2024-11-05 (Anthropic Model Context Protocol)

---

## 8. Dispute Resolution

### 8.1 Technical Disputes

1. Working group discussion
2. TSC mediation
3. Simple majority TSC vote

### 8.2 Non-Technical Disputes

1. Executive Director mediation
2. Board review
3. Final binding arbitration

### 8.3 Code of Conduct

All disputes follow the Code of Conduct. Violations may result in:
- Warning
- Suspension
- Expulsion
- Legal action (if applicable)

---

## 9. Amendments

### 9.1 Charter Amendments

- Requires 2/3 Board approval
- 30-day comment period
- Effective 30 days after approval

### 9.2 Specification Amendments

- Per Section 5 specification process
- Versioning preserves backward compatibility

---

## 10. Transition Provisions

### 10.1 Initial Structure

Upon founding:
- Interim Board appointed
- Interim TSC formed
- Initial Working Groups established

### 10.2 Timeline

- **Month 0-3:** Formation, initial governance
- **Month 3-6:** First TSC elections
- **Month 6-12:** First Board elections
- **Year 1+:** Fully operational governance

---

## 11. Definitions

| Term | Definition |
|------|-------------|
| **PCP** | Physical Context Protocol |
| **Spec** | Protocol specification |
| **Implementation** | Code implementing the spec |
| **Compliant** | Meets all Core spec requirements |
| **Foundation** | PCP Foundation |
| **TSC** | Technical Steering Committee |
| **WG** | Working Group |

---

## Annex A: Code of Conduct

### A.1 Expected Behavior

- Be respectful and inclusive
- Communicate clearly and constructively
- Accept constructive criticism gracefully
- Focus on what's best for the community

### A.2 Unacceptable Behavior

- Harassment, discrimination, or intimidation
- Personal attacks or trolling
- Publishing others' private information
- Deliberately disrupting discussions

### A.3 Reporting

Contact: conduct@pmcp.io

---

## Annex B: Trademark Policy

### B.1 Permitted Use

- "PCP Compliant" for certified implementations
- "PCP Compatible" for tested integrations
- Foundation logo for official activities

### B.2 Prohibited Use

- Implying endorsement without permission
- Modifying logos
- Using for commercial endorsement

---

*This charter is licensed under Apache 2.0. See LICENSE file for details.*

*For questions, contact: governance@pmcp.io*