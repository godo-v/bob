-- Bear (night 3+): behaves like Freddy.
--   * Every move plays a loud audio cue for all players.
--   * Its final stop is the Main Office or Patient Ward Office window.
--   * The occupant must flash it within 7/5/3 seconds (AIConfig AttackWindow)
--     or it kills them.
-- Window handling itself is the base class "Window" defense.

local Animatronic = require(script.Parent.Parent.Animatronic)

local Bear = setmetatable({}, { __index = Animatronic })
Bear.__index = Bear

function Bear.new(kind: string, director, model: Model?, id: string?)
	return setmetatable(Animatronic.new(kind, director, model, id), Bear)
end

function Bear:onMoved()
	self:emit("AudioCue", {
		Sound = self:setting("MoveSound"),
		Volume = self:setting("MoveSoundVolume"),
		Location = self.Location,
	})
end

return Bear
