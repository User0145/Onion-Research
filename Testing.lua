--[[
	Robin UI Library
	Usage:
		local Library = require(path.to.RobinUI)
		local Window = Library:CreateWindow({ Title = "Robin" })
		local Tab = Window:AddTab("Visuals")
		local Panel = Tab:AddPanel("ESP")
		Panel:AddToggle({ Name = "ESP", Default = true, Module = true, Flag = "ESP", Callback = function(v) end })
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer

local Library = {
	Flags = {},
	ToggleKey = Enum.KeyCode.RightShift,
	Theme = {
		Accent = Color3.fromRGB(134, 125, 224),
		Background = Color3.fromRGB(29, 29, 43),
		Element = Color3.fromRGB(40, 40, 58),
		Text = Color3.fromRGB(240, 240, 250),
		SubText = Color3.fromRGB(135, 135, 160),
		Stroke = Color3.fromRGB(12, 12, 20),
		Font = Enum.Font.SourceSans,
		TitleFont = Enum.Font.Garamond,
		TextSize = 14,
		RowHeight = 18,
	},
	_accent = {},
	_refresh = {},
	_connections = {},
	_z = 1,
}

local Theme = Library.Theme

local Window = {}
Window.__index = Window
local Tab = {}
Tab.__index = Tab
local Panel = {}
Panel.__index = Panel

local function create(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function tween(obj, props, t)
	TweenService:Create(obj, TweenInfo.new(t or 0.12, Enum.EasingStyle.Quad), props):Play()
end

local function accent(obj, prop)
	table.insert(Library._accent, { obj, prop })
	obj[prop] = Theme.Accent
	return obj
end

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(Library._connections, c)
	return c
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

-- InputObject positions exclude the top bar inset; our ScreenGui ignores it, so add it back.
local function toScreen(pos)
	local inset = GuiService:GetGuiInset()
	return Vector2.new(pos.X + inset.X, pos.Y + inset.Y)
end

local function bindDrag(target, onMove)
	local dragging = false
	connect(target.InputBegan, function(input)
		if isPress(input) then
			dragging = true
			onMove(toScreen(input.Position))
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			onMove(toScreen(input.Position))
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if isPress(input) then
			dragging = false
		end
	end)
end

local function makeDraggable(handle, frame)
	local dragging, startInput, startPos = false, nil, nil
	connect(handle.InputBegan, function(input)
		if isPress(input) then
			dragging, startInput, startPos = true, input.Position, frame.Position
			Library._z += 1
			frame.ZIndex = Library._z
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			local d = input.Position - startInput
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if isPress(input) then
			dragging = false
		end
	end)
end

local function textLabel(props)
	local base = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextSize = Theme.TextSize,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return create("TextLabel", base)
end

local function escapeRich(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function textWidth(text, size)
	return TextService:GetTextSize(text, size, Theme.Font, Vector2.new(10000, 100)).X
end

-- Executor environment helpers (all optional; falls back to plain Roblox APIs)
local env = (getgenv and getgenv()) or _G

local function getParent()
	if gethui then
		local ok, hui = pcall(gethui)
		if ok and hui then
			return hui
		end
	end
	local ok, core = pcall(game.GetService, game, "CoreGui")
	return ok and core or LocalPlayer:WaitForChild("PlayerGui")
end

local function protect(gui)
	if syn and syn.protect_gui then
		pcall(syn.protect_gui, gui)
	elseif protectgui then
		pcall(protectgui, gui)
	end
end

-- Accepts "rbxassetid://..." or a path in the executor workspace folder (e.g. "robin.png")
function Library:GetAsset(image)
	if type(image) ~= "string" or image:find("^rbxasset") or image:find("^https?://") then
		return image
	end
	local loader = getcustomasset or getsynasset
	if loader and isfile and isfile(image) then
		local ok, asset = pcall(loader, image)
		if ok then
			return asset
		end
	end
	return image
end

--------------------------------------------------------------------------------
-- Color picker (shared by AddColorPicker and AddToggle{Color=...})
--------------------------------------------------------------------------------
local function buildColorPicker(panel, row, o)
	local picker = { Value = o.Default or Color3.new(1, 1, 1) }
	local h, s, v = picker.Value:ToHSV()

	local swatch = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(22, 10),
		BackgroundColor3 = picker.Value,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	}, { create("UIStroke", { Color = Theme.Stroke }) })

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 110),
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = panel:_next(),
		Parent = panel.Frame,
	})

	local sv = create("TextButton", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -34, 1, -12),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = holder,
	})
	create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = sv }, {
		create("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
	})
	create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sv }, {
		create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }),
	})
	local svCursor = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = sv,
	}, { create("UIStroke", { Color = Color3.new(0, 0, 0) }) })

	local keypoints = {}
	for i = 0, 6 do
		keypoints[#keypoints + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1))
	end
	local hue = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.new(0, 16, 1, -12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = holder,
	}, { create("UIGradient", { Rotation = 90, Color = ColorSequence.new(keypoints) }) })
	local hueCursor = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = hue,
	}, { create("UIStroke", { Color = Color3.new(0, 0, 0) }) })

	local function update(fire)
		picker.Value = Color3.fromHSV(h, s, v)
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		swatch.BackgroundColor3 = picker.Value
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.fromScale(0, h)
		if o.Flag then
			Library.Flags[o.Flag] = picker.Value
		end
		if fire ~= false and o.Callback then
			task.spawn(o.Callback, picker.Value)
		end
	end

	bindDrag(sv, function(p)
		s = math.clamp((p.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
		v = 1 - math.clamp((p.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
		update()
	end)
	bindDrag(hue, function(p)
		h = math.clamp((p.Y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 1)
		update()
	end)
	connect(swatch.MouseButton1Click, function()
		holder.Visible = not holder.Visible
	end)

	function picker:Set(color)
		h, s, v = color:ToHSV()
		update()
	end

	update(o.FireOnStart == true)
	return picker
end

--------------------------------------------------------------------------------
-- Panel (a draggable column like "ESP", "Chams", "Cursor"...)
--------------------------------------------------------------------------------
function Panel:_next()
	self.Order += 1
	return self.Order
end

function Panel:_row(class, props)
	local base = {
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		LayoutOrder = self:_next(),
		Parent = self.Frame,
	}
	if class == "TextButton" then
		base.AutoButtonColor = false
		base.Text = ""
	end
	for k, v in pairs(props or {}) do
		base[k] = v
	end
	return create(class, base)
end

function Panel:AddLabel(text)
	local row = self:_row("Frame")
	local label = textLabel({
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		Text = text,
		TextColor3 = Theme.SubText,
		Parent = row,
	})
	return {
		Set = function(_, t)
			label.Text = t
		end,
	}
end

function Panel:AddToggle(o)
	o = o or {}
	local window = self.Window
	local toggle = { Value = o.Default == true }

	local row = self:_row("TextButton")
	local label = textLabel({
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		Text = o.Name or "Toggle",
		Parent = row,
	})

	local function render(instant)
		local rowProps = { BackgroundColor3 = toggle.Value and Theme.Accent or Theme.Background }
		local textProps = { TextColor3 = toggle.Value and Theme.Text or Theme.SubText }
		if instant then
			row.BackgroundColor3, label.TextColor3 = rowProps.BackgroundColor3, textProps.TextColor3
		else
			tween(row, rowProps)
			tween(label, textProps)
		end
	end

	function toggle:Set(value)
		self.Value = value and true or false
		if o.Flag then
			Library.Flags[o.Flag] = self.Value
		end
		render()
		if o.Module then
			window:_setModule(o.Name, self.Value)
		end
		if o.Callback then
			task.spawn(o.Callback, self.Value)
		end
	end

	connect(row.MouseButton1Click, function()
		toggle:Set(not toggle.Value)
	end)

	if o.Keybind then
		connect(UserInputService.InputBegan, function(input, processed)
			if not processed and input.KeyCode == o.Keybind then
				toggle:Set(not toggle.Value)
			end
		end)
	end

	if o.Color then
		toggle.ColorPicker = buildColorPicker(self, row, { Default = o.Color, Flag = o.ColorFlag, Callback = o.ColorCallback })
	end

	table.insert(Library._refresh, function()
		render(true)
	end)
	render(true)
	if o.Flag then
		Library.Flags[o.Flag] = toggle.Value
	end
	if toggle.Value and o.Module then
		window:_setModule(o.Name, true)
	end
	return toggle
end

function Panel:AddSlider(o)
	o = o or {}
	local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
	local decimals = (tostring(inc):match("%.(%d+)") or ""):len()
	local slider = { Value = nil }

	local row = self:_row("Frame", { Active = true })
	local fill = accent(create("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = row }), "BackgroundColor3")
	textLabel({
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		Text = o.Name or "Slider",
		ZIndex = 2,
		Parent = row,
	})
	local valueLabel = textLabel({
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
		Parent = row,
	})

	local function fmt(x)
		return string.format("%." .. decimals .. "f", x) .. (o.Suffix or "")
	end

	function slider:Set(value, silent)
		value = math.clamp(math.floor((value - min) / inc + 0.5) * inc + min, min, max)
		if value == self.Value then
			return
		end
		self.Value = value
		fill.Size = UDim2.fromScale((value - min) / (max - min), 1)
		valueLabel.Text = fmt(value) .. "/" .. fmt(max)
		if o.Flag then
			Library.Flags[o.Flag] = value
		end
		if not silent and o.Callback then
			task.spawn(o.Callback, value)
		end
	end

	bindDrag(row, function(p)
		local pct = math.clamp((p.X - row.AbsolutePosition.X) / row.AbsoluteSize.X, 0, 1)
		slider:Set(min + (max - min) * pct)
	end)

	slider:Set(o.Default or min, true)
	return slider
end

function Panel:AddDropdown(o)
	o = o or {}
	local dd = { Value = o.Default or (o.Options and o.Options[1]), Options = {} }

	if o.Name then
		self:AddLabel(o.Name)
	end

	local box = self:_row("TextButton", { BackgroundColor3 = Theme.Element })
	local valueLabel = textLabel({
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Parent = box,
	})
	local arrow = textLabel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(0, 12, 1, 0),
		Text = "▼",
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = box,
	})
	local list = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = self:_next(),
		Parent = self.Frame,
	}, { create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })

	local buttons = {}

	local function render()
		valueLabel.Text = tostring(dd.Value or "")
		for opt, btn in pairs(buttons) do
			btn.TextColor3 = opt == dd.Value and Theme.Accent or Theme.SubText
		end
	end

	local function setOpen(open)
		list.Visible = open
		arrow.Text = open and "▲" or "▼"
	end

	function dd:Set(value, silent)
		self.Value = value
		if o.Flag then
			Library.Flags[o.Flag] = value
		end
		render()
		if not silent and o.Callback then
			task.spawn(o.Callback, value)
		end
	end

	function dd:Refresh(options)
		for _, btn in pairs(buttons) do
			btn:Destroy()
		end
		buttons = {}
		self.Options = options
		for i, opt in ipairs(options) do
			local btn = create("TextButton", {
				Size = UDim2.new(1, 0, 0, Theme.RowHeight),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Font = Theme.Font,
				TextSize = Theme.TextSize,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "  " .. tostring(opt),
				LayoutOrder = i,
				Parent = list,
			})
			connect(btn.MouseButton1Click, function()
				dd:Set(opt)
				setOpen(false)
			end)
			buttons[opt] = btn
		end
		render()
	end

	connect(box.MouseButton1Click, function()
		setOpen(not list.Visible)
	end)

	table.insert(Library._refresh, render)
	dd:Refresh(o.Options or {})
	dd:Set(dd.Value, true)
	return dd
end

function Panel:AddColorPicker(o)
	o = o or {}
	local row = self:_row("Frame")
	textLabel({
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Text = o.Name or "Color",
		Parent = row,
	})
	return buildColorPicker(self, row, o)
end

function Panel:AddButton(o)
	o = o or {}
	local row = self:_row("TextButton", {
		BackgroundColor3 = Theme.Element,
		Font = Theme.Font,
		TextSize = Theme.TextSize,
		TextColor3 = Theme.Text,
		Text = o.Name or "Button",
	})
	connect(row.MouseButton1Click, function()
		row.BackgroundColor3 = Theme.Accent
		tween(row, { BackgroundColor3 = Theme.Element }, 0.3)
		if o.Callback then
			task.spawn(o.Callback)
		end
	end)
	return row
end

function Panel:AddKeybind(o)
	o = o or {}
	local kb = { Value = o.Default }
	local listening = false

	local row = self:_row("TextButton")
	textLabel({
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		Text = o.Name or "Keybind",
		Parent = row,
	})
	local keyLabel = textLabel({
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	function kb:Set(key)
		self.Value = key
		keyLabel.Text = "[" .. (key and key.Name or "None") .. "]"
		if o.Flag then
			Library.Flags[o.Flag] = key
		end
		if o.Changed then
			task.spawn(o.Changed, key)
		end
	end

	connect(row.MouseButton1Click, function()
		listening = true
		keyLabel.Text = "[...]"
	end)

	connect(UserInputService.InputBegan, function(input, processed)
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				listening = false
				kb:Set(input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode or nil)
			end
		elseif not processed and kb.Value and input.KeyCode == kb.Value and o.Callback then
			task.spawn(o.Callback)
		end
	end)

	kb:Set(kb.Value)
	return kb
end

--------------------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------------------
function Tab:AddPanel(name, opts)
	opts = opts or {}
	local width = opts.Width or 190

	Library._z += 1
	local frame = create("Frame", {
		Name = name,
		Position = opts.Position or UDim2.fromOffset(self.NextX, 40),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = Library._z,
		Parent = self.Page,
	}, {
		create("UIStroke", { Color = Theme.Stroke }),
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	self.NextX += width + 6

	local header = accent(create("TextButton", {
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font,
		TextSize = Theme.TextSize,
		TextColor3 = Theme.Text,
		Text = name,
		LayoutOrder = 0,
		Parent = frame,
	}), "BackgroundColor3")

	local content = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = frame,
	}, { create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })

	makeDraggable(header, frame)
	connect(header.MouseButton2Click, function()
		content.Visible = not content.Visible
	end)

	local panel = setmetatable({ Window = self.Window, Frame = content, Container = frame, Order = 0 }, Panel)
	table.insert(self.Panels, panel)
	return panel
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
function Library:CreateWindow(config)
	config = config or {}
	if config.Accent then
		Theme.Accent = config.Accent
	end
	if config.ToggleKey then
		Library.ToggleKey = config.ToggleKey
	end

	local window = setmetatable({
		Title = config.Title or "Robin",
		GameName = config.GameName or "",
		Tabs = {},
		Modules = {},
		Open = true,
	}, Window)

	-- Re-executing the script unloads the previous instance instead of stacking UIs
	if env.RobinUIWindow and env.RobinUIWindow.Destroy then
		pcall(env.RobinUIWindow.Destroy, env.RobinUIWindow)
	end

	local gui = create("ScreenGui", {
		Name = config.GuiName or "RobinUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
	})
	protect(gui)
	if not pcall(function()
		gui.Parent = config.Parent or getParent()
	end) then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end
	window.Gui = gui
	env.RobinUIWindow = window

	-- Top tab bar
	window.TabBar = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(0, Theme.RowHeight + 6),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
		}),
	})

	window.Pages = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })

	-- Watermark
	local watermark = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(0, Theme.RowHeight + 2),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		create("UIStroke", { Color = Theme.Stroke }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	accent(create("Frame", { Size = UDim2.new(1, 12, 0, 1), Position = UDim2.fromOffset(-6, 0), BorderSizePixel = 0, Parent = watermark }), "BackgroundColor3")
	window.Watermark = textLabel({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		RichText = true,
		Parent = watermark,
	})

	-- Arraylist (enabled modules)
	local array = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = config.ArrayListPosition or UDim2.new(1, -10, 0.2, 0),
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }),
	})
	local title = textLabel({
		Size = UDim2.new(1, 0, 0, 36),
		Font = Theme.TitleFont,
		TextSize = 34,
		Text = window.Title,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 0,
		Parent = array,
	})
	accent(create("UIStroke", { Thickness = 1.5, Parent = title }), "Color")
	window.ArrayList = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = array,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }),
	})

	-- Character image (bottom right)
	if config.Image then
		create("ImageLabel", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -10),
			Size = config.ImageSize or UDim2.fromOffset(220, 260),
			BackgroundTransparency = 1,
			Image = Library:GetAsset(config.Image),
			ScaleType = Enum.ScaleType.Fit,
			Parent = gui,
		})
	end

	-- Watermark updater
	if window.GameName == "" then
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
			window.GameName = ok and info and info.Name or "Unknown"
		end)
	end
	local frames, last = 0, os.clock()
	connect(RunService.RenderStepped, function()
		frames += 1
		local now = os.clock()
		if now - last >= 0.5 then
			window:_updateWatermark(math.floor(frames / (now - last) + 0.5))
			frames, last = 0, now
		end
	end)

	connect(UserInputService.InputBegan, function(input, processed)
		if not processed and input.KeyCode == Library.ToggleKey then
			window:Toggle()
		end
	end)

	return window
