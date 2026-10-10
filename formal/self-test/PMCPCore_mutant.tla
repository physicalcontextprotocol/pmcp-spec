---- MODULE PMCPCore_mutant ----
(***************************************************************************)
(* PCP core safety state machine: a single robot's lease acquisition,   *)
(* the Lease -> Constitution -> Shadow gate sequence, E-Stop bypass, and  *)
(* heartbeat/watchdog. Models SAFETY_ARCHITECTURE.md sections 3, 5, 6.    *)
(*                                                                         *)
(* Scope: one robot, one lease. Multi-robot spatial-overlap conflicts     *)
(* (SAFETY_ARCHITECTURE.md section 10.5) are out of scope for this pass. *)
(***************************************************************************)
EXTENDS Naturals, TLC

(* --algorithm PMCPCore
variables
  leaseState = "FREE",
  robotState = "INACTIVE",
  lastShadowVerdict = "NONE";

define
  LeaseStates == {"FREE", "PENDING", "ACTIVE", "EXPIRED", "DENIED"}
  RobotStates == {"INACTIVE", "GATE_CONSTITUTION", "GATE_SHADOW", "ACTUATING", "SAFE"}
  ShadowVerdicts == {"NONE", "PASS", "FAIL", "INDETERMINATE"}

  TypeOK ==
    /\ leaseState \in LeaseStates
    /\ robotState \in RobotStates
    /\ lastShadowVerdict \in ShadowVerdicts

  \* Invariant 1 (SAFETY_ARCHITECTURE.md sec 3): LeaseHeldBeforeConstitution.
  \* Constitution/Shadow/Actuating may only be entered with an ACTIVE lease.
  Inv_LeaseHeldBeforeConstitution ==
    (robotState \in {"GATE_CONSTITUTION", "GATE_SHADOW", "ACTUATING"})
      => (leaseState = "ACTIVE")

  \* Invariant 2: ShadowPassedBeforeActuation.
  \* ACTUATING may only be reached if the last Shadow verdict was PASS.
  Inv_ShadowPassedBeforeActuation ==
    (robotState = "ACTUATING") => (lastShadowVerdict = "PASS")

  \* Invariant 4: FailSafeOnDisagreement, restricted form.
  \* You can never be simultaneously ACTUATING and carrying a FAIL/INDETERMINATE
  \* verdict from the gate that's supposed to have blocked you.
  Inv_NoActuationOnBadVerdict ==
    (robotState = "ACTUATING") => (lastShadowVerdict # "FAIL" /\ lastShadowVerdict # "INDETERMINATE")

  SafetyInv ==
    /\ TypeOK
    /\ Inv_LeaseHeldBeforeConstitution
    /\ Inv_ShadowPassedBeforeActuation
    /\ Inv_NoActuationOnBadVerdict
end define;

fair process robot = "robot1"
begin
  Idle:
    while TRUE do
      either
        \* Acquire a free lease (Raft grant/deny modeled as nondeterministic choice)
        await leaseState = "FREE";
        either
          leaseState := "ACTIVE";
        or
          leaseState := "DENIED";
        end either;

      or
        \* A DENIED lease returns to the pool
        await leaseState = "DENIED";
        leaseState := "FREE";

      or
        \* Enter the Constitution gate -- requires an ACTIVE lease (Inv 1 source)
        await robotState = "INACTIVE";
        robotState := "GATE_CONSTITUTION";

      or
        \* Constitution check resolves
        await robotState = "GATE_CONSTITUTION";
        either
          robotState := "GATE_SHADOW";
        or
          \* Constitution failure -> Safe State, lease revoked (Inv 4)
          robotState := "SAFE" || leaseState := "EXPIRED";
        end either;

      or
        \* Shadow (HNN + monitor, sec 10.1) check resolves
        await robotState = "GATE_SHADOW";
        either
          lastShadowVerdict := "PASS" || robotState := "ACTUATING";
        or
          lastShadowVerdict := "FAIL" || robotState := "SAFE" || leaseState := "EXPIRED";
        or
          lastShadowVerdict := "INDETERMINATE" || robotState := "SAFE" || leaseState := "EXPIRED";
        end either;

      or
        \* Actuation completes normally
        await robotState = "ACTUATING";
        robotState := "INACTIVE" || lastShadowVerdict := "NONE" || leaseState := "FREE";

      or
        \* Heartbeat/watchdog timeout (sec 10.3): any active-lease state -> SAFE
        await leaseState \in {"ACTIVE", "PENDING"} /\ robotState # "SAFE";
        robotState := "SAFE" || leaseState := "EXPIRED";

      or
        \* E-Stop: reachable from EVERY state, always enabled (Inv 5, sec 3)
        robotState := "SAFE" || leaseState := "EXPIRED";

      or
        \* Recovery (simplified single-step form of sec 10.7's 5-phase handshake):
        \* only possible once the lease has fully cleared -- never resumes the
        \* old lease (LeaseMonotonicExpiry, Inv 3).
        await robotState = "SAFE" /\ leaseState \in {"EXPIRED", "FREE"};
        robotState := "INACTIVE" || leaseState := "FREE" || lastShadowVerdict := "NONE";
      end either;
    end while;
end process;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "8aa235fc" /\ chksum(tla) = "cc3a7b36")
VARIABLES leaseState, robotState, lastShadowVerdict

(* define statement *)
LeaseStates == {"FREE", "PENDING", "ACTIVE", "EXPIRED", "DENIED"}
RobotStates == {"INACTIVE", "GATE_CONSTITUTION", "GATE_SHADOW", "ACTUATING", "SAFE"}
ShadowVerdicts == {"NONE", "PASS", "FAIL", "INDETERMINATE"}

TypeOK ==
  /\ leaseState \in LeaseStates
  /\ robotState \in RobotStates
  /\ lastShadowVerdict \in ShadowVerdicts



Inv_LeaseHeldBeforeConstitution ==
  (robotState \in {"GATE_CONSTITUTION", "GATE_SHADOW", "ACTUATING"})
    => (leaseState = "ACTIVE")



Inv_ShadowPassedBeforeActuation ==
  (robotState = "ACTUATING") => (lastShadowVerdict = "PASS")




Inv_NoActuationOnBadVerdict ==
  (robotState = "ACTUATING") => (lastShadowVerdict # "FAIL" /\ lastShadowVerdict # "INDETERMINATE")

SafetyInv ==
  /\ TypeOK
  /\ Inv_LeaseHeldBeforeConstitution
  /\ Inv_ShadowPassedBeforeActuation
  /\ Inv_NoActuationOnBadVerdict


vars == << leaseState, robotState, lastShadowVerdict >>

ProcSet == {"robot1"}

Init == (* Global variables *)
        /\ leaseState = "FREE"
        /\ robotState = "INACTIVE"
        /\ lastShadowVerdict = "NONE"

robot == \/ /\ leaseState = "FREE"
            /\ \/ /\ leaseState' = "ACTIVE"
               \/ /\ leaseState' = "DENIED"
            /\ UNCHANGED <<robotState, lastShadowVerdict>>
         \/ /\ leaseState = "DENIED"
            /\ leaseState' = "FREE"
            /\ UNCHANGED <<robotState, lastShadowVerdict>>
         \/ /\ robotState = "INACTIVE"
            /\ robotState' = "GATE_CONSTITUTION"
            /\ UNCHANGED <<leaseState, lastShadowVerdict>>
         \/ /\ robotState = "GATE_CONSTITUTION"
            /\ \/ /\ robotState' = "GATE_SHADOW"
                  /\ UNCHANGED leaseState
               \/ /\ /\ leaseState' = "EXPIRED"
                     /\ robotState' = "SAFE"
            /\ UNCHANGED lastShadowVerdict
         \/ /\ robotState = "GATE_SHADOW"
            /\ \/ /\ /\ lastShadowVerdict' = "PASS"
                     /\ robotState' = "ACTUATING"
                  /\ UNCHANGED leaseState
               \/ /\ /\ lastShadowVerdict' = "FAIL"
                     /\ leaseState' = "EXPIRED"
                     /\ robotState' = "SAFE"
               \/ /\ /\ lastShadowVerdict' = "INDETERMINATE"
                     /\ leaseState' = "EXPIRED"
                     /\ robotState' = "SAFE"
         \/ /\ robotState = "ACTUATING"
            /\ /\ lastShadowVerdict' = "NONE"
               /\ leaseState' = "FREE"
               /\ robotState' = "INACTIVE"
         \/ /\ leaseState \in {"ACTIVE", "PENDING"} /\ robotState # "SAFE"
            /\ /\ leaseState' = "EXPIRED"
               /\ robotState' = "SAFE"
            /\ UNCHANGED lastShadowVerdict
         \/ /\ /\ leaseState' = "EXPIRED"
               /\ robotState' = "SAFE"
            /\ UNCHANGED lastShadowVerdict
         \/ /\ robotState = "SAFE" /\ leaseState \in {"EXPIRED", "FREE"}
            /\ /\ lastShadowVerdict' = "NONE"
               /\ leaseState' = "FREE"
               /\ robotState' = "INACTIVE"

Next == robot

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(robot)

\* END TRANSLATION 
====
