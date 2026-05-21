local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local StarterGui        = game:GetService("StarterGui")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local PlayerGui = player:WaitForChild("PlayerGui")

local SoundService = require(ReplicatedStorage:WaitForChild("SoundService"))
local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local Config       = require(ReplicatedStorage:WaitForChild("SharedConfig"))

-- ── Core UI Cleaner ──────────────────────────────────────────────────────────
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- ── Remotes ──────────────────────────────────────────────────────────────────
local AbilityEvent    = Remotes:WaitForChild("AbilityEvent")
local EconomyEvent    = Remotes:WaitForChild("EconomyEvent")
local MatchStateEvent = Remotes:WaitForChild("MatchStateEvent")
local TagEvent        = Remotes:WaitForChild("TagEvent")
local UpdateDualScore = Remotes:WaitForChild("UpdateDualScore")
local PostMatchXP     = Remotes:WaitForChild("PostMatchXP")

local VFXModule
local ok, result = pcall(function()
	return require(ReplicatedStorage:WaitForChild("VFXModule", 3))
end)
if ok then VFXModule = result end

-- ── UI State & Constants ─────────────────────────────────────────────────────
local activeCooldowns = {}
local rewardQueue = {}
local rewardActive = false
local isNeonPulsing = false
local neonPulseConn = nil
local lastDesignerScore = 0
local lastCriticScore = 0
local isClutchFlashActive = false
local currentCoins = -1 
local isCoinAnimating = false
local activeMenu = nil
local isMenuAnimating = false
local menuDebounceTime = 0.5
local lastMenuClickTime = 0
local inMatch = false

local REST_POSITIONS = {}

local RARITY_COLORS = {
	Common    = Color3.fromRGB(180, 180, 180),
	Rare      = Color3.fromRGB(80, 130, 255),
	Legendary = Color3.fromRGB(255, 180, 0),
	Mythic    = Color3.fromRGB(255, 50, 150),
}

local TWEEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local OUT_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local IN_INFO  = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FAST_IN  = TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_OFFSET = 50

-- ── Transition Configurations ────────────────────────────────────────────────
local LOBBY_REST = {
	BottomNav        = UDim2.new(0.5, 0,  1, -14),
	CurrencyDisplay  = UDim2.new(1, -12,  0,  12),
	DailyLookbookButton = UDim2.new(0,  12,  0.5, 0),
}
local LOBBY_OFF = {
	BottomNav        = UDim2.new(0.5, 0,  1.25, 0),
	CurrencyDisplay  = UDim2.new(1, -12, -0.15, 0),
	DailyLookbookButton = UDim2.new(-0.15, 0, 0.5,  0),
}
local HUD_REST = {
	ScoreboardFrame = UDim2.new(0.5, -150, 0.02, 0),
	ActionHotbar    = UDim2.new(0,    15,  1, -200),
	UltimateModule  = UDim2.new(0.5, -110, 1, -140),
	StatusTracker   = UDim2.new(0,    15,  1, -170),
}
local HUD_OFF = {
	ScoreboardFrame = UDim2.new(0.5, -150, -0.12, 0),
	ActionHotbar    = UDim2.new(0,    15,  1.15,  0),
	UltimateModule  = UDim2.new(0.5, -110, 1.22,  0),
	StatusTracker   = UDim2.new(-0.22, 0,  1, -170),
}

-- ── Menu Configuration ───────────────────────────────────────────────────────
local Menus = {
	Shop = { Gui = "ShopMenu", Frame = "ShopFrame" },
	Inventory = { Gui = "InventoryMenu", Frame = "MainWrapper" },
	Lookbook = { Gui = "DailyLookbook", Frame = "MainModal" },
	Marketplace = { Gui = "MetaMenus", Frame = "AbilityMarketplace" },
	Promo = { Gui = "MetaMenus", Frame = "PromoCodesModule" },
	Quests = { Gui = "QuestMenu", Frame = "MainFrame" },
	Settings = { Gui = "SettingsMenu", Frame = "MainFrame" }
}

-- ── UI Helpers ───────────────────────────────────────────────────────────────
local function getFrame(name)
	return PlayerGui:FindFirstChild(name, true)
end

