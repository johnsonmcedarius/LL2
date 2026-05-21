local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ServiceRegistry = require(ServerScriptService:WaitForChild("ServiceRegistry"))

local PLAYERS_GROUP = "Players"
local DEFAULT_GROUP = "Default"

local GROUPS = {
	"Designers",
	"Critics",
	"DesignerBarrier",
	"CriticBarrier"
}

local CollisionService = {}

-- ── Setup Collision Groups ─────────────────────────────────────────────────────
function CollisionService.Setup()
	-- Create collision groups (wrapped in pcall in case they already exist)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYERS_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(DEFAULT_GROUP)
	end)
	
	for _, name in ipairs(GROUPS) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end

	-- Configure Interactions
	-- Barriers should NOT collide with their own team
	PhysicsService:CollisionGroupSetCollidable("Designers", "DesignerBarrier", false)
	PhysicsService:CollisionGroupSetCollidable("Critics", "CriticBarrier", false)

	-- Barriers SHOULD collide with the OPPOSING team
	PhysicsService:CollisionGroupSetCollidable("Critics", "DesignerBarrier", true)
	PhysicsService:CollisionGroupSetCollidable("Designers", "CriticBarrier", true)

	-- Teammates don't collide with each other
	PhysicsService:CollisionGroupSetCollidable("Designers", "Designers", false)
	PhysicsService:CollisionGroupSetCollidable("Critics", "Critics", false)

	-- Legacy Player-to-player collision disabled
	PhysicsService:CollisionGroupSetCollidable(PLAYERS_GROUP, PLAYERS_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(PLAYERS_GROUP, DEFAULT_GROUP, true)
	
	print("[COLLISION] Groups initialized.")
end

-- ── Set Collision Group for a Player's Character ───────────────────────────────
function CollisionService.SetPlayerCollisionGroup(player, groupName)
	local char = player.Character
	if not char then return end
	
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = groupName
		end
	end
end

-- ── Enable/Disable Player-to-Player Collision ─────────────────────────────────
function CollisionService.SetPlayerCollisionEnabled(player, enabled)
	local group = enabled and DEFAULT_GROUP or PLAYERS_GROUP
	CollisionService.SetPlayerCollisionGroup(player, group)
end

-- ── Apply to all players (for round start) ─────────────────────────────────────
function CollisionService.ApplyToAllPlayers(enabled)
	for _, player in ipairs(Players:GetPlayers()) do
		CollisionService.SetPlayerCollisionEnabled(player, enabled)
	end
end

-- ── Character Spawn Handler ─────────────────────────────────────────────────────
local function onCharacterAdded(player, character)
	task.defer(function()
		local teamName = player.Team and player.Team.Name
		if teamName == "Designers" or teamName == "Critics" then
			CollisionService.SetPlayerCollisionGroup(player, teamName)
		else
			CollisionService.SetPlayerCollisionEnabled(player, false)
		end
	end)
end

local function onPlayerAdded(player)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
end

-- ── Initialize ────────────────────────────────────────────────────────────────
CollisionService.Setup()

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

ServiceRegistry.Register("CollisionService", CollisionService)
return CollisionService