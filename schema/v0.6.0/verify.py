#!/usr/bin/env python3
"""Round-trip the P-MCP JSON Schema against its example fixtures.

Three checks, in increasing strictness:

1. The schema is a valid JSON Schema 2020-12 document.
2. Every `examples/valid/` fixture validates against its `$defs[$defRef]`.
3. Every `examples/invalid/` fixture is rejected -- **and rejected for the
   stated reason**.

Check 3 is the one that matters. A safety schema that rejects a bad
message for an unrelated reason is not validating the property you think
it is. `invalid/lease_grant_bad_state.json` used to be rejected only
because it omitted the required `fence_token`, which meant the fixture
appeared to prove that `LeaseState` was enforced while actually proving
nothing of the sort. This script exists to make that class of false
confidence impossible to reintroduce silently.

Usage:
    python schema/v0.6.0/verify.py

Exits 0 if everything holds, 1 otherwise. Suitable for CI.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
    from jsonschema.exceptions import ValidationError
except ImportError:  # pragma: no cover
    sys.exit("jsonschema is required: pip install jsonschema")

HERE = Path(__file__).resolve().parent
SCHEMA_PATH = HERE / "pmcp.schema.json"

# Each invalid fixture declares the property it exists to probe. A
# rejection whose errors mention none of these words is a rejection for
# the wrong reason, and the fixture is lying about what it demonstrates.
# Add a key here when you add a fixture; a fixture with no entry is
# reported as undeclared rather than silently trusted.
EXPECTED_REJECTION_TERMS: dict[str, tuple[str, ...]] = {
    "estop_wrong_stop_category.json": ("stop_category", "const"),
    "lease_grant_bad_state.json": ("state", "LeaseState", "enum"),
    "shadow_result_bare_boolean.json": ("confidence", "monitoring", "determinism", "required"),
}


def load_schema() -> dict:
    with SCHEMA_PATH.open() as fh:
        return json.load(fh)


def sub_schema_for(ref: str, root: dict) -> dict:
    """Build a standalone schema that resolves `#/$defs/<ref>`."""
    dialect = root["$schema"].rsplit("/", 1)[-1]
    return {
        f"${dialect}": root["$schema"],
        "$defs": root["$defs"],
        "$ref": f"#/$defs/{ref}",
    }


def validate_fixtures(schema: dict) -> int:
    root = schema
    failures: list[str] = []
    checked = 0

    for path in sorted(HERE.glob("examples/valid/*.json")):
        doc = json.loads(path.read_text())
        ref, message = doc["$defRef"], doc["message"]
        validator = Draft202012Validator(sub_schema_for(ref, root))
        errors = sorted(validator.iter_errors(message), key=lambda e: list(e.path))
        checked += 1
        if errors:
            failures.append(
                f"examples/valid/{path.name}: expected to validate as "
                f"{ref}, but it was rejected: {errors[0].message}"
            )

    for path in sorted(HERE.glob("examples/invalid/*.json")):
        doc = json.loads(path.read_text())
        ref, message = doc["$defRef"], doc["message"]
        validator = Draft202012Validator(sub_schema_for(ref, root))
        errors = list(validator.iter_errors(message))
        checked += 1

        if not errors:
            failures.append(
                f"examples/invalid/{path.name}: expected to be REJECTED as "
                f"{ref}, but it validated cleanly"
            )
            continue

        terms = EXPECTED_REJECTION_TERMS.get(path.name)
        if terms is None:
            failures.append(
                f"examples/invalid/{path.name}: no entry in "
                f"EXPECTED_REJECTION_TERMS, so we cannot tell whether it was "
                f"rejected for the right reason. Add one."
            )
            continue

        blob = " ".join(
            [e.message for e in errors]
            + [str(p) for e in errors for p in e.absolute_path]
            + [e.validator or "" for e in errors]
        )
        if not any(term in blob for term in terms):
            failures.append(
                f"examples/invalid/{path.name}: rejected, but NOT for the "
                f"reason it claims to probe. Expected one of {terms}. Actual: "
                f"{errors[0].message}"
            )

    for failure in failures:
        print(f"FAIL  {failure}", file=sys.stderr)
    print(f"checked {checked} fixtures, {len(failures)} failure(s)")
    return 1 if failures else 0


def main() -> int:
    schema = load_schema()

    try:
        Draft202012Validator.check_schema(schema)
    except ValidationError as exc:
        print(f"FAIL  {SCHEMA_PATH.name} is not a valid 2020-12 schema: {exc}", file=sys.stderr)
        return 1
    print(f"PASS  {SCHEMA_PATH.name} is a valid JSON Schema 2020-12 document")

    return validate_fixtures(schema)


if __name__ == "__main__":
    sys.exit(main())
