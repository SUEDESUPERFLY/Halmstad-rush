--!strict
-- Gränssnitt för aktiviteter: startknapp vid markören, statuspanel (titel, roll, mål, tid,
-- poäng, avbryt), nedräkning och resultattavla. Visar bara det servern skickar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local ActivityController = require(script.Parent.Parent.Controllers.ActivityController)

local ActivityUI = {}

local INVITE_TIMEOUT = 1.6
local ACCENT = Color3.fromRGB(90, 230, 140)

local gui: ScreenGui
local prompt: TextButton
local promptDescription: TextLabel
local panel: Frame
local titleLabel: TextLabel
local roleLabel: TextLabel
local objectiveLabel: TextLabel
local timerLabel: TextLabel
local scoreLabel: TextLabel
local countdownLabel: TextLabel
local resultFrame: Frame

local invitedId: string? = nil
local lastInvite = 0
local current: { [string]: any }? = nil

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, size: number, height: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Size = UDim2.new(1, 0, 0, height)
	l.Text = ""
	l.Parent = parent
	return l
end

local function list(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = parent
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "ActivityUI"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	prompt = Instance.new("TextButton")
	prompt.AnchorPoint = Vector2.new(0.5, 1)
	prompt.Position = UDim2.new(0.5, 0, 1, -110)
	prompt.Size = UDim2.fromOffset(340, 70)
	prompt.BackgroundColor3 = ACCENT
	prompt.Font = Enum.Font.GothamBlack
	prompt.TextSize = 20
	prompt.TextColor3 = Color3.fromRGB(20, 25, 25)
	prompt.TextYAlignment = Enum.TextYAlignment.Top
	prompt.Visible = false
	prompt.Parent = gui
	corner(prompt, 14)
	local promptPad = Instance.new("UIPadding")
	promptPad.PaddingTop = UDim.new(0, 8)
	promptPad.Parent = prompt
	promptDescription = label(prompt, 13, 28, Color3.fromRGB(20, 40, 30))
	promptDescription.Position = UDim2.new(0, 10, 0, 28)
	promptDescription.Size = UDim2.new(1, -20, 0, 30)
	promptDescription.TextXAlignment = Enum.TextXAlignment.Center

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 120)
	panel.Size = UDim2.fromOffset(260, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	panel.BackgroundTransparency = 0.25
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	list(panel, 4)
	titleLabel = label(panel, 20, 26, ACCENT)
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.LayoutOrder = 1
	roleLabel = label(panel, 22, 28, Color3.fromRGB(255, 120, 200))
	roleLabel.Font = Enum.Font.GothamBlack
	roleLabel.LayoutOrder = 2
	objectiveLabel = label(panel, 14, 34)
	objectiveLabel.LayoutOrder = 3
	timerLabel = label(panel, 18, 22, Color3.fromRGB(255, 215, 80))
	timerLabel.LayoutOrder = 4
	scoreLabel = label(panel, 16, 22)
	scoreLabel.LayoutOrder = 5
	local leave = Instance.new("TextButton")
	leave.Text = Locale.T("QUIT")
	leave.Font = Enum.Font.GothamBold
	leave.TextSize = 14
	leave.TextColor3 = Color3.new(1, 1, 1)
	leave.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
	leave.Size = UDim2.new(1, 0, 0, 26)
	leave.LayoutOrder = 6
	leave.Parent = panel
	corner(leave, 8)
	leave.Activated:Connect(ActivityController.Leave)

	countdownLabel = Instance.new("TextLabel")
	countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	countdownLabel.Position = UDim2.fromScale(0.5, 0.4)
	countdownLabel.Size = UDim2.fromOffset(400, 140)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Font = Enum.Font.GothamBlack
	countdownLabel.TextSize = 110
	countdownLabel.TextColor3 = Color3.fromRGB(255, 120, 80)
	countdownLabel.TextStrokeTransparency = 0.2
	countdownLabel.Visible = false
	countdownLabel.Parent = gui

	resultFrame = Instance.new("Frame")
	resultFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	resultFrame.Position = UDim2.fromScale(0.5, 0.45)
	resultFrame.Size = UDim2.fromOffset(400, 0)
	resultFrame.AutomaticSize = Enum.AutomaticSize.Y
	resultFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	resultFrame.BackgroundTransparency = 0.1
	resultFrame.Visible = false
	resultFrame.Parent = gui
	corner(resultFrame, 14)
end

local function showResult(result: any)
	for _, child in resultFrame:GetChildren() do
		if child:IsA("GuiObject") or child:IsA("UIListLayout") or child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	list(resultFrame, 6)
	local small = label(resultFrame, 14, 18, Color3.fromRGB(200, 200, 210))
	small.Text = Locale.Resolve(result.Activity)
	small.LayoutOrder = 0
	local title = label(resultFrame, 30, 38, ACCENT)
	title.Font = Enum.Font.GothamBlack
	title.Text = Locale.Resolve(result.Title)
	title.LayoutOrder = 1
	for i, line in result.Lines or {} do
		local row = label(resultFrame, 16, 22)
		row.Text = Locale.Resolve(line)
		row.LayoutOrder = 1 + i
	end
	local reward = label(resultFrame, 22, 30, Color3.fromRGB(255, 215, 80))
	reward.Font = Enum.Font.GothamBlack
	reward.Text = if (result.Reward or 0) > 0 then ("+%d kr"):format(result.Reward) else Locale.T("No reward this time")
	reward.LayoutOrder = 100
	local ok = Instance.new("TextButton")
	ok.Text = "OK"
	ok.Font = Enum.Font.GothamBlack
	ok.TextSize = 20
	ok.Size = UDim2.new(1, 0, 0, 40)
	ok.BackgroundColor3 = ACCENT
	ok.LayoutOrder = 101
	ok.Parent = resultFrame
	corner(ok, 10)
	ok.Activated:Connect(function()
		resultFrame.Visible = false
	end)
	resultFrame.Visible = true
	task.delay(12, function()
		resultFrame.Visible = false
	end)
end

local function start()
	if invitedId and prompt.Visible then
		ActivityController.Request(invitedId)
		prompt.Visible = false
		lastInvite = 0
	end
end

local function formatTime(seconds: number): string
	seconds = math.max(0, seconds)
	return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60))
