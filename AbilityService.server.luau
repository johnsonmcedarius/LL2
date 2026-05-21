-- ─────────────────────────────────────────────────────────────────────────────
-- AbilityService: Server-side tactical ability execution and management
-- ─────────────────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ServiceRegistry = require(ServerScriptService:WaitForChild("ServiceRegistry"))
local DataManager = ServiceRegistry.Await("DataManager")
local SoundService = require(ReplicatedStorage:WaitForChild("SoundService"))
local Config = require(ReplicatedStorage:WaitForChild("SharedConfig"))

local PhysicsHandler = require(ServerScriptService:WaitForChild("PhysicsHandler"))
local ZoneHandler = require(ServerScriptService:WaitForChild("ZoneHandler"))
local IllusionHandler = require(ServerScriptService:WaitForChild("IllusionHandler"))
local StatusHandler = require(ServerScriptService:WaitForChild("StatusHandler"))
local WeaponVisibilityService = require(ServerScriptService:WaitForChild("WeaponVisibilityService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityEvent = Remotes:WaitForChild("AbilityEvent")
local PlayVFX = Remotes:FindFirstChild("PlayVFX") or Instance.new("RemoteEvent", Remotes)
PlayVFX.Name = "PlayVFX"

local Debris = game:GetService("Debris")

-- ── State Management ─────────────────────────────────────────────────────────
local cooldowns = {}
local activeCasts = {} -- Strict debounce for activation animations
local criticState = {} -- Immunity tracking

-- ── Immunity Constants ──
local IMMUNITY_WINDOW           = 15
local DIMINISHING_RETURN_FACTOR = 0.75
local MIN_EFFECT_MULTIPLIER     = 0.25

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function getState(critic)
	if not criticState[critic.UserId] then
		criticState[critic.UserId] = {immuneUntil = 0, hitCount = 0}
	end
	return criticState[critic.UserId]
end

local function syncLoadout(player)
	local data = DataManager.GetData(player)
	if not data then return end
	local equipped = {data.Equipped.Ability1 or "Empty"}
	AbilityEvent:FireClient(player, "UpdateAbilitySlots", equipped, 1)
end
local function routeAbility(player, abilityName)
	-- DYNAMIC LOADING: Find module in Universal folder
	local folder = ReplicatedStorage:WaitForChild("Abilities"):WaitForChild("Universal")
	
	local fileName = abilityName:gsub("%s+", "")
	local mod = folder:FindFirstChild(fileName)
	
	if mod and mod:IsA("ModuleScript") then
		local success, result = pcall(require, mod)
		if success and result.Execute then
			result.Execute(player)
		else
			warn("[ABILITY] Failed to execute module for " .. abilityName .. ": " .. tostring(result))
		end
	else
		warn("[ABILITY] No execution module found for " .. abilityName .. " at " .. folder:GetFullName() .. "." .. fileName)
	end
end

-- ── Activation & Management Handler ──────────────────────────────────────────
AbilityEvent.OnServerEvent:Connect(function(player, actionType, arg1, arg2)
	if actionType == "ActivateAbility" then
		local abilityName = arg1
		-- Death & Stun Bypass Check
		local char = player.Character
		if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then return end
		if char:GetAttribute("Stunned") or char:GetAttribute("Frozen") then return end

		-- Strict Debounce
		if activeCasts[player.UserId] then return end

		local abilityData = Config.ABILITIES[abilityName]
		if not abilityData then return end

		-- 1. Ownership & Loadout Check
		local data = DataManager.GetData(player)
		if not data or not data.Equipped then return end
		
		local isEquipped = false
		for k, v in pairs(data.Equipped) do
			if v == abilityName then
				isEquipped = true
				break
			end
		end
		
		if not isEquipped then
			warn("[ABILITY] " .. player.Name .. " does not have " .. tostring(abilityName) .. " equipped")
			return
		end

		-- 2. Cooldown Check
		local now = os.clock()
		if now < (cooldowns[player.UserId .. "_" .. abilityName] or 0) then 
			return 
		end

		-- 3. Execution Lock
		activeCasts[player.UserId] = true

		-- 4. Play VFX & SFX (Client-Side Pipeline)
		if abilityData.VFXAssetName ~= "" then
			PlayVFX:FireAllClients(abilityData.VFXAssetName, player.Character)
		end
		if abilityData.SFXId ~= "rbxassetid://0" then
			SoundService.FireToClient(player, abilityData.SFXId)
		end
		
		-- Hide weapon during cast (assume 0.5s cast animation for tactical abilities)
		WeaponVisibilityService.HideWeapon(player, 0.5)

		-- 5. Route Mechanical Execution
		print("[ABILITY] " .. player.Name .. " activated " .. abilityName)
		
		-- PHASE 4 FIX: Wrap in pcall to prevent permanent lockout on error
		local success, err = pcall(function()
			routeAbility(player, abilityName)
		end)
		
		if not success then
			warn("[ABILITY] CRITICAL ERROR executing " .. abilityName .. ": " .. tostring(err))
		end
		
		-- 6. Set Cooldown & Clean Lock
		local duration = abilityData.Cooldown
		cooldowns[player.UserId .. "_" .. abilityName] = now + duration
		activeCasts[player.UserId] = nil
		
		-- Sync cooldown to client for UI
		AbilityEvent:FireClient(player, "AbilityCooldownUpdate", abilityName, duration)

	elseif actionType == "PurchaseAbility" then
		local abilityName = arg1
		local ability = AbilityService:GetAbilityData(abilityName)
		if not ability or DataManager.HasItem(player, "Abilities", abilityName) then return end

		local cost = AbilityService:GetPrice(ability.Rarity)
		if DataManager.SubtractCoins(player, cost) then
			DataManager.GiveItem(player, "Abilities", abilityName)
			print("[SHOP] " .. player.Name .. " now owns " .. abilityName)
		end

	elseif actionType == "EquipAbility" then
		local abilityName = arg1
		if not DataManager.HasItem(player, "Abilities", abilityName) then return end
		if DataManager.UpdateEquipped then
			DataManager.UpdateEquipped(player, "Ability1", abilityName)
			syncLoadout(player)
		end
	end
end)

-- ── Failsafes ────────────────────────────────────────────────────────────────
local function cleanupPlayer(player)
	PhysicsHandler.Cleanup(player)
	ZoneHandler.Cleanup(player)
	IllusionHandler.Cleanup(player)
	StatusHandler.Cleanup(player)
end

Players.PlayerRemoving:Connect(function(player)
	cleanupPlayer(player)
	activeCasts[player.UserId] = nil
end)

local PlayerEliminated = Remotes:FindFirstChild("PlayerEliminated")
if PlayerEliminated then
	PlayerEliminated.OnServerEvent:Connect(function(player)
		cleanupPlayer(player)
	end)
end

local RoundEvents = ServerScriptService:FindFirstChild("RoundEvents")
if RoundEvents then
	local RE = require(RoundEvents)
	RE.Intermission.Event:Connect(function()
		PhysicsHandler.CleanupAll()
		ZoneHandler.CleanupAll()
		IllusionHandler.CleanupAll()
		StatusHandler.CleanupAll()
		cooldowns = {}
		criticState = {}
	end)
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	task.wait(3)
	syncLoadout(player)
end)

local AbilityService = {
	GetAbilityData = function(self, name)
		return Config.ABILITIES[name]
	end,

	GetPrice = function(self, rarity)
		return Config.ABILITY_PRICES[rarity] or 500
	end,

	GetCooldown = function(self, name)
		local abilityData = Config.ABILITIES[name]
		if abilityData and abilityData.Cooldown then
			return abilityData.Cooldown
		end
		return Config.DEFAULT_ABILITY_COOLDOWNS.DEFAULT or 8
	end,

	-- Immunity Logic
	CanHit = function(self, critic)
		if not critic or not critic.Parent then return false end
		return os.clock() >= getState(critic).immuneUntil
	end,

	RegisterHit = function(self, critic)
		if not critic or not critic.Parent then return 1 end
		local state = getState(critic)
		local multiplier = math.max(MIN_EFFECT_MULTIPLIER, DIMINISHING_RETURN_FACTOR ^ state.hitCount)
		state.hitCount += 1
		state.immuneUntil = os.clock() + IMMUNITY_WINDOW
		return multiplier
	end,

	TryHit = function(self, critic)
		if not self:CanHit(critic) then return nil end
		return self:RegisterHit(critic)
	end,

	GetEquipped = function(self, player)
		local data = DataManager.GetData(player)
		return data and data.Equipped.Ability1 or ""
	end,
}
ServiceRegistry.Register("AbilityService", AbilityService)

return AbilityService