end

function Window:_updateWatermark(fps)
	local t = os.date("*t")
	local hour = t.hour % 12
	local clock = string.format("%d:%02d (%s)", hour == 0 and 12 or hour, t.min, t.hour < 12 and "AM" or "PM")
	local ok, ping = pcall(function()
		return LocalPlayer:GetNetworkPing()
	end)
	local hex = Theme.Accent:ToHex()
	self.Watermark.Text = string.format(
		'%s | %s | <font color="#%s">%dms</font> | <font color="#%s">%dfps</font> | %s | %s',
		escapeRich(self.Title),
		clock,
		hex,
		ok and math.floor(ping * 1000) or 0,
		hex,
		fps,
		escapeRich(LocalPlayer.Name),
		escapeRich(self.GameName)
	)
end

function Window:_setModule(name, enabled)
	local entries = self.Modules
	if enabled and not entries[name] then
		local width = textWidth(name, 15) + 14
		local entry = create("Frame", {
			Size = UDim2.fromOffset(width, 17),
			BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = self.ArrayList,
		})
		accent(textLabel({
			Size = UDim2.new(1, -6, 1, 0),
			TextSize = 15,
			Text = name,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = entry,
		}), "TextColor3")
		accent(create("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BorderSizePixel = 0,
			Parent = entry,
		}), "BackgroundColor3")
		entries[name] = { Frame = entry, Width = width }
	elseif not enabled and entries[name] then
		entries[name].Frame:Destroy()
		entries[name] = nil
	end

	local sorted = {}
	for _, e in pairs(entries) do
		table.insert(sorted, e)
	end
	table.sort(sorted, function(a, b)
		return a.Width > b.Width
	end)
	for i, e in ipairs(sorted) do
		e.Frame.LayoutOrder = i
	end
