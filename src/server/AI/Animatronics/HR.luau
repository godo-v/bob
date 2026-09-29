-- HR (night 1+): watches the Patient Ward Nurse.
--
-- If the nurse's workload (GameState.getNurseWorkload) stays at WorkloadLimit
-- for GracePeriod seconds, or the nurse dies, HR is released. It then kills,
-- in order, the Patient Ward Nurse, Main Office Guard, Drug Room Guard and
-- Electrician, which ends the night for every office.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animatronic = require(script.Parent.Parent.Animatronic)
local MapGraph = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI"):WaitForChild("MapGraph"))

local NURSE = MapGraph.Roles.PatientWardNurse

local HR = setmetatable({}, { __index = Animatronic })
HR.__index = HR

function HR.new(kind: string, director, model: Model?, id: string?)
	local self = setmetatable(Animatronic.new(kind, director, model, id), HR)
	self.OverdueSince = nil
	return self
end

function HR:getPublicState()
	local public = Animatronic.getPublicState(self)
	public.NurseWorkload = self.GameState.getNurseWorkload()
	public.Overdue = self.OverdueSince ~= nil
	return public
end

function HR:shouldRelease(): boolean
	if not self.GameState.isAlive(NURSE) then
		return true
	end
	if self.GameState.getNurseWorkload() >= self:setting("WorkloadLimit") then
		self.OverdueSince = self.OverdueSince or os.clock()
		return os.clock() - self.OverdueSince >= self:setting("GracePeriod")
	end
	self.OverdueSince = nil
	return false
end

function HR:run()
	self:setLocation(self:setting("StartRoom"))
	self:setState("Watching")
	while self.Running do
		if self:shouldRelease() then
			self:terminate()
			return
		end
		self.Director.publish(self)
		if not self:sleep(self:setting("CheckInterval")) then
			return
		end
	end
end

function HR:terminate()
	self:setState("Released")
	self:emit("HRReleased")
	for _, role in self:setting("KillOrder") do
		if self.GameState.isRoleInPlay(role) and self.GameState.isAlive(role) then
			self:setLocation(MapGraph.officeOf(role) or role)
			self:killRole(role)
			if not self:sleep(self:setting("KillInterval")) then
				return
			end
		end
	end
	self.Director.terminateFacility(self.Id)
end

return HR
