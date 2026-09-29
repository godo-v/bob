-- MapGraph: the facility layout the AI moves through.
--
-- Room names are placeholders. Rename them to match your camera/room names
-- in Studio; nothing else in the AI depends on the specific strings.
--
-- A "target key" is "<Office>.<Entrance>", e.g. "MainOffice.Window".

local MapGraph = {}

MapGraph.Roles = {
	MainOfficeGuard = "MainOfficeGuard",
	PatientWardNurse = "PatientWardNurse",
	Electrician = "Electrician",
	DrugRoomGuard = "DrugRoomGuard",
}

-- Entrance kinds decide how the occupant defends it:
--   Door / Vent : must be closed when the attack window ends
--   Window      : occupant must shine the flashlight on it before the window ends
--   Hallway     : occupant must spot it with the flashlight, or be hiding when it arrives
--
-- Path lists the rooms walked through after leaving the animatronic's start room.
-- Room (optional) is where the animatronic stands while at the entrance; it
-- defaults to the target key itself.
MapGraph.Offices = {
	MainOffice = {
		Occupant = "MainOfficeGuard",
		Entrances = {
			LeftDoor = { Kind = "Door", Path = { "Lobby", "WestHall", "WestHallCorner" } },
			RightDoor = { Kind = "Door", Path = { "Lobby", "EastHall", "EastHallCorner" } },
			LeftVent = { Kind = "Vent", Path = { "Lobby", "Storage", "WestVent" } },
			Window = { Kind = "Window", Path = { "Lobby", "Courtyard" } },
		},
	},
	PatientWardOffice = {
		Occupant = "PatientWardNurse",
		Entrances = {
			LeftDoor = { Kind = "Door", Path = { "Lobby", "WardCorridor", "WardWestDoorway" } },
			RightDoor = { Kind = "Door", Path = { "Lobby", "WardCorridor", "WardEastDoorway" } },
			RightVent = { Kind = "Vent", Path = { "Lobby", "Storage", "WardVent" } },
			Window = { Kind = "Window", Path = { "Lobby", "WardGarden" } },
		},
	},
	ElectricalRoom = {
		Occupant = "Electrician",
		Entrances = {
			Hallway = { Kind = "Hallway", Path = { "Lobby", "Basement" }, Room = "ElectricalHallway" },
		},
	},
	DrugRoom = {
		Occupant = "DrugRoomGuard",
		Entrances = {
			Door = { Kind = "Door", Path = { "DrugRoomHall" } },
		},
	},
}

function MapGraph.parseTarget(key: string): (string, string)
	local office, entrance = string.match(key, "^([^%.]+)%.([^%.]+)$")
	assert(office and entrance, `Invalid target key "{key}"`)
	return office, entrance
end

function MapGraph.getEntrance(office: string, entrance: string)
	local officeData = MapGraph.Offices[office]
	assert(officeData, `Unknown office "{office}"`)
	local entranceData = officeData.Entrances[entrance]
	assert(entranceData, `Unknown entrance "{office}.{entrance}"`)
	return entranceData
end

-- Where the animatronic stands while at an entrance. This is also the
-- flashlight target name for windows and hallways.
function MapGraph.entranceLocation(office: string, entrance: string): string
	return MapGraph.getEntrance(office, entrance).Room or `{office}.{entrance}`
end

function MapGraph.occupantOf(office: string): string
	return MapGraph.Offices[office].Occupant
end

function MapGraph.officeOf(role: string): string?
	for office, data in MapGraph.Offices do
		if data.Occupant == role then
			return office
		end
	end
	return nil
end

-- Every entrance key for the given offices, e.g. for "can appear at any entrance".
function MapGraph.allEntrances(offices: { string }): { string }
	local keys = {}
	for _, office in offices do
		local names = {}
		for name in MapGraph.Offices[office].Entrances do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			table.insert(keys, `{office}.{name}`)
		end
	end
	return keys
end

-- Rooms from startRoom up to (not including) the entrance. `overrides` maps a
-- target key to a full custom route.
function MapGraph.buildRoute(startRoom: string, key: string, overrides: { [string]: { string } }?): { string }
	if overrides and overrides[key] then
		return table.clone(overrides[key])
	end
	local office, entrance = MapGraph.parseTarget(key)
	local route = { startRoom }
	for _, room in MapGraph.getEntrance(office, entrance).Path do
		if room ~= route[#route] then
			table.insert(route, room)
		end
	end
	return route
end

return MapGraph