local function formatNumber(num)
	local formatted = tostring(num)
	local k = 0
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then break end
	end
	return formatted
end

local function setCanvasAlpha(frame, alpha)
	local canvasGroup = frame:FindFirstChildWhichIsA("CanvasGroup")
	if canvasGroup then
		canvasGroup.GroupTransparency = 1 - alpha
	else
		frame.BackgroundTransparency = 1 - alpha
		for _, child in ipairs(frame:GetDescendants()) do
			if child:IsA("GuiObject") then
				if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then child.TextTransparency = 1 - alpha end
				if child:IsA("ImageLabel") or child:IsA("ImageButton") then child.ImageTransparency = 1 - alpha end
				if child:IsA("UIStroke") then child.Transparency = 1 - alpha end
			end
		end
	end
end

local function emitVFX(effectName, position)
	if VFXModule and VFXModule.Play then VFXModule.Play(effectName, position) end
end

-- ── Core HUD Logic ──────────────────────────────────────────────────────────

local function updateAbilitySlots(slots, unlockedSlots)
	for i = 1, 3 do
		local slot = getFrame("Slot" .. i .. "_Weapon") or getFrame("Slot" .. i .. "_Dash") or getFrame("Slot" .. i .. "_Ability")
		if not slot then continue end
		local nameLabel = slot:FindFirstChild("AbilityNameLabel")
		local rarityBorder = slot:FindFirstChild("RarityBorder")
		local lockOverlay = slot:FindFirstChild("LockOverlay")
		local abilityName = slots[i]
		if nameLabel then nameLabel.Text = (abilityName and abilityName ~= "" and abilityName ~= "Empty") and abilityName or (i == 1 and "Visit Shop!" or "") end
		if rarityBorder then
			local abilityData = Config.ABILITIES[abilityName]
			if abilityData and abilityData.Rarity then rarityBorder.BackgroundColor3 = RARITY_COLORS[abilityData.Rarity] rarityBorder.Visible = true
			else rarityBorder.Visible = false end
		end
		if lockOverlay then lockOverlay.Visible = (i > (unlockedSlots or 1)) end
	end
end

local function runCooldown(abilityName, duration)
	local slot = getFrame(abilityName .. "Slot")
	if not slot then return end
	local overlay = slot:FindFirstChild("CooldownOverlay")
	local label = slot:FindFirstChild("CooldownLabel")
	if activeCooldowns[abilityName] then task.cancel(activeCooldowns[abilityName]) end
	local start = os.clock()
	activeCooldowns[abilityName] = task.spawn(function()
		while true do
			local rem = math.max(0, duration - (os.clock() - start))
			if label then label.Text = string.format("%.1f", rem) .. "s" label.Visible = rem > 0 end
			if overlay then
				local pct = rem / duration
				overlay.Size = UDim2.new(1, 0, pct, 0)
				overlay.Position = UDim2.new(0, 0, 1 - pct, 0)
				overlay.Visible = rem > 0
			end
			if rem <= 0 then break end
			task.wait(0.05)
		end
		activeCooldowns[abilityName] = nil
	end)
end

-- ── XP & Reward Logic ────────────────────────────────────────────────────────
local function GetRequiredXP(level) return math.floor(Config.BASE_XP * (level ^ Config.XP_MULTIPLIER)) end

local function animateXPBar(currentLevel, currentXP, xpEarned)
	local xpFill = getFrame("XPBarFill")
	local xpLabel = getFrame("XPLabel")
	local levelUpBanner = getFrame("LevelUpBanner")
	if not xpFill then return end
	local required = GetRequiredXP(currentLevel)

	local startPct = math.clamp(currentXP / required, 0, 1)
	local endXP, newLevel, didLevelUp = currentXP + xpEarned, currentLevel, false
	while endXP >= GetRequiredXP(newLevel) do endXP -= GetRequiredXP(newLevel) newLevel += 1 didLevelUp = true end
	local endPct = math.clamp(endXP / GetRequiredXP(newLevel), 0, 1)
	if xpLabel then xpLabel.Text = "Level " .. currentLevel end
	xpFill.Size = UDim2.new(startPct, 0, 1, 0)
	task.wait(0.5)
	if didLevelUp then
		TweenService:Create(xpFill, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {Size = UDim2.new(1, 0, 1, 0)}):Play()
		task.wait(0.9)
		TweenService:Create(xpFill, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(255, 220, 0)}):Play()
		if levelUpBanner then
			levelUpBanner.Visible = true
			local lvlLabel = levelUpBanner:FindFirstChildOfClass("TextLabel")
			if lvlLabel then lvlLabel.Text = "LEVEL UP!\n" .. newLevel end
			task.delay(2, function() levelUpBanner.Visible = false end)
		end
		task.wait(0.3)
		xpFill.Size = UDim2.new(0, 0, 1, 0)
		if xpLabel then xpLabel.Text = "Level " .. newLevel end
	end
	TweenService:Create(xpFill, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {Size = UDim2.new(endPct, 0, 1, 0)}):Play()
