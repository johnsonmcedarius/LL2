local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Direct requires from ReplicatedStorage
local SoundService = require(ReplicatedStorage:WaitForChild("SoundService"))
local VFXModule = require(ReplicatedStorage:WaitForChild("VFXModule"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityEvent = Remotes:WaitForChild("AbilityEvent")

-- State
local currentCharge = 0
local maxCharge = 100
local isReady = false

-------------------------------------------------
-- Activation Logic
-------------------------------------------------
local SHOWSTOPPER_ACTION = "ActivateShowstopper"

local function handleActivation(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then return end

	if not isReady then
		print("[SHOWSTOPPER] Not enough hype: " .. currentCharge .. "/" .. maxCharge)
		return
	end

	print("[SHOWSTOPPER] Firing the main event!")
	AbilityEvent:FireServer("ActivateShowstopper", nil) -- nil = use team default
end

-- Bind for PC (F) and Console (ButtonY)
ContextActionService:BindAction(
	SHOWSTOPPER_ACTION,
	handleActivation,
	true, -- Creates mobile button
	Enum.KeyCode.F,
	Enum.KeyCode.ButtonY
)

-- Style the mobile button so it’s not mid
local mobileBtn = ContextActionService:GetButton(SHOWSTOPPER_ACTION)
if mobileBtn then
	mobileBtn.Text = "SHOW"
	mobileBtn.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	mobileBtn.BackgroundTransparency = 0.2
end

-------------------------------------------------
-- Remote Listeners
-------------------------------------------------

-- ── Sync charge level from server ──
AbilityEvent.OnClientEvent:Connect(function(actionType, charge, max)
	if actionType == "UpdateShowstopperCharge" then
		currentCharge = charge
		maxCharge = max
		isReady = (charge >= max)

		-- Update mobile button visuals based on readiness
		if mobileBtn then
			mobileBtn.BackgroundColor3 = isReady
				and Color3.fromRGB(255, 80, 200) -- Ready Pink
				or Color3.fromRGB(120, 120, 120) -- Charging Gray
		end
	elseif actionType == "ShowstopperFullAlert" then
		isReady = true
		print("[SHOWSTOPPER] Charge full. Ready to end their whole career.")

		if mobileBtn then
			mobileBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 200)
		end
		-- Note: HUDController handles the screen flash/UI popups
	elseif actionType == "ShowstopperLocalTrigger" then
		-- data usually contains Position, Scale, or Origin
		local data = charge -- in this case, the second arg is the data payload
		VFXModule.Play("ShowstopperBurst", data.Position or player.Character.PrimaryPart.Position)
		SoundService.PlayLocal("ShowstopperActivate") -- Added sound hook for the vibe
		print("[VFX] Showstopper triggered locally. Main character energy.")
	end
end)