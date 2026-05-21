-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

-- // Modules
local DataManager     = require(script.Parent:WaitForChild("DataManager"))
local ServiceRegistry = require(script.Parent:WaitForChild("ServiceRegistry"))
local ItemDatabase    = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemDatabase"))
local Config          = require(ReplicatedStorage:WaitForChild("SharedConfig"))

-- // Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local function getRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent") r.Name = name r.Parent = Remotes end
	return r
end

local EconomyEvent      = getRemote("EconomyEvent")
local AbilitySlotUnlock = getRemote("AbilitySlotUnlock")
local TriggerUnboxing    = getRemote("TriggerUnboxing")
local GlobalAnnouncement = getRemote("GlobalAnnouncement")

local ShopManager = {}
local Registry = Config.MARKETPLACE
local PurchaseRateLimits = {}
local SHOP_COOLDOWN = 0.5 

-- ── Gamepass & Subscription Logic (Consolidated from MarketplaceHandler) ──

local function applyGamepassPerks(player)
	for passKey, pass in pairs(Registry.GamePasses) do
		if pass.Id == 0 then continue end
		local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id) end)
		if not ok or not owns then continue end

		local perks = pass.Perks or {}
		if perks.IsVIP then
			player:SetAttribute("IsVIP", true)
			local d = DataManager.GetData(player)
			if d and d.Equipped and d.Equipped.Podium == "BasicPodium" and perks.AutoPodium then DataManager.SetEquipped(player, "Podium", perks.AutoPodium) end
			if perks.CoinBonus then player:SetAttribute("VIPCoinBonus", perks.CoinBonus) end
		end
		if perks.CoinsMultiplier then player:SetAttribute("CoinsMultiplier", perks.CoinsMultiplier) end
		if perks.XPMultiplier then player:SetAttribute("XPMultiplier", perks.XPMultiplier) end
		if perks.AbilitySlot then
			local cur = player:GetAttribute("UnlockedAbilitySlots") or 1
			if perks.AbilitySlot > cur then player:SetAttribute("UnlockedAbilitySlots", perks.AbilitySlot) end
		end
	end

	for bKey, bundle in pairs(Registry.Bundles) do
		if bundle.Id ~= 0 then
			local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, bundle.Id) end)
			if ok and owns then DataManager.UnlockBundle(player, bKey) end
		end
	end

	for iKey, item in pairs(Registry.Items) do
		if item.Id ~= 0 then
			local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, item.Id) end)
			if ok and owns then DataManager.GiveItem(player, item.Category, item.ItemName) end
		end
	end
end

local function applySubscriptionPerks(player)
	local subId = Registry.Subscription.SubscriptionId
	if not subId or subId == "EXP-0000000000" then return end
	local ok, status = pcall(function() return MarketplaceService:GetUserSubscriptionStatusAsync(player, subId) end)
	if ok and status and status.IsSubscribed then
		player:SetAttribute("IsSubscribed", true)
		local data = DataManager.GetData(player)
		if data and not data.SubscriptionCoinGrantedThisMonth then
			DataManager.AddCoins(player, Registry.Subscription.Perks.MonthlyCoins or 300)
			data.SubscriptionCoinGrantedThisMonth = true
		end
	end
end

-- ── ProcessReceipt ────────────────────────────────────────────────────────────

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local GiftingService = ServiceRegistry.Get("GiftingService")
	if GiftingService and GiftingService.ProcessGiftReceipt(receiptInfo) then return Enum.ProductPurchaseDecision.PurchaseGranted end

	local pId = receiptInfo.ProductId
	for _, crate in ipairs(Config.CRATES) do
		if crate.productId == pId then
			TriggerUnboxing:FireClient(player, crate.id)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	for _, pEntry in pairs(Registry.Products) do
		if pEntry.Id == pId then
			if pEntry.Reward.Coins then DataManager.AddCoins(player, pEntry.Reward.Coins) end
			if pEntry.Reward.Crate then
				local Gacha = ServiceRegistry.Get("GachaService")
				if Gacha then Gacha.AddCrate(player, pEntry.Reward.Crate, pEntry.Reward.Amount or 1) end
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	for cat, data in pairs(ItemDatabase) do
		if typeof(data) == "table" and data.Items then
			for iName, iData in pairs(data.Items) do
				if iData.ProductId == pId then
					DataManager.GiveItem(player, cat, iName)
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
			end
		end
	end

	for _, pass in pairs(Registry.GamePasses) do
		if pass.Id == pId and pass.Perks and pass.Perks.AbilitySlot then
			local cur = player:GetAttribute("UnlockedAbilitySlots") or 1
			if pass.Perks.AbilitySlot > cur then
				player:SetAttribute("UnlockedAbilitySlots", pass.Perks.AbilitySlot)
				AbilitySlotUnlock:FireClient(player, pass.Perks.AbilitySlot)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ── Shop & Interaction Logic ──────────────────────────────────────────────────

EconomyEvent.OnServerEvent:Connect(function(player, actionType, action, itemName)
	if actionType ~= "ShopRequest" then return end
	if type(action) ~= "string" or type(itemName) ~= "string" then return end
	local now = os.clock()
	if now - (PurchaseRateLimits[player.UserId] or 0) < SHOP_COOLDOWN then return end
	PurchaseRateLimits[player.UserId] = now

	local profile = DataManager.GetProfile(player)
	if not profile then return end

	if action == "Purchase" then
		local itemData, category = ItemDatabase.GetItemData(itemName)
		if not category or not itemData or table.find(profile.Data.OwnedItems[category], itemName) then return end

		if itemData.Currency == "Coins" then
			if DataManager.SubtractCoins(player, math.max(0, math.floor(itemData.Cost or 0))) then
				DataManager.GiveItem(player, category, itemName)
			end
		elseif itemData.Currency == "Robux" and itemData.ProductId then
			MarketplaceService:PromptProductPurchase(player, itemData.ProductId)
		end
	elseif action == "Equip" then
		local itemData, category = ItemDatabase.GetItemData(itemName)
		if not category or not ItemDatabase[category] then return end
		local equipKey = ItemDatabase[category].EquipSlot 
		if equipKey and table.find(profile.Data.OwnedItems[category], itemName) then
			profile.Data.Equipped[equipKey] = itemName
			player:SetAttribute("Equipped" .. equipKey, itemName)
		end
	end
end)

local function onPlayerAdded(p)
	applyGamepassPerks(p)
	applySubscriptionPerks(p)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
Players.PlayerRemoving:Connect(function(p) PurchaseRateLimits[p.UserId] = nil end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	for bKey, b in pairs(Registry.Bundles) do
		if b.Id == passId then
			DataManager.UnlockBundle(player, bKey)
			GlobalAnnouncement:FireAllClients(player.Name .. " unlocked the " .. b.Name .. "!")
			return
		end
	end
	for _, item in pairs(Registry.Items) do
		if item.Id == passId then DataManager.GiveItem(player, item.Category, item.ItemName) return end
	end
	applyGamepassPerks(player)
end)

getRemote("PromptSubscription").OnServerEvent:Connect(function(player)
	getRemote("SubscriptionIdRelay"):FireClient(player, Registry.Subscription.SubscriptionId)
end)

ServiceRegistry.Register("ShopManager", ShopManager)
return ShopManager