end

local function showNextReward()
	if rewardActive or #rewardQueue == 0 then return end
	rewardActive = true
	local data = table.remove(rewardQueue, 1)
	local popup = getFrame("RewardPopup")
	if not popup then rewardActive = false return end
	popup.Text = data.xpText .. "  " .. data.coinsText
	popup.Visible = true popup.TextTransparency = 0 popup.Position = UDim2.new(0.5, 0, 0.4, 0)
	TweenService:Create(popup, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.28, 0), TextTransparency = 1 }):Play()
	task.delay(1.3, function() popup.Visible = false rewardActive = false showNextReward() end)
end

-- ── Currency Display ─────────────────────────────────────────────────────────
local function updateCoinDisplay(newCoins, animate)
	local lobbyHUD = PlayerGui:FindFirstChild("LobbyHUD")
	local coinDisplay = lobbyHUD and lobbyHUD:FindFirstChild("CurrencyDisplay")
	local coinAmount = coinDisplay and coinDisplay:FindFirstChild("CoinAmount")

	-- Fallback structural scan if layout hierarchy scales differently
	if not coinAmount or not coinDisplay then
		coinDisplay = getFrame("CurrencyDisplay")
		coinAmount = getFrame("CoinAmount")
	end

	if coinAmount then
		if currentCoins == newCoins and coinAmount.Text == formatNumber(newCoins) then return end
		currentCoins = newCoins
		coinAmount.Text = formatNumber(newCoins)
	else
		currentCoins = -1
		return
	end

	if animate and not isCoinAnimating and coinDisplay then
		isCoinAnimating = true
		local originalSize = coinDisplay.Size
		local bigSize = UDim2.new(originalSize.X.Scale, originalSize.X.Offset, originalSize.Y.Scale, originalSize.Y.Offset + 6)
		coinDisplay.Size = bigSize
		local t = TweenService:Create(coinDisplay, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = originalSize})
		t:Play() t.Completed:Connect(function() isCoinAnimating = false end)
	end
end

-- ── Score & Clutch Logic ─────────────────────────────────────────────────────
local function playClutchFlash(teamName)
	if isClutchFlashActive then return end
	isClutchFlashActive = true
	local flashFrame = getFrame("ClutchFlash")
	if not flashFrame then isClutchFlashActive = false return end
	flashFrame.BackgroundColor3 = teamName == "Designers" and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(255, 100, 150)
	flashFrame.Visible = true
	TweenService:Create(flashFrame, TweenInfo.new(0.15), {BackgroundTransparency = 0.7}):Play()
	task.wait(0.15)
	TweenService:Create(flashFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
	task.wait(0.3)
	flashFrame.Visible = false isClutchFlashActive = false
end

-- ── Menu Navigation ──────────────────────────────────────────────────────────
local function closeMenu(menuName, silent)
	local menuData = Menus[menuName]
	if not menuData then return end
	local gui = PlayerGui:FindFirstChild(menuData.Gui)
	local frame = gui and gui:FindFirstChild(menuData.Frame, true)
	if not frame or not frame.Visible then return end
	if silent then
		frame.Visible = false
		local otherVisible = false
		for _, m in pairs(Menus) do
			local mg = PlayerGui:FindFirstChild(m.Gui)
			local mf = mg and mg:FindFirstChild(m.Frame, true)
			if mg == gui and mf and mf.Visible then otherVisible = true break end
		end
		if not otherVisible then gui.Enabled = false end
		if activeMenu == menuName then activeMenu = nil end
		return
	end
	local targetPos = REST_POSITIONS[menuName] or frame.Position
	local hiddenPos = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset + SLIDE_OFFSET)
	isMenuAnimating = true
	local alphaVal = Instance.new("NumberValue")
	alphaVal.Value = 1
	alphaVal.Changed:Connect(function(val) setCanvasAlpha(frame, val) end)
	local t = TweenService:Create(frame, TWEEN_INFO, {Position = hiddenPos})
	local at = TweenService:Create(alphaVal, TWEEN_INFO, {Value = 0})
	t:Play() at:Play()
	t.Completed:Connect(function()
		frame.Visible = false
		local otherVisible = false
		for _, m in pairs(Menus) do
			local mg = PlayerGui:FindFirstChild(m.Gui)
			local mf = mg and mg:FindFirstChild(m.Frame, true)
			if mg == gui and mf and mf.Visible then otherVisible = true break end
		end
		if not otherVisible then gui.Enabled = false end
		if activeMenu == menuName then activeMenu = nil end
		isMenuAnimating = false alphaVal:Destroy()
	end)
