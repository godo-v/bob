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
- **Hallway**: the Electrician shines the flashlight down the hallway to spot animatronics. Spotting the Bunny or Weasel makes it back off; if never spotted, the Electrician must be hiding when the window ends. The Wolf and Fox charge instead, whether spotted or left unchecked for `HallwayWindow` seconds, and the Electrician has 3 s to hide.

Room names in `MapGraph.luau` are placeholders. Rename them to match your real camera and room names.

## Movement model

Every `MoveInterval` seconds, each animatronic rolls 1–20. If the roll is at or below its `AILevel`, it moves one room along its route. After the last room it reaches the entrance and the attack window starts. When a trip ends, the animatronic goes back to its start room and picks a new random target.

Targets are chosen by picking a random office first, then a random entrance in that office. Offices whose occupant is dead or not in play are skipped.

## Animatronics

| Animatronic | Active from | Targets | Special rules |
|---|---|---|---|
| Bear | Night 3 | Main Office / Patient Ward windows | Every move sends a loud `AudioCue`. If not flashed within 7 / 5 / 3 s (nights 3 / 4 / 5+), it kills the occupant. |
| Bunny | Night 1 | Main Office left vent, Patient Ward right vent, Electrical Hallway | None |
| Weasel | Night 2 | Main Office right door, Patient Ward left door, Electrical Hallway | At an office it first stares through the window. Staring is harmless and the flashlight does nothing. On its next move it goes to that office's door and attacks there. |
| Wolf | Night 1 | Every Main Office / Patient Ward entrance, Electrical Hallway | In the hallway it charges when spotted, or after `HallwayWindow` seconds unchecked (3 s to hide). |
| Fox | Night 1 | Electrical Hallway only | The Electrician can see it only in the hallway. It charges when spotted, or after `HallwayWindow` seconds unchecked (3 s to hide). The Main Office can warn the Electrician (`WarnElectrician` remote). |
| Test Dummy | Night 1 | Drug Room door | If the door is open when the window ends, or the Drug Room Guard is dead, it is **Released**. See below. |
| HR | Night 1 | None (watches the nurse) | If the nurse dies, or the nurse's workload stays at the limit for 15 s, HR is **released**. It kills the Nurse, Main Office Guard, Drug Room Guard, then the Electrician, and the night fails. |

**A Released Test Dummy:**
- kills the Drug Room Guard;
- then targets any entrance of the Main Office, Patient Ward Office, or Electrical Room;
- uses AI level 20 and moves faster;
- drains 25% of an office's power each time a closed door stops it, and only for the Main Office and Patient Ward Office (never the Drug Room);
- makes other animatronics heading to the same office move 1.75× faster.

## Assumptions to confirm

1. **Bear timings.** The spec gives 7/5/3 seconds, which is read as nights 3/4/5+.
2. **Doors are checked when the attack window ends,** not held for the whole window.
3. **Weasel window stop.** It stares on every trip to the Main Office or Patient Ward. At the Patient Ward it then attacks the left door.
4. **Bunny, Weasel, and Wolf reach the Electrical Room through the Electrical Hallway.** Spotting the Bunny or Weasel backs them off.
5. **Power is tracked per office** (`GameState.SharedPower = false`). Only closed *doors* (not vents) that stop a Released Test Dummy drain power.
6. **Nurse work** is a 0–1 workload value that your nurse-task system sets with `GameState.setNurseWorkload`. "Falling behind" means that value stays at 1 for 15 seconds.
7. **Roles not in play** (such as empty offices in single player) are ignored. The Fox, Test Dummy, and HR don't spawn if their role isn't in play.
8. **The night fails** (`Director.NightFailed`) when every in-play role is dead, or when HR finishes its kill order.
9. **AI levels and intervals** are first-pass values. Tune them in `AIConfig.luau`.
