-- Wolf (night 1+, multiplayer only): heads to a random office each trip.
--   * Can use every entrance of the Main Office and Patient Ward Office.
--   * Also goes for the Electrical Room through the Electrical Hallway.
--   * If the Electrician catches it in their flashlight it charges them
--     instead of backing off; they must hide within ChargeHideWindow seconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animatronic = require(script.Parent.Parent.Animatronic)
local MapGraph = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI"):WaitForChild("MapGraph"))

local Wolf = setmetatable({}, { __index = Animatronic })
Wolf.__index = Wolf

function Wolf.new(id: string, director)
	return setmetatable(Animatronic.new(id, director), Wolf)
end

function Wolf:onSpotted(role: string): string?
	if role == MapGraph.Roles.Electrician then
		return self:charge(role)
	end
	return "Repelled"
end

return Wolf
