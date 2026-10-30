--!strict
-- Butiken: daglig belöning, game passes och developer products.
-- Köp startas med Robloxs egna köpfönster (MarketplaceService); servern delar ut.
-- I Studio finns "Testa"-knappar så att allt kan provas utan riktiga köp.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EffectsController = require(script.Parent.Parent.Controllers.EffectsController)
local VehicleController = require(script.Parent.Parent.Controllers.VehicleController)

local ShopUI = {}

local ACCENT = Color3.fromRGB(255, 120, 200)
local CARD = Color3.fromRGB(35, 40, 58)
local GOLD = Color3.fromRGB(255, 215, 80)

local player = Players.LocalPlayer
local gui: ScreenGui
local window: Frame
local content: ScrollingFrame
local dailyToast: TextButton
local actionRemote: RemoteEvent
local shopState: any = nil
local toastShown = false

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, height: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = text
	l.Size = UDim2.new(1, 0, 0, height)
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 15
	b.TextColor3 = Color3.fromRGB(20, 20, 25)
	b.BackgroundColor3 = color
	b.Size = UDim2.new(0, 150, 0, 32)
	b.Parent = parent
	corner(b, 8)
	b.Activated:Connect(onClick)
	return b
end

local function card(order: number, title: string, description: string): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = CARD
	frame.Size = UDim2.new(1, -8, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	frame.Parent = content
	corner(frame, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	label(frame, title, 18, 22, GOLD).LayoutOrder = 1
	label(frame, description, 13, 32, Color3.fromRGB(210, 210, 220)).LayoutOrder = 2
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 32)
	row.LayoutOrder = 3
	row.Parent = frame
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = row
	return row
end

local function render()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not shopState then
		return
	end
	local studio = shopState.Studio == true
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Daglig belöning
	local daily = shopState.Daily
	local dailyRow = card(nextOrder(), Locale.T("Daily reward"), if daily.Available
		then Locale.T("%d kr to collect (day %d in a row)", daily.Reward, daily.Streak + 1)
		else Locale.T("Collected! Come back tomorrow. %d days in a row.", daily.Streak))
	if daily.Available then
		button(dailyRow, Locale.T("COLLECT"), GOLD, function()
			actionRemote:FireServer("ClaimDaily")
		end)
	end

	label(content, Locale.T("GAME PASSES · cosmetics and convenience"), 15, 22, ACCENT).LayoutOrder = nextOrder()
	for _, pass in ShopConfig.Passes do
		local owned = shopState.Passes[pass.Key] == true
		local row = card(nextOrder(), Locale.T(pass.Name) .. (if owned then "  ✓" else ""), Locale.T(pass.Description))
		if not owned and pass.Id ~= 0 then
			button(row, Locale.T("BUY"), ACCENT, function()
				MarketplaceService:PromptGamePassPurchase(player, pass.Id)
			end)
		elseif not owned then
			label(row, Locale.T("Not in the store yet"), 13, 32, Color3.fromRGB(160, 160, 170)).Size = UDim2.new(0, 150, 0, 32)
		end
		if studio then
			button(row, Locale.T(if owned then "Remove (Studio)" else "Try (Studio)"), Color3.fromRGB(150, 150, 160), function()
				actionRemote:FireServer("StudioTest", pass.Key)
			end)
		end
	end

	label(content, Locale.T("EXTRA · one-time purchases"), 15, 22, ACCENT).LayoutOrder = nextOrder()
	for _, product in ShopConfig.Products do
		local row = card(nextOrder(), Locale.T(product.Name), Locale.T(product.Description))
		if product.Id ~= 0 then
			button(row, Locale.T("BUY"), ACCENT, function()
				MarketplaceService:PromptProductPurchase(player, product.Id)
			end)
		else
			label(row, Locale.T("Not in the store yet"), 13, 32, Color3.fromRGB(160, 160, 170)).Size = UDim2.new(0, 150, 0, 32)
		end
		if studio then
			button(row, Locale.T("Try (Studio)"), Color3.fromRGB(150, 150, 160), function()
				actionRemote:FireServer("StudioTest", product.Key)
			end)
		end
	end
end

local function setOpen(open: boolean)
	window.Visible = open
	if open then
		dailyToast.Visible = false
		render()
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "ShopUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Text = "SHOP (B)"
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 18
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	toggle.BackgroundTransparency = 0.3
	toggle.Position = UDim2.fromOffset(272, 70)
	toggle.Size = UDim2.fromOffset(110, 40)
	toggle.Parent = gui
	corner(toggle, 10)
	toggle.Activated:Connect(function()
		setOpen(not window.Visible)
	end)

	window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.8, 0.82)
	window.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	window.Visible = false
	window.Parent = gui
	corner(window, 16)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(520, 520)
	constraint.Parent = window

	local title = label(window, "SHOP", 24, 36, ACCENT)
	title.Font = Enum.Font.GothamBlack
	title.Position = UDim2.fromOffset(18, 10)
	title.Size = UDim2.new(1, -80, 0, 36)

	local close = Instance.new("TextButton")
	close.Text = "✕"
	close.Font = Enum.Font.GothamBlack
	close.TextSize = 20
	close.TextColor3 = Color3.new(1, 1, 1)
	close.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(36, 36)
	close.Parent = window
	corner(close, 18)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	content = Instance.new("ScrollingFrame")
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(16, 56)
	content.Size = UDim2.new(1, -24, 1, -68)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.ScrollBarThickness = 4
	content.Parent = window
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	dailyToast = Instance.new("TextButton")
	dailyToast.AnchorPoint = Vector2.new(0.5, 0)
	dailyToast.Position = UDim2.new(0.5, 0, 0, 96)
	dailyToast.Size = UDim2.fromOffset(340, 44)
	dailyToast.BackgroundColor3 = GOLD
	dailyToast.Font = Enum.Font.GothamBlack
	dailyToast.TextSize = 18
	dailyToast.TextColor3 = Color3.fromRGB(30, 25, 10)
	dailyToast.Visible = false
	dailyToast.Parent = gui
	corner(dailyToast, 12)
	dailyToast.Activated:Connect(function()
		setOpen(true)
	end)
end

function ShopUI.Start()
	actionRemote = Remotes.Get("ShopAction")
	build()

	Remotes.Get("ShopState").OnClientEvent:Connect(function(state: any)
		if typeof(state) ~= "table" or typeof(state.Passes) ~= "table" or typeof(state.Daily) ~= "table" then
			return
		end
		shopState = state
		if window.Visible then
			render()
		end
		if state.Daily.Available and not toastShown then
			toastShown = true
			dailyToast.Text = "🎁 " .. Locale.T("Daily reward: %d kr – tap here", state.Daily.Reward)
			dailyToast.Visible = true
			task.delay(12, function()
				dailyToast.Visible = false
			end)
		elseif not state.Daily.Available then
			dailyToast.Visible = false
		end
	end)

	Remotes.Get("Celebrate").OnClientEvent:Connect(function(position: unknown)
		if typeof(position) == "Vector3" then
			EffectsController.Confetti(position :: Vector3)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and gui.Enabled and input.KeyCode == Enum.KeyCode.B then
			setOpen(not window.Visible)
		end
	end)
	VehicleController.Entered:Connect(function()
		gui.Enabled = true
	end)
end

return ShopUI
