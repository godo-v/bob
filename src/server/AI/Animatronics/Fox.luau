-- Fox (night 1+): only goes for the Electrical Room.
--   * Visible to the Electrician only in the Electrical Hallway. The Main
--     Office can track it on the main cameras and warn the Electrician
--     (WarnElectrician remote, handled by the Director).
--   * Once in the hallway it charges as soon as the Electrician's flashlight
--     hits it, or after HallwayWindow seconds if nobody checks.
--   * On a charge the Electrician has ChargeHideWindow (3s) to hide.
-- The hallway charge is driven by ChargeWhenSpotted / ChargeWhenUnchecked in AIConfig.

local Animatronic = require(script.Parent.Parent.Animatronic)

local Fox = setmetatable({}, { __index = Animatronic })
Fox.__index = Fox

function Fox.new(kind: string, director, model: Model?, id: string?)
	return setmetatable(Animatronic.new(kind, director, model, id), Fox)
end

return Fox