end

function Window:AddTab(name)
	local btn = create("TextButton", {
		Size = UDim2.fromOffset(textWidth(name, Theme.TextSize) + 20, Theme.RowHeight + 2),
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font,
		TextSize = Theme.TextSize,
		TextColor3 = Theme.SubText,
		Text = name,
		LayoutOrder = #self.Tabs + 1,
		Parent = self.TabBar,
	}, { create("UIStroke", { Color = Theme.Stroke }) })
	local page = create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.Pages,
	})

	local tab = setmetatable({ Window = self, Name = name, Button = btn, Page = page, Panels = {}, NextX = 10 }, Tab)
	table.insert(self.Tabs, tab)
	connect(btn.MouseButton1Click, function()
		self:SelectTab(tab)
	end)
	if not self.ActiveTab then
		self:SelectTab(tab)
	end
	return tab
end

function Window:SelectTab(tab)
	self.ActiveTab = tab
	for _, t in ipairs(self.Tabs) do
		local active = t == tab
		t.Page.Visible = active
		tween(t.Button, {
			BackgroundColor3 = active and Theme.Accent or Theme.Element,
			TextColor3 = active and Theme.Text or Theme.SubText,
		})
	end
end

function Window:Toggle(state)
	if state == nil then
		state = not self.Open
	end
	self.Open = state
	self.TabBar.Visible = state
	self.Pages.Visible = state
end

function Window:SetAccent(color)
	Theme.Accent = color
	for _, entry in ipairs(Library._accent) do
		entry[1][entry[2]] = color
	end
	for _, fn in ipairs(Library._refresh) do
		fn()
	end
	if self.ActiveTab then
		self:SelectTab(self.ActiveTab)
	end
end

function Window:Destroy()
	for _, c in ipairs(Library._connections) do
		c:Disconnect()
	end
	table.clear(Library._connections)
	table.clear(Library._accent)
	table.clear(Library._refresh)
	self.Gui:Destroy()
	if env.RobinUIWindow == self then
		env.RobinUIWindow = nil
	end
end

return Library
