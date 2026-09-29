-- Test Dummy (night 1+): keeps attacking the Drug Room door to get to the drugs.
--
-- Contained: walks Containment -> DrugRoomHall -> Drug Room door. If the door
-- is shut when the attack window ends it goes back to Containment and tries
-- again. If not, or if the Drug Room Guard is dead, it is Released.
--
-- Released:
--   * Kills the Drug Room Guard.
--   * Can use any entrance of the Main Office, Patient Ward Office and Electrical Room.
--   * Drains 25% of an office's power each time a closed door stops it
--     (Main Office and Patient Ward Office only; never the Drug Room).
--   * Uses the far more aggressive Released config.
--   * Other animatronics heading to the same office move faster
--     (Director.getSpeedMultiplier).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animatronic = require(script.Parent.Parent.Animatronic)
local SharedAI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI")
local AIConfig = require(SharedAI:WaitForChild("AIConfig"))
local MapGraph = require(SharedAI:WaitForChild("MapGraph"))

local DRUG_ROOM_GUARD = MapGraph.Roles.DrugRoomGuard

local TestDummy = setmetatable({}, { __index = Animatronic })
TestDummy.__index = TestDummy

function TestDummy.new(kind: string, director, model: Model?, id: string?)
	local self = setmetatable(Animatronic.new(kind, director, model, id), TestDummy)
	self.Released = false
	return self
end

function TestDummy:setting(key: string): any
	if self.Released then
		local value = self.Config.Released[key]
		if value ~= nil then
			return AIConfig.forNight(value, self.Night)
		end
	end
	return Animatronic.setting(self, key)
end

function TestDummy:getPublicState()
	local public = Animatronic.getPublicState(self)
	public.Released = self.Released
	return public
end

function TestDummy:release()
	if self.Released then
		return
	end
	self.Released = true
	self.AILevel = self:setting("AILevel")
	self:emit("TestDummyReleased")
	self:killRole(DRUG_ROOM_GUARD)
end

function TestDummy:waitForMoveOpportunity(): boolean
	-- Nobody left to hold the Drug Room: it gets out on its own.
	if not self.Released and not self.GameState.isAlive(DRUG_ROOM_GUARD) then
		self:release()
		self:resetToStart()
	end
	return Animatronic.waitForMoveOpportunity(self)
end

function TestDummy:onRepelled(office: string, entranceName: string, entrance)
	if not self.Released or entrance.Kind ~= "Door" then
		return
	end
	if not table.find(self:setting("PowerDrainOffices"), office) then
		return
	end
	local amount = self:setting("PowerDrainOnDoor")
	self.GameState.drainPower(office, amount)
	self:emit("PowerDrained", {
		Office = office,
		Entrance = entranceName,
		Amount = amount,
	})
end

function TestDummy:onBreach(office: string, entranceName: string)
	if not self.Released then
		self:release()
		return
	end
	Animatronic.onBreach(self, office, entranceName)
end

return TestDummy
