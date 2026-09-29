-- Fox (night 1+): only goes for the Electrical Room.
--   * Visible to the Electrician only in the Electrical Hallway. The Main
--     Office can track it on the main cameras and warn the Electrician
--     (WarnElectrician remote, handled by the Director).
--   * Once in the hallway it charges as soon as the Electrician's flashlight
--     hits it, or after AttackWindow seconds if nobody checks.
--   * On a charge the Electrician has ChargeHideWindow (3s) to hide.

local Animatronic = require(script.Parent.Parent.Animatronic)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapGraph = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI"):WaitForChild("MapGraph"))

local Fox = setmetatable({}, { __index = Animatronic })
Fox.__index = Fox

function Fox.new(id: string, director)
	return setmetatable(Animatronic.new(id, director), Fox)
end

function Fox:resolveEntrance(office: string, entranceName: string, _entrance): string?
	local role = MapGraph.occupantOf(office)
	local location = MapGraph.entranceLocation(office, entranceName)
	local spotted = self:waitFor(self:setting("AttackWindow"), function()
		return self.GameState.isFlashlightOn(role, location)
	end)
	if spotted == nil then
		return nil
	end
	-- Spotted or not, the Fox charges; being spotted only makes it happen sooner.
	return self:charge(role)
end

return Fox
