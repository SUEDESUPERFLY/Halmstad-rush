--!strict
-- Topplistor och "spela tillsammans": fönster (L eller TOP-knappen) med listorna, veckans race,
-- bjud in vänner, Roblox-gruppen och listan över gömda laxar. Ritar också texten på tavlan
-- på Stora torg (taggen "LeaderboardBoard"), så att den hamnar på spelarens språk.

local CollectionService = game:GetService("CollectionService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")

local CommunityConfig = require(ReplicatedStorage.Shared.Config.CommunityConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CollectibleController = require(script.Parent.Parent.Controllers.CollectibleController)

local LeaderboardUI = {}

local ACCENT = Color3.fromRGB(255, 200, 40)
local DONE = Color3.fromRGB(120, 230, 140)

local player = Players.LocalPlayer
local gui: ScreenGui
local window: Frame
local boardsColumn: ScrollingFrame
local sideColumn: ScrollingFrame
local state: any = nil
local boardGuis: { [Instance]: Frame } = {}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function list(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3, order: number, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamMedium
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

local function button(parent: Instance, text: string, color: Color3, order: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = Color3.fromRGB(20, 20, 25)
	b.BackgroundColor3 = color
	b.Size = UDim2.new(1, 0, 0, 36)
	b.LayoutOrder = order
	b.Parent = parent
	corner(b, 8)
	b.Activated:Connect(onClick)
	return b
end

local function formatValue(entry: any, format: string): string
	local value = tonumber(entry.Value) or 0
	if format == "time" then
		return ("%d:%04.1f"):format(value // 60, value % 60)
	end
	return tostring(math.floor(value))
end

-- Ritar en lista (rubrik + rader) i en behållare med UIListLayout.
local function drawBoard(parent: Instance, board: any, textSize: number, order: number): number
	label(parent, Locale.Resolve(board.Title), textSize + 2, ACCENT, order, Enum.Font.GothamBlack)
	order += 1
	local entries = board.Entries or {}
	if #entries == 0 then
		label(parent, Locale.T("No entries yet – be the first!"), textSize, Color3.fromRGB(170, 170, 185), order)
		return order + 1
	end
	for _, entry in entries do
		local mine = entry.UserId == player.UserId
		label(
			parent,
			("%d. %s   %s"):format(entry.Rank or 0, tostring(entry.Name), formatValue(entry, board.Format)),
			textSize,
			if mine then DONE else Color3.new(1, 1, 1),
			order
		)
		order += 1
	end
	return order
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function inviteFriends()
	local ok, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and canInvite then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end
end

local function joinGroup()
	local groupId = player:GetAttribute("GroupId")
	if typeof(groupId) ~= "number" or groupId == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			(GroupService :: any):PromptJoinAsync(groupId)
		end)
		Remotes.Get("CommunityAction"):FireServer("CheckGroup")
	end)
end

local function renderSide()
	clear(sideColumn)
	list(sideColumn, 6)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	if state and state.Weekly then
		local w = state.Weekly
		label(sideColumn, Locale.T("RACE OF THE WEEK"), 16, ACCENT, nextOrder(), Enum.Font.GothamBlack)
		local left = math.max(0, (w.EndsAt or 0) - os.time())
		label(
			sideColumn,
			Locale.T("%s: beat %s for +%d kr. Ends in %d days %d h.", tostring(w.RaceName), formatValue({ Value = w.Target }, "time"), w.Reward or 0, left // 86400, (left % 86400) // 3600),
			14,
			Color3.new(1, 1, 1),
			nextOrder()
		)
	end

	label(sideColumn, Locale.T("PLAY TOGETHER"), 16, ACCENT, nextOrder(), Enum.Font.GothamBlack)
	label(sideColumn, Locale.T("Friends on the same server give everyone +%d%% kronor.", math.floor(CommunityConfig.FriendBonus * 100)), 14, Color3.new(1, 1, 1), nextOrder())
	if player:GetAttribute("FriendBonus") == true then
		label(sideColumn, "✓ " .. Locale.T("Friend bonus active"), 14, DONE, nextOrder())
	end
	button(sideColumn, Locale.T("INVITE FRIENDS"), Color3.fromRGB(90, 210, 120), nextOrder(), inviteFriends)
	local groupId = player:GetAttribute("GroupId")
	if typeof(groupId) == "number" and groupId ~= 0 then
		if player:GetAttribute("Unlock_Group") == true then
			label(sideColumn, "✓ " .. Locale.T("Group member: Rush blue paint unlocked"), 14, DONE, nextOrder())
		else
			button(sideColumn, Locale.T("JOIN THE GROUP: free paint"), Color3.fromRGB(80, 160, 255), nextOrder(), joinGroup)
		end
	end

	local found, total = CollectibleController.GetFound()
	local count = 0
	for _ in found do
		count += 1
	end
	label(sideColumn, Locale.T("HIDDEN SALMON %d/%d", count, total), 16, ACCENT, nextOrder(), Enum.Font.GothamBlack)
	label(sideColumn, Locale.T("Drive through a silver salmon to catch it. Find them all for a special paint."), 13, Color3.fromRGB(200, 205, 220), nextOrder())
	for _, spot in CommunityConfig.Salmon do
		local isFound = found[spot.Id] == true
		label(sideColumn, (if isFound then "✓ " else "· ") .. spot.Name, 14, if isFound then DONE else Color3.fromRGB(170, 170, 185), nextOrder())
	end
end

local function renderBoards()
	clear(boardsColumn)
	list(boardsColumn, 3)
	local order = 0
	for _, board in (state and state.Boards) or {} do
		order = drawBoard(boardsColumn, board, 15, order) + 1
		local spacer = Instance.new("Frame")
		spacer.BackgroundTransparency = 1
		spacer.Size = UDim2.new(1, 0, 0, 8)
		spacer.LayoutOrder = order
		spacer.Parent = boardsColumn
		order += 1
	end
end

-- Tavlan på Stora torg: tre kolumner på skyltens framsida.
local function drawWorldBoard(panelPart: Instance)
	local frame = boardGuis[panelPart]
	if not frame then
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Front
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 20
		surface.LightInfluence = 0.1
		surface.Parent = panelPart
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(1, 1)
		holder.Parent = surface
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 16)
		padding.PaddingTop = UDim.new(0, 12)
		padding.Parent = holder
		local columns = Instance.new("UIListLayout")
		columns.FillDirection = Enum.FillDirection.Horizontal
		columns.Padding = UDim.new(0, 16)
		columns.Parent = holder
		boardGuis[panelPart] = holder
		frame = holder
		panelPart.AncestryChanged:Connect(function()
			if not panelPart.Parent then
				boardGuis[panelPart] = nil
			end
		end)
	end
	local holder = frame :: Frame
	clear(holder)
	local boards = (state and state.Boards) or {}
	for index, board in boards do
		local column = Instance.new("Frame")
		column.BackgroundTransparency = 1
		column.Size = UDim2.new(1 / math.max(#boards, 1), -16, 1, 0)
		column.LayoutOrder = index
		column.Parent = holder
		list(column, 2)
		drawBoard(column, board, 20, 1)
	end
end

local function render()
	if window.Visible then
		renderBoards()
		renderSide()
	end
	for _, panelPart in CollectionService:GetTagged("LeaderboardBoard") do
		drawWorldBoard(panelPart)
	end
end

local function setOpen(open: boolean)
	window.Visible = open
	render()
end

function LeaderboardUI.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "LeaderboardUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Text = Locale.T("TOP (L)")
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 18
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	toggle.BackgroundTransparency = 0.3
	toggle.Position = UDim2.fromOffset(486, 70)
	toggle.Size = UDim2.fromOffset(96, 40)
	toggle.Parent = gui
	corner(toggle, 10)
	toggle.Activated:Connect(function()
		setOpen(not window.Visible)
	end)

	window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.85, 0.82)
	window.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	window.Visible = false
	window.Parent = gui
	corner(window, 16)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(820, 560)
	constraint.Parent = window

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextColor3 = ACCENT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = Locale.T("TOP LISTS & FRIENDS")
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

	local function column(x: number, width: number): ScrollingFrame
		local scroll = Instance.new("ScrollingFrame")
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.Position = UDim2.new(x, 18, 0, 56)
		scroll.Size = UDim2.new(width, -30, 1, -70)
		scroll.ScrollBarThickness = 6
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
		scroll.Parent = window
		return scroll
	end
	boardsColumn = column(0, 0.55)
	sideColumn = column(0.55, 0.45)

	Remotes.Get("LeaderboardState").OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" then
			state = data
			render()
		end
	end)
	CollectibleController.Changed:Connect(function()
		if window.Visible then
			renderSide()
		end
	end)
	for _, name in { "FriendBonus", "Unlock_Group" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if window.Visible then
				renderSide()
			end
		end)
	end
	CollectionService:GetInstanceAddedSignal("LeaderboardBoard"):Connect(function(panelPart)
		task.defer(drawWorldBoard, panelPart)
	end)
	for _, panelPart in CollectionService:GetTagged("LeaderboardBoard") do
		drawWorldBoard(panelPart)
	end
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.L then
			setOpen(not window.Visible)
		end
	end)
end

return LeaderboardUI
