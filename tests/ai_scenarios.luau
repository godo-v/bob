-- AI scenario tests: a minimal Roblox mock with a virtual clock. Run via tests/run.sh.
local now = 0
local sleepers = {}
local log = {}

local task = {}
function task.spawn(f, ...)
	local co = coroutine.create(f)
	local ok, err = coroutine.resume(co, ...)
	if not ok then error(err) end
	return co
end
function task.wait(t)
	t = math.max(t or 0, 1/60)
	table.insert(sleepers, { co = coroutine.running(), wake = now + t })
	coroutine.yield()
	return t
end
local function runFor(seconds)
	local stop = now + seconds
	while true do
		table.sort(sleepers, function(a, b) return a.wake < b.wake end)
		local s = sleepers[1]
		if not s or s.wake > stop then now = stop return end
		table.remove(sleepers, 1)
		now = s.wake
		local ok, err = coroutine.resume(s.co)
		if not ok then error(err) end
	end
end

local Signal = {}
Signal.__index = Signal
local function newSignal() return setmetatable({ handlers = {} }, Signal) end
function Signal:Connect(f) table.insert(self.handlers, f) end
function Signal:fireAll(...) for _, f in self.handlers do f(...) end end

local newInstance
local InstanceMeta = {}
InstanceMeta.__index = function(self, key)
	local methods = rawget(self, "_methods")
	if methods[key] then return methods[key] end
	local children = rawget(self, "_children")
	if children[key] then return children[key] end
	return nil
end
InstanceMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old then old._children[self.Name] = nil end
		rawset(self, "_parent", value)
		if value then value._children[self.Name] = self end
	elseif key == "Name" then
		rawset(self, "_name", value)
	else
		rawset(self, key, value)
	end
end

local methods = {}
function methods.FindFirstChild(self, name) return self._children[name] end
function methods.WaitForChild(self, name) return assert(self._children[name], "missing " .. name) end
function methods.SetAttribute(self, k, v) self._attributes[k] = v end
function methods.GetAttribute(self, k) return self._attributes[k] end
function methods.ClearAllChildren(self) table.clear(self._children) end
function methods.GetService(self, name) return self._children[name] end
function methods.IsServer() return true end
function methods.GetPlayers() return {} end
function methods.Fire(self, ...) self.Event:fireAll(...) end
function methods.FireAllClients(self, name, payload) table.insert(log, { t = now, name = name, p = payload }) end
function methods.FireClient(self, player, name, payload) table.insert(log, { t = now, name = name, p = payload, to = player }) end

function newInstance(className, name, parent)
	local inst = setmetatable({ _methods = methods, _children = {}, _attributes = {}, ClassName = className }, InstanceMeta)
	rawset(inst, "_nameProxy", true)
	inst.Name = name or className
	if className == "BindableEvent" then rawset(inst, "Event", newSignal()) end
	if className == "RemoteEvent" then rawset(inst, "OnServerEvent", newSignal()) end
	if parent then inst.Parent = parent end
	return inst
end
-- Name lives in _name
local oldIndex = InstanceMeta.__index
InstanceMeta.__index = function(self, key)
	if key == "Name" then return rawget(self, "_name") end
	if key == "Parent" then return rawget(self, "_parent") end
	return oldIndex(self, key)
end

local Instance = { new = function(className) return newInstance(className) end }

local game = newInstance("DataModel", "game")
for _, svc in { "ReplicatedStorage", "ServerScriptService", "Players", "RunService", "Workspace", "StarterPlayer" } do
	newInstance("Service", svc, game)
end

-- Build module tree from SOURCES
local moduleSource = {}
local function ensureFolder(parent, name)
	return parent._children[name] or newInstance("Folder", name, parent)
