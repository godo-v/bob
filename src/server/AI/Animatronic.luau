-- Animatronic: shared behavior for route-walking animatronics.
--
-- Lifecycle of a trip:
--   1. resetToStart   pick a random office, then a random entrance there
--   2. advance        on each successful movement roll, step one room along the route
--   3. attack         at the entrance: wait out the attack window, check the defense
--   4. outcome        Repelled -> back to start; Breach -> kill occupant, back to start
--
-- Subclasses override the hook methods (onMoved, onReachedEntrance,
-- resolveEntrance, onSpotted, onRepelled, onBreach, setting) for their
-- special rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedAI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI")
local AIConfig = require(SharedAI:WaitForChild("AIConfig"))
local MapGraph = require(SharedAI:WaitForChild("MapGraph"))

local Animatronic = {}
Animatronic.__index = Animatronic

function Animatronic.new(id: string, director)
	local config = AIConfig.Animatronics[id]
	assert(config, `No config for animatronic "{id}"`)

	local self = setmetatable({}, Animatronic)
	self.Id = id
	self.Config = config
	self.Director = director
	self.GameState = director.GameState
	self.Night = 0
	self.AILevel = 0
	self.Running = false
	self.Route = {}
	self.RouteIndex = 1
	self.TargetKey = nil
	self.TargetOffice = nil
	self.TargetEntrance = nil
	self.Location = config.StartRoom
	self.State = "Idle"
	return self
end

-- Config lookup for the current night. Subclasses can override to swap
-- config sets (see TestDummy).
function Animatronic:setting(key: string): any
	return AIConfig.forNight(self.Config[key], self.Night)
end

-- Lifecycle -------------------------------------------------------------------

function Animatronic:start(night: number)
	self.Night = night
	self.AILevel = self:setting("AILevel") or 0
	self.Running = true
	task.spawn(function()
		local ok, err = pcall(self.run, self)
		if not ok then
			warn(`[AI] {self.Id} crashed: {err}`)
		end
	end)
end

function Animatronic:stop()
	self.Running = false
	self:setState("Idle")
end

function Animatronic:run()
	self:resetToStart()
	while self.Running do
		if not self:waitForMoveOpportunity() then
			return
		end
		if self:rollMovement() then
			self:advance()
		end
	end
end

-- Timing helpers --------------------------------------------------------------

-- Returns false if the night ended while waiting.
function Animatronic:sleep(seconds: number): boolean
	local deadline = os.clock() + seconds
	while self.Running and os.clock() < deadline do
		task.wait(math.min(AIConfig.PollInterval, deadline - os.clock()))
	end
	return self.Running
end

-- Polls `predicate` for up to `seconds`. Returns true if it became true,
-- false on timeout, nil if the night ended.
function Animatronic:waitFor(seconds: number, predicate: () -> boolean): boolean?
	local deadline = os.clock() + seconds
	while self.Running do
		if predicate() then
			return true
		end
		if os.clock() >= deadline then
			return false
		end
		task.wait(AIConfig.PollInterval)
	end
	return nil
end

function Animatronic:waitForMoveOpportunity(): boolean
	local multiplier = self.Director.getSpeedMultiplier(self.TargetOffice, self)
	return self:sleep(self:setting("MoveInterval") / multiplier)
end

function Animatronic:rollMovement(): boolean
	return math.random(1, AIConfig.MaxAILevel) <= self.AILevel
end

-- State / publishing ------------------------------------------------------------

function Animatronic:setLocation(location: string)
	self.Location = location
	self.Director.publish(self)
end

function Animatronic:setState(state: string)
	self.State = state
	self.Director.publish(self)
end

-- Extra fields added to the replicated AIState folder (see Director.publish).
function Animatronic:getPublicState(): { [string]: any }
	return {
		Location = self.Location,
		State = self.State,
		Target = self.TargetKey or "",
		AILevel = self.AILevel,
	}
end

-- Targeting -------------------------------------------------------------------

function Animatronic:availableTargets(): { string }
	local result = {}
	for _, key in self:setting("Targets") do
		local office = MapGraph.parseTarget(key)
		if self.GameState.isOfficeOccupied(office) then
			table.insert(result, key)
		end
	end
	return result
end

