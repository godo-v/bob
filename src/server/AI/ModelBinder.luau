-- ModelBinder: connects AI behaviors to animatronic models in the world.
--
-- Attaching a behavior:
--   Tag a Model with "AI_<Kind>" (e.g. "AI_Bear", "AI_TestDummy"). Every
--   tagged model gets its own copy of that behavior when a night starts, or
--   as soon as it is tagged mid-night. Removing the tag or destroying the model
--   stops its behavior. The model's Name is used as its AI id.
--
-- Placing models:
--   Tag a BasePart or Attachment with "AIWaypoint" to mark where an
--   animatronic stands for a location. The location name comes from its
--   "Location" attribute, or the part's Name if there is none. Locations are
--   MapGraph room names ("WestHall") and entrance spots ("MainOffice.Window",
--   "ElectricalHallway").
--   Optional "Animatronic" attribute (a kind like "Bear", or a model name)
--   makes a waypoint specific to that animatronic, e.g. a custom window pose.
--   When several animatronics share a location, each takes a free generic
--   waypoint if one exists.
--
-- Models are moved with PivotTo, so keep them anchored. The model's original
-- pivot is restored when the night ends. Each move also sets these attributes
-- on the model for client visuals and animation scripts:
--   AIKind, AIId, AILocation, AIState, AITarget

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AIConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AI"):WaitForChild("AIConfig"))

local ModelBinder = {}

local originalPivots = {} :: { [Instance]: CFrame }
local occupied = {} :: { [Instance]: string } -- waypoint -> animatronic id
local placedAt = {} :: { [string]: Instance } -- animatronic id -> waypoint
local warnedMissing = {} :: { [string]: boolean }

function ModelBinder.getTaggedModels(kind: string): { Instance }
	local models = {}
	for _, instance in CollectionService:GetTagged(AIConfig.tagFor(kind)) do
		if instance:IsA("Model") then
			table.insert(models, instance)
		end
	end
	return models
end

function ModelBinder.bind(model: Instance)
	if originalPivots[model] == nil then
		originalPivots[model] = (model :: Model):GetPivot()
	end
end

function ModelBinder.unbind(animatronic)
	local waypoint = placedAt[animatronic.Id]
	if waypoint then
		occupied[waypoint] = nil
		placedAt[animatronic.Id] = nil
	end
end

-- Puts every bound model back where it was before the night started.
function ModelBinder.restoreAll()
	for model, pivot in originalPivots do
		if model.Parent then
			(model :: Model):PivotTo(pivot)
		end
	end
	table.clear(originalPivots)
	table.clear(occupied)
	table.clear(placedAt)
end

local function waypointLocation(waypoint: Instance): string
	local location = waypoint:GetAttribute("Location")
	return if type(location) == "string" then location else waypoint.Name
end

local function waypointCFrame(waypoint: Instance): CFrame
	if waypoint:IsA("Attachment") then
		return (waypoint :: Attachment).WorldCFrame
	end
	return (waypoint :: BasePart):GetPivot()
end

-- Best waypoint for this animatronic at `location`: one made for this model,
-- then one made for its kind, then a free generic one, then any generic one.
local function findWaypoint(animatronic, location: string): Instance?
	local forModel, forKind, freeGeneric, anyGeneric
	for _, waypoint in CollectionService:GetTagged(AIConfig.WaypointTag) do
		if waypointLocation(waypoint) == location then
			local owner = waypoint:GetAttribute("Animatronic")
			if owner == animatronic.Id then
				forModel = forModel or waypoint
			elseif owner == animatronic.Kind then
				forKind = forKind or waypoint
			elseif owner == nil then
				anyGeneric = anyGeneric or waypoint
				local holder = occupied[waypoint]
				if holder == nil or holder == animatronic.Id then
					freeGeneric = freeGeneric or waypoint
				end
			end
		end
	end
	return forModel or forKind or freeGeneric or anyGeneric
end

-- Called whenever an animatronic's location or state changes.
function ModelBinder.sync(animatronic)
	local model = animatronic.Model
	if not model or not model.Parent then
		return
	end

	for key, value in animatronic:getPublicState() do
		model:SetAttribute(if string.sub(key, 1, 2) == "AI" then key else `AI{key}`, value)
	end
	model:SetAttribute("AIKind", animatronic.Kind)
	model:SetAttribute("AIId", animatronic.Id)

	local location = animatronic.Location
	local current = placedAt[animatronic.Id]
	if current and waypointLocation(current) == location then
		return
	end

	local waypoint = findWaypoint(animatronic, location)
	if not waypoint then
		if not warnedMissing[location] then
			warnedMissing[location] = true
			warn(`[AI] No "{AIConfig.WaypointTag}" waypoint for location "{location}"; {animatronic.Id} stays where it is`)
		end
		return
	end

	if current then
		occupied[current] = nil
	end
	occupied[waypoint] = animatronic.Id
	placedAt[animatronic.Id] = waypoint;
	(model :: Model):PivotTo(waypointCFrame(waypoint))
end

return ModelBinder
