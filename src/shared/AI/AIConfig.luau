-- AIConfig: every tuning number for the animatronics lives here.
--
-- A value is either a plain value, or AIConfig.perNight({ [night] = value }).
-- A per-night value uses the highest night defined at or below the current
-- night, so { [3] = 7, [4] = 5, [5] = 3 } means night 3 -> 7, night 4 -> 5,
-- night 5+ -> 3.
--
-- AILevel is 0-20. At each movement opportunity (every MoveInterval seconds)
-- the animatronic moves one step if a 1-20 roll is <= its AILevel.

local MapGraph = require(script.Parent.MapGraph)

local AIConfig = {}

local PerNight = {}

function AIConfig.perNight(values: { [number]: any })
	return setmetatable(values, PerNight)
end

function AIConfig.forNight(value: any, night: number): any
	if type(value) ~= "table" or getmetatable(value) ~= PerNight then
		return value
	end
	for n = night, 1, -1 do
		if value[n] ~= nil then
			return value[n]
		end
	end
	return nil
end

local perNight = AIConfig.perNight

AIConfig.MaxAILevel = 20
AIConfig.PollInterval = 0.1

-- Start order when a night begins.
AIConfig.SpawnOrder = { "Bunny", "Chicken", "Bear", "Wolf", "Fox", "TestDummy", "HR" }

AIConfig.Animatronics = {
	-- Acts like Freddy: loud audio cue on every move. Ends at a window; must be
	-- flashed within 7/5/3 seconds (nights 3/4/5+) or it kills the occupant.
	Bear = {
		ActiveFromNight = 3,
		AILevel = perNight({ [3] = 8, [4] = 12, [5] = 16, [6] = 20 }),
		MoveInterval = 5,
		StartRoom = "ShowStage",
		Targets = { "MainOffice.Window", "PatientWardOffice.Window" },
		AttackWindow = perNight({ [3] = 7, [4] = 5, [5] = 3 }),
		MoveSound = "BearMove",
		MoveSoundVolume = 1,
	},

	-- Random office each trip; comes through vents at the offices.
	Bunny = {
		ActiveFromNight = 1,
		AILevel = perNight({ [1] = 5, [2] = 8, [3] = 11, [4] = 14, [5] = 17, [6] = 20 }),
		MoveInterval = 5,
		StartRoom = "ShowStage",
		Targets = { "MainOffice.LeftVent", "PatientWardOffice.RightVent", "ElectricalRoom.Hallway" },
		AttackWindow = perNight({ [1] = 8, [3] = 6, [5] = 4 }),
	},

	-- Random office each trip. Main Office: right door or window.
	-- Patient Ward: window or left door.
	Chicken = {
		ActiveFromNight = 2,
		AILevel = perNight({ [2] = 6, [3] = 9, [4] = 13, [5] = 16, [6] = 20 }),
		MoveInterval = 5,
		StartRoom = "ShowStage",
		Targets = {
			"MainOffice.RightDoor",
			"MainOffice.Window",
			"PatientWardOffice.Window",
			"PatientWardOffice.LeftDoor",
			"ElectricalRoom.Hallway",
		},
		AttackWindow = perNight({ [2] = 8, [3] = 6, [5] = 4 }),
	},

	-- Multiplayer only. Any entrance of the Main Office / Patient Ward, or the
	-- Electrical Hallway. Charges the Electrician when caught in their flashlight.
	Wolf = {
		ActiveFromNight = 1,
		MultiplayerOnly = true,
		AILevel = perNight({ [1] = 4, [2] = 7, [3] = 10, [4] = 13, [5] = 16, [6] = 20 }),
		MoveInterval = 5,
		StartRoom = "ShowStage",
		Targets = (function()
			local keys = MapGraph.allEntrances({ "MainOffice", "PatientWardOffice" })
			table.insert(keys, "ElectricalRoom.Hallway")
			return keys
		end)(),
		AttackWindow = perNight({ [1] = 8, [3] = 6, [5] = 4 }),
		ChargeHideWindow = 3,
	},

	-- Only goes for the Electrical Room. The Electrician sees it only in the
	-- Electrical Hallway; the Main Office sees it on the main cameras.
	-- Spotted in the hallway -> charges; Electrician has 3s to hide.
	Fox = {
		ActiveFromNight = 1,
		RequiresRole = "Electrician",
		AILevel = perNight({ [1] = 4, [2] = 7, [3] = 10, [4] = 13, [5] = 16, [6] = 20 }),
		MoveInterval = 6,
		StartRoom = "FoxDen",
		Targets = { "ElectricalRoom.Hallway" },
		Routes = {
			["ElectricalRoom.Hallway"] = { "FoxDen", "Basement" },
		},
		-- How long the Fox waits unseen in the hallway before charging anyway.
		-- This is what forces the Electrician to check the hallway regularly.
		AttackWindow = perNight({ [1] = 20, [3] = 15, [5] = 10 }),
		ChargeHideWindow = 3,
	},

	-- Keeps trying to reach the Drug Room. If the Drug Room door isn't shut in
	-- time it is Released (see the Released block).
	TestDummy = {
		ActiveFromNight = 1,
		RequiresRole = "DrugRoomGuard",
		AILevel = perNight({ [1] = 10, [2] = 12, [3] = 14, [4] = 16, [5] = 18, [6] = 20 }),
		MoveInterval = 3,
		StartRoom = "Containment",
		Targets = { "DrugRoom.Door" },
		AttackWindow = perNight({ [1] = 5, [3] = 4, [5] = 3 }),

		-- Overrides used once Released. Anything not listed here falls back to
		-- the values above.
		Released = {
			AILevel = 20,
			MoveInterval = 2,
			StartRoom = "DrugRoom",
			Targets = MapGraph.allEntrances({ "MainOffice", "PatientWardOffice", "ElectricalRoom" }),
			AttackWindow = 3,
			-- Fraction of power drained each time it reaches a door.
			PowerDrainOnDoor = 0.25,
			-- Other animatronics heading to the same office move this much faster.
			BoostMultiplier = 1.75,
		},
	},

	-- Watches the Patient Ward Nurse. If the nurse's work backlog stays at the
	-- limit for GracePeriod seconds, or the nurse dies, HR is released and kills
	-- everyone in KillOrder.
	HR = {
		ActiveFromNight = 1,
		RequiresRole = "PatientWardNurse",
		StartRoom = "HRDepartment",
		CheckInterval = 0.5,
		-- Nurse workload is 0-1 (see GameState.setNurseWorkload).
		WorkloadLimit = 1,
		GracePeriod = 5,
		KillOrder = { "PatientWardNurse", "MainOfficeGuard", "DrugRoomGuard", "Electrician" },
		KillInterval = 2.5,
	},
}

-- Seconds between warnings the Main Office can send the Electrician.
AIConfig.WarnElectricianCooldown = 2

return AIConfig