end

local function openMenu(menuName)
	if isMenuAnimating then return end
	if activeMenu and activeMenu ~= menuName then closeMenu(activeMenu, true) end
	local menuData = Menus[menuName]
	if not menuData then return end
	local gui = PlayerGui:FindFirstChild(menuData.Gui)
	local frame = gui and gui:FindFirstChild(menuData.Frame, true)
	if not frame then return end
	if activeMenu == menuName then closeMenu(menuName) return end
	activeMenu = menuName
	isMenuAnimating = true
	local targetPos = REST_POSITIONS[menuName] or frame.Position
	frame.Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset + SLIDE_OFFSET)
	frame.Visible = true setCanvasAlpha(frame, 0) 
	gui.Enabled = true
	for _, m in pairs(Menus) do
		local mg = PlayerGui:FindFirstChild(m.Gui)
		local mf = mg and mg:FindFirstChild(m.Frame, true)
		if mg == gui and mf ~= frame then mf.Visible = false end
	end
	local alphaVal = Instance.new("NumberValue")
	alphaVal.Value = 0
	alphaVal.Changed:Connect(function(val) setCanvasAlpha(frame, val) end)
	local t = TweenService:Create(frame, TWEEN_INFO, {Position = targetPos})
	local at = TweenService:Create(alphaVal, TWEEN_INFO, {Value = 1})
	t:Play() at:Play()
	t.Completed:Connect(function() isMenuAnimating = false alphaVal:Destroy() end)
end

local function closeAllMenus() if activeMenu then closeMenu(activeMenu) end end

-- ── Transitions ──────────────────────────────────────────────────────────────
local function transitionToMatch()
	if inMatch then return end
	inMatch = true
	local ghud, lhud = PlayerGui:WaitForChild("GameplayHUD"), PlayerGui:WaitForChild("LobbyHUD")
	ghud.Enabled = true
	local sf, ah, um, st = getFrame("ScoreboardFrame"), getFrame("ActionHotbar"), getFrame("UltimateModule"), getFrame("StatusTracker")
	if sf then sf.Position = HUD_OFF.ScoreboardFrame end
	if ah then 
		ah.Position = HUD_OFF.ActionHotbar end
	if um then um.Position = HUD_OFF.UltimateModule end
	if st then st.Position = HUD_OFF.StatusTracker end
	local bn, cd, dlb = getFrame("BottomNav"), getFrame("CurrencyDisplay"), getFrame("DailyLookbookButton")
	TweenService:Create(bn, OUT_INFO, {Position = LOBBY_OFF.BottomNav}):Play()
	TweenService:Create(cd, OUT_INFO, {Position = LOBBY_OFF.CurrencyDisplay}):Play()
	TweenService:Create(dlb, OUT_INFO, {Position = LOBBY_OFF.DailyLookbookButton}):Play()
	task.delay(0.12, function() if sf then TweenService:Create(sf, IN_INFO, {Position = HUD_REST.ScoreboardFrame}):Play() end end)
	task.delay(0.20, function() if ah then TweenService:Create(ah, IN_INFO, {Position = HUD_REST.ActionHotbar}):Play() end end)
	task.delay(0.28, function() if um then TweenService:Create(um, IN_INFO, {Position = HUD_REST.UltimateModule}):Play() end end)
	task.delay(0.22, function() if st then TweenService:Create(st, FAST_IN, {Position = HUD_REST.StatusTracker}):Play() end end)
	task.delay(0.5, function()
		lhud.Enabled = false
		if bn then bn.Position = LOBBY_OFF.BottomNav end
		if cd then cd.Position = LOBBY_OFF.CurrencyDisplay end
		if dlb then dlb.Position = LOBBY_OFF.DailyLookbookButton end
	end)
