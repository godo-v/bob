-- AIRemotes: network objects shared by the AI server and clients.
--
--   AIEvent          server -> client  (eventName: string, payload: table)
--   WarnElectrician  client -> server  Main Office guard pings the Electrician
--
-- AIEvent names: NightStarted, NightEnded, AudioCue, Moved, AtEntrance,
-- Repelled, Charge, Jumpscare, TestDummyReleased, PowerDrained, HRReleased,
-- FacilityTerminated, ElectricianWarning.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "AIRemotes"

local AIRemotes = {}

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function AIRemotes.get()
	local folder
	if RunService:IsServer() then
		folder = getOrCreate(ReplicatedStorage, "Folder", FOLDER_NAME)
		getOrCreate(folder, "RemoteEvent", "AIEvent")
		getOrCreate(folder, "RemoteEvent", "WarnElectrician")
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
	return {
		AIEvent = folder:WaitForChild("AIEvent") :: RemoteEvent,
		WarnElectrician = folder:WaitForChild("WarnElectrician") :: RemoteEvent,
	}
end

return AIRemotes
