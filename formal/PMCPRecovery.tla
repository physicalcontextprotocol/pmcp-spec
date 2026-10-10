---- MODULE PMCPRecovery ----
(***************************************************************************)
(* PCP five-phase recovery handshake after Safe State.                  *)
(* Models SAFETY_ARCHITECTURE.md sec 10.7.                                *)
(*                                                                         *)
(* Key modeling choice: manual reset and operator-start confirmation are  *)
(* actions of a SEPARATE "operator" process, not the "robot_sw" process.  *)
(* This is a direct, literal encoding of sec 10.7's requirement that      *)
(* manual reset "cannot be done remotely via the protocol" -- in this     *)
(* model, no protocol/software action is even capable of setting          *)
(* manualReset, structurally, not just by omission.                       *)
(***************************************************************************)
EXTENDS Naturals, TLC

(* --algorithm PMCPRecovery
variables
  robotState = "ACTIVE",
  causeRemoved = FALSE,
  manualReset = FALSE,
  selftestPassed = FALSE,
  attested = FALSE,
  leaseHeld = TRUE,        \* does the robot currently hold a lease at all
  leaseFreshSinceSafe = TRUE; \* was the CURRENT lease acquired via a full
                               \* recovery cycle since the last time SAFE
                               \* was entered? (captures "never resumes the
                               \* old lease" without needing an unbounded
                               \* counter -- keeps the state space finite)

define
  RobotStates == {"ACTIVE", "SAFE", "RECOVERING_CAUSE", "RECOVERING_SELFTEST",
                   "RECOVERING_ATTEST", "RECOVERING_LEASE", "INACTIVE"}

  TypeOK ==
    /\ robotState \in RobotStates
    /\ causeRemoved \in BOOLEAN
    /\ manualReset \in BOOLEAN
    /\ selftestPassed \in BOOLEAN
    /\ attested \in BOOLEAN
    /\ leaseHeld \in BOOLEAN
    /\ leaseFreshSinceSafe \in BOOLEAN

  \* No phase may be entered without every phase before it having completed --
  \* this is what makes the handshake actually a sequence, not just five
  \* independently-reachable named states.
  Inv_CauseBeforeSelftest ==
    (robotState \in {"RECOVERING_SELFTEST","RECOVERING_ATTEST","RECOVERING_LEASE","INACTIVE"})
      => causeRemoved

  Inv_ManualResetBeforeAttest ==
    (robotState \in {"RECOVERING_ATTEST","RECOVERING_LEASE","INACTIVE"})
      => manualReset

  Inv_SelftestBeforeLease ==
    (robotState \in {"RECOVERING_LEASE","INACTIVE"})
      => selftestPassed

  Inv_AttestBeforeInactive ==
    (robotState = "INACTIVE") => attested

  \* LeaseMonotonicExpiry (SAFETY_ARCHITECTURE.md sec 3, invariant 3),
  \* specialized to recovery: the system can only be back in ACTIVE while
  \* holding a lease that was freshly (re)acquired via the recovery cycle --
  \* this is the formal statement of "the old lease is never resumed."
  Inv_FreshLeaseOnResume ==
    (robotState = "ACTIVE") => (leaseHeld /\ leaseFreshSinceSafe)

  RecoverySafetyInv ==
    /\ TypeOK
    /\ Inv_CauseBeforeSelftest
    /\ Inv_ManualResetBeforeAttest
    /\ Inv_SelftestBeforeLease
    /\ Inv_AttestBeforeInactive
    /\ Inv_FreshLeaseOnResume
end define;

fair process robot_sw = "robot_sw"
begin
  RobotLoop:
    while TRUE do
      either
        \* Abstracts any Safe-State trigger already modeled in PMCPCore.tla
        \* (E-Stop, watchdog timeout, gate disagreement, ...).
        await robotState = "ACTIVE";
        robotState := "SAFE"
          || causeRemoved := FALSE || manualReset := FALSE
          || selftestPassed := FALSE || attested := FALSE
          || leaseHeld := FALSE || leaseFreshSinceSafe := FALSE;

      or
        await robotState = "SAFE";
        causeRemoved := TRUE || robotState := "RECOVERING_CAUSE";

      or
        \* Self-test can only run once RECOVERING_SELFTEST has been entered,
        \* which only the operator's ManualReset action can do (see below).
        await robotState = "RECOVERING_SELFTEST";
        selftestPassed := TRUE || robotState := "RECOVERING_ATTEST";

      or
        await robotState = "RECOVERING_ATTEST";
        attested := TRUE || robotState := "RECOVERING_LEASE";

      or
        \* Fresh lease acquisition -- this is the ONLY place leaseHeld and
        \* leaseFreshSinceSafe both become TRUE together, so
        \* Inv_FreshLeaseOnResume is satisfiable only via this path.
        await robotState = "RECOVERING_LEASE";
        leaseHeld := TRUE || leaseFreshSinceSafe := TRUE || robotState := "INACTIVE";
      end either;
    end while;
end process;

fair process operator = "operator"
begin
  OperatorLoop:
    while TRUE do
      either
        \* Manual reset: hardware/safety-rated-logic action, modeled as the
        \* ONLY transition into RECOVERING_SELFTEST. No robot_sw action can
        \* reach this state.
        await robotState = "RECOVERING_CAUSE" /\ causeRemoved;
        manualReset := TRUE || robotState := "RECOVERING_SELFTEST";

      or
        \* Explicit operator start confirmation -- separate button from reset.
        await robotState = "INACTIVE";
        robotState := "ACTIVE";
      end either;
    end while;
end process;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "9d3c229" /\ chksum(tla) = "cf36e7e1")
VARIABLES robotState, causeRemoved, manualReset, selftestPassed, attested, 
          leaseHeld, leaseFreshSinceSafe

(* define statement *)
RobotStates == {"ACTIVE", "SAFE", "RECOVERING_CAUSE", "RECOVERING_SELFTEST",
                 "RECOVERING_ATTEST", "RECOVERING_LEASE", "INACTIVE"}

TypeOK ==
  /\ robotState \in RobotStates
  /\ causeRemoved \in BOOLEAN
  /\ manualReset \in BOOLEAN
  /\ selftestPassed \in BOOLEAN
  /\ attested \in BOOLEAN
  /\ leaseHeld \in BOOLEAN
  /\ leaseFreshSinceSafe \in BOOLEAN




Inv_CauseBeforeSelftest ==
  (robotState \in {"RECOVERING_SELFTEST","RECOVERING_ATTEST","RECOVERING_LEASE","INACTIVE"})
    => causeRemoved

Inv_ManualResetBeforeAttest ==
  (robotState \in {"RECOVERING_ATTEST","RECOVERING_LEASE","INACTIVE"})
    => manualReset

Inv_SelftestBeforeLease ==
  (robotState \in {"RECOVERING_LEASE","INACTIVE"})
    => selftestPassed

Inv_AttestBeforeInactive ==
  (robotState = "INACTIVE") => attested





Inv_FreshLeaseOnResume ==
  (robotState = "ACTIVE") => (leaseHeld /\ leaseFreshSinceSafe)

RecoverySafetyInv ==
  /\ TypeOK
  /\ Inv_CauseBeforeSelftest
  /\ Inv_ManualResetBeforeAttest
  /\ Inv_SelftestBeforeLease
  /\ Inv_AttestBeforeInactive
  /\ Inv_FreshLeaseOnResume


vars == << robotState, causeRemoved, manualReset, selftestPassed, attested, 
           leaseHeld, leaseFreshSinceSafe >>

ProcSet == {"robot_sw"} \cup {"operator"}

Init == (* Global variables *)
        /\ robotState = "ACTIVE"
        /\ causeRemoved = FALSE
        /\ manualReset = FALSE
        /\ selftestPassed = FALSE
        /\ attested = FALSE
        /\ leaseHeld = TRUE
        /\ leaseFreshSinceSafe = TRUE

robot_sw == \/ /\ robotState = "ACTIVE"
               /\ /\ attested' = FALSE
                  /\ causeRemoved' = FALSE
                  /\ leaseFreshSinceSafe' = FALSE
                  /\ leaseHeld' = FALSE
                  /\ manualReset' = FALSE
                  /\ robotState' = "SAFE"
                  /\ selftestPassed' = FALSE
            \/ /\ robotState = "SAFE"
               /\ /\ causeRemoved' = TRUE
                  /\ robotState' = "RECOVERING_CAUSE"
               /\ UNCHANGED <<manualReset, selftestPassed, attested, leaseHeld, leaseFreshSinceSafe>>
            \/ /\ robotState = "RECOVERING_SELFTEST"
               /\ /\ robotState' = "RECOVERING_ATTEST"
                  /\ selftestPassed' = TRUE
               /\ UNCHANGED <<causeRemoved, manualReset, attested, leaseHeld, leaseFreshSinceSafe>>
            \/ /\ robotState = "RECOVERING_ATTEST"
               /\ /\ attested' = TRUE
                  /\ robotState' = "RECOVERING_LEASE"
               /\ UNCHANGED <<causeRemoved, manualReset, selftestPassed, leaseHeld, leaseFreshSinceSafe>>
            \/ /\ robotState = "RECOVERING_LEASE"
               /\ /\ leaseFreshSinceSafe' = TRUE
                  /\ leaseHeld' = TRUE
                  /\ robotState' = "INACTIVE"
               /\ UNCHANGED <<causeRemoved, manualReset, selftestPassed, attested>>

operator == /\ \/ /\ robotState = "RECOVERING_CAUSE" /\ causeRemoved
                  /\ /\ manualReset' = TRUE
                     /\ robotState' = "RECOVERING_SELFTEST"
               \/ /\ robotState = "INACTIVE"
                  /\ robotState' = "ACTIVE"
                  /\ UNCHANGED manualReset
            /\ UNCHANGED << causeRemoved, selftestPassed, attested, leaseHeld, 
                            leaseFreshSinceSafe >>

Next == robot_sw \/ operator

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(robot_sw)
        /\ WF_vars(operator)

\* END TRANSLATION 
====