end

local function transitionToLobby()
	if not inMatch then return end
	inMatch = false
	local ghud, lhud = PlayerGui:WaitForChild("GameplayHUD"), PlayerGui:WaitForChild("LobbyHUD")
	lhud.Enabled = true
	local bn, cd, dlb = getFrame("BottomNav"), getFrame("CurrencyDisplay"), getFrame("DailyLookbookButton")
	if bn then bn.Position = LOBBY_OFF.BottomNav end
	if cd then cd.Position = LOBBY_OFF.CurrencyDisplay end
	if dlb then dlb.Position = LOBBY_OFF.DailyLookbookButton end
	local sf, ah, um, st = getFrame("ScoreboardFrame"), getFrame("ActionHotbar"), getFrame("UltimateModule"), getFrame("StatusTracker")
	if sf then TweenService:Create(sf, OUT_INFO, {Position = HUD_OFF.ScoreboardFrame}):Play() end
	if ah then TweenService:Create(ah, OUT_INFO, {Position = HUD_OFF.ActionHotbar}):Play() end
	if um then TweenService:Create(um, OUT_INFO, {Position = HUD_OFF.UltimateModule}):Play() end
	if st then TweenService:Create(st, OUT_INFO, {Position = HUD_OFF.StatusTracker}):Play() end
	task.delay(0.10, function() if cd then TweenService:Create(cd, IN_INFO, {Position = LOBBY_REST.CurrencyDisplay}):Play() end end)
	task.delay(0.18, function() if bn then TweenService:Create(bn, IN_INFO, {Position = LOBBY_REST.BottomNav}):Play() end end)
	task.delay(0.26, function() if dlb then TweenService:Create(dlb, IN_INFO, {Position = LOBBY_REST.DailyLookbookButton}):Play() end end)
	task.delay(0.55, function() ghud.Enabled = false end)
end

