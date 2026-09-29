-- Chicken (night 2+): heads to a random office each trip.
--   * Main Office: right door, or staring through the window.
--   * Patient Ward Office: left door, or staring through the window.
--   * Electrical Room: through the Electrical Hallway.

local Animatronic = require(script.Parent.Parent.Animatronic)

local Chicken = setmetatable({}, { __index = Animatronic })
Chicken.__index = Chicken

function Chicken.new(id: string, director)
	return setmetatable(Animatronic.new(id, director), Chicken)
end

function Chicken:onReachedEntrance(office: string, entranceName: string, entrance)
	if entrance.Kind == "Window" then
		-- Clients use this to pose the Chicken staring at the occupant.
		self.Director.broadcast("Staring", { Animatronic = self.Id, Office = office, Entrance = entranceName })
	end
end

return Chicken
