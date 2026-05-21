local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

-- Dependencies
local ServiceRegistry = require(ServerScriptService:WaitForChild("ServiceRegistry"))
local Config          = require(ReplicatedStorage:WaitForChild("SharedConfig"))
local SoundService    = require(ReplicatedStorage:WaitForChild("SoundService"))
local SkinEffects     = require(ServerScriptService:WaitForChild("SkinEffectService"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SpawnPodiumVFX    = Remotes:WaitForChild("SpawnPodiumVFX")
local DespawnPodiumVFX  = Remotes:WaitForChild("DespawnPodiumVFX")
local FreezeEvent       = Remotes:WaitForChild("FreezeEvent")

local TeamService = {}

-- ── State ──
local frozenPlayers = {} -- [userId] = {TimeLeft, Podium, PoseAnim, Player, Countdown, TimerLabel}
local frozenCritics = {}
local pendingFreezes = {}
local CLASH_WINDOW = 0.1
local CLASH_PUSH_FORCE = 50

-- ── Team Management ──
local DesignersTeam = Teams:WaitForChild("Designers")
local CriticsTeam = Teams:WaitForChild("Critics")
local LobbyTeam = Teams:WaitForChild("Lobby")

function TeamService.ResetTeams()
	for _, player in ipairs(Players:GetPlayers()) do
		player.Team = LobbyTeam
	end
end

function TeamService.AssignTeams()
	local allPlayers = Players:GetPlayers()
	if #allPlayers < 2 then return {}, {} end

	for i = #allPlayers, 2, -1 do
		local j = math.random(i)
		allPlayers[i], allPlayers[j] = allPlayers[j], allPlayers[i]
	end

	local splitPoint = math.floor(#allPlayers / 2)
	local critics = {}
	local designers = {}

	for i, player in ipairs(allPlayers) do
		if i <= splitPoint then
			player.Team = CriticsTeam
			table.insert(critics, player)
		else
			player.Team = DesignersTeam
			table.insert(designers, player)
		end
	end

	local MatchRegistry = ServiceRegistry.Get("MatchRegistry")
	if MatchRegistry then
		MatchRegistry.CalculateMatchStyle(#allPlayers)
	end

	print("[TEAMSERVICE] 50/50 Split: " .. #critics .. " Critics, " .. #designers .. " Designers")
	return critics, designers
end

-- ── Tag & Freeze Management (Consolidated from TagManager) ──

local function createCountdownBillboard(root)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CancelCountdown"
	billboard.Size = UDim2.fromOffset(120, 40)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "TimerLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = Config.CANCELLATION_TIME .. "s"
	label.Parent = billboard

	return billboard, label
end

function TeamService.CheckTotalFreeze()
	local designers = DesignersTeam:GetPlayers()
	local totalFrozen = 0
	for _ in pairs(frozenPlayers) do totalFrozen += 1 end
	if totalFrozen >= #designers and #designers > 0 then
		ReplicatedStorage:SetAttribute("AllDesignersFrozen", true)
	end
end

function TeamService.CheckTotalCriticFreeze()
	local critics = CriticsTeam:GetPlayers()
	local totalFrozen = 0
	for _ in pairs(frozenCritics) do totalFrozen += 1 end
	if totalFrozen >= #critics and #critics > 0 then
		ReplicatedStorage:SetAttribute("AllCriticsFrozen", true)
	end
end

function TeamService.UnfreezePlayer(targetPlayer, rescuer)
	local data = frozenPlayers[targetPlayer.UserId] or frozenCritics[targetPlayer.UserId]
	if not data then return end

	local isDesigner = frozenPlayers[targetPlayer.UserId] ~= nil
	local frozenTable = isDesigner and frozenPlayers or frozenCritics

	if targetPlayer.Character then
		SkinEffects.ClearManual(targetPlayer.Character)
		local standEffect = targetPlayer:GetAttribute("EquippedSkinEffect") or "None"
		SkinEffects.ApplyManual(targetPlayer, targetPlayer.Character, standEffect)
	end

	if data.Podium then
		DespawnPodiumVFX:FireAllClients(data.Podium:GetPivot().Position)
		SoundService.FireToAll("PodiumDespawn", data.Podium:GetPivot().Position)
		data.Podium:Destroy()
	end

	if data.PoseAnim then data.PoseAnim:Stop() end
	if data.Countdown then data.Countdown:Destroy() end

	local root = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
	local humanoid = targetPlayer.Character and targetPlayer.Character:FindFirstChild("Humanoid")
	if root then root.Anchored = false end

	if targetPlayer.Character and humanoid then
		targetPlayer:SetAttribute("IsGhosting", true)
		humanoid.WalkSpeed = 0
		for _, part in ipairs(targetPlayer.Character:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then part.Transparency = 0.6 end
		end
		task.delay(2, function()
			if not targetPlayer.Character then return end
			targetPlayer:SetAttribute("IsGhosting", false)
			humanoid.WalkSpeed = Config.WALK_SPEED or 16
			for _, part in ipairs(targetPlayer.Character:GetDescendants()) do
				if part:IsA("BasePart") then part.Transparency = 0 end
			end
		end)
	end

	SoundService.FireToAll("PlayerUnfrozen", root and root.Position or Vector3.zero)

	if rescuer then
		local ShowstopperService = ServiceRegistry.Get("ShowstopperService")
		local RewardTracker = ServiceRegistry.Get("RewardTracker")
		if ShowstopperService then ShowstopperService.OnTeamRescue(rescuer) end
		if RewardTracker then RewardTracker.OnUnfreezeAlly(rescuer) end
	end

	frozenTable[targetPlayer.UserId] = nil
	if isDesigner then
		ReplicatedStorage:SetAttribute("AllDesignersFrozen", false)
	else
		ReplicatedStorage:SetAttribute("AllCriticsFrozen", false)
	end
end

function TeamService.FreezePlayer(targetPlayer, attacker)
	local isDesigner = targetPlayer.Team == DesignersTeam
	local isCritic = targetPlayer.Team == CriticsTeam
	if not isDesigner and not isCritic then return end

	local frozenTable = isDesigner and frozenPlayers or frozenCritics
	if frozenTable[targetPlayer.UserId] then return end

	local Relevance = ServiceRegistry.Get("RelevanceSystem")
	if Relevance and Relevance.AddStrike(targetPlayer) then
		if isDesigner then task.defer(TeamService.CheckTotalFreeze) else task.defer(TeamService.CheckTotalCriticFreeze) end
		return
	end

	local char = targetPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChild("Humanoid")
	if not root or not hum then return end

	local tool = char:FindFirstChild("FBRoll") or targetPlayer.Backpack:FindFirstChild("FBRoll")
	if tool then tool:Destroy() end

	local FabricManager = ServiceRegistry.Get("FabricManager")
	if FabricManager and FabricManager.OnPlayerFrozen then
		FabricManager.OnPlayerFrozen(targetPlayer)
	end

	root.Anchored = true
	local RewardTracker = ServiceRegistry.Get("RewardTracker")
	if RewardTracker then RewardTracker.OnPlayerFrozen(targetPlayer) end

	local equippedEffect = targetPlayer:GetAttribute("EquippedSkinEffect") or "None"
	SkinEffects.ApplyManual(targetPlayer, char, equippedEffect)

	local podiumName = targetPlayer:GetAttribute("EquippedPodium") or "BasicPodium"
	local podiumTemplate = ReplicatedStorage.Assets.Podiums:FindFirstChild(podiumName) or ReplicatedStorage.Assets.Podiums.BasicPodium
	local podium = podiumTemplate:Clone()

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {char}
	local rayResult = workspace:Raycast(root.Position, Vector3.new(0, -10, 0), rayParams)
	local groundPos = rayResult and rayResult.Position or (root.Position - Vector3.new(0, 3, 0))

	podium:PivotTo(CFrame.new(groundPos) * CFrame.Angles(0, math.rad(root.Orientation.Y), 0))
	podium.Parent = workspace

	local standPoint = podium:FindFirstChild("StandPoint", true)
	if standPoint then root.CFrame = standPoint.WorldCFrame
	else root.CFrame = CFrame.new(groundPos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.rad(root.Orientation.Y), 0) end

	local poseID = targetPlayer:GetAttribute("EquippedPose") or "rbxassetid://74997474532222"
	local animObj = Instance.new("Animation")
	animObj.AnimationId = poseID
	local poseTrack = hum:LoadAnimation(animObj)
	poseTrack:Play()

	local promptPart = podium:FindFirstChild("Base") or podium:FindFirstChildWhichIsA("BasePart") or podium.PrimaryPart
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Unfreeze Teammate"
	prompt.ObjectText = targetPlayer.Name
	prompt.HoldDuration = 0
	prompt.Parent = promptPart

	CollectionService:AddTag(prompt, isDesigner and "DesignerPrompt" or "CriticPrompt")

	prompt.Triggered:Connect(function(rescuer)
		if rescuer.Team == targetPlayer.Team then
			TeamService.UnfreezePlayer(targetPlayer, rescuer)
		end
	end)

	local billboard, timerLabel = createCountdownBillboard(root)
	local podiumPos = podium:GetPivot().Position
	SpawnPodiumVFX:FireAllClients(podiumPos)
	SoundService.FireToAll("PodiumSpawn", podiumPos)

	frozenTable[targetPlayer.UserId] = {
		TimeLeft = Config.CANCELLATION_TIME,
		Podium = podium,
		PoseAnim = poseTrack,
		Player = targetPlayer,
		Countdown = billboard,
		TimerLabel = timerLabel,
	}

	if attacker then
		if RewardTracker then RewardTracker.OnFreezePlayer(attacker) end
		local ShowstopperService = ServiceRegistry.Get("ShowstopperService")
		if ShowstopperService and ShowstopperService.OnFreezePlayer then ShowstopperService.OnFreezePlayer(attacker) end
	end

	if isDesigner then TeamService.CheckTotalFreeze() else TeamService.CheckTotalCriticFreeze() end
end

-- ── Systems Loop ──
task.spawn(function()
	while true do
		task.wait(1)
		local Relevance = ServiceRegistry.Get("RelevanceSystem")
		
		local function processFrozen(frozenTable)
			for userId, data in pairs(frozenTable) do
				local isCamped = false
				local targetChar = data.Player.Character
				local enemyTeam = (data.Player.Team == DesignersTeam) and CriticsTeam or DesignersTeam
				
				if enemyTeam then
					for _, enemy in ipairs(enemyTeam:GetPlayers()) do
						local ec = enemy.Character
						if ec and targetChar and ec:FindFirstChild("HumanoidRootPart") and targetChar:FindFirstChild("HumanoidRootPart") then
							if (ec.HumanoidRootPart.Position - targetChar.HumanoidRootPart.Position).Magnitude < Config.ANTI_CAMP_DISTANCE then
								isCamped = true break
							end
						end
					end
				end

				if not isCamped then
					data.TimeLeft -= 1
					if data.TimerLabel and data.TimerLabel.Parent then data.TimerLabel.Text = data.TimeLeft .. "s" end
					if data.TimeLeft <= 0 then
						local pToElim = data.Player
						frozenTable[userId] = nil
						if Relevance then Relevance.Eliminate(pToElim) end
						if data.Podium then data.Podium:Destroy() end
						if data.Countdown then data.Countdown:Destroy() end
					end
				end
			end
		end
		
		processFrozen(frozenPlayers)
		processFrozen(frozenCritics)
	end
end)

-- ── Clash Mechanic ──
local function applyClashPushback(p1, p2)
	local p1Root = p1.Character and p1.Character:FindFirstChild("HumanoidRootPart")
	local p2Root = p2.Character and p2.Character:FindFirstChild("HumanoidRootPart")
	if not p1Root or not p2Root then return end

	local dir = (p1Root.Position - p2Root.Position).Unit
	if dir.Magnitude == 0 then dir = Vector3.new(1, 0, 0) end

	p1Root.AssemblyLinearVelocity = dir * CLASH_PUSH_FORCE
	p2Root.AssemblyLinearVelocity = -dir * CLASH_PUSH_FORCE

	local midPoint = (p1Root.Position + p2Root.Position) / 2
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ClashNotification = remotes:FindFirstChild("ClashNotification")
	if ClashNotification then ClashNotification:FireAllClients(p1.Name, p2.Name) end
end

FreezeEvent.OnServerEvent:Connect(function(player, targetChar)
	if not (player.Team == DesignersTeam or player.Team == CriticsTeam) then return end
	if not targetChar or not targetChar:FindFirstChild("HumanoidRootPart") then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local dist = (root.Position - targetChar.HumanoidRootPart.Position).Magnitude
	if dist > (Config.MAX_INTERACTION_DISTANCE + 5) then return end

	local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
	if not targetPlayer or player.Team == targetPlayer.Team then return end

	if targetPlayer:GetAttribute("MainEventActive") or targetPlayer:GetAttribute("VIPProtection") then return end
	if targetPlayer:GetAttribute("ControlsInverted") then
		TeamService.FreezePlayer(player, targetPlayer)
		return
	end

	if frozenPlayers[targetPlayer.UserId] or frozenCritics[targetPlayer.UserId] then return end

	local now = os.clock()
	local pending = pendingFreezes[targetPlayer.UserId]
	if pending and (now - pending.timestamp) < CLASH_WINDOW then
		applyClashPushback(player, targetPlayer)
		pendingFreezes[player.UserId] = nil
		pendingFreezes[targetPlayer.UserId] = nil
		return
	end

	pendingFreezes[player.UserId] = { targetUserId = targetPlayer.UserId, timestamp = now }
	task.delay(CLASH_WINDOW, function()
		if pendingFreezes[player.UserId] and pendingFreezes[player.UserId].targetUserId == targetPlayer.UserId then
			pendingFreezes[player.UserId] = nil
		end
	end)

	TeamService.FreezePlayer(targetPlayer, player)
end)

-- ── API ──
function TeamService.Unfreeze(player) TeamService.UnfreezePlayer(player, nil) end

ServiceRegistry.Register("TeamService", TeamService)
return TeamService
