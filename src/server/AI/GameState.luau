-- GameState: the single seam between the AI and the rest of the game.
--
-- The AI only reads and writes game state through these functions. Your
-- existing systems (door buttons, flashlight tool, hiding spots, power meter,
-- nurse tasks, role assignment) should call the setters below, or you can
-- replace the bodies of these functions to read from your own systems.
--
-- Flashlight targets are location names: "MainOffice.Window",
-- "PatientWardOffice.Window", "ElectricalHallway", or any room name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapGraph = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI"):WaitForChild("MapGraph"))

local GameState = {}

local roleKilled = Instance.new("BindableEvent")
local powerChanged = Instance.new("BindableEvent")

-- (role: string, killer: string)
GameState.RoleKilled = roleKilled.Event
-- (powerKey: string, newValue: number) -- value is 0-1
GameState.PowerChanged = powerChanged.Event

-- Power is one facility-wide pool by default. Set to false to give each
-- office its own pool.
GameState.SharedPower = true

local state = {
	inPlay = {} :: { [string]: boolean },
	alive = {} :: { [string]: boolean },
	players = {} :: { [string]: Player },
	blocked = {} :: { [string]: boolean },
	flashlight = {} :: { [string]: string? },
	hiding = {} :: { [string]: boolean },
	power = {} :: { [string]: number },
	nurseWorkload = 0,
}

local function entranceKey(office: string, entrance: string): string
	return `{office}.{entrance}`
end

local function powerKey(office: string): string
	return if GameState.SharedPower then "Facility" else office
end

-- Called by the Director at the start of each night. `activeRoles` lists the
-- roles in play; offices without a role are ignored by the AI.
function GameState.reset(activeRoles: { string }?)
	table.clear(state.inPlay)
	table.clear(state.alive)
	table.clear(state.blocked)
	table.clear(state.flashlight)
	table.clear(state.hiding)
	table.clear(state.power)
	state.nurseWorkload = 0

	local roles = activeRoles
	if not roles then
		roles = {}
		for role in MapGraph.Roles do
			table.insert(roles, role)
		end
	end
	for _, role in roles do
		assert(MapGraph.Roles[role], `Unknown role "{role}"`)
		state.inPlay[role] = true
		state.alive[role] = true
	end
end

-- Roles / players ------------------------------------------------------------

function GameState.assignPlayer(role: string, player: Player?)
	state.players[role] = player
end

function GameState.getPlayer(role: string): Player?
	return state.players[role]
end

function GameState.getRoleOf(player: Player): string?
	for role, p in state.players do
		if p == player then
			return role
		end
	end
	return nil
end

function GameState.isRoleInPlay(role: string): boolean
	return state.inPlay[role] == true
end

function GameState.isAlive(role: string): boolean
	return state.alive[role] == true
end

function GameState.anyoneAlive(): boolean
	for role in state.inPlay do
		if state.alive[role] then
			return true
		end
	end
	return false
end

-- An office is a valid target when its occupant is in play and alive.
function GameState.isOfficeOccupied(office: string): boolean
	local role = MapGraph.occupantOf(office)
	return GameState.isRoleInPlay(role) and GameState.isAlive(role)
end

function GameState.killRole(role: string, killer: string)
	if not state.alive[role] then
		return
	end
	state.alive[role] = false
	state.hiding[role] = false
	state.flashlight[role] = nil
	roleKilled:Fire(role, killer)
end

-- Doors & vents --------------------------------------------------------------

function GameState.setEntranceBlocked(office: string, entrance: string, blocked: boolean)
	state.blocked[entranceKey(office, entrance)] = blocked
end

function GameState.isEntranceBlocked(office: string, entrance: string): boolean
	return state.blocked[entranceKey(office, entrance)] == true
end

-- Flashlight ------------------------------------------------------------------

-- target = nil turns the flashlight off.
function GameState.setFlashlightTarget(role: string, target: string?)
	state.flashlight[role] = target
end

function GameState.isFlashlightOn(role: string, target: string): boolean
	return state.alive[role] == true and state.flashlight[role] == target
end

-- Hiding ------------------------------------------------------------------------

function GameState.setHiding(role: string, hiding: boolean)
	state.hiding[role] = hiding
end

function GameState.isHiding(role: string): boolean
	return state.hiding[role] == true
end

-- Power (0-1) -------------------------------------------------------------------

function GameState.getPower(office: string): number
	return state.power[powerKey(office)] or 1
end

function GameState.setPower(office: string, value: number)
	local key = powerKey(office)
	local clamped = math.clamp(value, 0, 1)
	state.power[key] = clamped
	powerChanged:Fire(key, clamped)
end

function GameState.drainPower(office: string, fraction: number)
	GameState.setPower(office, GameState.getPower(office) - fraction)
end

-- Patient Ward nurse workload (0 = caught up, 1 = at the limit) -------------------

function GameState.setNurseWorkload(value: number)
	state.nurseWorkload = math.clamp(value, 0, 1)
end

function GameState.getNurseWorkload(): number
	return state.nurseWorkload
end

return GameState
