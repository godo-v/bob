-- Weasel (night 2+): heads to a random office each trip.
--   * Main Office: stares through the window, then attacks the right door.
--   * Patient Ward Office: stares through the window, then attacks the left door.
--   * Electrical Room: through the Electrical Hallway.
-- Staring is harmless: the Weasel never attacks through a window and the
-- flashlight doesn't drive it off. It stays at the window until its next
-- successful movement roll, then moves to the door (WindowStops in AIConfig).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animatronic = require(script.Parent.Parent.Animatronic)
local MapGraph = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI"):WaitForChild("MapGraph"))

local Weasel = setmetatable({}, { __index = Animatronic })
Weasel.__index = Weasel

function Weasel.new(kind: string, director, model: Model?, id: string?)
	local self = setmetatable(Animatronic.new(kind, director, model, id), Weasel)
	self.HasStared = false
	return self
end

function Weasel:resetToStart()
	self.HasStared = false
	Animatronic.resetToStart(self)
end

function Weasel:attack()
	local windowKey = self.TargetKey and (self:setting("WindowStops") or {})[self.TargetKey]
	if windowKey and not self.HasStared then
		self.HasStared = true
		local office, entranceName = MapGraph.parseTarget(windowKey)
		self:setState("Staring")
		self:setLocation(MapGraph.entranceLocation(office, entranceName))
		-- Clients use this to pose the Weasel staring at the occupant.
		self:emit("Staring", { Office = office, Entrance = entranceName })
		return
	end
	Animatronic.attack(self)
end

return Weasel
