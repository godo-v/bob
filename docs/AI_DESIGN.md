# Animatronic AI design

This document explains how each animatronic behaves, which tuning values control it, and which assumptions were made where the original spec left something open.

## Roles and offices

| Office | Role | Entrances (`Kind`) |
|---|---|---|
| Main Office | `MainOfficeGuard` | LeftDoor (Door), RightDoor (Door), LeftVent (Vent), Window (Window) |
| Patient Ward Office | `PatientWardNurse` | LeftDoor (Door), RightDoor (Door), RightVent (Vent), Window (Window) |
| Electrical Room | `Electrician` | Hallway (Hallway), which is the Electrical Hallway |
| Drug Room | `DrugRoomGuard` | Door (Door) |

How each kind of entrance is defended:

- **Door / Vent**: the door or vent must be closed when the attack window ends.
- **Window**: the occupant must shine the flashlight on the window before the attack window ends.
- **Hallway**: the Electrician shines the flashlight down the hallway to spot animatronics. Spotting a normal animatronic makes it back off. If the Electrician never spots it, they must be hiding when the window ends.

Room names in `MapGraph.luau` are placeholders. Rename them to match your real camera and room names.

## Movement model

Every `MoveInterval` seconds, each animatronic rolls 1–20. If the roll is at or below its `AILevel`, it moves one room along its route. After the last room it reaches the entrance and the attack window starts. When a trip ends, the animatronic goes back to its start room and picks a new random target.

Targets are chosen by picking a random office first, then a random entrance in that office. Offices whose occupant is dead or not in play are skipped.

## Animatronics

| Animatronic | Active from | Targets | Special rules |
|---|---|---|---|
| Bear | Night 3 | Main Office / Patient Ward windows | Every move sends a loud `AudioCue`. If not flashed within 7 / 5 / 3 s (nights 3 / 4 / 5+), it kills the occupant. |
| Bunny | Night 1 | Main Office left vent, Patient Ward right vent, Electrical Hallway | None |
| Chicken | Night 2 | Main Office right door and window; Patient Ward left door and window; Electrical Hallway | Sends a `Staring` event at windows |
| Wolf | Night 1, multiplayer only | Every Main Office / Patient Ward entrance, Electrical Hallway | If the Electrician's flashlight hits it, it charges (3 s to hide). |
| Fox | Night 1 | Electrical Hallway only | The Electrician can see it only in the hallway. When spotted, or after `AttackWindow` seconds unspotted, it charges and the Electrician has 3 s to hide. The Main Office can warn the Electrician (`WarnElectrician` remote). |
| Test Dummy | Night 1 | Drug Room door | If the door is open when the window ends, or the Drug Room Guard is dead, it is **Released**. See below. |
| HR | Night 1 | None (watches the nurse) | If the nurse dies, or the nurse's workload stays at the limit for 5 s, HR is **released**. It kills the Nurse, Main Office Guard, Drug Room Guard, then the Electrician, and the night fails. |

**A Released Test Dummy:**
- kills the Drug Room Guard;
- then targets any entrance of the Main Office, Patient Ward Office, or Electrical Room;
- uses AI level 20 and moves faster;
- drains 25% power each time it reaches a door;
- makes other animatronics heading to the same office move 1.75× faster.

## Assumptions to confirm

1. **Bear timings.** The spec gives 7/5/3 seconds, which is read as nights 3/4/5+.
2. **Doors are checked when the attack window ends,** not held for the whole window.
3. **Chicken at a window** is defended like the Bear: flash it.
4. **Bunny, Chicken, and Wolf reach the Electrical Room through the Electrical Hallway.** Spotting them backs them off, except the Wolf, which charges.
5. **The Fox charges even if never spotted,** after `AttackWindow` seconds. Without this rule, an Electrician who never checks the hallway would be safe.
6. **Power is one facility-wide pool** (`GameState.SharedPower`). The Test Dummy drains power on reaching a door whether or not the door is closed.
7. **Nurse work** is a 0–1 workload value that your nurse-task system sets with `GameState.setNurseWorkload`.
8. **Roles not in play** (such as empty offices in single player) are ignored. The Fox, Test Dummy, and HR don't spawn if their role isn't in play.
9. **The night fails** (`Director.NightFailed`) when every in-play role is dead, or when HR finishes its kill order.
10. **AI levels and intervals** are first-pass values. Tune them in `AIConfig.luau`.
