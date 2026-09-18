-- AutomationUI.lua
-- A modern, dark-themed UI framework for Roblox automation scripts.
-- Matches LoaderUI's design language (green accents, soft borders).
--
-- Usage:
--   local AutoUI = loadstring(game:HttpGet(".../AutomationUI.lua"))()
--   local ui = AutoUI.new(playerGui, { Title = "Steal An Egg" })
--   local mainTab = ui:addTab("Main", "🏠")
--   local s = ui:addSection(mainTab, "Automation")
--   ui:addToggle(s, "Auto Steal Egg", false, function(v) print("toggled", v) end)

local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local AutoUI = {}
AutoUI.__index = AutoUI

-- =========================================================
-- Palette
-- =========================================================
local C = {
    bg          = Color3.fromRGB(15, 15, 22),
    bgCard      = Color3.fromRGB(22, 22, 31),
    bgHover     = Color3.fromRGB(28, 28, 40),
    border      = Color3.fromRGB(40, 40, 55),
    primary     = Color3.fromRGB(128, 255, 160),
    primaryDim  = Color3.fromRGB(90, 200, 120),
    text        = Color3.fromRGB(240, 240, 250),
    textMuted   = Color3.fromRGB(138, 138, 165),
    danger      = Color3.fromRGB(255, 100, 100),
    knob        = Color3.fromRGB(255, 255, 255),
    trackOff    = Color3.fromRGB(45, 45, 60),
    trackOn     = Color3.fromRGB(60, 180, 100),
}

local FONT         = Enum.Font.Gotham
local FONT_MEDIUM  = Enum.Font.GothamMedium
local FONT_BOLD    = Enum.Font.GothamBold

-- =========================================================
-- Helpers
-- =========================================================
local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or C.border
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0.3
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function padding(parent, t, b, l, r)
    local p = Instance.new("UIPadding")
    p.PaddingTop    = UDim.new(0, t or 0)
    p.PaddingBottom = UDim.new(0, b or 0)
    p.PaddingLeft   = UDim.new(0, l or 0)
    p.PaddingRight  = UDim.new(0, r or 0)
    p.Parent = parent
    return p
end

local function listLayout(parent, dir, spacing, align)
    local l = Instance.new("UIListLayout")
    l.FillDirection = dir or Enum.FillDirection.Vertical
    l.HorizontalAlignment = align or Enum.HorizontalAlignment.Left
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, spacing or 8)
    l.Parent = parent
    return l
end