-- ── Event Handlers ───────────────────────────────────────────────────────────
AbilityEvent.OnClientEvent:Connect(function(actionType, arg1, arg2, arg3)
	if actionType == "UpdateAbilitySlots" then updateAbilitySlots(arg1, arg2)
	elseif actionType == "AbilityCooldownUpdate" then runCooldown(arg1, arg2)
	elseif actionType == "UpdateShowstopperCharge" then
		local fill, neon = getFrame("ProgressFill"), getFrame("NeonPulse")
		local pct = math.clamp(arg1 / arg2, 0, 1)
		if fill then TweenService:Create(fill, TweenInfo.new(0.3), {Size = UDim2.new(pct, 0, 1, 0)}):Play() fill.BackgroundColor3 = pct >= 1 and Color3.fromRGB(255, 80, 200) or Color3.fromRGB(180, 180, 180) end
		if pct >= 1 then
			if not isNeonPulsing and neon then
				isNeonPulsing = true neon.Visible = true
				neonPulseConn = task.spawn(function() while isNeonPulsing do TweenService:Create(neon, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {ImageTransparency = 0.3}):Play() task.wait(1) end end)
			end
		else
			isNeonPulsing = false if neonPulseConn then task.cancel(neonPulseConn) neonPulseConn = nil end
			if neon then neon.Visible = false end
		end
	elseif actionType == "ShowstopperFullAlert" then
		SoundService.PlayLocal("ShowstopperReady")
		local banner = getFrame("ShowstopperAnnounceBanner")
		if banner then banner.Visible = true banner.BackgroundColor3 = Color3.fromRGB(255, 80, 200) TweenService:Create(banner, TweenInfo.new(0.5), {BackgroundTransparency = 0}):Play() task.delay(3, function() TweenService:Create(banner, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play() task.delay(0.6, function() banner.Visible = false end) end) end
	end
end)

local function startSnappyRngSpin(winningItemName, rarity)
	local gachaGui = PlayerGui:FindFirstChild("GachaGui")
	if not gachaGui then return end

	local rollContainer = gachaGui:FindFirstChild("RollContainer", true)
	local itemScroller = rollContainer and rollContainer:FindFirstChild("ItemScroller", true)
	if not itemScroller then return end

	local cards = itemScroller:GetChildren()
	local cardTemplates = {}
	for _, child in ipairs(cards) do
		if child:IsA("ImageLabel") then table.insert(cardTemplates, child) end
	end

	if #cardTemplates < 4 then return end

	gachaGui.Enabled = true
	rollContainer.Visible = true
	rollContainer.Size = UDim2.fromScale(0.1, 0.1)
	TweenService:Create(rollContainer, TweenInfo.new(0.4, Enum.EasingStyle.Back), {Size = UDim2.fromOffset(400, 150)}):Play()

	local winningCard = cardTemplates[4]
	winningCard.ItemLabel.Text = winningItemName
	winningCard.BackgroundColor3 = RARITY_COLORS[rarity] or RARITY_COLORS.Common

	itemScroller.Position = UDim2.new(0.5, 0, 0, 0)

	local spinInfo = TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local spinTween = TweenService:Create(itemScroller, spinInfo, {
		Position = UDim2.new(0.5, 0, 0, -320)
	})

	spinTween:Play()
	SoundService.PlayLocal("CrateSpin")

	spinTween.Completed:Connect(function()
		SoundService.PlayLocal("FabricDunk")
		local pop = TweenService:Create(winningCard, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), {
			Size = UDim2.new(0, 130, 0, 130)
		})
		pop:Play()

		local flash = gachaGui:FindFirstChild("FlashOverlay", true)
		if flash then
			flash.BackgroundColor3 = RARITY_COLORS[rarity] or Color3.new(1,1,1)
			flash.Visible = true
			flash.BackgroundTransparency = 0
			TweenService:Create(flash, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
			task.delay(0.4, function() flash.Visible = false end)
		end

		task.delay(2.5, function()
			TweenService:Create(rollContainer, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.fromScale(0, 0)}):Play()
			task.wait(0.3)
			gachaGui.Enabled = false
			winningCard.Size = UDim2.new(0, 100, 0, 100)
		end)
	end)
end

EconomyEvent.OnClientEvent:Connect(function(actionType, arg1, arg2)
	if actionType == "ShowRewardPopup" then table.insert(rewardQueue, {xpText = arg1, coinsText = arg2}) showNextReward()
	elseif actionType == "OpenMarketplace" then openMenu("Marketplace")
	elseif actionType == "CrateResult" then
		startSnappyRngSpin(arg2.Name, arg2.Rarity)
	end
end)

MatchStateEvent.OnClientEvent:Connect(function(actionType, arg1, arg2)
	if actionType == "MatchStart" then transitionToMatch()
	elseif actionType == "MatchEnd" then task.delay(0.2, transitionToLobby) end
end)

UpdateDualScore.OnClientEvent:Connect(function(dScore, cScore, target)
	local dLabel, cLabel, tLabel = getFrame("DesignerScore"), getFrame("CriticScore"), getFrame("TargetScoreLabel")
	if dLabel then dLabel.Text = tostring(dScore) if dScore > lastDesignerScore then TweenService:Create(dLabel, TweenInfo.new(0.1), {TextColor3 = Color3.fromRGB(100, 200, 255)}):Play() task.delay(0.2, function() TweenService:Create(dLabel, TweenInfo.new(0.2), {TextColor3 = Color3.fromRGB(255, 255, 255)}):Play() end) end end
	if cLabel then cLabel.Text = tostring(cScore) if cScore > lastCriticScore then TweenService:Create(cLabel, TweenInfo.new(0.1), {TextColor3 = Color3.fromRGB(255, 100, 150)}):Play() task.delay(0.2, function() TweenService:Create(cLabel, TweenInfo.new(0.2), {TextColor3 = Color3.fromRGB(255, 255, 255)}):Play() end) end end
	if tLabel then tLabel.Text = "/ " .. tostring(target) end
	if dScore >= target - 1 then playClutchFlash("Designers") 
	elseif cScore >= target - 1 then playClutchFlash("Critics") end
	lastDesignerScore, lastCriticScore = dScore, cScore
end)

