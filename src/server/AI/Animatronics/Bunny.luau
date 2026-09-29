-- Bunny (night 1+): heads to a random office each trip.
--   * Main Office: left vent.
--   * Patient Ward Office: right vent.
--   * Electrical Room: through the Electrical Hallway.
-- Targets live in AIConfig; everything else is base behavior.

local Animatronic = require(script.Parent.Parent.Animatronic)

local Bunny = setmetatable({}, { __index = Animatronic })
Bunny.__index = Bunny

function Bunny.new(kind: string, director, model: Model?, id: string?)
	return setmetatable(Animatronic.new(kind, director, model, id), Bunny)
end

return Bunny