end

function ActivityUI.Start()
	build()

	ActivityController.Invited:Connect(function(id: string, name: string, description: string)
		invitedId = id
		lastInvite = os.clock()
		local key = if UserInputService.TouchEnabled then "" else " (E)"
		prompt.Text = ("%s%s · %s"):format(Locale.T("START"), key, name)
		promptDescription.Text = description
		prompt.Visible = true
	end)
	prompt.Activated:Connect(start)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and (input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonB) then
			start()
		end
	end)

	ActivityController.StateChanged:Connect(function(state: any)
		current = state
		prompt.Visible = false
		resultFrame.Visible = false
		panel.Visible = true
		titleLabel.Text = Locale.Resolve(state.Title)
		roleLabel.Text = Locale.Resolve(state.Role)
		roleLabel.Visible = state.Role ~= nil
		objectiveLabel.Text = Locale.Resolve(state.Objective)
		scoreLabel.Text = Locale.Resolve(state.Score)
	end)
	ActivityController.Finished:Connect(function(result: any)
		current = nil
		panel.Visible = false
		countdownLabel.Visible = false
		if not result.Left then
			showResult(result)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if prompt.Visible and os.clock() - lastInvite > INVITE_TIMEOUT then
			prompt.Visible = false
		end
		local state = current
		if not state then
			return
		end
		local now = workspace:GetServerTimeNow()
		if typeof(state.EndsAt) == "number" then
			timerLabel.Text = "⏱ " .. formatTime(state.EndsAt - now)
		else
			timerLabel.Text = ""
		end
		local countdown = state.CountdownTo
		if typeof(countdown) == "number" and countdown - now > -0.8 then
			countdownLabel.Visible = true
			countdownLabel.Text = if countdown - now > 0 then tostring(math.ceil(countdown - now)) else Locale.T("GO!")
		else
			countdownLabel.Visible = false
		end
	end)
end

return ActivityUI
