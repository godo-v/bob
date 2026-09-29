-- Wolf (night 1+): heads to a random office each trip.
--   * Can use every entrance of the Main Office and Patient Ward Office.
--   * Also goes for the Electrical Room through the Electrical Hallway. There it
--     charges the Electrician when caught in their flashlight, or after
--     HallwayWindow seconds if nobody checks; they must hide within
--     ChargeHideWindow seconds.
-- The hallway charge is driven by ChargeWhenSpotted / ChargeWhenUnchecked in AIConfig.

local Animatronic = require(script.Parent.Parent.Animatronic)

local Wolf = setmetatable({}, { __index = Animatronic })
Wolf.__index = Wolf

function Wolf.new(id: string, director)
	return setmetatable(Animatronic.new(id, director), Wolf)
end

return Wolf