local function tween(inst, time, props)
    local t = TweenService:Create(inst, TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

-- =========================================================
-- Constructor
-- =========================================================
function AutoUI.new(playerGui, config)
    local self = setmetatable({}, AutoUI)
    self.config = config or {}
    self.title = self.config.Title or "Automation"
    self.subtitle = self.config.Subtitle or ""
    self.playerGui = playerGui
    self.tabs = {}
    self.activeTab = nil
    self.toggles = {}
    self.sliders = {}
    self.dropdowns = {}

    self:_buildWindow()
    return self
end

-- =========================================================
-- Window construction
-- =========================================================
function AutoUI:_buildWindow()
    -- ScreenGui
    local screen = Instance.new("ScreenGui")
    screen.Name = "AutoUI"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 99999
    screen.Parent = self.playerGui
    self.screen = screen

    -- Main window
    local win = Instance.new("Frame")
    win.Name = "Window"
    win.Size = UDim2.fromOffset(560, 400)
    win.Position = UDim2.new(0.5, -280, 0.5, -200)
    win.BackgroundColor3 = C.bg
    win.BorderSizePixel = 0
    win.Active = true
    win.Parent = screen
    corner(win, 12)
    stroke(win, C.border, 1, 0.4)
    self.window = win

    -- Drop shadow (fake with a slightly offset darker frame behind)
    local shadow = Instance.new("Frame")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 4, 1, 4)
    shadow.Position = UDim2.fromOffset(-2, 2)
    shadow.BackgroundColor3 = Color3.new(0, 0, 0)
    shadow.BackgroundTransparency = 0.6
    shadow.BorderSizePixel = 0
    shadow.ZIndex = 0
    shadow.Parent = screen
    corner(shadow, 12)
    self.shadow = shadow

    -- Header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 44)
    header.BackgroundTransparency = 1
    header.Parent = win
    self.header = header

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(16, 0)
    title.Size = UDim2.new(1, -100, 1, 0)
    title.Font = FONT_BOLD
    title.Text = self.title
    title.TextSize = 15
    title.TextColor3 = C.text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    -- Title accent dot
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(7, 7)
    dot.Position = UDim2.fromOffset(0, 18)
    dot.BackgroundColor3 = C.primary
    dot.BorderSizePixel = 0
    dot.Parent = title
    corner(dot, 999)

    -- Status pill in header
    local statusPill = Instance.new("Frame")
    statusPill.Name = "StatusPill"
    statusPill.AnchorPoint = Vector2.new(1, 0.5)
    statusPill.Position = UDim2.new(1, -80, 0.5, 0)
    statusPill.Size = UDim2.fromOffset(70, 22)
    statusPill.BackgroundColor3 = C.bgCard
    statusPill.BorderSizePixel = 0
    statusPill.Parent = header
    corner(statusPill, 11)
    stroke(statusPill, C.border, 1, 0.5)

    local statusDot = Instance.new("Frame")
    statusDot.Size = UDim2.fromOffset(6, 6)
    statusDot.Position = UDim2.new(0, 8, 0.5, -3)
    statusDot.BackgroundColor3 = C.textMuted
    statusDot.BorderSizePixel = 0
    statusDot.Parent = statusPill
    corner(statusDot, 999)
    self.statusDot = statusDot

    local statusText = Instance.new("TextLabel")
    statusText.BackgroundTransparency = 1
    statusText.Position = UDim2.new(0, 20, 0, 0)
    statusText.Size = UDim2.new(1, -22, 1, 0)
    statusText.Font = FONT_MEDIUM
    statusText.Text = "Idle"
    statusText.TextSize = 11
    statusText.TextColor3 = C.textMuted
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.Parent = statusPill
    self.statusText = statusText

    -- Close button
    local close = Instance.new("TextButton")
    close.Name = "Close"
    close.AnchorPoint = Vector2.new(1, 0.5)
    close.Position = UDim2.new(1, -10, 0.5, 0)
    close.Size = UDim2.fromOffset(28, 28)
    close.BackgroundColor3 = C.bgCard
    close.BorderSizePixel = 0
    close.Text = "×"
    close.Font = FONT_BOLD
    close.TextSize = 18
    close.TextColor3 = C.textMuted
    close.AutoButtonColor = false
    close.Parent = header
    corner(close, 8)

    close.MouseEnter:Connect(function()
        tween(close, 0.15, { BackgroundColor3 = C.danger, TextColor3 = C.text })
    end)
    close.MouseLeave:Connect(function()
        tween(close, 0.15, { BackgroundColor3 = C.bgCard, TextColor3 = C.textMuted })
    end)
    close.MouseButton1Click:Connect(function()
        self:destroy()
    end)

    -- Minimize button
    local min = Instance.new("TextButton")
    min.Name = "Min"
    min.AnchorPoint = Vector2.new(1, 0.5)
    min.Position = UDim2.new(1, -44, 0.5, 0)
    min.Size = UDim2.fromOffset(28, 28)
    min.BackgroundColor3 = C.bgCard
    min.BorderSizePixel = 0
    min.Text = "–"
    min.Font = FONT_BOLD
    min.TextSize = 14
    min.TextColor3 = C.textMuted
    min.AutoButtonColor = false
    min.Parent = header
    corner(min, 8)
    self.minButton = min

    min.MouseEnter:Connect(function()
        tween(min, 0.15, { BackgroundColor3 = C.bgHover, TextColor3 = C.text })
    end)
    min.MouseLeave:Connect(function()
        tween(min, 0.15, { BackgroundColor3 = C.bgCard, TextColor3 = C.textMuted })
    end)

    self.minimized = false
    min.MouseButton1Click:Connect(function()
        self:_toggleMinimize()
    end)

    -- Header divider line
    local divider = Instance.new("Frame")
    divider.Name = "HeaderDivider"
    divider.Position = UDim2.fromOffset(0, 44)
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.BackgroundColor3 = C.border
    divider.BorderSizePixel = 0
    divider.BackgroundTransparency = 0.5
    divider.Parent = win
    self.headerDivider = divider

    -- Body container (below header)
    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Position = UDim2.fromOffset(0, 45)
    body.Size = UDim2.new(1, 0, 1, -45)
    body.BackgroundTransparency = 1
    body.ClipsDescendants = true
    body.Parent = win
    self.body = body

    -- Sidebar
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.fromOffset(150, 1)
    sidebar.BackgroundColor3 = C.bgCard
    sidebar.BackgroundTransparency = 0.4
    sidebar.BorderSizePixel = 0
    sidebar.Parent = body
    self.sidebar = sidebar

    local sideLayout = listLayout(sidebar, Enum.FillDirection.Vertical, 4)
    padding(sidebar, 10, 10, 8, 8)

    -- Sidebar divider
    local sideDivider = Instance.new("Frame")
    sideDivider.Position = UDim2.fromOffset(150, 0)
    sideDivider.Size = UDim2.new(0, 1, 1, 0)
    sideDivider.BackgroundColor3 = C.border
    sideDivider.BorderSizePixel = 0
    sideDivider.BackgroundTransparency = 0.5
    sideDivider.Parent = body

    -- Content area
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Position = UDim2.fromOffset(151, 0)
    content.Size = UDim2.new(1, -151, 1, 0)
    content.BackgroundTransparency = 1
    content.Parent = body
    self.contentArea = content

    -- Status bar (bottom of window)
    local statusBar = Instance.new("Frame")
    statusBar.Name = "StatusBar"
    statusBar.AnchorPoint = Vector2.new(0, 1)
    statusBar.Position = UDim2.new(0, 0, 1, 0)
    statusBar.Size = UDim2.new(1, 0, 0, 24)
    statusBar.BackgroundColor3 = C.bgCard
    statusBar.BackgroundTransparency = 0.4
    statusBar.BorderSizePixel = 0
    statusBar.Parent = win
    self.statusBar = statusBar

    local sbDivider = Instance.new("Frame")
    sbDivider.Position = UDim2.new(0, 0, 0, 0)
    sbDivider.Size = UDim2.new(1, 0, 0, 1)
    sbDivider.BackgroundColor3 = C.border
    sbDivider.BorderSizePixel = 0
    sbDivider.BackgroundTransparency = 0.5
    sbDivider.Parent = statusBar

    local sbText = Instance.new("TextLabel")
    sbText.Name = "StatusBarText"
    sbText.BackgroundTransparency = 1
    sbText.Position = UDim2.fromOffset(14, 0)
    sbText.Size = UDim2.new(1, -28, 1, 0)
    sbText.Font = FONT_MEDIUM
    sbText.Text = "Ready"
    sbText.TextSize = 11
    sbText.TextColor3 = C.textMuted
    sbText.TextXAlignment = Enum.TextXAlignment.Left
    sbText.Parent = statusBar
    self.statusBarText = sbText

    -- Shrink body by status bar height
    body.Size = UDim2.new(1, 0, 1, -45 - 24)
    sidebar.Size = UDim2.new(0, 150, 1, 0)
    content.Size = UDim2.new(1, -151, 1, 0)

    -- Enable dragging on the header
    self:_makeDraggable(header, win)
