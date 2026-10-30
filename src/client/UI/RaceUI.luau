--!strict
-- Race-gränssnitt: startknapp vid startlinjen, nedräkning, racepanel och resultattavla.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local RaceController = require(script.Parent.Parent.Controllers.RaceController)

local RaceUI = {}

local INVITE_TIMEOUT = 1.6

local gui: ScreenGui
local prompt: TextButton
local countdownLabel: TextLabel
local panel: Frame
local positionLabel: TextLabel
local checkpointLabel: TextLabel
local timeLabel: TextLabel
local results: Frame
local resultList: Frame

local invitedRace: string? = nil
local lastInvite = 0
local startAt: number? = nil
local totalCheckpoints = 0
local raceStartedLocal = false

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, position: UDim2, dimension: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Position = position
	l.Size = dimension
	l.Parent = parent
	return l
end

local function formatTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return ("%d:%04.1f"):format(minutes, seconds - minutes * 60)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "RaceUI"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	prompt = Instance.new("TextButton")
	prompt.Name = "Prompt"
	prompt.AnchorPoint = Vector2.new(0.5, 1)
	prompt.Position = UDim2.new(0.5, 0, 1, -40)
	prompt.Size = UDim2.fromOffset(320, 56)
	prompt.BackgroundColor3 = Color3.fromRGB(255, 190, 40)
	prompt.Font = Enum.Font.GothamBlack
	prompt.TextSize = 22
	prompt.TextColor3 = Color3.fromRGB(25, 25, 30)
	prompt.Visible = false
	prompt.Parent = gui
	corner(prompt, 14)

	countdownLabel = Instance.new("TextLabel")
	countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	countdownLabel.Position = UDim2.fromScale(0.5, 0.4)
	countdownLabel.Size = UDim2.fromOffset(400, 140)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Font = Enum.Font.GothamBlack
	countdownLabel.TextSize = 110
	countdownLabel.TextColor3 = Color3.fromRGB(255, 210, 60)
	countdownLabel.TextStrokeTransparency = 0.2
	countdownLabel.Visible = false
	countdownLabel.Parent = gui

	panel = Instance.new("Frame")
	panel.Name = "RacePanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 120)
	panel.Size = UDim2.fromOffset(200, 128)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	panel.BackgroundTransparency = 0.25
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	positionLabel = label(panel, "POS -/-", 26, UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 32))
	checkpointLabel = label(panel, "CP 0/0", 18, UDim2.fromOffset(12, 40), UDim2.new(1, -24, 0, 22))
	timeLabel = label(panel, "0:00.0", 18, UDim2.fromOffset(12, 62), UDim2.new(1, -24, 0, 22))

	local leave = Instance.new("TextButton")
	leave.Text = Locale.T("LEAVE RACE")
	leave.Font = Enum.Font.GothamBold
	leave.TextSize = 14
	leave.TextColor3 = Color3.new(1, 1, 1)
	leave.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
	leave.Position = UDim2.fromOffset(12, 92)
	leave.Size = UDim2.new(1, -24, 0, 26)
	leave.Parent = panel
	corner(leave, 8)
	leave.Activated:Connect(RaceController.Leave)

	results = Instance.new("Frame")
	results.Name = "Results"
	results.AnchorPoint = Vector2.new(0.5, 0.5)
	results.Position = UDim2.fromScale(0.5, 0.45)
	results.Size = UDim2.fromOffset(420, 0)
	results.AutomaticSize = Enum.AutomaticSize.Y
	results.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	results.BackgroundTransparency = 0.1
	results.Visible = false
	results.Parent = gui
	corner(results, 14)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = results
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = results
	resultList = results
end

local function showResults(data: any)
	for _, child in resultList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local title = label(resultList, Locale.T("RESULTS · %s", Locale.T(tostring(data.RaceName or ""))), 22, UDim2.new(), UDim2.new(1, 0, 0, 30))
	title.TextColor3 = Color3.fromRGB(255, 210, 60)
	title.LayoutOrder = 0
	local me = Players.LocalPlayer.UserId
	for i, result in data.Results or {} do
		local time = if result.Time then formatTime(result.Time) else "DNF"
		local reward = if (result.Reward or 0) > 0 then ("  +%d kr"):format(result.Reward) else ""
		local row = label(resultList, ("%d. %s   %s%s"):format(result.Position, result.Name, time, reward), 18, UDim2.new(), UDim2.new(1, 0, 0, 24))
		row.LayoutOrder = i
		row.Font = Enum.Font.GothamBold
		if result.UserId == me then
			row.TextColor3 = Color3.fromRGB(120, 255, 140)
		end
	end
	local close = Instance.new("TextButton")
	close.Text = "OK"
	close.Font = Enum.Font.GothamBlack
	close.TextSize = 20
	close.Size = UDim2.new(1, 0, 0, 40)
	close.BackgroundColor3 = Color3.fromRGB(255, 190, 40)
	close.LayoutOrder = 999
	close.Parent = resultList
	corner(close, 10)
	close.Activated:Connect(function()
		results.Visible = false
	end)
	results.Visible = true
	task.delay(15, function()
		results.Visible = false
	end)
end

local function join()
	if invitedRace and prompt.Visible then
		RaceController.Join(invitedRace)
		prompt.Visible = false
		lastInvite = 0
	end
end

function RaceUI.Start()
	build()

	RaceController.Invited:Connect(function(raceId: string, raceName: string, lobbyOpen: boolean)
		invitedRace = raceId
		lastInvite = os.clock()
		local action = Locale.T(if lobbyOpen then "JOIN RACE" else "START RACE")
		local key = if UserInputService.TouchEnabled then "" else " (E)"
		prompt.Text = ("%s%s · %s"):format(action, key, Locale.T(raceName))
		prompt.Visible = true
	end)
	prompt.Activated:Connect(join)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and (input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonB) then
			join()
		end
	end)

	RaceController.SetupReceived:Connect(function(setup: any)
		startAt = setup.StartAt
		totalCheckpoints = #setup.Checkpoints
		raceStartedLocal = false
		prompt.Visible = false
		results.Visible = false
		panel.Visible = true
		positionLabel.Text = ("POS -/%d"):format(setup.Participants)
		checkpointLabel.Text = ("CP 0/%d"):format(totalCheckpoints)
		timeLabel.Text = "0:00.0"
	end)
	RaceController.CheckpointPassed:Connect(function(passed: number, total: number)
		checkpointLabel.Text = ("CP %d/%d"):format(passed, total)
	end)
	RaceController.Updated:Connect(function(position: number, total: number, _elapsed: number)
		positionLabel.Text = ("POS %d/%d"):format(position, total)
	end)
	RaceController.Finished:Connect(function(data: any)
		startAt = nil
		panel.Visible = false
		countdownLabel.Visible = false
		if not data.Left then
			showResults(data)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if prompt.Visible and os.clock() - lastInvite > INVITE_TIMEOUT then
			prompt.Visible = false
		end
		local start = startAt
		if not start then
			return
		end
		local now = workspace:GetServerTimeNow()
		local left = start - now
		if left > 0 then
			countdownLabel.Visible = true
			countdownLabel.Text = tostring(math.ceil(left))
		elseif left > -1 then
			countdownLabel.Visible = true
			countdownLabel.Text = Locale.T("GO!")
			raceStartedLocal = true
		else
			countdownLabel.Visible = false
		end
		if raceStartedLocal or left <= 0 then
			timeLabel.Text = formatTime(math.max(0, now - start))
		end
	end)
end

return RaceUI
