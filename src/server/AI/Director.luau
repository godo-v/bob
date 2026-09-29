-- Director: starts and stops the animatronics for a night and connects them to
-- clients and to each other.
--
-- Usage from your night/game-flow script:
--
--   local Director = require(ServerScriptService.AI.Director)
--   Director.GameState.assignPlayer("MainOfficeGuard", player)  -- per role
--   Director.startNight(3)
--   Director.NightFailed:Connect(function(reason) ... end)
--   Director.endNight()  -- at 6 AM
--
-- Animatronic locations are replicated as attributes on
-- ReplicatedStorage.AIState.<Id> (Location, State, Target, ...) so camera
-- systems can show them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedAI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI")
local AIConfig = require(SharedAI:WaitForChild("AIConfig"))
local AIRemotes = require(SharedAI:WaitForChild("AIRemotes"))
local MapGraph = require(SharedAI:WaitForChild("MapGraph"))
local GameState = require(script.Parent.GameState)

local AnimatronicsFolder = script.Parent.Animatronics
local CLASSES = {
	Bear = require(AnimatronicsFolder.Bear),
	Bunny = require(AnimatronicsFolder.Bunny),
	Weasel = require(AnimatronicsFolder.Weasel),
	Wolf = require(AnimatronicsFolder.Wolf),
	Fox = require(AnimatronicsFolder.Fox),
	TestDummy = require(AnimatronicsFolder.TestDummy),
	HR = require(AnimatronicsFolder.HR),
}

local Director = {}
Director.GameState = GameState

local nightFailed = Instance.new("BindableEvent")
-- (reason: "FacilityTerminated" | "AllDead")
Director.NightFailed = nightFailed.Event

local remotes
local stateFolder: Folder
local active = {} -- [id] = animatronic
local currentNight = 0
local initialized = false
local lastWarning = 0

-- Networking ------------------------------------------------------------------

function Director.broadcast(eventName: string, payload: { [string]: any }?)
	remotes.AIEvent:FireAllClients(eventName, payload or {})
end

function Director.sendToRole(role: string, eventName: string, payload: { [string]: any }?)
	local player = GameState.getPlayer(role)
	if player then
		remotes.AIEvent:FireClient(player, eventName, payload or {})
	end
end

function Director.publish(animatronic)
	local folder = stateFolder:FindFirstChild(animatronic.Id)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = animatronic.Id
		folder.Parent = stateFolder
	end
	for key, value in animatronic:getPublicState() do
		folder:SetAttribute(key, value)
	end
end

-- Cross-animatronic rules --------------------------------------------------------

-- A Released Test Dummy speeds up every other animatronic heading to the
-- office it is targeting.
function Director.getSpeedMultiplier(office: string?, requester): number
	local dummy = active.TestDummy
	if office and dummy and dummy ~= requester and dummy.Released and dummy.TargetOffice == office then
		return dummy:setting("BoostMultiplier")
	end
	return 1
end

function Director.getAnimatronic(id: string)
	return active[id]
end

function Director.getNight(): number
	return currentNight
end

-- Night control -------------------------------------------------------------------

export type NightOptions = {
	-- Roles in play this night. Offices whose role isn't listed are ignored.
	-- Defaults to all four roles.
	ActiveRoles: { string }?,
	-- Set to false if your game resets GameState itself.
	ResetGameState: boolean?,
}

function Director.startNight(night: number, options: NightOptions?)
	Director.init()
	Director.endNight()

	local opts: NightOptions = options or {}
	if opts.ResetGameState ~= false then
		GameState.reset(opts.ActiveRoles)
	end

	currentNight = night
	for _, id in AIConfig.SpawnOrder do
		local config = AIConfig.Animatronics[id]
		local eligible = night >= config.ActiveFromNight
			and (not config.RequiresRole or GameState.isRoleInPlay(config.RequiresRole))
		if eligible then
			local animatronic = CLASSES[id].new(id, Director)
			active[id] = animatronic
			animatronic:start(night)
		end
	end

	Director.broadcast("NightStarted", { Night = night })
end

function Director.endNight()
	local hadNight = next(active) ~= nil
	for _, animatronic in active do
		animatronic:stop()
	end
	table.clear(active)
	if stateFolder then
		stateFolder:ClearAllChildren()
	end
	if hadNight then
		Director.broadcast("NightEnded", { Night = currentNight })
	end
end

-- Called by HR once it has killed everyone.
function Director.terminateFacility(source: string)
	Director.broadcast("FacilityTerminated", { Animatronic = source })
	Director.endNight()
	nightFailed:Fire("FacilityTerminated")
end

-- Setup ----------------------------------------------------------------------------

function Director.init()
	if initialized then
		return
	end
	initialized = true

	remotes = AIRemotes.get()

	stateFolder = ReplicatedStorage:FindFirstChild("AIState") or Instance.new("Folder")
	stateFolder.Name = "AIState"
	stateFolder.Parent = ReplicatedStorage

	-- Main Office guard warns the Electrician about what they see on the cameras.
	remotes.WarnElectrician.OnServerEvent:Connect(function(player: Player, animatronicId: unknown)
		if GameState.getRoleOf(player) ~= MapGraph.Roles.MainOfficeGuard then
			return
		end
		if not GameState.isAlive(MapGraph.Roles.MainOfficeGuard) then
			return
		end
		if os.clock() - lastWarning < AIConfig.WarnElectricianCooldown then
			return
		end
		lastWarning = os.clock()
		local id = if typeof(animatronicId) == "string" and AIConfig.Animatronics[animatronicId]
			then animatronicId
			else nil
		Director.sendToRole(MapGraph.Roles.Electrician, "ElectricianWarning", { Animatronic = id })
	end)

	GameState.RoleKilled:Connect(function(role: string, killer: string)
		Director.broadcast("RoleKilled", { Role = role, Animatronic = killer })
		-- HR ends the night itself once its kill order finishes.
		local hr = active.HR
		if hr and hr.State == "Released" then
			return
		end
		if next(active) ~= nil and not GameState.anyoneAlive() then
			Director.endNight()
			nightFailed:Fire("AllDead")
		end
	end)
end

return Director
