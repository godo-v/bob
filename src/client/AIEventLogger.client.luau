-- AIEventLogger: prints every AI event to the output while testing.
-- Replace or extend with real audio, jumpscares and camera visuals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AIRemotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI"):WaitForChild("AIRemotes"))

local remotes = AIRemotes.get()

local function describe(payload: { [string]: any }): string
	local parts = {}
	for key, value in payload do
		table.insert(parts, `{key}={value}`)
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

remotes.AIEvent.OnClientEvent:Connect(function(eventName: string, payload: { [string]: any })
	print(`[AI] {eventName} {describe(payload)}`)
end)