-- Picks an office at random, then an entrance at random within it, so an
-- office with more entrances isn't picked more often.
function Animatronic:chooseTarget(): boolean
	local byOffice, offices = {}, {}
	for _, key in self:availableTargets() do
		local office = MapGraph.parseTarget(key)
		if not byOffice[office] then
			byOffice[office] = {}
			table.insert(offices, office)
		end
		table.insert(byOffice[office], key)
	end

	local startRoom = self:setting("StartRoom")
	if #offices == 0 then
		self.TargetKey, self.TargetOffice, self.TargetEntrance = nil, nil, nil
		self.Route = { startRoom }
		return false
	end

	local keys = byOffice[offices[math.random(#offices)]]
	local key = keys[math.random(#keys)]
	self.TargetKey = key
	self.TargetOffice, self.TargetEntrance = MapGraph.parseTarget(key)
	self.Route = MapGraph.buildRoute(startRoom, key, self:setting("Routes"))
	return true
end

function Animatronic:resetToStart()
	self:chooseTarget()
	self.RouteIndex = 1
	self:setState("Roaming")
	self:setLocation(self.Route[1])
end

-- Movement --------------------------------------------------------------------

function Animatronic:advance()
	-- No target yet, or the target's occupant died on the way: pick again.
	if not self.TargetOffice or not self.GameState.isOfficeOccupied(self.TargetOffice) then
		self:resetToStart()
		return
	end

	if self.RouteIndex < #self.Route then
		self.RouteIndex += 1
		self:setLocation(self.Route[self.RouteIndex])
		self.Director.broadcast("Moved", { Animatronic = self.Id, Location = self.Location })
		self:onMoved()
	else
		self:attack()
	end
end

function Animatronic:attack()
	local office, entranceName = self.TargetOffice, self.TargetEntrance
	local entrance = MapGraph.getEntrance(office, entranceName)

	self:setState("AtEntrance")
	self:setLocation(MapGraph.entranceLocation(office, entranceName))
	self.Director.broadcast("AtEntrance", {
		Animatronic = self.Id,
		Office = office,
		Entrance = entranceName,
		Kind = entrance.Kind,
	})
	self:onMoved()
	self:onReachedEntrance(office, entranceName, entrance)

	local outcome = self:resolveEntrance(office, entranceName, entrance)
	if outcome == nil or not self.Running then
		return
	end

	if outcome == "Repelled" then
		self.Director.broadcast("Repelled", { Animatronic = self.Id, Office = office, Entrance = entranceName })
		self:onRepelled(office, entranceName, entrance)
	elseif outcome == "Breach" then
		self:onBreach(office, entranceName)
	end
	if self.Running then
		self:resetToStart()
	end
end

-- Returns "Repelled", "Breach", "Handled" (outcome already dealt with, e.g.
-- by a charge), or nil if the night ended.
function Animatronic:resolveEntrance(office: string, entranceName: string, entrance): string?
	local gameState = self.GameState
	local role = MapGraph.occupantOf(office)
	local location = MapGraph.entranceLocation(office, entranceName)
	local window = self:setting("AttackWindow")

	if entrance.Kind == "Door" or entrance.Kind == "Vent" then
		if not self:sleep(window) then
			return nil
		end
		return if gameState.isEntranceBlocked(office, entranceName) then "Repelled" else "Breach"
	elseif entrance.Kind == "Window" then
		local flashed = self:waitFor(window, function()
			return gameState.isFlashlightOn(role, location)
		end)
		if flashed == nil then
			return nil
		end
		return if flashed then "Repelled" else "Breach"
	elseif entrance.Kind == "Hallway" then
		local spotted = self:waitFor(self:setting("HallwayWindow") or window, function()
			return gameState.isFlashlightOn(role, location)
		end)
		if spotted == nil then
			return nil
		end
		if spotted then
			return self:onSpotted(role)
		end
		-- Nobody checked the hallway in time.
		if self:setting("ChargeWhenUnchecked") then
			return self:charge(role)
		end
		return if gameState.isHiding(role) then "Repelled" else "Breach"
	end

	warn(`[AI] Unknown entrance kind "{entrance.Kind}" at {office}.{entranceName}`)
	return "Repelled"
end

-- Charge at `role`; they must be hiding when ChargeHideWindow runs out.
function Animatronic:charge(role: string): string?
	local hideWindow = self:setting("ChargeHideWindow")
	self:setState("Charging")
	self.Director.broadcast("Charge", { Animatronic = self.Id, Role = role, HideWindow = hideWindow })
	if not self:sleep(hideWindow) then
		return nil
	end
	if self.GameState.isHiding(role) then
		return "Repelled"
	end
	self:killRole(role)
	return "Handled"
end

function Animatronic:killRole(role: string): boolean
	if not self.GameState.isAlive(role) then
		return false
	end
	self.Director.broadcast("Jumpscare", { Animatronic = self.Id, Role = role })
	self.GameState.killRole(role, self.Id)
	return true
end

-- Hooks -------------------------------------------------------------------------

function Animatronic:onMoved() end

function Animatronic:onReachedEntrance(_office: string, _entranceName: string, _entrance) end

-- Caught in the flashlight while in a hallway. Backs off, unless
-- ChargeWhenSpotted is set.
function Animatronic:onSpotted(role: string): string?
	if self:setting("ChargeWhenSpotted") then
		return self:charge(role)
	end
	return "Repelled"
end

function Animatronic:onRepelled(_office: string, _entranceName: string, _entrance) end

function Animatronic:onBreach(office: string, _entranceName: string)
	self:killRole(MapGraph.occupantOf(office))
end

return Animatronic