end

-- =========================================================
-- Draggable
-- =========================================================
function AutoUI:_makeDraggable(handle, target)
    local dragging = false
    local dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
        end
    end)

    handle.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                        or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
            if self.shadow then
                self.shadow.Position = UDim2.new(
                    target.Position.X.Scale, target.Position.X.Offset - 2,
                    target.Position.Y.Scale, target.Position.Y.Offset + 2
                )
            end
        end
    end)

    handle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- =========================================================
-- Minimize
-- =========================================================
function AutoUI:_toggleMinimize()
    self.minimized = not self.minimized
    local targetHeight = self.minimized and 45 or 400
    tween(self.window, 0.25, { Size = UDim2.fromOffset(560, targetHeight) })
    self.body.Visible = not self.minimized
    self.statusBar.Visible = not self.minimized
    self.headerDivider.Visible = not self.minimized
    self.minButton.Text = self.minimized and "+" or "–"
end

-- =========================================================
-- Tabs
-- =========================================================
function AutoUI:addTab(name, icon)
    local tab = {}

    -- Tab button
    local btn = Instance.new("TextButton")
    btn.Name = "Tab_" .. name
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = C.bg
    btn.BackgroundTransparency = 1
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = self.sidebar
    corner(btn, 8)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.fromOffset(12, 0)
    lbl.Size = UDim2.new(1, -20, 1, 0)
    lbl.Font = FONT_MEDIUM
    lbl.Text = (icon and (icon .. "   ") or "") .. name
    lbl.TextSize = 12
    lbl.TextColor3 = C.textMuted
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = btn
    tab.label = lbl

    -- Accent bar (left of active tab)
    local accent = Instance.new("Frame")
    accent.Name = "Accent"
    accent.AnchorPoint = Vector2.new(0, 0.5)
    accent.Position = UDim2.new(0, -4, 0.5, 0)
    accent.Size = UDim2.fromOffset(2, 18)
    accent.BackgroundColor3 = C.primary
    accent.BorderSizePixel = 0
    accent.BackgroundTransparency = 1
    accent.Parent = btn
    corner(accent, 1)
    tab.accent = accent

    -- Content frame (hidden by default)
    local content = Instance.new("ScrollingFrame")
    content.Name = "Content_" .. name
    content.Size = UDim2.new(1, 0, 1, 0)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 4
    content.ScrollBarImageColor3 = C.primaryDim
    content.ScrollBarImageTransparency = 0.6
    content.CanvasSize = UDim2.new(0, 0, 0, 0)
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.Visible = false
    content.Parent = self.contentArea
    padding(content, 16, 16, 16, 16)
    listLayout(content, Enum.FillDirection.Vertical, 10)
    tab.content = content
    tab.button = btn

    -- Click handling
    btn.MouseEnter:Connect(function()
        if self.activeTab ~= tab then
            tween(btn, 0.15, { BackgroundTransparency = 0.5, BackgroundColor3 = C.bgHover })
        end
    end)
    btn.MouseLeave:Connect(function()
        if self.activeTab ~= tab then
            tween(btn, 0.15, { BackgroundTransparency = 1 })
        end
    end)
    btn.MouseButton1Click:Connect(function()
        self:selectTab(tab)
    end)

    table.insert(self.tabs, tab)

    -- Auto-select the first tab
    if not self.activeTab then
        self:selectTab(tab)
    end

    return content
