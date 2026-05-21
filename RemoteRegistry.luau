local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RemoteRegistry = {}


local REMOTE_NAMES = {
	-- Generic Categorized Remotes
	"AbilityEvent",
	"MatchStateEvent",
	"TagEvent",
	"EconomyEvent",
	"UiEvent",
	"CombatEvent",
	"MatchFlowEvent",
	"SoundEvent",

	-- Legacy / Specialized (To be migrated)
	"FreezeEvent",
	"UpdateFabricUI",
	"OpenMarketplace",
	"TriggerUnboxing",
	"CratePurchaseRequest",
	"UpdateDualScore",
	"MatchStart",
	"MatchEnd",
	"MatchIntermission",
}

-- Cache
local cache = {}

function RemoteRegistry.Get(name)
	if cache[name] then return cache[name] end

	local existing = Remotes:FindFirstChild(name)
	if existing then
		cache[name] = existing
		return existing
	end

	-- Name BEFORE parent to avoid race condition
	local remote = Instance.new("RemoteEvent")
	remote.Name   = name
	remote.Parent = Remotes

	cache[name] = remote
	return remote
end

function RemoteRegistry.GetFunction(name)
	if cache[name] then return cache[name] end

	local existing = Remotes:FindFirstChild(name)
	if existing then
		cache[name] = existing
		return existing
	end

	local rf = Instance.new("RemoteFunction")
	rf.Name   = name
	rf.Parent = Remotes

	cache[name] = rf
	return rf
end

-- Pre-create all remotes at startup
for _, name in ipairs(REMOTE_NAMES) do
	RemoteRegistry.Get(name)
end

return RemoteRegistry