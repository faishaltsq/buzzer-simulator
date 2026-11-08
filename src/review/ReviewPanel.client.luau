--!strict
-- ReviewPanel.client.luau  —  STUDIO-ONLY progression and inspection panel.
-- ScreenGui with presets, teleport, and backdrop options for review scenarios.
-- Communicates with server via ReplicatedStorage.ReviewRemotes.ReviewCommand.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui", 15) :: PlayerGui

-- Wait for ReviewRemotes
local remotesFolder = ReplicatedStorage:WaitForChild("ReviewRemotes", 10) :: Folder
if remotesFolder == nil then
	warn("[ReviewPanel] ReviewRemotes not found in ReplicatedStorage.")
	return
end

local commandRemote = remotesFolder:WaitForChild("ReviewCommand", 5) :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild("ReviewNotify", 5) :: RemoteEvent

-- Cleanup existing GUI
local existing = playerGui:FindFirstChild("ReviewPanelGui")
if existing then existing:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = "ReviewPanelGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- ===== Notification Banner =====
local notifyLabel = Instance.new("TextLabel")
notifyLabel.Name = "NotifyLabel"
notifyLabel.Size = UDim2.new(0, 300, 0, 32)
notifyLabel.Position = UDim2.new(0.5, -150, 0, 20)
notifyLabel.BackgroundColor3 = Color3.fromRGB(30, 35, 45)
notifyLabel.TextColor3 = Color3.fromRGB(100, 220, 140)
notifyLabel.Font = Enum.Font.GothamMedium
notifyLabel.TextSize = 13
notifyLabel.Visible = false
notifyLabel.Parent = screen
local notifyCorner = Instance.new("UICorner")
notifyCorner.CornerRadius = UDim.new(0, 6)
notifyCorner.Parent = notifyLabel

local function showNotification(text: string)
	notifyLabel.Text = text
	notifyLabel.Visible = true
	task.delay(3, function()
		if notifyLabel.Text == text then
			notifyLabel.Visible = false
		end
	end)
end

if notifyRemote then
	notifyRemote.OnClientEvent:Connect(function(msg: string)
		showNotification(msg)
	end)
end

-- ===== Toggle Pill Button (Especially for Mobile) =====
local pill = Instance.new("TextButton")
pill.Name = "TogglePill"
pill.Size = UDim2.new(0, 90, 0, 28)
pill.Position = UDim2.new(1, -100, 0, 8)
pill.BackgroundColor3 = Color3.fromRGB(45, 90, 180)
pill.Text = "🎮 Review"
pill.TextColor3 = Color3.fromRGB(255, 255, 255)
pill.TextSize = 12
pill.Font = Enum.Font.GothamBold
pill.Parent = screen
local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0, 14)
pillCorner.Parent = pill

-- ===== Main Panel Frame =====
local frame = Instance.new("Frame")
frame.Name = "PanelFrame"
frame.Size = UDim2.new(0, 230, 0, 360)
frame.Position = UDim2.new(1, -240, 0, 42)
frame.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
frame.BackgroundTransparency = 0.08
frame.BorderSizePixel = 0
frame.Visible = true
frame.Parent = screen

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(70, 130, 220)
frameStroke.Thickness = 1.5
frameStroke.Parent = frame

-- Title Bar
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundColor3 = Color3.fromRGB(35, 70, 150)
title.Text = "🎮 Review Controls  [`]"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 12
title.Font = Enum.Font.GothamBold
title.Parent = frame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = frame

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 36)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = frame

-- Toggle Functionality
local function toggle()
	frame.Visible = not frame.Visible
end
pill.MouseButton1Click:Connect(toggle)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Tilde then
		toggle()
	end
end)

-- Button Helper
local order = 0
local function makeBtn(label: string, color: Color3, onClick: () -> ()): TextButton
	order += 1
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 30)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Text = label
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.TextSize = 11
	b.Font = Enum.Font.GothamMedium
	b.LayoutOrder = order
	b.Parent = frame

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 5)
	c.Parent = b

	b.MouseButton1Click:Connect(onClick)
	return b
end

local function send(cmd: string)
	if commandRemote then
		commandRemote:FireServer(cmd)
	end
end

-- Section: Presets
makeBtn("Fresh Player (Tier 0)", Color3.fromRGB(50, 110, 200), function()
	send("preset:fresh")
end)

makeBtn("Mid Progression (Tier 1)", Color3.fromRGB(40, 150, 80), function()
	send("preset:mid")
end)

makeBtn("Home Studio (Tier 2)", Color3.fromRGB(210, 120, 30), function()
	send("preset:tier2")
end)

makeBtn("Reset Local Profile", Color3.fromRGB(180, 50, 50), function()
	send("preset:reset")
end)

-- Section: Navigation
makeBtn("Teleport → Gang Melati", Color3.fromRGB(40, 140, 150), function()
	send("teleport:city")
end)

makeBtn("Return Home → Bedroom", Color3.fromRGB(40, 140, 150), function()
	send("teleport:home")
end)

-- Section: Skyline Variants
makeBtn("Backdrop: Baseline", Color3.fromRGB(120, 60, 180), function()
	send("backdrop:baseline")
end)

makeBtn("Backdrop: Centered (D1)", Color3.fromRGB(150, 60, 180), function()
	send("backdrop:centered")
end)
