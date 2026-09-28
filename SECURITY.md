# Security policy

This is the default security policy for every repository in the
`physicalcontextprotocol` GitHub organization. Repositories with a
sub-project-specific policy override this one; where they differ, the
repository-local `SECURITY.md` wins.

## Reporting a vulnerability

**Do not open a public GitHub issue for a suspected vulnerability.**

Use **private vulnerability reporting** instead. It is enabled on every
repository in this organization, so you can submit a report through the
GitHub UI without an email address and without making anything public:

1. Open the affected repository on GitHub.
2. Click **Security** → **Report a vulnerability**.
3. Fill in the advisory form.

That is the same form the maintainers read first, and it keeps the
discussion private until a fix exists.

If private reporting is unavailable to you (for example you are using a
mirror or an older GitHub client), fall back to opening an
[organization security advisory](https://github.com/physicalcontextprotocol/security/advisories/new)
rather than a public issue.

Please include:

1. A description of the vulnerability and its impact.
2. Steps to reproduce, ideally with a minimal proof-of-concept.
3. Known affected versions or sub-projects.
4. Your suggested severity, if you would like to propose one.

## Response targets

| Stage | Target |
|---|---|
| Acknowledgement of a valid report | 5 business days |
| Fix or mitigation published, high severity | 90 days |
| Fix or mitigation published, actively exploited | as fast as we can safely ship |
| Credit | offered in the advisory, unless you prefer otherwise |

We will keep you posted while we work the report. We will not share
details of an unfixed vulnerability publicly.

## Supported versions

| Repository | Supported | Notes |
|---|---|---|
| `pmcp-spec` | yes | v0.5 protocol line and JSON Schema v0.6.0 |
| `pmcp-python` | yes | v0.5 line |
| `pmcp-typescript` | best-effort | v0.5, skeleton SDK — no test suite yet |
| `pmcp-rust` | best-effort | `pmcp-core` only; `pmcp-ledger` does not currently compile |
| `pmcp-conformance` | best-effort | v0.5 |
| `pmcp-safety` | best-effort | TEE attestator and safety-loop are mock-backed |
| `pmcp-servers` | best-effort | illustrative only, no hardware drivers |
| `pmcp-registry` | **not for untrusted networks** | no auth, CORS `*` on write verbs, no body-size limit |
| `pmcp-labs` | **no** | private quarantine; no support, no guarantees |

Security guarantees for anything marked "best-effort" are provisional
until that repository carries its own supported-version table. Each
repository's README states its honest maturity — read it before relying
on it.

## What is in scope

- Correctness or safety-pipeline bypasses in the protocol
  (`pmcp-spec`) or in the shipping v0.5 code (`pmcp-python`).
- Auth, authorization, injection, deserialization, resource-exhaustion
  or SSRF issues in network-facing components, especially
  `pmcp-registry`.
- Supply-chain issues in the SDKs (`pmcp-python`, `pmcp-typescript`,
  `pmcp-rust`).
- Leaked secrets or credentials in any repository in this organization.

## What is not in scope

- Clearly labelled placeholder or mock code. `pmcp-safety`'s
  `tee-attestator` ships `MOCK_QUOTE` and `pmcp-safety`'s safety loop
  defaults to `--simulator mock`. These are documented limitations, not
  vulnerabilities.
- Examples and demos under `pmcp-servers/examples/` — illustrative.
- Anything in `pmcp-labs` — unsupported by policy, and not public.
- Docker and compose files under `pmcp-labs/infra/` — they reference
  pre-split paths and do not build against the current layout.
- Attacks that require an attacker to already hold the `release`
  environment or a maintainer account.
- Missing hardening in a component whose README already says it is
  experimental and names the gap. Reporting it is still welcome, but it
  will be triaged as an enhancement, not a vulnerability.

## If we overclaim

If you find that something is presented as more verified than it is —
especially anything in [`LIMITATIONS.md`](https://github.com/physicalcontextprotocol/pmcp-spec/blob/main/LIMITATIONS.md)
that no longer matches reality — that is a real report and we will treat
it as one. See the "Honest limitations" section of the protocol
specification for the current list of things we know we have not
proven.