end

function AutoUI:selectTab(tab)
    if self.activeTab == tab then return end
    for _, t in ipairs(self.tabs) do
        if t == tab then
            t.content.Visible = true
            t.label.TextColor3 = C.text
            tween(t.button, 0.15, { BackgroundTransparency = 0.3, BackgroundColor3 = C.bgHover })
            tween(t.accent, 0.15, { BackgroundTransparency = 0 })
        else
            t.content.Visible = false
            t.label.TextColor3 = C.textMuted
            tween(t.button, 0.15, { BackgroundTransparency = 1 })
            tween(t.accent, 0.15, { BackgroundTransparency = 1 })
        end
    end
    self.activeTab = tab
end

-- =========================================================
-- Sections
-- =========================================================
function AutoUI:addSection(parent, title)
    local section = Instance.new("Frame")
    section.Size = UDim2.new(1, 0, 0, 0)
    section.AutomaticSize = Enum.AutomaticSize.Y
    section.BackgroundColor3 = C.bgCard
    section.BackgroundTransparency = 0.3
    section.BorderSizePixel = 0
    section.Parent = parent
    corner(section, 10)
    stroke(section, C.border, 1, 0.6)
    padding(section, 12, 12, 12, 12)
    listLayout(section, Enum.FillDirection.Vertical, 6)

    if title and title ~= "" then
        local t = Instance.new("TextLabel")
        t.BackgroundTransparency = 1
        t.Size = UDim2.new(1, 0, 0, 16)
        t.Font = FONT_BOLD
        t.Text = string.upper(title)
        t.TextSize = 10
        t.TextColor3 = C.primary
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.LayoutOrder = -1
        t.Parent = section
    end

    return section