end
local function mount(rootInst, prefix)
	for path, src in SOURCES do
		if string.sub(path, 1, #prefix) == prefix then
			local rel = string.sub(path, #prefix + 2)
			local parts = string.split(rel, "/")
			local parent = rootInst
			for i = 1, #parts - 1 do parent = ensureFolder(parent, parts[i]) end
			local file = parts[#parts]
			local name = string.gsub(string.gsub(string.gsub(file, "%.luau$", ""), "%.server$", ""), "%.client$", "")
			local m = newInstance("ModuleScript", name, parent)
			moduleSource[m] = { src = src, path = path }
		end
	end
end
mount(ensureFolder(game.ReplicatedStorage, "Shared"), "src/shared")
mount(ensureFolder(game.ServerScriptService, "AI"), "src/server/AI")

local cache = {}
local baseEnv = getfenv(1)
local function req(m)
	if cache[m] ~= nil then return cache[m] end
	local info = assert(moduleSource[m], "not a module")
	local fn = assert(loadstring(info.src, info.path))
	local env = setmetatable({
		script = m, game = game, require = req, task = task, Instance = Instance,
		os = { clock = function() return now end },
		warn = function(...) print("WARN", ...) end,
		typeof = function(v) return type(v) end,
	}, { __index = baseEnv })
	setfenv(fn, env)
	local result = fn()
	cache[m] = result
	return result
end

local AI = game.ServerScriptService.AI
local Director = req(AI.Director)
local GameState = Director.GameState
local AIConfig = req(game.ReplicatedStorage.Shared.AI.AIConfig)
Director.init()

local failed = {}
Director.NightFailed:Connect(function(reason) table.insert(failed, { t = now, reason = reason }) end)

local function reset()
	Director.endNight()
	table.clear(log); table.clear(failed); table.clear(sleepers)
	now = 0
end
local function events(name)
	local out = {}
	for _, e in log do if e.name == name then table.insert(out, e) end end
	return out
end
local function only(ids)
	local keep = {}
	for _, id in ids do keep[id] = true end
	local order = {}
	for _, id in { "Bunny", "Weasel", "Bear", "Wolf", "Fox", "TestDummy", "HR" } do
		if keep[id] then table.insert(order, id) end
	end
	AIConfig.SpawnOrder = order
end
local function check(cond, msg)
	print((cond and "PASS " or "FAIL ") .. msg)
	if not cond then _G.anyFail = true end
end

math.randomseed(42)

-- 1. Bear, window never flashed: kills within 7s of reaching window on night 3
reset(); only({ "Bear" })
Director.startNight(3, { ActiveRoles = { "MainOfficeGuard" } })
runFor(400)
local at, js = events("AtEntrance"), events("Jumpscare")
check(#at > 0 and #js > 0, "Bear reaches window and kills")
if #at > 0 and #js > 0 then
	local dt = js[1].t - at[1].t
	check(math.abs(dt - 7) < 0.2, ("Bear kill delay night 3 = %.2f (want 7)"):format(dt))
	check(at[1].p.Entrance == "Window" and at[1].p.Office == "MainOffice", "Bear at Main Office window")
end
check(#events("AudioCue") >= 2, "Bear plays audio cues when moving")
check(#failed == 1 and failed[1].reason == "AllDead", "NightFailed AllDead when only role dies")

-- 1b. Bear night 5 deadline 3s
reset(); only({ "Bear" })
Director.startNight(5, { ActiveRoles = { "MainOfficeGuard" } })
runFor(400)
at, js = events("AtEntrance"), events("Jumpscare")
check(#js > 0 and math.abs(js[1].t - at[1].t - 3) < 0.2, "Bear kill delay night 5 = 3s")

-- 2. Bear flashed: never kills
reset(); only({ "Bear" })
Director.startNight(3, { ActiveRoles = { "MainOfficeGuard", "PatientWardNurse" } })
GameState.setFlashlightTarget("MainOfficeGuard", "MainOffice.Window")
GameState.setFlashlightTarget("PatientWardNurse", "PatientWardOffice.Window")
runFor(600)
check(#events("Jumpscare") == 0 and #events("Repelled") > 0, "Flashed Bear is repelled, no kills")

-- 3. Bunny targets vents; closed vents repel
reset(); only({ "Bunny" })
Director.startNight(1, { ActiveRoles = { "MainOfficeGuard", "PatientWardNurse" } })
GameState.setEntranceBlocked("MainOffice", "LeftVent", true)
GameState.setEntranceBlocked("PatientWardOffice", "RightVent", true)
runFor(1500)
local okEntr = true
for _, e in events("AtEntrance") do
	local k = e.p.Office .. "." .. e.p.Entrance
	if k ~= "MainOffice.LeftVent" and k ~= "PatientWardOffice.RightVent" then okEntr = false end
end
check(#events("AtEntrance") > 1 and okEntr, "Bunny only uses Main left vent / Ward right vent")
check(#events("Jumpscare") == 0, "Closed vents stop Bunny")

-- 4. Fox: electrician hides -> survives; no hide -> dies 3s after charge
reset(); only({ "Fox" })
Director.startNight(1, { ActiveRoles = { "Electrician" } })
GameState.setHiding("Electrician", true)
runFor(800)
check(#events("Charge") > 0 and #events("Jumpscare") == 0, "Hiding Electrician survives Fox charges")
reset(); only({ "Fox" })
Director.startNight(1, { ActiveRoles = { "Electrician" } })
GameState.setFlashlightTarget("Electrician", "ElectricalHallway")
runFor(800)
local ch = events("Charge"); js = events("Jumpscare"); at = events("AtEntrance")
check(#ch > 0 and #js > 0 and math.abs(js[1].t - ch[1].t - 3) < 0.2, "Fox kills 3s after charge if not hiding")
check(#at > 0 and math.abs(ch[1].t - at[1].t) < 0.2, "Fox charges immediately when spotted")

-- 5. Wolf spawns in any game and charges from the hallway when left unchecked
reset(); only({ "Wolf" })
Director.startNight(1, { ActiveRoles = { "Electrician" } })
check(Director.getAnimatronic("Wolf") ~= nil, "Wolf spawns without multiplayer")
runFor(1500)
ch = events("Charge"); at = events("AtEntrance"); js = events("Jumpscare")
check(#ch > 0 and math.abs(ch[1].t - at[1].t - 20) < 0.2, "Unchecked Wolf charges after 20s in hallway (night 1)")
check(#js > 0 and math.abs(js[1].t - ch[1].t - 3) < 0.2, "Wolf kills 3s after charge if not hiding")

-- 5b. Weasel stares through the window (harmless), then attacks the door
reset(); only({ "Weasel" })
Director.startNight(2, { ActiveRoles = { "MainOfficeGuard", "PatientWardNurse" } })
runFor(3000)
local stares, doorAttacks, windowAttacks, orderOk = 0, 0, 0, true
local lastStare = {}
for _, e in log do
	if e.name == "Staring" then
		stares += 1
		lastStare[e.p.Office] = true
	elseif e.name == "AtEntrance" then
		if e.p.Kind == "Window" then windowAttacks += 1 end
		if e.p.Kind == "Door" then
			doorAttacks += 1
			local expected = if e.p.Office == "MainOffice" then "RightDoor" else "LeftDoor"
			if not lastStare[e.p.Office] or e.p.Entrance ~= expected then orderOk = false end
			lastStare[e.p.Office] = nil
		end
	end
end
check(stares > 0 and doorAttacks > 0 and windowAttacks == 0, ("Weasel never attacks windows (stares=%d doors=%d)"):format(stares, doorAttacks))
check(orderOk, "Weasel stares through window before each door attack (Main right / Ward left)")

-- 6. Test Dummy: door open -> released, kills Drug guard, drains power, boosts
reset(); only({ "TestDummy", "Bunny" })
Director.startNight(1, { ActiveRoles = { "DrugRoomGuard", "MainOfficeGuard", "PatientWardNurse", "Electrician" } })
GameState.setHiding("Electrician", true)
runFor(600)
local rel = events("TestDummyReleased")
check(#rel == 1, "Test Dummy released when Drug Room door left open")
local firstKill = events("Jumpscare")[1]
check(firstKill and firstKill.p.Role == "DrugRoomGuard", "Released Test Dummy kills Drug Room Guard first")
check(#events("PowerDrained") == 0, "No power drained when no door stops the Test Dummy")

-- 6a. Released dummy stopped by doors drains only Main Office / Patient Ward
reset(); only({ "TestDummy" })
Director.startNight(1, { ActiveRoles = { "DrugRoomGuard", "MainOfficeGuard", "PatientWardNurse", "Electrician" } })
GameState.setHiding("Electrician", true)
for _, office in { "MainOffice", "PatientWardOffice" } do
	for _, entrance in { "LeftDoor", "RightDoor", "LeftVent", "RightVent" } do
		GameState.setEntranceBlocked(office, entrance, true)
	end
	GameState.setFlashlightTarget(if office == "MainOffice" then "MainOfficeGuard" else "PatientWardNurse", office .. ".Window")
end
runFor(1200)
local drains = events("PowerDrained")
local drainOk = #drains > 0
for _, d in drains do
	if d.p.Amount ~= 0.25 or d.p.Entrance == "LeftVent" or d.p.Entrance == "RightVent"
		or (d.p.Office ~= "MainOffice" and d.p.Office ~= "PatientWardOffice") then drainOk = false end
end
check(#events("TestDummyReleased") == 1, "Test Dummy released (Drug Room door open)")
check(drainOk, ("Doors that stop the released dummy lose 25%% (drains=%d)"):format(#drains))
check(GameState.getPower("DrugRoom") == 1 and GameState.getPower("ElectricalRoom") == 1, "Drug Room / Electrical Room power untouched")
check(GameState.getPower("MainOffice") < 1 or GameState.getPower("PatientWardOffice") < 1, "Office power actually drained")

-- 6b. Door closed -> never released
reset(); only({ "TestDummy" })
Director.startNight(1, { ActiveRoles = { "DrugRoomGuard" } })
GameState.setEntranceBlocked("DrugRoom", "Door", true)
runFor(600)
check(#events("TestDummyReleased") == 0 and #events("Repelled") > 3, "Closed Drug Room door holds Test Dummy")

-- 6c. Boost multiplier
reset(); only({ "TestDummy", "Bunny" })
Director.startNight(1, nil)
local dummy = Director.getAnimatronic("TestDummy")
local bunny = Director.getAnimatronic("Bunny")
dummy.Released = true; dummy.TargetOffice = "MainOffice"
check(Director.getSpeedMultiplier("MainOffice", bunny) == 1.75, "Released dummy boosts others to same office")
check(Director.getSpeedMultiplier("PatientWardOffice", bunny) == 1, "No boost for other offices")
check(Director.getSpeedMultiplier("MainOffice", dummy) == 1, "Dummy doesn't boost itself")

-- 7. HR: overloaded nurse -> after grace, kills all in order, NightFailed
reset(); only({ "HR" })
Director.startNight(1, nil)
runFor(10)
check(#events("HRReleased") == 0, "HR waits while nurse keeps up")
GameState.setNurseWorkload(1)
runFor(14)
check(#events("HRReleased") == 0, "HR honours 15s grace period")
runFor(20)
local order = {}
for _, e in events("Jumpscare") do table.insert(order, e.p.Role) end
check(table.concat(order, ",") == "PatientWardNurse,MainOfficeGuard,DrugRoomGuard,Electrician", "HR kill order: " .. table.concat(order, ","))
check(#failed == 1 and failed[1].reason == "FacilityTerminated", "HR ends night with FacilityTerminated")

-- 7b. HR on nurse death
reset(); only({ "HR" })
Director.startNight(1, nil)
GameState.killRole("PatientWardNurse", "Test")
runFor(20)
check(#events("HRReleased") == 1, "HR released when nurse dies")

-- 8. Full night 5 smoke test with everything, no defenses
reset(); only({ "Bunny", "Weasel", "Bear", "Wolf", "Fox", "TestDummy", "HR" })
Director.startNight(5, nil)
runFor(600)
print("smoke: events", #log, "kills", #events("Jumpscare"), "failed", failed[1] and failed[1].reason)
check(#failed == 1, "Full night ends in failure with no defense")

-- 9. Warn electrician remote
reset(); only({})
Director.startNight(1, nil)
local guard, elec, other = { Name = "g" }, { Name = "e" }, { Name = "o" }
GameState.assignPlayer("MainOfficeGuard", guard); GameState.assignPlayer("Electrician", elec)
local remote = game.ReplicatedStorage.AIRemotes.WarnElectrician
now = 100
remote.OnServerEvent:fireAll(other, "Fox")
remote.OnServerEvent:fireAll(guard, "Fox")
remote.OnServerEvent:fireAll(guard, "Fox")
local w = events("ElectricianWarning")
check(#w == 1 and w[1].to == elec and w[1].p.Animatronic == "Fox", "WarnElectrician relays once (guard only, cooldown)")

print(_G.anyFail and "SOME TESTS FAILED" or "ALL TESTS PASSED")
