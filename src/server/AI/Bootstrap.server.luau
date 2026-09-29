-- Bootstrap: sets up the AI when the server starts.
--
-- Nights are started by your game-flow script via Director.startNight.
-- For quick Studio testing, set a number attribute "AIDebugNight" on
-- Workspace (e.g. 3) and press Play; that night starts automatically.

local Workspace = game:GetService("Workspace")

local Director = require(script.Parent:WaitForChild("Director"))

Director.init()

local debugNight = Workspace:GetAttribute("AIDebugNight")
if typeof(debugNight) == "number" and debugNight >= 1 then
	task.wait(2)
	warn(`[AI] Debug: starting night {debugNight}`)
	Director.startNight(debugNight)
end
