local SharedConfig = {
	DATA_VERSION = "v1.5",

	-- ── Team Names ──
	TEAMS = {
		DESIGNER = "Designers",
		CRITIC = "Critics",
	},

	-- ── Core Gameplay Constants ──
	MAX_INTERACTION_DISTANCE = 15, 
	TOTAL_FABRIC_NEEDED = 5,
	ROUND_DURATION = 300,
	INTERMISSION_DURATION = 15,
	MIN_PLAYERS = 2,
	MAX_STRIKES = 3,
	RACK_COOLDOWN = 5,
	PASS_RANGE = 8,
	FREEZE_COOLDOWN = 4.0,  -- Anti-spam for weapon freeze attempts

	-- ── Sabotage Balance ──
	SABOTAGE_LIMIT = 2,       
	SABOTAGE_DURATION = 20,       
	SABOTAGE_COOLDOWN = 45,       

	-- ── Movement & Feel ──
	WALK_SPEED = 16,
	SPRINT_SPEED = 26,            
	DASH_SPEED = 95,
	DASH_DURATION = 0.22,
	DASH_COOLDOWN = 0.8,          
	JUMP_POWER = 50,

	-- ── Economics & Gacha ──
	COIN_CRATE_COST = 500,
	PITY_THRESHOLD = 50,          
	ROBUX_PRODUCT_ID = 0,

	-- Rarity Weights (Total: 1000)
	RARITY_WEIGHTS = { 
		Common = 650, 
		Rare = 300, 
		Legendary = 40, 
		Mythic = 10 
	},

	-- Duplicate Rewards (Coins)
	DUPLICATE_REWARDS = {
		Common = 25,
		Rare = 75,
		Legendary = 1000,
		Mythic = 5000
	},

	-- ── Inventory Categories ──
	CATEGORIES = {
		SKINS = "Skins",
		PODIUMS = "Podiums",
		WEAPON_SKINS = "WeaponSkins",
		SKIN_EFFECTS = "SkinEffects",
		SHOWSTOPPERS = "Showstoppers",
		EMOTES = "Emotes",
		ABILITIES = "Abilities",
	},

	-- ── Progression ──
	BASE_XP = 100,
	XP_MULTIPLIER = 1.18,

	LOGIN_REWARDS = {
		[1] = {Type = "Coins", Amount = 200},
		[2] = {Type = "Coins", Amount = 400},
		[3] = {Type = "Coins", Amount = 600},
		[4] = {Type = "Coins", Amount = 800},
		[5] = {Type = "Coins", Amount = 1000},
		[6] = {Type = "Coins", Amount = 1500},
		[7] = {Type = "Crate", Amount = 1, CrateType = "CoinDesignerCrate"}
	},

	-- ── Competition Points (MVP Engine) ──
	POINTS = {
		FABRIC_COLLECT = 10,
		FABRIC_DUNK    = 50,
		SHRED_FABRIC   = 50,
		SABOTAGE       = 40,
		CLEAN_RUNWAY   = 100,
	},

	-- ── Reward Config (XP & Coins) ──
	-- PARITY: Both teams have equal rewards
	REWARDS = {
		DesignerWin       = {XP = 175,  Coins = 60},
		CriticWin         = {XP = 175,  Coins = 60},
		FabricCollect     = {XP = 15,   Coins = 5},
		FabricDunk        = {XP = 25,   Coins = 10},
		FabricShred       = {XP = 25,   Coins = 10},
		UnfreezeAlly      = {XP = 50,   Coins = 15},
		SurvivalPerMinute = {XP = 10,   Coins = 2},
		FreezeDesigner    = {XP = 75,   Coins = 20},
		FreezeCritic      = {XP = 75,   Coins = 20},
		SabotageStation   = {XP = 25,   Coins = 10},
		ApplyPressure     = {XP = 10,   Coins = 3},
		DesignerMVP       = {XP = 100,  Coins = 50},
		CriticMVP         = {XP = 100,  Coins = 50},
		
		-- PHASE 7: Universal objective completion reward
		-- DataManager doesn't need to check which team did what
		ObjectiveComplete  = {XP = 25,   Coins = 10},
	},

	-- ── MVP Scoring Weights ──
	MVP_WEIGHTS = {
		DUNK_MULTIPLIER = 10,
		FABRIC_MULTIPLIER = 2,
		UNFREEZE_MULTIPLIER = 5,
		NEVER_FROZEN_BONUS = 15,
		FREEZE_MULTIPLIER = 10,
		SABOTAGE_MULTIPLIER = 5,
	},

	-- ── Pressure Detection ──
	PRESSURE = {
		DETECTION_RANGE = 10,
		TIME_THRESHOLD = 15,
	},

	-- ── Redeemable Codes ──
	CODES = {
		LASTLOOK  = {Reward = "Coins",             Amount = 100, Active = true},
		RUNWAY100 = {Reward = "Coins",             Amount = 100, Active = true},
		VIPACCESS = {Reward = "CoinDesignerCrate", Amount = 1,   Active = true},
		XPBOOST   = {Reward = "XP",                Amount = 200, Active = true},
	},

	-- ── Jump Pad Settings ──
	JUMPPAD = {
		HEIGHT = 100,
		COOLDOWN = 0.1,
		RESET_DELAY = 0.1,
		DEFAULT_JUMP_HEIGHT = 7.2,
	},

	-- ── CollectionService Tags ──
	TAGS = {
		JUMPPAD = "JumpPad",
		DESIGNER_PROMPT = "DesignerPrompt",
		CRITIC_PROMPT = "CriticPrompt",
	},

	-- ── Hitbox Parity (PHASE 2: Anti Pay-to-Win) ──
	HITBOX_PARITY = {
		-- Standard character hitbox dimensions
		VALID_HITBOX_SIZE = Vector3.new(4, 5, 1),
		-- Maximum allowed deviation from standard (percentage)
		ALLOWED_DEVIATION = 0.1, -- 10% tolerance
		-- Whether to log warnings for non-compliant skins
		ENABLE_VALIDATION = true,
	},

	-- ── Character Stats & Abilities ──
	MAX_CHARGE = 100,
	CANCELLATION_TIME = 30,
	ANTI_CAMP_DISTANCE = 15,
	DUNK_DENIED_RANGE = 5,

	-- ── Ability Settings ──
	ABILITY_PRICES = {
		Common    = 500,
		Rare      = 1200,
		Legendary = 7500,
		Mythic    = 20000,
	},

	-- ── Marketplace Configuration (Consolidated from MarketplaceRegistry) ──
	MARKETPLACE = {
		GamePasses = {
			-- [Name] = {Id = assetId, Perks = {Table}}
		},
		Subscription = {
			SubscriptionId = 0,
			Perks = {
				CrateDiscount = 0.1,
				MonthlyCoins = 0,
				ExclusiveBadge = false,
			}
		}
	},

	DEFAULT_ABILITY_COOLDOWNS = {
		DEFAULT = 8, 
	},

	-- Ability metadata and stats
	ABILITIES = {
		["The Smoke Machine"] = {
			Category = "Ability",
			Rarity = "Common",
			Cooldown = 8,
			Duration = 5,
			Radius = 20,
			AnimationId = "",
			VFXAssetName = "SmokeMachineVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Zone",
		},
		["Slippery Gloss"] = {
			Category = "Ability",
			Rarity = "Common",
			Cooldown = 8,
			Duration = 2,
			Radius = 15,
			AnimationId = "",
			VFXAssetName = "SlipperyGlossVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Physics",
		},
		["The Wind Machine"] = {
			Category = "Ability",
			Rarity = "Rare",
			Cooldown = 8,
			Duration = 3,
			Radius = 30, -- Linear pushback
			AnimationId = "",
			VFXAssetName = "WindMachineVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Physics",
		},
		["Glitter Perfume Bomb"] = {
			Category = "Ability",
			Rarity = "Common",
			Cooldown = 8,
			Duration = 2,
			Radius = 15,
			AnimationId = "",
			VFXAssetName = "PerfumeBombVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Projectile",
		},
		["The Measuring Tape"] = {
			Category = "Ability",
			Rarity = "Rare",
			Cooldown = 8,
			Duration = 0, -- Instant pull
			Radius = 50, -- Range
			AnimationId = "",
			VFXAssetName = "MeasuringTapeVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Physics",
		},
		["The Fabric Shield"] = {
			Category = "Ability",
			Rarity = "Rare",
			Cooldown = 8,
			Duration = 4,
			Radius = 10,
			AnimationId = "",
			VFXAssetName = "FabricShieldVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Zone",
		},
		["The Mannequin Decoy"] = {
			Category = "Ability",
			Rarity = "Legendary",
			Cooldown = 12,
			Duration = 5,
			Radius = 0,
			AnimationId = "",
			VFXAssetName = "MannequinDecoyVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Illusion",
		}
	},

	SHOWSTOPPERS = {
		["The Main Event"] = {
			Category = "Showstopper",
			ChargeCost = 100,
			Duration = 10,
			Radius = 20, -- Trend-Killer Aura radius
			AnimationId = "",
			VFXAssetName = "MainEventVFX",
			SFXId = "rbxassetid://0", -- High-energy house track
			EffectType = "GlobalBuff",
		},
		["The Glitch Gala"] = {
			Category = "Showstopper",
			ChargeCost = 100,
			Duration = 8,
			Radius = 30,
			AnimationId = "",
			VFXAssetName = "GlitchGalaVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Zone",
		},
		["The Velvet Rope"] = {
			Category = "Showstopper",
			ChargeCost = 100,
			Duration = 7,
			Radius = 40,
			AnimationId = "",
			VFXAssetName = "VelvetRopeVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Zone",
		},
		["The Flash Mob"] = {
			Category = "Showstopper",
			ChargeCost = 100,
			Duration = 12,
			Radius = 0,
			AnimationId = "",
			VFXAssetName = "FlashMobVFX",
			SFXId = "rbxassetid://0",
			EffectType = "GlobalBuff",
		},
		["The Editorial Mirror"] = {
			Category = "Showstopper",
			ChargeCost = 100,
			Duration = 6,
			Radius = 0,
			AnimationId = "",
			VFXAssetName = "EditorialMirrorVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Status",
		},
		["The Paparazzi Swarm"] = {
			Category = "Showstopper",
			ChargeCost = 100,
			Duration = 9,
			Radius = 0, -- Global swarm
			AnimationId = "",
			VFXAssetName = "PaparazziSwarmVFX",
			SFXId = "rbxassetid://0",
			EffectType = "ScreenModify",
		},
		["The Afterparty"] = {
			Category = "Showstopper",
			ChargeCost = 100,
			Duration = 5,
			Radius = 0, -- Global
			AnimationId = "",
			VFXAssetName = "AfterpartyVFX",
			SFXId = "rbxassetid://0",
			EffectType = "Resurrection",
		},
	},

	-- ── Crate Registry ──
	CRATES = {
		{
			id        = "RobuxDesignerCrate",
			label     = "DESIGNER DROP",
			price     = "99 R$",
			currency  = "Robux",
			productId = 0,
			order     = 1,
			color     = Color3.fromRGB(212, 175, 55),
		},
		{
			id        = "CoinDesignerCrate",
			label     = "CREATIVE CRATE",
			price     = "500 COINS",
			currency  = "Coins",
			coinCost  = 500,
			productId = 0,
			order     = 2,
			color     = Color3.fromRGB(100, 200, 255),
		},
	},

	CHARGES = {
		-- Shared Events
		FabricDunk = 20,
		FabricShred = 20,
		FabricPass = 10,
		TeamRescue = 25,
		AbilityHit = 5,
		CloseDodge = 3,

		-- Freeze Events (Both Teams)
		FreezeDesigner = 30,
		FreezeCritic = 30,
		DunkDenied = 35,
		ShredDenied = 35,
		FinalCancel = 40,
		InterceptPass = 15,
	}
}

-- ── Registry Helpers ──

function SharedConfig.GetCrateById(id)
	for _, crate in ipairs(SharedConfig.CRATES) do
		if crate.id == id then return crate end
	end
end

function SharedConfig.GetAllCrates()
	local list = {}
	for _, crate in ipairs(SharedConfig.CRATES) do
		table.insert(list, crate)
	end
	table.sort(list, function(a, b) return (a.order or 99) < (b.order or 99) end)
	return list
end

function SharedConfig.GetAbilityData(name)
	return SharedConfig.ABILITIES[name]
end

return SharedConfig