#!/usr/bin/env bash
#
# Model-check both P-MCP TLA+ specs, then prove the checker is not
# passing vacuously.
#
# The second half matters more than the first. A model checker that
# accepts a deliberately broken spec will happily accept anything, and
# that is not a hypothetical here: a `pcal.trans` retranslation bug once
# silently overwrote the .cfg files and wiped the invariant declarations,
# after which every check went green while testing nothing. So this
# script's pass condition is not "TLC said no error" -- it is "TLC said
# no error on the real specs AND said error on the mutants".
#
# Exit 0 = all four behaved correctly.
# Exit 1 = something regressed. Do not trust any formal claim until fixed.
#
# Usage:  ./formal/check.sh
# Needs:  a JDK 11+ on PATH, curl, sha256sum (or shasum -a 256)

set -uo pipefail

TLA_VERSION="1.8.0"
# sha256 of tla2tools.jar from the official tlaplus release.
TLA_SHA256="ab4694601923fd5ac06452abbf847c366a5054a3d739552085edd6ed986c29ec"

cd "$(dirname "$0")/.."
JAR="tla2tools.jar"
FAILED=0

tlc() { java -cp "$JAR" tlc2.TLC -workers auto -config "$1" "$2"; }

# --- obtain TLC, verified -------------------------------------------------
if [ ! -f "$JAR" ] || ! echo "$TLA_SHA256  $JAR" | sha256sum -c - >/dev/null 2>&1; then
  echo "fetching tla2tools v${TLA_VERSION}..."
  curl -fsSL --retry 3 --retry-delay 2 -o "$JAR" \
    "https://github.com/tlaplus/tlaplus/releases/download/v${TLA_VERSION}/tla2tools.jar" \
    || { echo "ERROR: could not download tla2tools. The models were NOT checked."; exit 1; }
fi
echo "$TLA_SHA256  $JAR" | sha256sum -c - >/dev/null 2>&1 \
  || { echo "ERROR: tla2tools.jar checksum mismatch. Refusing to run."; exit 1; }
echo "TLC v${TLA_VERSION} (checksum verified)"

# --- the real specs: must check clean -------------------------------------
for m in PMCPCore PMCPRecovery; do
  echo
  echo "=== $m ==="
  out=$(tlc "formal/${m}.cfg" "formal/${m}.tla" 2>&1); rc=$?
  echo "$out" | grep -E "Model checking completed|Invariant .* is violated|states generated"
  if [ $rc -ne 0 ] || ! echo "$out" | grep -q "No error has been found"; then
    echo "FAIL: $m did not check clean"
    FAILED=1
  fi
done

# --- the mutants: must NOT check clean ------------------------------------
# A non-zero exit IS the pass condition here. If this ever prints
# "TLC accepted a deliberately mutated spec", the checker is not
# validating and every verification claim resting on it is void.
for m in PMCPCore_mutant PMCPRecovery_mutant; do
  echo
  echo "=== $m (must be REJECTED) ==="
  out=$(tlc "formal/self-test/${m}.cfg" "formal/self-test/${m}.tla" 2>&1); rc=$?
  echo "$out" | grep -E "Invariant .* is violated" | head -1
  if [ $rc -eq 0 ]; then
    echo "FAIL: TLC accepted a deliberately mutated spec."
    echo "      The model checker is not validating. Do not trust any"
    echo "      formal claim until this is fixed."
    FAILED=1
  else
    echo "OK: TLC correctly rejected $m"
  fi
done

# --- trace files are build junk ------------------------------------------
find formal -name '*TTrace*' -delete 2>/dev/null
rm -rf formal/states formal/self-test/states 2>/dev/null

echo
if [ $FAILED -eq 0 ]; then
  echo "PASS: both specs check clean AND TLC rejects both mutants."
  echo "Reminder: these models explore ~10 distinct states. Clean means"
  echo "self-consistent, not 'real hardware is proved'. See LIMITATIONS.md."
else
  echo "FAILED: see above."
fi
exit $FAILED
