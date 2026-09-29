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
-- Behaviors run on tagged models: tag a Model "AI_Bear" (AIConfig.tagFor) and
-- it becomes a Bear. See ModelBinder for tags and waypoints.
--
-- Animatronic locations are replicated as attributes on
-- ReplicatedStorage.AIState.<Id> (Kind, Location, State, Target, ...) and on
-- the model itself (AIKind, AILocation, AIState, ...) so camera systems can
-- show them.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedAI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI")
local AIConfig = require(SharedAI:WaitForChild("AIConfig"))
local AIRemotes = require(SharedAI:WaitForChild("AIRemotes"))
local MapGraph = require(SharedAI:WaitForChild("MapGraph"))
local GameState = require(script.Parent.GameState)
local ModelBinder = require(script.Parent.ModelBinder)

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
local nightRunning = false
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
	folder:SetAttribute("Kind", animatronic.Kind)
	for key, value in animatronic:getPublicState() do
		folder:SetAttribute(key, value)
	end
	ModelBinder.sync(animatronic)
end

-- Cross-animatronic rules --------------------------------------------------------

-- A Released Test Dummy speeds up every other animatronic heading to the
-- office it is targeting.
function Director.getSpeedMultiplier(office: string?, requester): number
	if not office then
		return 1
	end
	local multiplier = 1
	for _, other in active do
		if other ~= requester and other.Kind == "TestDummy" and other.Released and other.TargetOffice == office then
			multiplier = math.max(multiplier, other:setting("BoostMultiplier"))
		end
	end
	return multiplier
end

-- By id (the model's Name).
function Director.getAnimatronic(id: string)
	return active[id]
end

function Director.getAnimatronicsOfKind(kind: string): { any }
	local result = {}
	for _, animatronic in active do
		if animatronic.Kind == kind then
			table.insert(result, animatronic)
		end
	end
	return result
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

local function isEligible(kind: string): boolean
	local config = AIConfig.Animatronics[kind]
	return currentNight >= config.ActiveFromNight
		and (not config.RequiresRole or GameState.isRoleInPlay(config.RequiresRole))
end

local function isBound(model: Instance): boolean
	for _, animatronic in active do
		if animatronic.Model == model then
			return true
		end
	end
	return false
end

local function uniqueId(name: string): string
	local id, n = name, 1
	while active[id] do
		n += 1
		id = `{name}_{n}`
	end
	return id
end

local function spawnFor(kind: string, model: Instance)
	if isBound(model) then
		return
	end
	ModelBinder.bind(model)
	local animatronic = CLASSES[kind].new(kind, Director, model, uniqueId(model.Name))
	active[animatronic.Id] = animatronic
	animatronic:start(currentNight)
end

local function despawnModel(model: Instance)
	for id, animatronic in active do
		if animatronic.Model == model then
			animatronic:stop()
			ModelBinder.unbind(animatronic)
			active[id] = nil
			local folder = stateFolder:FindFirstChild(id)
			if folder then
				folder:Destroy()
			end
		end
	end
end

function Director.startNight(night: number, options: NightOptions?)
	Director.init()
	Director.endNight()

	local opts: NightOptions = options or {}
	if opts.ResetGameState ~= false then
		GameState.reset(opts.ActiveRoles)
	end

	currentNight = night
	nightRunning = true
	for _, kind in AIConfig.SpawnOrder do
		if isEligible(kind) then
			local models = ModelBinder.getTaggedModels(kind)
			if #models == 0 then
				warn(`[AI] No Model tagged "{AIConfig.tagFor(kind)}"; {kind} will not run tonight`)
			end
			for _, model in models do
				spawnFor(kind, model)
			end
		end
	end

	Director.broadcast("NightStarted", { Night = night })
end

function Director.endNight()
	local hadNight = nightRunning
	nightRunning = false
	for _, animatronic in active do
		animatronic:stop()
	end
	table.clear(active)
	ModelBinder.restoreAll()
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
		-- Accepts a kind ("Fox") or a model id ("Fox_2").
		local id = if typeof(animatronicId) == "string"
				and (AIConfig.Animatronics[animatronicId] or active[animatronicId])
			then animatronicId
			else nil
		Director.sendToRole(MapGraph.Roles.Electrician, "ElectricianWarning", { Animatronic = id })
	end)

	-- Models tagged or untagged mid-night gain or lose their behavior right away.
	for kind in CLASSES do
		local tag = AIConfig.tagFor(kind)
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
			if nightRunning and instance:IsA("Model") and isEligible(kind) then
				spawnFor(kind, instance)
			end
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(despawnModel)
	end

	GameState.RoleKilled:Connect(function(role: string, killer: string)
		Director.broadcast("RoleKilled", { Role = role, Animatronic = killer })
		-- HR ends the night itself once its kill order finishes.
		for _, hr in Director.getAnimatronicsOfKind("HR") do
			if hr.State == "Released" then
				return
			end
		end
		if nightRunning and not GameState.anyoneAlive() then
			Director.endNight()
			nightFailed:Fire("AllDead")
		end
	end)
end

return Director
