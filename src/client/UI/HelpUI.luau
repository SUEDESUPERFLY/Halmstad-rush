--!strict
-- Hjälpruta med kontrollerna. Öppnas med H eller ?-knappen och visas en gång vid första start.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local HelpUI = {}

local ACCENT = Color3.fromRGB(255, 200, 40)

-- { Vad, Tangentbord, Handkontroll, Touch }
local ROWS = {
	{ "Gas", "W / ↑", "RT", "GAS" },
	{ "Broms / back", "S / ↓", "LT", "BRAKE" },
	{ "Styr", "A D / ← →", "Vänster spak", "◀ ▶" },
	{ "Drift", "Space", "X", "DRIFT" },
	{ "Boost", "Shift", "A", "BOOST" },
	{ "Återställ (2 tryck = till väg)", "R", "Y", "↻" },
	{ "Snabbresa", "M", "Select", "MAP" },
	{ "Starta race / aktivitet", "E", "B", "START" },
	{ "Garage", "G", "–", "GARAGE" },
	{ "Butik", "B", "–", "SHOP" },
	{ "Minikarta av/på", "N", "–", "–" },
	{ "Den här hjälpen", "H", "–", "?" },
}

local TIPS = "Drifta, flyg och kör nära hinder för att ladda boost. Knuffa trafiken tills den kvaddas för TAKEDOWN!\n"
	.. "Gröna ringar är aktiviteter, den gula är racet. Pengar köper bilar, uppgraderingar och lack i garaget."

local gui: ScreenGui
local window: Frame

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function cell(parent: Instance, text: string, x: number, width: number, y: number, color: Color3, bold: boolean)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color
	label.Text = text
	label.Position = UDim2.new(x, 0, 0, y)
	label.Size = UDim2.new(width, -6, 0, 22)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
end

local function setOpen(open: boolean)
	window.Visible = open
end

function HelpUI.Start()
	local player = Players.LocalPlayer
	gui = Instance.new("ScreenGui")
	gui.Name = "HelpUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Text = "?"
	toggle.Font = Enum.Font.GothamBlack
	toggle.TextSize = 22
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	toggle.BackgroundTransparency = 0.3
	toggle.Position = UDim2.fromOffset(390, 70)
	toggle.Size = UDim2.fromOffset(40, 40)
	toggle.Parent = gui
	corner(toggle, 10)
	toggle.Activated:Connect(function()
		setOpen(not window.Visible)
	end)

	window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.8, 0.8)
	window.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	window.Visible = false
	window.Parent = gui
	corner(window, 16)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(720, 520)
	constraint.Parent = window

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextColor3 = ACCENT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "HALMSTAD RUSH – KONTROLLER"
	title.Position = UDim2.fromOffset(18, 10)
	title.Size = UDim2.new(1, -80, 0, 36)
	title.Parent = window

	local close = Instance.new("TextButton")
	close.Text = "✕"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 20
	close.TextColor3 = Color3.new(1, 1, 1)
	close.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(36, 36)
	close.Parent = window
	corner(close, 8)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(18, 56)
	scroll.Size = UDim2.new(1, -36, 1, -70)
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = window

	local columns = { { 0, 0.4 }, { 0.4, 0.2 }, { 0.6, 0.2 }, { 0.8, 0.2 } }
	local header = { "", "Tangentbord", "Handkontroll", "Touch" }
	for i, column in columns do
		cell(scroll, header[i], column[1], column[2], 0, ACCENT, true)
	end
	for r, row in ROWS do
		for i, column in columns do
			cell(scroll, row[i], column[1], column[2], r * 24, Color3.new(1, 1, 1), i == 1)
		end
	end

	local tips = Instance.new("TextLabel")
	tips.BackgroundTransparency = 1
	tips.Font = Enum.Font.Gotham
	tips.TextSize = 15
	tips.TextWrapped = true
	tips.TextXAlignment = Enum.TextXAlignment.Left
	tips.TextYAlignment = Enum.TextYAlignment.Top
	tips.TextColor3 = Color3.fromRGB(200, 205, 220)
	tips.Text = TIPS
	tips.Position = UDim2.fromOffset(0, (#ROWS + 1) * 24 + 12)
	tips.Size = UDim2.new(1, -10, 0, 70)
	tips.Parent = scroll

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.H then
			setOpen(not window.Visible)
		end
	end)

	-- Visa hjälpen en gång när spelaren kommer in.
	task.delay(3, function()
		setOpen(true)
	end)
end

return HelpUI
