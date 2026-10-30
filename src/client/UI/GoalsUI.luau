--!strict
-- Panelen till höger: kom igång-guiden för nya spelare, annars dagens utmaningar,
-- veckans race och antalet hittade laxar. Visar bara det servern skickar (GoalsState).
-- J fäller ihop panelen. Den döljs under race och aktiviteter (de har egna paneler).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ActivityController = require(script.Parent.Parent.Controllers.ActivityController)
local CollectibleController = require(script.Parent.Parent.Controllers.CollectibleController)
local RaceController = require(script.Parent.Parent.Controllers.RaceController)
local VehicleController = require(script.Parent.Parent.Controllers.VehicleController)

local GoalsUI = {}

local ACCENT = Color3.fromRGB(255, 200, 40)
local DONE = Color3.fromRGB(120, 230, 140)
local WIDTH = 270

local gui: ScreenGui
local panel: Frame
local header: TextButton
local body: Frame
local collapsed = false
local state: any = nil

local function formatTime(seconds: number): string
	return ("%d:%04.1f"):format(seconds // 60, seconds % 60)
end

local function label(parent: Instance, text: string, size: number, color: Color3, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1, 0, 0, 0)
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

local function bar(parent: Instance, ratio: number, color: Color3, order: number)
	local track = Instance.new("Frame")
	track.BackgroundColor3 = Color3.fromRGB(50, 52, 64)
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, 0, 0, 5)
	track.LayoutOrder = order
	track.Parent = parent
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	fill.Parent = track
end

local function render()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not state then
		return
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local title = if state.Mode == "Tutorial" then Locale.T("GETTING STARTED") else Locale.T("DAILY CHALLENGES")
	if state.Mode ~= "Tutorial" and typeof(state.ResetsAt) == "number" then
		local left = math.max(0, state.ResetsAt - os.time())
		title ..= ("  ⏱ %dh %02dm"):format(left // 3600, (left % 3600) // 60)
	end
	header.Text = (if collapsed then "▸ " else "▾ ") .. title

	for _, item in state.Items or {} do
		local done = item.Done == true
		local text = Locale.Resolve(item.Text)
		local progress = if done then "✓" else ("%d/%d"):format(item.Progress or 0, item.Goal or 1)
		label(body, ("%s  ·  %s  ·  +%d kr"):format(text, progress, item.Reward or 0), 14, if done then DONE else Color3.new(1, 1, 1), nextOrder())
		if not done then
			bar(body, (item.Progress or 0) / math.max(item.Goal or 1, 1), ACCENT, nextOrder())
		end
	end
	if state.Bonus then
		local done = state.Bonus.Done == true
		label(body, Locale.T("All three: +%d kr", state.Bonus.Reward or 0) .. (if done then "  ✓" else ""), 13, if done then DONE else ACCENT, nextOrder())
	end
	if state.Weekly then
		local w = state.Weekly
		local best = if (w.Best or 0) > 0 then Locale.T("your best %s", formatTime(w.Best)) else Locale.T("no time yet")
		local text = Locale.T("Race of the week: %s – beat %s (+%d kr)", tostring(w.RaceName), formatTime(w.Target or 0), w.Reward or 0)
		label(body, text .. (if w.Done then "  ✓" else "  ·  " .. best), 13, if w.Done then DONE else Color3.fromRGB(150, 200, 255), nextOrder())
	end
	local _, total = CollectibleController.GetFound()
	local salmon = state.Salmon
	if salmon then
		label(body, "🐟 " .. Locale.T("Hidden salmon: %d/%d", salmon.Found or 0, salmon.Total or total), 13, Color3.fromRGB(200, 215, 230), nextOrder())
	end
end

local function updateVisibility()
	local busy = RaceController.IsRacing() or ActivityController.IsActive()
	panel.Visible = state ~= nil and VehicleController.GetCar() ~= nil and not busy
	body.Visible = not collapsed
end

function GoalsUI.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "GoalsUI"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 0)
	-- På pekskärm står återställningsknappen uppe till höger, så panelen flyttas in en bit
	panel.Position = UDim2.new(1, if UserInputService.TouchEnabled then -90 else -16, 0, 120)
	panel.Size = UDim2.fromOffset(WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	panel.BackgroundTransparency = 0.25
	panel.Visible = false
	panel.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	header = Instance.new("TextButton")
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 14
	header.TextColor3 = ACCENT
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Size = UDim2.new(1, 0, 0, 20)
	header.LayoutOrder = 0
	header.Parent = panel
	header.Activated:Connect(function()
		collapsed = not collapsed
		render()
		updateVisibility()
	end)

	body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 1
	body.Parent = panel
	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 3)
	bodyLayout.Parent = body

	Remotes.Get("GoalsState").OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" then
			state = data
			render()
			updateVisibility()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.J then
			collapsed = not collapsed
			render()
			updateVisibility()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			updateVisibility()
		end
	end)
	-- Nedräkningen till nya utmaningar
	task.spawn(function()
		while true do
			task.wait(30)
			render()
		end
	end)
end

return GoalsUI