end

-- =========================================================
-- Toggle
-- =========================================================
function AutoUI:addToggle(parent, name, default, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -60, 1, 0)
    lbl.Font = FONT_MEDIUM
    lbl.Text = name
    lbl.TextSize = 12
    lbl.TextColor3 = C.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local track = Instance.new("TextButton")
    track.AnchorPoint = Vector2.new(1, 0.5)
    track.Position = UDim2.new(1, 0, 0.5, 0)
    track.Size = UDim2.fromOffset(40, 22)
    track.BackgroundColor3 = C.trackOff
    track.BorderSizePixel = 0
    track.Text = ""
    track.AutoButtonColor = false
    track.Parent = row
    corner(track, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(16, 16)
    knob.Position = UDim2.fromOffset(3, 3)
    knob.BackgroundColor3 = C.knob
    knob.BorderSizePixel = 0
    knob.Parent = track
    corner(knob, 999)

    local state = { on = default or false }
    local function apply(animate)
        local t = animate and 0.18 or 0
        if state.on then
            tween(track, t, { BackgroundColor3 = C.trackOn })
            tween(knob,  t, { Position = UDim2.fromOffset(21, 3) })
        else
            tween(track, t, { BackgroundColor3 = C.trackOff })
            tween(knob,  t, { Position = UDim2.fromOffset(3, 3) })
        end
    end
    apply(false)

    track.MouseButton1Click:Connect(function()
        state.on = not state.on
        apply(true)
        if callback then
            task.spawn(function()
                local ok, err = pcall(callback, state.on)
                if not ok then warn("[AutoUI] Toggle callback error:", err) end
            end)
        end
    end)

    local obj = {
        set = function(v)
            state.on = v and true or false
            apply(true)
        end,
        get = function() return state.on end,
        destroy = function() row:Destroy() end,
    }
    self.toggles[name] = obj
    return obj
end

-- =========================================================
-- Button
-- =========================================================
function AutoUI:addButton(parent, name, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = C.bgHover
    btn.BorderSizePixel = 0
    btn.Text = name
    btn.Font = FONT_MEDIUM
    btn.TextSize = 12
    btn.TextColor3 = C.text
    btn.AutoButtonColor = false
    btn.Parent = parent
    corner(btn, 8)
    stroke(btn, C.border, 1, 0.5)

    btn.MouseEnter:Connect(function()
        tween(btn, 0.15, { BackgroundColor3 = C.primary, TextColor3 = C.bg })
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, 0.15, { BackgroundColor3 = C.bgHover, TextColor3 = C.text })
    end)
    btn.MouseButton1Click:Connect(function()
        if callback then
            task.spawn(function()
                local ok, err = pcall(callback)
                if not ok then warn("[AutoUI] Button callback error:", err) end
            end)
        end
    end)

    return btn
end

-- =========================================================
-- Slider
-- =========================================================
function AutoUI:addSlider(parent, name, min, max, default, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 44)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -60, 0, 18)
    lbl.Font = FONT_MEDIUM
    lbl.Text = name
    lbl.TextSize = 12
    lbl.TextColor3 = C.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local valueLbl = Instance.new("TextLabel")
    valueLbl.BackgroundTransparency = 1
    valueLbl.AnchorPoint = Vector2.new(1, 0)
    valueLbl.Position = UDim2.new(1, 0, 0, 0)
    valueLbl.Size = UDim2.fromOffset(60, 18)
    valueLbl.Font = FONT_MEDIUM
    valueLbl.Text = tostring(default)
    valueLbl.TextSize = 12
    valueLbl.TextColor3 = C.primary
    valueLbl.TextXAlignment = Enum.TextXAlignment.Right
    valueLbl.Parent = row

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0, 1)
    track.Position = UDim2.new(0, 0, 1, -8)
    track.Size = UDim2.new(1, 0, 0, 6)
    track.BackgroundColor3 = C.trackOff
    track.BorderSizePixel = 0
    track.Parent = row
    corner(track, 3)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = C.primary
    fill.BorderSizePixel = 0
    fill.Parent = track
    corner(fill, 3)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.fromOffset(14, 14)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = C.knob
    knob.BorderSizePixel = 0
    knob.Parent = track
    corner(knob, 999)
    stroke(knob, C.primary, 2, 0)

    local value = default or min
    local dragging = false

    local function setValue(v, fire)
        v = math.clamp(v, min, max)
        value = v
        local pct = (v - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, 0, 0.5, 0)
        valueLbl.Text = tostring(math.floor(v * 100) / 100)
        if fire and callback then
            task.spawn(function()
                local ok, err = pcall(callback, value)
                if not ok then warn("[AutoUI] Slider callback error:", err) end
            end)
        end
    end

    local inputBegan, inputChanged, inputEnded

    inputBegan = track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local mx = input.Position.X
            local ax = track.AbsolutePosition.X
            local aw = track.AbsoluteSize.X
            setValue(min + (mx - ax) / aw * (max - min), true)
        end
    end)

    inputChanged = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                        or input.UserInputType == Enum.UserInputType.Touch) then
            local mx = input.Position.X
            local ax = track.AbsolutePosition.X
            local aw = track.AbsoluteSize.X
            setValue(min + (mx - ax) / aw * (max - min), true)
        end
    end)

    inputEnded = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    setValue(default or min, false)

    local obj = {
        set = function(v) setValue(v, true) end,
        get = function() return value end,
    }
    self.sliders[name] = obj
    return obj
