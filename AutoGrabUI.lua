--[[
    AutoGrabUI — Reusable UI module for the Auto-Grab script.
    Keep this file as a separate script; the main script requires it.
]]

local AutoGrabUI = {}

-- Public constructor
-- config = {
--     parent        = Instance (ScreenGui parent — usually PlayerGui)
--     eggGroups     = { { name = "Common", eggs = { {category=, display=, icon=} } }, ... }
--     onStart       = function() end
--     onStop        = function() end
--     onSetSafeZone = function() end
--     onTargetChange= function(categoryOrNil) end
-- }

function AutoGrabUI.new(config)
    config = config or {}
    local self = {}
    self._cleaned = false
    self._connections = {}
    self._minimized = false
    self._selected = nil  -- nil = Any

    local COLORS = {
        bg       = Color3.fromRGB(15, 15, 22),
        bgAlt    = Color3.fromRGB(22, 22, 32),
        accent   = Color3.fromRGB(120, 255, 160),
        warn     = Color3.fromRGB(255, 180, 100),
        err      = Color3.fromRGB(255, 120, 120),
        text     = Color3.fromRGB(220, 220, 235),
        textDim  = Color3.fromRGB(140, 140, 160),
        border   = Color3.fromRGB(60, 80, 70),
    }
    self._colors = COLORS

    local function track(c)
        if c then table.insert(self._connections, c) end
        return c
    end

    ----------------------------------------------------------------
    -- Root
    ----------------------------------------------------------------
    local gui = Instance.new("ScreenGui")
    gui.Name = "AutoGrabUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 99999
    gui.Parent = config.parent
    self._gui = gui

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(1, 0)
    panel.Position = UDim2.new(1, -20, 0, 20)
    panel.Size = UDim2.fromOffset(300, 470)
    panel.BackgroundColor3 = COLORS.bg
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.Draggable = true
    panel.Parent = gui
    self._panel = panel

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 14)
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = COLORS.accent
    panelStroke.Thickness = 1
    panelStroke.Transparency = 0.6
    panelStroke.Parent = panel

    ----------------------------------------------------------------
    -- Header
    ----------------------------------------------------------------
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = COLORS.bgAlt
    header.BorderSizePixel = 0
    header.Parent = panel

    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 14)
    hCorner.Parent = header

    local hTitle = Instance.new("TextLabel")
    hTitle.BackgroundTransparency = 1
    hTitle.Position = UDim2.fromOffset(14, 0)
    hTitle.Size = UDim2.new(1, -60, 1, 0)
    hTitle.Font = Enum.Font.GothamBold
    hTitle.TextSize = 14
    hTitle.TextColor3 = COLORS.accent
    hTitle.TextXAlignment = Enum.TextXAlignment.Left
    hTitle.Text = "🥚  AUTO GRAB"
    hTitle.Parent = header

    local minBtn = Instance.new("TextButton")
    minBtn.AnchorPoint = Vector2.new(1, 0.5)
    minBtn.Position = UDim2.new(1, -10, 0.5, 0)
    minBtn.Size = UDim2.fromOffset(22, 22)
    minBtn.BackgroundColor3 = COLORS.bg
    minBtn.BackgroundTransparency = 0.3
    minBtn.BorderSizePixel = 0
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 14
    minBtn.TextColor3 = COLORS.accent
    minBtn.Text = "−"
    minBtn.Parent = header

    local mCorner = Instance.new("UICorner")
    mCorner.CornerRadius = UDim.new(0, 6)
    mCorner.Parent = minBtn

    local content = Instance.new("Frame")
    content.Position = UDim2.fromOffset(0, 36)
    content.Size = UDim2.new(1, 0, 1, -36)
    content.BackgroundTransparency = 1
    content.Parent = panel
    self._content = content

    track(minBtn.MouseButton1Click:Connect(function()
        self._minimized = not self._minimized
        content.Visible = not self._minimized
        panel.Size = self._minimized
            and UDim2.fromOffset(300, 36)
            or UDim2.fromOffset(300, 470)
        minBtn.Text = self._minimized and "+" or "−"
    end))

    ----------------------------------------------------------------
    -- Target label
    ----------------------------------------------------------------
    local targetLbl = Instance.new("TextLabel")
    targetLbl.BackgroundTransparency = 1
    targetLbl.Position = UDim2.fromOffset(14, 8)
    targetLbl.Size = UDim2.new(1, -28, 0, 16)
    targetLbl.Font = Enum.Font.GothamBold
    targetLbl.TextSize = 11
    targetLbl.TextColor3 = COLORS.textDim
    targetLbl.TextXAlignment = Enum.TextXAlignment.Left
    targetLbl.Text = "TARGET EGG"
    targetLbl.Parent = content

    ----------------------------------------------------------------
    -- Dropdown button
    ----------------------------------------------------------------
    local ddBtn = Instance.new("TextButton")
    ddBtn.Position = UDim2.fromOffset(14, 26)
    ddBtn.Size = UDim2.new(1, -28, 0, 32)
    ddBtn.BackgroundColor3 = COLORS.bgAlt
    ddBtn.BorderSizePixel = 0
    ddBtn.Font = Enum.Font.Gotham
    ddBtn.TextSize = 13
    ddBtn.TextColor3 = COLORS.text
    ddBtn.TextXAlignment = Enum.TextXAlignment.Left
    ddBtn.Text = "  Any (default)"
    ddBtn.Parent = content

    local ddCorner = Instance.new("UICorner")
    ddCorner.CornerRadius = UDim.new(0, 8)
    ddCorner.Parent = ddBtn

    local ddStroke = Instance.new("UIStroke")
    ddStroke.Color = COLORS.border
    ddStroke.Thickness = 1
    ddStroke.Parent = ddBtn

    local ddArrow = Instance.new("TextLabel")
    ddArrow.BackgroundTransparency = 1
    ddArrow.AnchorPoint = Vector2.new(1, 0.5)
    ddArrow.Position = UDim2.new(1, -10, 0.5, 0)
    ddArrow.Size = UDim2.fromOffset(16, 16)
    ddArrow.Font = Enum.Font.GothamBold
    ddArrow.TextSize = 12
    ddArrow.TextColor3 = COLORS.accent
    ddArrow.Text = "▼"
    ddArrow.Parent = ddBtn

    ----------------------------------------------------------------
    -- Search
    ----------------------------------------------------------------
    local search = Instance.new("TextBox")
    search.Position = UDim2.fromOffset(14, 62)
    search.Size = UDim2.new(1, -28, 0, 26)
    search.BackgroundColor3 = COLORS.bgAlt
    search.BorderSizePixel = 0
    search.Font = Enum.Font.Gotham
    search.TextSize = 12
    search.TextColor3 = COLORS.text
    search.PlaceholderText = "  Search..."
    search.PlaceholderColor3 = COLORS.textDim
    search.Text = ""
    search.ClearTextOnFocus = false
    search.Visible = false
    search.ZIndex = 6
    search.Parent = content

    local sCorner = Instance.new("UICorner")
    sCorner.CornerRadius = UDim.new(0, 8)
    sCorner.Parent = search

    ----------------------------------------------------------------
    -- Dropdown list
    ----------------------------------------------------------------
    local ddList = Instance.new("ScrollingFrame")
    ddList.Position = UDim2.fromOffset(14, 62)
    ddList.Size = UDim2.new(1, -28, 0, 190)
    ddList.BackgroundColor3 = COLORS.bgAlt
    ddList.BorderSizePixel = 0
    ddList.ScrollBarThickness = 6
    ddList.ScrollBarImageColor3 = COLORS.accent
    ddList.CanvasSize = UDim2.new(0, 0, 0, 0)
    ddList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ddList.Visible = false
    ddList.ZIndex = 5
    ddList.Parent = content

    local dlCorner = Instance.new("UICorner")
    dlCorner.CornerRadius = UDim.new(0, 8)
    dlCorner.Parent = ddList

    local dlStroke = Instance.new("UIStroke")
    dlStroke.Color = COLORS.accent
    dlStroke.Thickness = 1
    dlStroke.Transparency = 0.4
    dlStroke.Parent = ddList

    local dlLayout = Instance.new("UIListLayout")
    dlLayout.Padding = UDim.new(0, 2)
    dlLayout.SortOrder = Enum.SortOrder.LayoutOrder
    dlLayout.Parent = ddList

    local dlPad = Instance.new("UIPadding")
    dlPad.PaddingTop = UDim.new(0, 4)
    dlPad.PaddingBottom = UDim.new(0, 4)
    dlPad.PaddingLeft = UDim.new(0, 4)
    dlPad.PaddingRight = UDim.new(0, 4)
    dlPad.Parent = ddList

    ----------------------------------------------------------------
    -- Dropdown rebuild
    ----------------------------------------------------------------
    local filter = ""

    local function rebuildList()
        for _, c in ipairs(ddList:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
        end

        -- Flat list of items with group headers
        local items = { { kind = "option", label = "Any", value = nil } }
        for _, group in ipairs(config.eggGroups or {}) do
            table.insert(items, { kind = "header", label = group.name })
            for _, egg in ipairs(group.eggs or {}) do
                table.insert(items, {
                    kind   = "option",
                    label  = egg.display or egg.category,
                    value  = egg.category,
                    icon   = egg.icon,
                })
            end
        end

        -- Apply search
        local lf = string.lower(filter)
        local visible = {}
        for _, it in ipairs(items) do
            if it.kind == "option" then
                if lf == "" or string.find(string.lower(it.label), lf, 1, true) then
                    table.insert(visible, it)
                end
            end
            -- headers are skipped in filtered view to keep it clean
        end

        if lf ~= "" then
            -- flat list only when searching
            for i, it in ipairs(visible) do
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(1, 0, 0, 26)
                b.BackgroundColor3 = COLORS.bg
                b.BackgroundTransparency = 1
                b.BorderSizePixel = 0
                b.Font = Enum.Font.Gotham
                b.TextSize = 12
                b.TextColor3 = COLORS.text
                b.TextXAlignment = Enum.TextXAlignment.Left
                b.Text = "  " .. it.label
                b.LayoutOrder = i
                b.Parent = ddList
                track(b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.7 end))
                track(b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end))
                track(b.MouseButton1Click:Connect(function()
                    self._selected = it.value
                    ddBtn.Text = "  " .. it.label
                    ddList.Visible = false
                    search.Visible = false
                    ddArrow.Text = "▼"
                    if config.onTargetChange then
                        config.onTargetChange(it.value)
                    end
                end))
            end
            return
        end

        -- full list with headers
        local order = 0
        for _, it in ipairs(items) do
            order = order + 1
            if it.kind == "header" then
                local h = Instance.new("TextLabel")
                h.Size = UDim2.new(1, 0, 0, 20)
                h.BackgroundTransparency = 1
                h.Font = Enum.Font.GothamBold
                h.TextSize = 10
                h.TextColor3 = COLORS.accent
                h.TextXAlignment = Enum.TextXAlignment.Left
                h.Text = "  ── " .. string.upper(it.label) .. " ──"
                h.LayoutOrder = order
                h.Parent = ddList
            else
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(1, 0, 0, 26)
                b.BackgroundColor3 = COLORS.bg
                b.BackgroundTransparency = 1
                b.BorderSizePixel = 0
                b.Font = Enum.Font.Gotham
                b.TextSize = 12
                b.TextColor3 = COLORS.text
                b.TextXAlignment = Enum.TextXAlignment.Left
                b.Text = "    " .. it.label
                b.LayoutOrder = order
                b.Parent = ddList
                track(b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.7 end))
                track(b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end))
                track(b.MouseButton1Click:Connect(function()
                    self._selected = it.value
                    ddBtn.Text = "  " .. it.label
                    ddList.Visible = false
                    search.Visible = false
                    ddArrow.Text = "▼"
                    if config.onTargetChange then
                        config.onTargetChange(it.value)
                    end
                end))
            end
        end
    end

    track(search:GetPropertyChangedSignal("Text"):Connect(function()
        filter = search.Text or ""
        rebuildList()
    end))

    track(ddBtn.MouseButton1Click:Connect(function()
        local open = not ddList.Visible
        ddList.Visible = open
        search.Visible = open
        ddArrow.Text = open and "▲" or "▼"
        if open then
            filter = ""
            search.Text = ""
            rebuildList()
        end
    end))

    rebuildList()

    ----------------------------------------------------------------
    -- Safe zone
    ----------------------------------------------------------------
    local safeBtn = Instance.new("TextButton")
    safeBtn.Position = UDim2.fromOffset(14, 262)
    safeBtn.Size = UDim2.new(1, -28, 0, 30)
    safeBtn.BackgroundColor3 = COLORS.bgAlt
    safeBtn.BorderSizePixel = 0
    safeBtn.Font = Enum.Font.GothamBold
    safeBtn.TextSize = 12
    safeBtn.TextColor3 = COLORS.accent
    safeBtn.Text = "📍  Set Safe Zone"
    safeBtn.Parent = content

    local sfCorner = Instance.new("UICorner")
    sfCorner.CornerRadius = UDim.new(0, 8)
    sfCorner.Parent = safeBtn

    local sfStroke = Instance.new("UIStroke")
    sfStroke.Color = COLORS.accent
    sfStroke.Thickness = 1
    sfStroke.Transparency = 0.5
    sfStroke.Parent = safeBtn

    local safeLbl = Instance.new("TextLabel")
    safeLbl.BackgroundTransparency = 1
    safeLbl.Position = UDim2.fromOffset(14, 296)
    safeLbl.Size = UDim2.new(1, -28, 0, 16)
    safeLbl.Font = Enum.Font.Code
    safeLbl.TextSize = 11
    safeLbl.TextColor3 = COLORS.textDim
    safeLbl.TextXAlignment = Enum.TextXAlignment.Left
    safeLbl.Text = "Safe Zone: NOT SET"
    safeLbl.Parent = content
    self._safeLbl = safeLbl

    track(safeBtn.MouseButton1Click:Connect(function()
        if config.onSetSafeZone then
            local ok = config.onSetSafeZone()
            if ok then
                safeLbl.Text = "Safe Zone: SET"
                safeLbl.TextColor3 = COLORS.accent
            end
        end
    end))

    ----------------------------------------------------------------
    -- Start / Stop
    ----------------------------------------------------------------
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Position = UDim2.fromOffset(14, 320)
    toggleBtn.Size = UDim2.new(1, -28, 0, 38)
    toggleBtn.BackgroundColor3 = COLORS.accent
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 14
    toggleBtn.TextColor3 = COLORS.bg
    toggleBtn.Text = "▶  START"
    toggleBtn.Parent = content
    self._toggleBtn = toggleBtn

    local tgCorner = Instance.new("UICorner")
    tgCorner.CornerRadius = UDim.new(0, 10)
    tgCorner.Parent = toggleBtn

    self._running = false

    track(toggleBtn.MouseButton1Click:Connect(function()
        if not self._running then
            self._running = true
            if config.onStart then config.onStart() end
        else
            self._running = false
            if config.onStop then config.onStop() end
        end
        self:refreshToggleVisual()
    end))

    ----------------------------------------------------------------
    -- Stats
    ----------------------------------------------------------------
    local statusLbl = Instance.new("TextLabel")
    statusLbl.BackgroundTransparency = 1
    statusLbl.Position = UDim2.fromOffset(14, 366)
    statusLbl.Size = UDim2.new(1, -28, 0, 14)
    statusLbl.Font = Enum.Font.Gotham
    statusLbl.TextSize = 11
    statusLbl.TextColor3 = COLORS.text
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.Text = "Status: Idle"
    statusLbl.Parent = content
    self._statusLbl = statusLbl

    local lastLbl = Instance.new("TextLabel")
    lastLbl.BackgroundTransparency = 1
    lastLbl.Position = UDim2.fromOffset(14, 382)
    lastLbl.Size = UDim2.new(1, -28, 0, 14)
    lastLbl.Font = Enum.Font.Gotham
    lastLbl.TextSize = 11
    lastLbl.TextColor3 = COLORS.text
    lastLbl.TextXAlignment = Enum.TextXAlignment.Left
    lastLbl.Text = "Last: —"
    lastLbl.Parent = content
    self._lastLbl = lastLbl

    local statsLbl = Instance.new("TextLabel")
    statsLbl.BackgroundTransparency = 1
    statsLbl.Position = UDim2.fromOffset(14, 398)
    statsLbl.Size = UDim2.new(1, -28, 0, 14)
    statsLbl.Font = Enum.Font.Code
    statsLbl.TextSize = 10
    statsLbl.TextColor3 = COLORS.accent
    statsLbl.TextXAlignment = Enum.TextXAlignment.Left
    statsLbl.Text = "Grabbed: 0 · Failed: 0 · Returns: 0"
    statsLbl.Parent = content
    self._statsLbl = statsLbl

    local fieldLbl = Instance.new("TextLabel")
    fieldLbl.BackgroundTransparency = 1
    fieldLbl.Position = UDim2.fromOffset(14, 414)
    fieldLbl.Size = UDim2.new(1, -28, 0, 14)
    fieldLbl.Font = Enum.Font.Code
    fieldLbl.TextSize = 10
    fieldLbl.TextColor3 = COLORS.textDim
    fieldLbl.TextXAlignment = Enum.TextXAlignment.Left
    fieldLbl.Text = "Field eggs: 0"
    fieldLbl.Parent = content
    self._fieldLbl = fieldLbl

    local assetLbl = Instance.new("TextLabel")
    assetLbl.BackgroundTransparency = 1
    assetLbl.Position = UDim2.fromOffset(14, 430)
    assetLbl.Size = UDim2.new(1, -28, 0, 14)
    assetLbl.Font = Enum.Font.Code
    assetLbl.TextSize = 10
    assetLbl.TextColor3 = COLORS.textDim
    assetLbl.TextXAlignment = Enum.TextXAlignment.Left
    assetLbl.Text = "Loaded: 0 eggs"
    assetLbl.Parent = content
    self._assetLbl = assetLbl

    ----------------------------------------------------------------
    -- Public methods
    ----------------------------------------------------------------
    function self:refreshToggleVisual()
        if self._running then
            toggleBtn.Text = "■  STOP"
            toggleBtn.BackgroundColor3 = COLORS.warn
            statusLbl.TextColor3 = COLORS.accent
        else
            toggleBtn.Text = "▶  START"
            toggleBtn.BackgroundColor3 = COLORS.accent
            statusLbl.TextColor3 = COLORS.textDim
        end
    end

    function self:setStatus(text)
        statusLbl.Text = "Status: " .. (text or "—")
    end

    function self:setLastGrabbed(text)
        lastLbl.Text = "Last: " .. (text or "—")
    end

    function self:setStats(t)
        t = t or {}
        statsLbl.Text = string.format(
            "Grabbed: %d · Failed: %d · Returns: %d",
            t.grabbed or 0, t.failed or 0, t.returned or 0
        )
    end

    function self:setFieldCount(n)
        fieldLbl.Text = "Field eggs: " .. (n or 0)
    end

    function self:setAssetCount(n)
        assetLbl.Text = "Loaded: " .. (n or 0) .. " eggs"
    end

    function self:setSafeZoneStatus(isSet)
        if isSet then
            safeLbl.Text = "Safe Zone: SET"
            safeLbl.TextColor3 = COLORS.accent
        else
            safeLbl.Text = "Safe Zone: NOT SET"
            safeLbl.TextColor3 = COLORS.textDim
        end
    end

    function self:getSelected()
        return self._selected
    end

    function self:isRunning()
        return self._running
    end

    function self:destroy()
        if self._cleaned then return end
        self._cleaned = true
        for _, c in ipairs(self._connections) do
            pcall(function() c:Disconnect() end)
        end
        self._connections = {}
        if self._gui then
            pcall(function() self._gui:Destroy() end)
        end
    end

    -- Initial state
    self:refreshToggleVisual()
    self:setAssetCount(0)

    return self
end

return AutoGrabUI
