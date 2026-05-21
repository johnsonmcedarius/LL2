-- ─────────────────────────────────────────────────────────────────────────────
-- LiveOpsService: Event scheduling, bonus multipliers, and Daily Lookbook
-- ─────────────────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ServiceRegistry = require(ServerScriptService:WaitForChild("ServiceRegistry"))
local DataManager     = ServiceRegistry.Await("DataManager")
local GachaService    = ServiceRegistry.Await("GachaService")
local Config          = require(ReplicatedStorage:WaitForChild("SharedConfig"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local function getRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent") r.Name = name r.Parent = Remotes end
	return r
end

local GetDailyChallenges   = getRemote("GetDailyChallenges")
local DailyChallengeUpdate = getRemote("DailyChallengeUpdate")
local GlobalAnnouncement    = getRemote("GlobalAnnouncement")

local LiveOpsEnabled = true -- Now enabled as we've consolidated
local LiveOpsService = {}
local currentEvent = nil
local dailyData = {} -- [userId] = runtime cache

-- ── Challenge Pool (DailyLookbook) ──
local ChallengeTemplates = {
	{Id = "play_3",       Desc = "Play 3 matches",        Goal = 3,   Stat = "MatchesPlayed"},
	{Id = "earn_250xp",   Desc = "Earn 250 XP",           Goal = 250, Stat = "XPEarned"},
	{Id = "earn_500xp",   Desc = "Earn 500 XP",           Goal = 500, Stat = "XPEarned"},
	{Id = "survive_5min", Desc = "Survive 5 minutes total",Goal = 5,  Stat = "SurvivalMins"},
	{Id = "pass_3",       Desc = "Pass the fabric 3 times",Goal = 3,  Stat = "Passes"},
}

-- ── Helpers ──
local function getMidnight(timestamp)
	local date = os.date("!*t", timestamp)
	return os.time({year=date.year, month=date.month, day=date.day, hour=0, min=0, sec=0})
end

-- ── Event Logic ──

function LiveOpsService.GetCurrentEvent()
	if not LiveOpsEnabled then return nil end
	local now = os.time()
	for _, event in ipairs(Config.LIVEOPS.Events or {}) do
		if now >= event.StartTime and now < event.EndTime then return event end
	end
	return nil
end

function LiveOpsService.GetBonusMultiplier(player)
	local event = LiveOpsService.GetCurrentEvent()
	return (event and event.Type == "XPBoost") and (event.Multiplier or 1.5) or 1.0
end

function LiveOpsService.GetCoinMultiplier(player)
	local event = LiveOpsService.GetCurrentEvent()
	return (event and event.Type == "CoinBoost") and (event.Multiplier or 1.5) or 1.0
end

-- ── Daily Lookbook Logic ──

local function getOrCreateDaily(player)
	if dailyData[player.UserId] then return dailyData[player.UserId] end
	local profile = DataManager.GetData(player)
	local saved = profile and profile.DailyLookbook
	local now = os.time()
	local needsReset = not saved or getMidnight(now) > getMidnight(saved.lastReset or 0)

	if needsReset then
		local shuffled = {}
		for _, t in ipairs(ChallengeTemplates) do table.insert(shuffled, t) end
		for i = #shuffled, 2, -1 do local j = math.random(i) shuffled[i], shuffled[j] = shuffled[j], shuffled[i] end
		local chosen = {shuffled[1], shuffled[2], shuffled[3]}
		local fresh = { challenges = chosen, progress = {0, 0, 0}, lastReset = now, completed = false, rewarded = false }
		dailyData[player.UserId] = fresh
		if profile then profile.DailyLookbook = fresh end
		print("[LIVEOPS] New daily challenges for " .. player.Name)
	else
		dailyData[player.UserId] = saved
	end
	return dailyData[player.UserId]
end

local function syncDaily(player)
	local d = dailyData[player.UserId]
	if d then DailyChallengeUpdate:FireClient(player, d.challenges, d.progress, d.completed) end
end

function LiveOpsService.AddProgress(player, stat, amount)
	local d = getOrCreateDaily(player)
	if not d or d.completed then return end
	local changed = false
	for i, c in ipairs(d.challenges) do
		if c.Stat == stat then
			d.progress[i] = math.min((d.progress[i] or 0) + (amount or 1), c.Goal)
			changed = true
		end
	end
	if changed then
		local allDone = true
		for i, c in ipairs(d.challenges) do if (d.progress[i] or 0) < c.Goal then allDone = false break end end
		if allDone then
			d.completed, d.rewarded = true, true
			if math.random(2) == 1 then DataManager.AddCoins(player, 100) else GachaService.AddCrate(player, "CoinDesignerCrate", 1) end
		end
		syncDaily(player)
	end
end

-- ── Lifecycle ──

GetDailyChallenges.OnServerEvent:Connect(function(p) getOrCreateDaily(p) syncDaily(p) end)
DataManager.OnDataLoaded(function(p) getOrCreateDaily(p) syncDaily(p) end)

task.spawn(function()
	while true do
		task.wait(60)
		local newE = LiveOpsService.GetCurrentEvent()
		if newE ~= currentEvent then
			currentEvent = newE
			if currentEvent then GlobalAnnouncement:FireAllClients("EVENT", currentEvent.Name, currentEvent.Description or "") end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p) dailyData[p.UserId] = nil end)

ServiceRegistry.Register("LiveOpsService", LiveOpsService)
return LiveOpsService