end

-- =========================================================
-- Dropdown
-- =========================================================
function AutoUI:addDropdown(parent, name, options, default, callback)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 32)
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false
    container.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(0, 100, 1, 0)
    lbl.Font = FONT_MEDIUM
    lbl.Text = name
    lbl.TextSize = 12
    lbl.TextColor3 = C.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = container

    local btn = Instance.new("TextButton")
    btn.AnchorPoint = Vector2.new(1, 0.5)
    btn.Position = UDim2.new(1, 0, 0.5, 0)
    btn.Size = UDim2.new(0, 220, 0, 28)
    btn.BackgroundColor3 = C.bg
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = container
    corner(btn, 6)
    stroke(btn, C.border, 1, 0.5)

    local btnText = Instance.new("TextLabel")
    btnText.BackgroundTransparency = 1
    btnText.Position = UDim2.fromOffset(10, 0)
    btnText.Size = UDim2.new(1, -30, 1, 0)
    btnText.Font = FONT_MEDIUM
    btnText.Text = default or (options[1] or "—")
    btnText.TextSize = 12
    btnText.TextColor3 = C.text
    btnText.TextXAlignment = Enum.TextXAlignment.Left
    btnText.Parent = btn

    local arrow = Instance.new("TextLabel")
    arrow.BackgroundTransparency = 1
    arrow.AnchorPoint = Vector2.new(1, 0.5)
    arrow.Position = UDim2.new(1, -10, 0.5, 0)
    arrow.Size = UDim2.fromOffset(14, 14)
    arrow.Font = FONT_BOLD
    arrow.Text = "▾"
    arrow.TextSize = 12
    arrow.TextColor3 = C.textMuted
    arrow.Parent = btn

    -- Dropdown menu (renders above, absolute)
    local menu = Instance.new("ScrollingFrame")
    menu.Size = UDim2.new(1, 0, 0, 0)
    menu.Position = UDim2.new(0, 0, 1, 4)
    menu.BackgroundColor3 = C.bgCard
    menu.BorderSizePixel = 0
    menu.ScrollBarThickness = 4
    menu.ScrollBarImageColor3 = C.primaryDim
    menu.Visible = false
    menu.ZIndex = 50
    menu.Parent = btn
    corner(menu, 6)
    stroke(menu, C.border, 1, 0.3)
    listLayout(menu, Enum.FillDirection.Vertical, 2)
    padding(menu, 6, 6, 6, 6)

    local menuOpen = false
    local selected = default or (options[1] or nil)

    local function closeMenu()
        menuOpen = false
        menu.Visible = false
        tween(arrow, 0.15, { Rotation = 0 })
    end

    local function openMenu()
        menuOpen = true
        menu.Size = UDim2.new(1, 0, 0, math.min(#options * 26 + 12, 160))
        menu.Visible = true
        tween(arrow, 0.15, { Rotation = 180 })
    end

    -- Populate
    for _, opt in ipairs(options) do
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1, 0, 0, 24)
        item.BackgroundColor3 = C.bgCard
        item.BorderSizePixel = 0
        item.Text = "  " .. opt
        item.Font = FONT_MEDIUM
        item.TextSize = 12
        item.TextColor3 = (opt == selected) and C.primary or C.text
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.AutoButtonColor = false
        item.Parent = menu
        corner(item, 4)

        item.MouseEnter:Connect(function()
            tween(item, 0.1, { BackgroundColor3 = C.bgHover })
        end)
        item.MouseLeave:Connect(function()
            tween(item, 0.1, { BackgroundColor3 = C.bgCard })
        end)
        item.MouseButton1Click:Connect(function()
            selected = opt
            btnText.Text = opt
            for _, child in ipairs(menu:GetChildren()) do
                if child:IsA("TextButton") then
                    child.TextColor3 = (child.Text == "  " .. opt) and C.primary or C.text
                end
            end
            closeMenu()
            if callback then
                task.spawn(function()
                    local ok, err = pcall(callback, opt)
                    if not ok then warn("[AutoUI] Dropdown callback error:", err) end
                end)
            end
        end)
    end

    btn.MouseButton1Click:Connect(function()
        if menuOpen then closeMenu() else openMenu() end
    end)

    -- Click-outside close
    UserInputService.InputBegan:Connect(function(input)
        if menuOpen and input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mouse = UserInputService:GetMouseLocation()
            local pos = btn.AbsolutePosition
            local sz = btn.AbsoluteSize
            if not (mouse.X >= pos.X and mouse.X <= pos.X + sz.X
                    and mouse.Y >= pos.Y and mouse.Y <= pos.Y + sz.Y) then
                closeMenu()
            end
        end
    end)

    local obj = {
        set = function(v) selected = v; btnText.Text = v end,
        get = function() return selected end,
    }
    self.dropdowns[name] = obj
    return obj
end

-- =========================================================
-- Label & Divider
-- =========================================================
function AutoUI:addLabel(parent, text, color)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.Font = FONT
    lbl.Text = text
    lbl.TextSize = 11
    lbl.TextColor3 = color or C.textMuted
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped = true
    lbl.Parent = parent
    return lbl
end

function AutoUI:addDivider(parent)
    local d = Instance.new("Frame")
    d.Size = UDim2.new(1, 0, 0, 1)
    d.BackgroundColor3 = C.border
    d.BorderSizePixel = 0
    d.BackgroundTransparency = 0.5
    d.Parent = parent
    return d
end

-- =========================================================
-- Status
-- =========================================================
function AutoUI:setStatus(text, state)
    self.statusText.Text = text or "Idle"
    local color = C.textMuted
    if state == "running" then color = C.primary
    elseif state == "error" then color = C.danger end
    self.statusDot.BackgroundColor3 = color
    self.statusText.TextColor3 = color
end

function AutoUI:setBottomStatus(text)
    self.statusBarText.Text = text or ""
end

-- =========================================================
-- Destroy
-- =========================================================
function AutoUI:destroy()
    if self.screen then
        self.screen:Destroy()
        self.screen = nil
    end
    if self.shadow then
        self.shadow:Destroy()
        self.shadow = nil
    end
end

return AutoUI