TagEvent.OnClientEvent:Connect(function(actionType, arg1)
	if actionType == "BlindClient" then
		local overlay = getFrame("BlindOverlay")
		if overlay then overlay.Visible = true overlay.BackgroundTransparency = 0 TweenService:Create(overlay, TweenInfo.new(arg1 or 2), {BackgroundTransparency = 1}):Play() task.delay(arg1 or 2, function() overlay.Visible = false end) end
	end
end)

-- ── Initialization ───────────────────────────────────────────────────────────
local function setupReplicaListener()
	local rModule = ReplicatedStorage:FindFirstChild("ReplicaController")
	if rModule then
		local ok, RC = pcall(require, rModule)
		if ok and RC.ReplicaOfClassCreated then
			RC.ReplicaOfClassCreated("PlayerData", function(replica)
				replica:ListenToChange({"Coins"}, function(new) updateCoinDisplay(new, true) end)
				updateCoinDisplay(replica.Data.Coins or 0, false)
			end)
			if RC.RequestData then RC.RequestData() end return true
		end
	end
	return false
end

-- Safely path and loop to find the essential frames before setting up active listeners
task.spawn(function()
	local gameplayHUD = PlayerGui:WaitForChild("GameplayHUD")
	local lobbyHUD = PlayerGui:WaitForChild("LobbyHUD")

	-- Explicit layout confirmation
	local currencyDisplay = lobbyHUD:WaitForChild("CurrencyDisplay")
	currencyDisplay:WaitForChild("CoinAmount")

	gameplayHUD.Enabled = false
	lobbyHUD.Enabled = true

	for name, menu in pairs(Menus) do
		local gui = PlayerGui:WaitForChild(menu.Gui, 5)
		local frame = gui and gui:FindFirstChild(menu.Frame, true)
		if frame then REST_POSITIONS[name] = frame.Position frame.Visible = false end
	end

	local bottomNav = lobbyHUD:WaitForChild("BottomNav"):WaitForChild("ButtonContainer")
	local mappings = { Btn_Shop = "Shop", Btn_Inventory = "Inventory", Btn_Codes = "Promo", Btn_Quests = "Quests", Btn_Settings = "Settings" }
	for btnName, menuName in pairs(mappings) do
		local btn = bottomNav:FindFirstChild(btnName)
		if btn then btn.MouseButton1Click:Connect(function() if tick() - lastMenuClickTime < menuDebounceTime then return end lastMenuClickTime = tick() openMenu(menuName) end) end
	end

	local lookbookBtn = lobbyHUD:FindFirstChild("DailyLookbookButton")
	if lookbookBtn then lookbookBtn.MouseButton1Click:Connect(function() if tick() - lastMenuClickTime < menuDebounceTime then return end lastMenuClickTime = tick() openMenu("Lookbook") end) end

	for _, menu in pairs(Menus) do
		local gui = PlayerGui:FindFirstChild(menu.Gui)
		local frame = gui and gui:FindFirstChild(menu.Frame, true)
		local close = frame and frame:FindFirstChild("CloseButton", true)
		if close then close.MouseButton1Click:Connect(closeAllMenus) end
	end

	_G.CloseAllMenus = closeAllMenus
	player.CharacterAdded:Connect(closeAllMenus)

	-- Kick off replication configurations
	if not setupReplicaListener() then
		player:GetAttributeChangedSignal("Coins"):Connect(function() updateCoinDisplay(player:GetAttribute("Coins") or 0, true) end)
		updateCoinDisplay(player:GetAttribute("Coins") or 0, false)
	end

	-- Break any stale caches to force visual alignment with loaded server attributes
	currentCoins = -1
	local initialCoins = player:GetAttribute("Coins") or 0
	updateCoinDisplay(initialCoins, false)

	print("[HUD] Master Controller Initialized Successfully")
end)

return {}
