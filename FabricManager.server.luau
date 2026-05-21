local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Service & Module Imports
local ServiceRegistry = require(ServerScriptService:WaitForChild("ServiceRegistry"))
local Config          = require(ReplicatedStorage:WaitForChild("SharedConfig"))
local VFX             = require(ReplicatedStorage:WaitForChild("VFXModule"))
local SoundService    = require(ReplicatedStorage:WaitForChild("SoundService"))
local Remotes         = ReplicatedStorage:WaitForChild("Remotes")

-- ── Remotes Helper ───────────────────────────────────────────────────────────
local function getRemote(name, className)
	local r = Remotes:FindFirstChild(name)
	if not r then 
		r = Instance.new(className or "RemoteEvent") 
		r.Name = name 
		r.Parent = Remotes 
	end
	return r
end

local UpdateDualScore = getRemote("UpdateDualScore")
local SabotagePing = getRemote("SabotagePing")
local ObjectiveWarning = getRemote("ObjectiveWarning")
local RackStateChanged = getRemote("RackStateChanged")
local ShowRewardPopup = getRemote("ShowRewardPopup")
local FabricCarrierUpdate = getRemote("FabricCarrierUpdate")

-- ── Constants & Balancing ──
local SABOTAGE_DURATION      = 20
local SABOTAGE_HOLD_DURATION = 3.5
local REBOOT_HOLD_DURATION   = 3
local NORMAL_PICKUP_HOLD     = 2.5
local SABOTAGED_PICKUP_HOLD  = 5.0
local RACK_COOLDOWN          = 5
local BIN_HITBOX_SIZE        = Vector3.new(10, 8, 10)
local SHREDDER_HITBOX_SIZE   = Vector3.new(10, 8, 10)

local GameSettings = {
	TotalFabricNeeded = 5,
	CriticTeamName    = "Critics",
	DesignerTeamName  = "Designers",
}

-- ── State Management ──
local designerScore = 0
local criticScore = 0
local activeSabotages = 0
local tangleTimers = {}
local teamCarriers = { Designers = nil, Critics = nil }

local function UpdateDualScoreUI()
	local MatchRegistry = ServiceRegistry.Get("MatchRegistry")
	local target = MatchRegistry and MatchRegistry.GetTargetScore() or 5
	UpdateDualScore:FireAllClients(designerScore, criticScore, target)
end

local FabricManager = {}

-- ── Carrier Logic (Consolidated from FabricCarrierService) ──

function FabricManager.CanCarry(player)
	local teamName = player.Team and player.Team.Name
	if not teamName or not teamCarriers[teamName] then return (teamName ~= nil) end
	return teamCarriers[teamName] == nil or teamCarriers[teamName] == player
end

function FabricManager.SetCarrier(player)
	local teamName = player.Team and player.Team.Name
	if not teamName then return false end
	if teamCarriers[teamName] and teamCarriers[teamName] ~= player then return false end
	teamCarriers[teamName] = player
	FabricCarrierUpdate:FireAllClients(teamName, player.UserId, player.Name)
	print("[FABRIC] " .. player.Name .. " is now carrying fabric for " .. teamName)
	return true
end

function FabricManager.ClearCarrier(player)
	local teamName = player.Team and player.Team.Name
	if not teamName then return end
	if teamCarriers[teamName] == player then
		teamCarriers[teamName] = nil
		FabricCarrierUpdate:FireAllClients(teamName, nil, nil)
		print("[FABRIC] " .. player.Name .. " is no longer carrying fabric for " .. teamName)
	end
end

function FabricManager.OnPlayerFrozen(player)
	local teamName = player.Team and player.Team.Name
	if teamName and teamCarriers[teamName] == player then
		local char = player.Character
		if char then
			local t1 = char:FindFirstChild("FBRoll")
			local t2 = player.Backpack:FindFirstChild("FBRoll")
			if t1 then t1:Destroy() end
			if t2 then t2:Destroy() end
		end
		teamCarriers[teamName] = nil
		FabricCarrierUpdate:FireAllClients(teamName, nil, nil)
	end
end

function FabricManager.OnFabricDeposited(player)
	FabricManager.ClearCarrier(player)
end

-- ── Tagging Logic (Consolidated from FabricTagService) ──

local function tagCharacter(player)
	local char = player.Character
	if char and player.Team and player.Team.Name == GameSettings.DesignerTeamName then
		CollectionService:AddTag(char, "HoldingFabric")
	end
end

local function untagCharacter(player)
	if player.Character then CollectionService:RemoveTag(player.Character, "HoldingFabric") end
end

