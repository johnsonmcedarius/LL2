local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ServiceRegistry = require(ServerScriptService:WaitForChild("ServiceRegistry"))
local DataManager = ServiceRegistry.Await("DataManager")
local Config = require(ReplicatedStorage:WaitForChild("SharedConfig"))
local LootTable = require(ReplicatedStorage:WaitForChild("LootTable"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EconomyEvent = Remotes:WaitForChild("EconomyEvent")

-- Lazy load DataManager --
local function getDataManager()
	return ServiceRegistry.Get("DataManager")
end

local MarketplaceService = game:GetService("MarketplaceService")

-- ── Rate Limiting ──
local RateLimits = {}
local SPIN_COOLDOWN = 1.5 
local PURCHASE_COOLDOWN = 2

-- State for Robux flow
local pendingPurchases = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function canPurchase(player)
	local now = os.clock()
	if now - (RateLimits[player.UserId] or 0) < PURCHASE_COOLDOWN then
		return false, "Please wait before purchasing again."
	end
	return true, nil
end
local PoolCaches = {}

local function rebuildPoolCache(crateType)
	local pool = LootTable[crateType]
	if not pool then return end

	local cache = {
		Normal = { items = {}, totalWeight = 0 },
		Pity = { items = {}, totalWeight = 0 }
	}

	for _, item in ipairs(pool) do
		local weight = Config.RARITY_WEIGHTS[item.Rarity] or 1

		-- Normal Pool logic
		cache.Normal.totalWeight += weight
		table.insert(cache.Normal.items, { item = item, threshold = cache.Normal.totalWeight })

		-- Pity Pool logic (Legendary/Mythic Only)
		if item.Rarity == "Legendary" or item.Rarity == "Mythic" then
			cache.Pity.totalWeight += weight
			table.insert(cache.Pity.items, { item = item, threshold = cache.Pity.totalWeight })
		end
	end

	PoolCaches[crateType] = cache
end

for crateName in pairs(LootTable) do rebuildPoolCache(crateName) end

-- ── Logic ──

local function pickItem(crateType, guaranteeLegendary, luckMultiplier)
	local poolData = PoolCaches[crateType]
	if not poolData then return nil end

	local targetPool
	if guaranteeLegendary and poolData.Pity.totalWeight > 0 then
		targetPool = poolData.Pity
	else
		-- If luckMultiplier is active, we dynamically alter the Normal pool's weight distribution
		if luckMultiplier and luckMultiplier > 1 then
			local modifiedItems = {}
			local modifiedTotalWeight = 0
			
			local pool = LootTable[crateType]
			for _, item in ipairs(pool) do
				local weight = Config.RARITY_WEIGHTS[item.Rarity] or 1
				
				-- Buff Legendary and Mythic, Nerf Common
				if item.Rarity == "Legendary" or item.Rarity == "Mythic" then
					weight = weight * luckMultiplier
				elseif item.Rarity == "Common" then
					weight = math.max(1, weight / luckMultiplier)
				end
				
				modifiedTotalWeight += weight
				table.insert(modifiedItems, { item = item, threshold = modifiedTotalWeight })
			end
			
			targetPool = { items = modifiedItems, totalWeight = modifiedTotalWeight }
		else
			targetPool = poolData.Normal
		end
	end

	local roll = math.random() * targetPool.totalWeight

	-- Binary Search: O(log n) speed
	local low, high = 1, #targetPool.items
	while low <= high do
		local mid = math.floor((low + high) / 2)
		if targetPool.items[mid].threshold >= roll then
			if mid == 1 or targetPool.items[mid - 1].threshold < roll then
				return targetPool.items[mid].item
			end
			high = mid - 1
		else
			low = mid + 1
		end
	end
	return targetPool.items[#targetPool.items].item
end

local function processSpin(player, crateType)
	local DataManager = getDataManager()
	if not DataManager then return nil end

	local data = DataManager.GetData(player)
	if not data then return nil end

	local luckMultiplier = player:GetAttribute("LuckMultiplier") or 1
	local pity = (data.PityCounter and data.PityCounter[crateType]) or 0
	local guarantee = pity >= Config.PITY_THRESHOLD
	local item = pickItem(crateType, guarantee, luckMultiplier)

	if not item then return nil end

	-- Update Pity State
	if not data.PityCounter then data.PityCounter = {} end
	if item.Rarity == "Legendary" or item.Rarity == "Mythic" then
		data.PityCounter[crateType] = 0
	else
		data.PityCounter[crateType] = pity + 1
	end

	-- Sync Pity to Replica right after mutation so the UI updates instantly
	if DataManager.UpdatePityReplica then
		DataManager.UpdatePityReplica(player)
	end

	-- Inventory Logic
	local isDuplicate = DataManager.HasItem(player, item.Category, item.Name)
	local compensation = 0

	if isDuplicate then
		compensation = Config.DUPLICATE_REWARDS[item.Rarity] or 50
		DataManager.AddCoins(player, compensation)
	else
		DataManager.GiveItem(player, item.Category, item.Name)
	end

	-- Mythic Flexing
	if item.Rarity == "Mythic" and not isDuplicate then
		Remotes.GlobalAnnouncement:FireAllClients(player.Name .. " just pulled a MYTHIC: " .. item.Name .. "!")
	end

	return { 
		Name = item.Name, 
		Category = item.Category, 
		Rarity = item.Rarity, 
		IsDuplicate = isDuplicate, 
		Compensation = compensation 
	}
end

-- ── Listeners ──

EconomyEvent.OnServerEvent:Connect(function(player, actionType, arg1, arg2)
	local DataManager = getDataManager()
	if not DataManager then return end

	if actionType == "OpenCrate" then
		local crateType = arg1
		-- Exploitation & Validation checks
		if type(crateType) ~= "string" or not LootTable[crateType] then return end

		local now = os.clock()
		if now - (RateLimits[player.UserId] or 0) < SPIN_COOLDOWN then return end
		RateLimits[player.UserId] = now

		local data = DataManager.GetData(player)
		if data and data.Inventory and (data.Inventory[crateType] or 0) > 0 then
			data.Inventory[crateType] -= 1

			-- Sync current crate counts down to client UI replica
			if DataManager.UpdateInventoryReplica then
				DataManager.UpdateInventoryReplica(player)
			end

			local result = processSpin(player, crateType)
			if result then EconomyEvent:FireClient(player, "CrateResult", crateType, result) end
		end
	elseif actionType == "BatchOpenCrate" then
		local crateType = arg1
		local count = arg2
		-- Exploitation & Validation checks
		if type(crateType) ~= "string" or not LootTable[crateType] then return end

		local now = os.clock()
		if now - (RateLimits[player.UserId] or 0) < SPIN_COOLDOWN then return end
		RateLimits[player.UserId] = now

		local cleanCount = math.clamp(math.floor(count or 1), 1, 10)
		local data = DataManager.GetData(player)

		if data and data.Inventory and (data.Inventory[crateType] or 0) >= cleanCount then
			data.Inventory[crateType] -= cleanCount

			-- Sync current crate counts down to client UI replica
			if DataManager.UpdateInventoryReplica then
				DataManager.UpdateInventoryReplica(player)
			end

			local results = {}
			for i = 1, cleanCount do
				local res = processSpin(player, crateType)
				if res then table.insert(results, res) end
			end
			EconomyEvent:FireClient(player, "BatchCrateResults", crateType, results)
		end
	elseif actionType == "CratePurchaseRequest" then
		local crateId = arg1
		local crate = GachaService.GetById(crateId)
		if not crate then return end

		local canBuy, err = canPurchase(player)
		if not canBuy then
			EconomyEvent:FireClient(player, "UiAlert", "WAIT", err)
			return
		end
		RateLimits[player.UserId] = os.clock()

		if crate.currency == "Coins" then
			local coins = DataManager.GetCoins(player)
			local cost = crate.coinCost or 0
			if coins < cost then
				EconomyEvent:FireClient(player, "UiAlert", "NOT ENOUGH COINS!", "Need " .. cost .. " coins")
				return
			end

			DataManager.SubtractCoins(player, cost)
			-- GachaService.AddCrate(player, crate.id, 1) -- Removed intermediate inventory step
			-- EconomyEvent:FireClient(player, "TriggerUnboxing", crate.id) -- Removed old cinematic trigger
			
			-- Immediately process spin and fire result to client
			local result = processSpin(player, crate.id)
			if result then
				EconomyEvent:FireClient(player, "CrateResult", crate.id, result)
			end
			
			print(string.format("[GACHA] %s rolled %s for %d coins", player.Name, crate.id, cost))

		elseif crate.currency == "Robux" then
			local productId = crate.productId or 0
			if productId == 0 then return end
			pendingPurchases[player.UserId] = crate.id
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	RateLimits[player.UserId] = nil
end)

-- ── Service Methods ──
local GachaService = {
	GetById = function(id)
		for _, crate in ipairs(Config.CRATES) do
			if crate.id == id then
				return crate
			end
		end
		return nil
	end,

	GetAll = function()
		local list = {}
		for _, crate in ipairs(Config.CRATES) do
			table.insert(list, crate)
		end
		table.sort(list, function(a, b) return (a.order or 99) < (b.order or 99) end)
		return list
	end,

	IsValid = function(id)
		for _, crate in ipairs(Config.CRATES) do
			if crate.id == id then
				return true
			end
		end
		return false
	end,
}

function GachaService.BuyCoinCrate(player)
	local cost = Config.COIN_CRATE_COST or 500
	if DataManager.SubtractCoins(player, cost) then
		GachaService.AddCrate(player, "CoinDesignerCrate", 1)
		return true
	end
	return false
end

function GachaService.AddCrate(player, crateType, amount)
	local data = DataManager.GetData(player)
	if data then
		if not data.Inventory then data.Inventory = {} end
		data.Inventory[crateType] = (data.Inventory[crateType] or 0) + (amount or 1)

		-- Sync right away when giving a crate externally (like your daily login reward pass)
		if DataManager.UpdateInventoryReplica then
			DataManager.UpdateInventoryReplica(player)
		end
	end
end

ServiceRegistry.Register("GachaService", GachaService)
return GachaService