local function watchPlayerForTagging(player)
	local function onChildAdded(child) if child.Name == "FBRoll" then tagCharacter(player) end end
	local function onChildRemoved(child)
		if child.Name == "FBRoll" then
			local hasAnother = (player.Character and player.Character:FindFirstChild("FBRoll")) or player.Backpack:FindFirstChild("FBRoll")
			if not hasAnother then untagCharacter(player) end
		end
	end
	player.Backpack.ChildAdded:Connect(onChildAdded)
	player.Backpack.ChildRemoved:Connect(onChildRemoved)
	player.CharacterAdded:Connect(function(char)
		untagCharacter(player)
		char.ChildAdded:Connect(onChildAdded)
		char.ChildRemoved:Connect(onChildRemoved)
		CollectionService:RemoveTag(char, "HoldingFabric")
	end)
	if player.Character then
		player.Character.ChildAdded:Connect(onChildAdded)
		player.Character.ChildRemoved:Connect(onChildRemoved)
	end
end

-- ── Interaction Logic ──

local function isWithinRange(player, target)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return false end
	local dist = (player.Character.HumanoidRootPart.Position - target.Position).Magnitude
	return dist <= (Config.MAX_INTERACTION_DISTANCE or 30)
end

local function attachFabricToBack(player, tool)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local handle = tool:FindFirstChild("Handle") or tool:FindFirstChild("BackHandle")
	if not hrp or not handle then return end
	for _, child in ipairs(handle:GetChildren()) do if child:IsA("WeldConstraint") then child:Destroy() end end
	handle.CFrame = hrp.CFrame * CFrame.new(0, 0, 1.5) * CFrame.Angles(0, math.rad(180), 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp weld.Part1 = handle weld.Parent = handle
end

local function watchFabricEquipment(player)
	local function onChildAdded(child) if child:IsA("Tool") and child.Name == "FBRoll" then task.defer(function() attachFabricToBack(player, child) end) end end
	player.Character.ChildAdded:Connect(onChildAdded)
end

local function setRackState(rack, sabotaged)
	local regular, sabState = rack:FindFirstChild("RegularState"), rack:FindFirstChild("SabotagedState")
	if regular then for _, p in ipairs(regular:GetDescendants()) do if p:IsA("BasePart") then p.Transparency = sabotaged and 1 or 0 p.CanCollide = not sabotaged end end end
	if sabState then for _, p in ipairs(sabState:GetDescendants()) do if p:IsA("BasePart") then p.Transparency = sabotaged and 0 or 1 p.CanCollide = sabotaged end end end
	rack:SetAttribute("IsSabotaged", sabotaged)
	RackStateChanged:FireAllClients(rack, sabotaged)
end

function FabricManager.GetDesignerScore() return designerScore end
function FabricManager.GetCriticScore() return criticScore end
function FabricManager.ResetScores() designerScore = 0 criticScore = 0 end

function FabricManager.CleanseNearbySabotage(player, radius)
	local pos = player.Character and player.Character.PrimaryPart and player.Character.PrimaryPart.Position
	if not pos then return end
	for _, bin in ipairs(CollectionService:GetTagged("FabricBins")) do
		if (bin:GetPivot().Position - pos).Magnitude <= radius and bin:GetAttribute("IsSabotaged") then
			bin:SetAttribute("IsSabotaged", false)
			VFX.Play("SabotageClear", bin:GetPivot().Position)
			SoundService.FireToAll("Unsabotage", bin:GetPivot().Position)
			ObjectiveWarning:FireAllClients("Designers", false)
			local reboot = bin:FindFirstChild("BinReboot")
			if reboot then reboot:Destroy() end
		end
	end
	for _, shredder in ipairs(CollectionService:GetTagged("FabricShredders")) do
		if (shredder:GetPivot().Position - pos).Magnitude <= radius and shredder:GetAttribute("IsSabotaged") then
			shredder:SetAttribute("IsSabotaged", false)
			VFX.Play("SabotageClear", shredder:GetPivot().Position)
			SoundService.FireToAll("Unsabotage", shredder:GetPivot().Position)
			ObjectiveWarning:FireAllClients("Critics", false)
			local reboot = shredder:FindFirstChild("ShredderReboot")
			if reboot then reboot:Destroy() end
		end
	end
end

local function setupFabricRack(rack)
	rack:SetAttribute("IsOnCooldown", false)
	rack:SetAttribute("IsSabotaged", false)
	setRackState(rack, false)

	local function setupPrompt(name, team)
		local p = rack:FindFirstChild(name) or Instance.new("ProximityPrompt")
		p.Name = name p.ActionText = "Collect Fabric" p.ObjectText = "Fabric Rack" p.HoldDuration = NORMAL_PICKUP_HOLD p.MaxActivationDistance = 8 p.Parent = rack
		CollectionService:AddTag(p, team .. "Prompt")
		p.Triggered:Connect(function(player)
			if not (player.Team and player.Team.Name == (team == "Designer" and GameSettings.DesignerTeamName or GameSettings.CriticTeamName)) then return end
			if rack:GetAttribute("IsOnCooldown") or not isWithinRange(player, rack:GetPivot()) then return end
			if not FabricManager.CanCarry(player) then return end
			if player.Backpack:FindFirstChild("FBRoll") or (player.Character and player.Character:FindFirstChild("FBRoll")) then return end

			local wasSab = rack:GetAttribute("IsSabotaged")
			local assets = ReplicatedStorage:FindFirstChild("Assets")
			if assets and assets:FindFirstChild("FBRoll") then assets.FBRoll:Clone().Parent = player.Backpack end
			FabricManager.SetCarrier(player)

			VFX.Play("FabricRackPickup", rack:GetPivot().Position)
			SoundService.FireToAll("FabricPickup", rack:GetPivot().Position)
			if wasSab then setRackState(rack, false) end

			local RewardTracker = ServiceRegistry.Get("RewardTracker")
			if RewardTracker then RewardTracker.OnFabricCollect(player) end
			rack:SetAttribute("IsOnCooldown", true)
			local dp, cp = rack:FindFirstChild("DesignerPickup"), rack:FindFirstChild("CriticPickup")
			if dp then dp.Enabled = false end if cp then cp.Enabled = false end
			task.delay(RACK_COOLDOWN, function()
				if rack and rack.Parent then rack:SetAttribute("IsOnCooldown", false) if dp then dp.Enabled = true end if cp then cp.Enabled = true end end
			end)
		end)
	end
	setupPrompt("DesignerPickup", "Designer")
	setupPrompt("CriticPickup", "Critic")
end

local function setupScoringZone(zone, team, vfxName, sabotagedVfxName)
	local hitbox = zone:FindFirstChild("Hitbox") or Instance.new("Part")
	if not hitbox.Parent then
		hitbox.Name = "Hitbox" hitbox.Size = BIN_HITBOX_SIZE hitbox.Transparency = 1 hitbox.CanCollide = false hitbox.Anchored = true
		hitbox.CFrame = zone:GetPivot() hitbox.Parent = zone
	end
	local depositing = {}
	hitbox.Touched:Connect(function(hit)
		local RoundService = ServiceRegistry.Get("RoundService")
		if not RoundService or RoundService.Phase ~= "Active" then return end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player or not (player.Team and player.Team.Name == (team == "Designer" and GameSettings.DesignerTeamName or GameSettings.CriticTeamName)) then return end
		if depositing[player.UserId] then return end
		local tool = hit.Parent:FindFirstChild("FBRoll") or player.Backpack:FindFirstChild("FBRoll")
		if not tool then return end
		depositing[player.UserId] = true tool:Destroy()
		FabricManager.OnFabricDeposited(player)
		if zone:GetAttribute("IsSabotaged") then
			VFX.Play(sabotagedVfxName, hitbox.Position)
			ShowRewardPopup:FireClient(player, "SABOTAGED!", "Fabric lost!")
		else
			if team == "Designer" then designerScore += 1 else criticScore += 1 end
			UpdateDualScoreUI()
			VFX.Play(vfxName, hitbox.Position)
			local ShowstopperService = ServiceRegistry.Get("ShowstopperService")
			if team == "Designer" then if ShowstopperService then ShowstopperService.OnFabricDunk(player) end
			else if ShowstopperService and ShowstopperService.OnFabricShred then ShowstopperService.OnFabricShred(player) end end
			ShowRewardPopup:FireClient(player, "+25 XP", "+10 Coins")
		end
		task.delay(0.5, function() depositing[player.UserId] = nil end)
	end)
end

-- ── Lifecycle ──

local function resetAll()
	designerScore, criticScore, activeSabotages = 0, 0, 0
	UpdateDualScoreUI()
	teamCarriers = { Designers = nil, Critics = nil }
	FabricCarrierUpdate:FireAllClients("Designers", nil, nil)
	FabricCarrierUpdate:FireAllClients("Critics", nil, nil)
	for _, r in ipairs(CollectionService:GetTagged("FabricRacks")) do setRackState(r, false) r:SetAttribute("IsOnCooldown", false) end
	for _, b in ipairs(CollectionService:GetTagged("FabricBins")) do b:SetAttribute("IsSabotaged", false) end
	for _, s in ipairs(CollectionService:GetTagged("FabricShredders")) do s:SetAttribute("IsSabotaged", false) end
end

task.spawn(function()
	local RoundService = ServiceRegistry.Await("RoundService")
	RoundService.Events.Intermission.Event:Connect(resetAll)
end)

for _, r in ipairs(CollectionService:GetTagged("FabricRacks")) do setupFabricRack(r) end
for _, b in ipairs(CollectionService:GetTagged("FabricBins")) do setupScoringZone(b, "Designer", "FabricDeposit", "SabotagedDeposit") end
for _, s in ipairs(CollectionService:GetTagged("FabricShredders")) do setupScoringZone(s, "Critic", "FabricShred", "SabotagedShred") end

for _, p in ipairs(Players:GetPlayers()) do
	watchPlayerForTagging(p)
	p.CharacterAdded:Connect(function() watchFabricEquipment(p) end)
	if p.Character then watchFabricEquipment(p.Character) end
end
Players.PlayerAdded:Connect(function(p) watchPlayerForTagging(p) p.CharacterAdded:Connect(function() watchFabricEquipment(p) end) end)

ServiceRegistry.Register("FabricManager", FabricManager)
return FabricManager