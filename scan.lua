--[[
    Steal an Egg — Auto Grab (Common Test Build)
    For Delta Executor

    Test version — only Common eggs in the dropdown.
    Once this works, we'll expand to the full catalog.

    Features:
      - Common-only dropdown with icons
      - Search
      - Safe zone return
      - Restart-safe (run again = clean restart)
]]

-- ============================================================
--  RE-EXECUTION GUARD
-- ============================================================
local GENV = getgenv and getgenv() or _G
if GENV.__AutoGrabInstance and GENV.__AutoGrabInstance.cleanup then
    pcall(function() GENV.__AutoGrabInstance.cleanup() end)
    print("[AutoGrab] Previous instance stopped.")
end
GENV.__AutoGrabInstance = nil

-- ============================================================
--  Services
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ===== CONFIG =====
local GRAB_COOLDOWN     = 2.0
local TELEPORT_DELAY    = 0.35
local RETURN_DELAY      = 0.55
local EGG_ARRIVE_OFFSET = Vector3.new(0, 3, 0)
local RESCAN_INTERVAL   = 30
-- ==================

-- ===== COMMON EGGS (from EggCatalog.json) =====
local EGG_POOL = {
    { name = "Any",      category = nil,        icon = nil },
    { name = "Chicken",  category = "Chicken",  icon = "rbxassetid://87733160598688" },
    { name = "Dog",      category = "Dog",      icon = "rbxassetid://128470938015055" },
    { name = "Duckling", category = "Duckling", icon = "rbxassetid://81116137079823" },
    { name = "Frog",     category = "Frog",     icon = "rbxassetid://114669220150056" },
    { name = "Jerboa",   category = "Jerboa",   icon = "rbxassetid://139650837807677" },
}
-- ================================================

------------------------------------------------------------
-- Remotes
------------------------------------------------------------
local ok, Remotes = pcall(require, ReplicatedStorage.Shared.Remotes)
if not ok or not Remotes or not Remotes.EggWorld then
    warn("[AutoGrab] Could not load Remotes.EggWorld")
    return
end
local E = Remotes.EggWorld

local log = function(...) print("[AutoGrab]", ...) end

------------------------------------------------------------
-- Instance + state
------------------------------------------------------------
local Instance = {
    connections = {},
    cleaned     = false,
    state = {
        enabled     = false,
        selectedEgg = nil,
        safeZone    = nil,
        eggList     = {},
        isCarrying  = false,
        lastGrab    = 0,
        stats       = { grabbed = 0, failed = 0, returned = 0 },
        lastGrabbed = "—",
        status      = "Idle",
    },
}
local State = Instance.state

local function track(conn)
    if conn then table.insert(Instance.connections, conn) end
    return conn
end

local function getHRP()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 5)
end

------------------------------------------------------------
-- COLORS
------------------------------------------------------------
local COLORS = {
    bg       = Color3.fromRGB(15, 15, 22),
    bgAlt    = Color3.fromRGB(22, 22, 32),
    accent   = Color3.fromRGB(120, 255, 160),
    warn     = Color3.fromRGB(255, 180, 100),
    err      = Color3.fromRGB(255, 120, 120),
    text     = Color3.fromRGB(220, 220, 235),
    textDim  = Color3.fromRGB(140, 140, 160),
    border   = Color3.fromRGB(60, 80, 70),
    common   = Color3.fromRGB(160, 160, 170),
}

------------------------------------------------------------
-- ROOT GUI
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AutoGrabUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99999
gui.Parent = PlayerGui
Instance.gui = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -20, 0, 20)
panel.Size = UDim2.fromOffset(300, 440)
panel.BackgroundColor3 = COLORS.bg
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.accent
panelStroke.Thickness = 1
panelStroke.Transparency = 0.6
panelStroke.Parent = panel

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = COLORS.bgAlt
header.BorderSizePixel = 0
header.Parent = panel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 14)
headerCorner.Parent = header

local headerTitle = Instance.new("TextLabel")
headerTitle.BackgroundTransparency = 1
headerTitle.Position = UDim2.fromOffset(14, 0)
headerTitle.Size = UDim2.new(1, -60, 1, 0)
headerTitle.Font = Enum.Font.GothamBold
headerTitle.TextSize = 14
headerTitle.TextColor3 = COLORS.accent
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Text = "🥚  AUTO GRAB"
headerTitle.Parent = header

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.AnchorPoint = Vector2.new(1, 0.5)
minimizeBtn.Position = UDim2.new(1, -10, 0.5, 0)
minimizeBtn.Size = UDim2.fromOffset(22, 22)
minimizeBtn.BackgroundColor3 = COLORS.bg
minimizeBtn.BackgroundTransparency = 0.3
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 14
minimizeBtn.TextColor3 = COLORS.accent
minimizeBtn.Text = "−"
minimizeBtn.Parent = header

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = minimizeBtn

local content = Instance.new("Frame")
content.Position = UDim2.fromOffset(0, 36)
content.Size = UDim2.new(1, 0, 1, -36)
content.BackgroundTransparency = 1
content.Parent = panel

local minimized = false
track(minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    panel.Size = minimized and UDim2.fromOffset(300, 36) or UDim2.fromOffset(300, 440)
    minimizeBtn.Text = minimized and "+" or "−"
end))

------------------------------------------------------------
-- TARGET LABEL
------------------------------------------------------------
local targetLbl = Instance.new("TextLabel")
targetLbl.BackgroundTransparency = 1
targetLbl.Position = UDim2.fromOffset(14, 8)
targetLbl.Size = UDim2.new(1, -28, 0, 16)
targetLbl.Font = Enum.Font.GothamBold
targetLbl.TextSize = 11
targetLbl.TextColor3 = COLORS.textDim
targetLbl.TextXAlignment = Enum.TextXAlignment.Left
targetLbl.Text = "TARGET EGG  ·  COMMON"
targetLbl.Parent = content

------------------------------------------------------------
-- DROPDOWN BUTTON
------------------------------------------------------------
local dropdownBtn = Instance.new("TextButton")
dropdownBtn.Position = UDim2.fromOffset(14, 26)
dropdownBtn.Size = UDim2.new(1, -28, 0, 36)
dropdownBtn.BackgroundColor3 = COLORS.bgAlt
dropdownBtn.BorderSizePixel = 0
dropdownBtn.Font = Enum.Font.Gotham
dropdownBtn.TextSize = 13
dropdownBtn.TextColor3 = COLORS.text
dropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
dropdownBtn.Text = "  Any"
dropdownBtn.Parent = content

local ddCorner = Instance.new("UICorner")
ddCorner.CornerRadius = UDim.new(0, 8)
ddCorner.Parent = dropdownBtn

local ddStroke = Instance.new("UIStroke")
ddStroke.Color = COLORS.border
ddStroke.Thickness = 1
ddStroke.Parent = dropdownBtn

local ddArrow = Instance.new("TextLabel")
ddArrow.BackgroundTransparency = 1
ddArrow.AnchorPoint = Vector2.new(1, 0.5)
ddArrow.Position = UDim2.new(1, -10, 0.5, 0)
ddArrow.Size = UDim2.fromOffset(16, 16)
ddArrow.Font = Enum.Font.GothamBold
ddArrow.TextSize = 12
ddArrow.TextColor3 = COLORS.accent
ddArrow.Text = "▼"
ddArrow.Parent = dropdownBtn

------------------------------------------------------------
-- DROPDOWN LIST
------------------------------------------------------------
local dropdownList = Instance.new("ScrollingFrame")
dropdownList.Position = UDim2.fromOffset(14, 66)
dropdownList.Size = UDim2.new(1, -28, 0, 200)
dropdownList.BackgroundColor3 = COLORS.bgAlt
dropdownList.BorderSizePixel = 0
dropdownList.ScrollBarThickness = 6
dropdownList.ScrollBarImageColor3 = COLORS.accent
dropdownList.CanvasSize = UDim2.new(0, 0, 0, 0)
dropdownList.AutomaticCanvasSize = Enum.AutomaticSize.Y
dropdownList.Visible = false
dropdownList.ZIndex = 5
dropdownList.Parent = content

local dlCorner = Instance.new("UICorner")
dlCorner.CornerRadius = UDim.new(0, 8)
dlCorner.Parent = dropdownList

local dlStroke = Instance.new("UIStroke")
dlStroke.Color = COLORS.accent
dlStroke.Thickness = 1
dlStroke.Transparency = 0.4
dlStroke.Parent = dropdownList

local dlLayout = Instance.new("UIListLayout")
dlLayout.Padding = UDim.new(0, 2)
dlLayout.SortOrder = Enum.SortOrder.LayoutOrder
dlLayout.Parent = dropdownList

local dlPadding = Instance.new("UIPadding")
dlPadding.PaddingTop = UDim.new(0, 4)
dlPadding.PaddingBottom = UDim.new(0, 4)
dlPadding.PaddingLeft = UDim.new(0, 4)
dlPadding.PaddingRight = UDim.new(0, 4)
dlPadding.Parent = dropdownList

------------------------------------------------------------
-- POPULATE DROPDOWN
------------------------------------------------------------
local function rebuildDropdown()
    for _, c in ipairs(dropdownList:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end

    for i, egg in ipairs(EGG_POOL) do
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1, 0, 0, 32)
        item.BackgroundColor3 = COLORS.bg
        item.BackgroundTransparency = 1
        item.BorderSizePixel = 0
        item.Text = ""
        item.LayoutOrder = i
        item.AutoButtonColor = false
        item.Parent = dropdownList

        -- Icon
        if egg.icon then
            local icon = Instance.new("ImageLabel")
            icon.BackgroundTransparency = 1
            icon.Position = UDim2.fromOffset(4, 4)
            icon.Size = UDim2.fromOffset(24, 24)
            icon.Image = egg.icon
            icon.ScaleType = Enum.ScaleType.Fit
            icon.Parent = item
        end

        -- Name
        local nameLbl = Instance.new("TextLabel")
        nameLbl.BackgroundTransparency = 1
        nameLbl.Position = UDim2.fromOffset(egg.icon and 34 or 8, 0)
        nameLbl.Size = UDim2.new(1, -40, 1, 0)
        nameLbl.Font = Enum.Font.Gotham
        nameLbl.TextSize = 13
        nameLbl.TextColor3 = COLORS.text
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.Text = egg.name
        nameLbl.Parent = item

        -- Rarity dot (all common here, just visual)
        local dot = Instance.new("Frame")
        dot.AnchorPoint = Vector2.new(1, 0.5)
        dot.Position = UDim2.new(1, -8, 0.5, 0)
        dot.Size = UDim2.fromOffset(8, 8)
        dot.BackgroundColor3 = COLORS.common
        dot.BorderSizePixel = 0
        dot.Parent = item
        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = dot

        track(item.MouseEnter:Connect(function()
            item.BackgroundTransparency = 0.7
        end))
        track(item.MouseLeave:Connect(function()
            item.BackgroundTransparency = 1
        end))
        track(item.MouseButton1Click:Connect(function()
            State.selectedEgg = egg.category
            dropdownBtn.Text = "  " .. egg.name
            dropdownList.Visible = false
            ddArrow.Text = "▼"
            log("Selected target: " .. egg.name)
        end))
    end
end

track(dropdownBtn.MouseButton1Click:Connect(function()
    local open = not dropdownList.Visible
    dropdownList.Visible = open
    ddArrow.Text = open and "▲" or "▼"
end))

------------------------------------------------------------
-- SAFE ZONE
------------------------------------------------------------
local safeBtn = Instance.new("TextButton")
safeBtn.Position = UDim2.fromOffset(14, 280)
safeBtn.Size = UDim2.new(1, -28, 0, 30)
safeBtn.BackgroundColor3 = COLORS.bgAlt
safeBtn.BorderSizePixel = 0
safeBtn.Font = Enum.Font.GothamBold
safeBtn.TextSize = 12
safeBtn.TextColor3 = COLORS.accent
safeBtn.Text = "📍  Set Safe Zone"
safeBtn.Parent = content

local safeCorner = Instance.new("UICorner")
safeCorner.CornerRadius = UDim.new(0, 8)
safeCorner.Parent = safeBtn

local safeStroke = Instance.new("UIStroke")
safeStroke.Color = COLORS.accent
safeStroke.Thickness = 1
safeStroke.Transparency = 0.5
safeStroke.Parent = safeBtn

local safeStatusLbl = Instance.new("TextLabel")
safeStatusLbl.BackgroundTransparency = 1
safeStatusLbl.Position = UDim2.fromOffset(14, 314)
safeStatusLbl.Size = UDim2.new(1, -28, 0, 16)
safeStatusLbl.Font = Enum.Font.Code
safeStatusLbl.TextSize = 11
safeStatusLbl.TextColor3 = COLORS.textDim
safeStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
safeStatusLbl.Text = "Safe Zone: NOT SET"
safeStatusLbl.Parent = content

track(safeBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        State.safeZone = hrp.CFrame
        safeStatusLbl.Text = "Safe Zone: SET"
        safeStatusLbl.TextColor3 = COLORS.accent
        log("Safe zone set")
    end
end))

------------------------------------------------------------
-- TOGGLE
------------------------------------------------------------
local toggleBtn = Instance.new("TextButton")
toggleBtn.Position = UDim2.fromOffset(14, 336)
toggleBtn.Size = UDim2.new(1, -28, 0, 38)
toggleBtn.BackgroundColor3 = COLORS.accent
toggleBtn.BorderSizePixel = 0
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.TextColor3 = COLORS.bg
toggleBtn.Text = "▶  START"
toggleBtn.Parent = content

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 10)
toggleCorner.Parent = toggleBtn

track(toggleBtn.MouseButton1Click:Connect(function()
    if not State.enabled then
        if not State.safeZone then
            local hrp = getHRP()
            if hrp then
                State.safeZone = hrp.CFrame
                safeStatusLbl.Text = "Safe Zone: AUTO-SET"
                safeStatusLbl.TextColor3 = COLORS.warn
                log("Safe zone auto-set")
            end
        end
        State.enabled = true
        log("STARTED")
        task.spawn(fetchSnapshot)
    else
        State.enabled = false
        log("STOPPED")
    end
end))

------------------------------------------------------------
-- STATUS LABELS
------------------------------------------------------------
local statusLbl = Instance.new("TextLabel")
statusLbl.BackgroundTransparency = 1
statusLbl.Position = UDim2.fromOffset(14, 382)
statusLbl.Size = UDim2.new(1, -28, 0, 14)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 11
statusLbl.TextColor3 = COLORS.text
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text = "Status: Idle"
statusLbl.Parent = content

local lastLbl = Instance.new("TextLabel")
lastLbl.BackgroundTransparency = 1
lastLbl.Position = UDim2.fromOffset(14, 398)
lastLbl.Size = UDim2.new(1, -28, 0, 14)
lastLbl.Font = Enum.Font.Gotham
lastLbl.TextSize = 11
lastLbl.TextColor3 = COLORS.text
lastLbl.TextXAlignment = Enum.TextXAlignment.Left
lastLbl.Text = "Last: —"
lastLbl.Parent = content

local statsLbl = Instance.new("TextLabel")
statsLbl.BackgroundTransparency = 1
statsLbl.Position = UDim2.fromOffset(14, 414)
statsLbl.Size = UDim2.new(1, -28, 0, 14)
statsLbl.Font = Enum.Font.Code
statsLbl.TextSize = 10
statsLbl.TextColor3 = COLORS.accent
statsLbl.TextXAlignment = Enum.TextXAlignment.Left
statsLbl.Text = "Grabbed: 0 · Failed: 0 · Returns: 0"
statsLbl.Parent = content

------------------------------------------------------------
-- REFRESH LOOP
------------------------------------------------------------
track(task.spawn(function()
    while not Instance.cleaned and gui.Parent do
        if State.enabled then
            toggleBtn.Text = "■  STOP"
            toggleBtn.BackgroundColor3 = COLORS.warn
        else
            toggleBtn.Text = "▶  START"
            toggleBtn.BackgroundColor3 = COLORS.accent
        end

        statusLbl.Text = "Status: " .. (State.enabled and State.status or "Idle")
        statusLbl.TextColor3 = State.enabled and COLORS.accent or COLORS.textDim
        lastLbl.Text = "Last: " .. State.lastGrabbed

        statsLbl.Text = string.format(
            "Grabbed: %d · Failed: %d · Returns: %d",
            State.stats.grabbed, State.stats.failed, State.stats.returned
        )

        task.wait(0.4)
    end
end))

------------------------------------------------------------
-- GRAB LOGIC
------------------------------------------------------------
local function matchesFilter(egg)
    if not egg or type(egg) ~= "table" then return false end
    if egg.State ~= "Slot" then return false end
    if not egg.Uid then return false end
    if not State.selectedEgg then return true end
    return egg.AssetCategory == State.selectedEgg
end

local function teleportBack()
    if not State.safeZone then return end
    local hrp = getHRP()
    if not hrp then return end
    hrp.CFrame = State.safeZone
    State.stats.returned = State.stats.returned + 1
end

local function tryGrab(egg)
    if Instance.cleaned then return end
    if not State.enabled then return end
    if State.isCarrying then return end
    if not matchesFilter(egg) then return end

    local now = tick()
    if now - State.lastGrab < GRAB_COOLDOWN then return end
    State.lastGrab = now

    local cframe = egg.BottomCFrame or egg.BoundsCFrame
    if not cframe then return end
    local position = cframe.Position or cframe

    State.status = "Grabbing " .. (egg.AssetCategory or "?")
    log(("Grab: %s @ %s"):format(egg.AssetCategory or "?", egg.AreaId or "?"))

    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(position + EGG_ARRIVE_OFFSET)
        task.wait(TELEPORT_DELAY)
    end

    if Instance.cleaned then return end

    local args = { Uid = egg.Uid }
    if type(egg.Uid) == "string" and string.find(egg.Uid, "^FirstAreaEgg_") then
        args.FirstAreaSlotKey = (egg.AreaId or "") .. ":" .. (egg.NestId or "")
    end

    local success, err = pcall(function()
        E.AskFieldEggCarry:InvokeServer(args)
    end)

    if success then
        State.stats.grabbed = State.stats.grabbed + 1
        State.lastGrabbed = (egg.AssetCategory or "?") .. " @ " .. (egg.AreaId or "?")
    else
        State.stats.failed = State.stats.failed + 1
        log("Grab failed: " .. tostring(err))
    end

    task.wait(RETURN_DELAY)
    if Instance.cleaned then return end
    teleportBack()
    State.status = "Running"
end

------------------------------------------------------------
-- EVENTS
------------------------------------------------------------
track(E.FieldEggShifted.OnClientEvent:Connect(function(egg)
    if Instance.cleaned then return end
    if type(egg) ~= "table" or not egg.Uid then return end
    State.eggList[egg.Uid] = egg
    if egg.State == "Slot" then tryGrab(egg) end
end))

track(E.FieldEggBatchShifted.OnClientEvent:Connect(function(batch)
    if Instance.cleaned then return end
    if type(batch) ~= "table" then return end
    for _, egg in ipairs(batch) do
        if type(egg) == "table" and egg.Uid then
            State.eggList[egg.Uid] = egg
            if egg.State == "Slot" then tryGrab(egg) end
        end
    end
end))

track(E.FieldEggGone.OnClientEvent:Connect(function(uid)
    if type(uid) == "string" then State.eggList[uid] = nil end
end))

track(E.FieldEggCarry.OnClientEvent:Connect(function(info)
    if type(info) == "table" then
        State.isCarrying = info.IsCarrying == true
        State.status = State.isCarrying and "Carrying" or "Running"
    end
end))

------------------------------------------------------------
-- SNAPSHOT
------------------------------------------------------------
function fetchSnapshot()
    if Instance.cleaned then return end
    local okSnap, snapshot = pcall(function()
        return E.AskFieldEggSnapshot:InvokeServer()
    end)
    if okSnap and snapshot and snapshot.Records then
        local count = 0
        for _, egg in ipairs(snapshot.Records) do
            if egg.Uid then
                State.eggList[egg.Uid] = egg
                count = count + 1
            end
        end
        log(("Snapshot: %d eggs on field"):format(count))
        if State.enabled then
            for _, egg in ipairs(snapshot.Records) do
                if Instance.cleaned then return end
                tryGrab(egg)
            end
        end
    else
        warn("[AutoGrab] Snapshot failed")
    end
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------
track(task.spawn(function()
    rebuildDropdown()
    log(("Loaded %d target eggs (Common only)"):format(#EGG_POOL - 1))

    task.wait(2)
    if Instance.cleaned then return end
    fetchSnapshot()

    while not Instance.cleaned and gui.Parent do
        task.wait(RESCAN_INTERVAL)
        if State.enabled and not Instance.cleaned then fetchSnapshot() end
    end
end))

------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------
function Instance.cleanup()
    if Instance.cleaned then return end
    Instance.cleaned = true
    State.enabled = false
    for _, conn in ipairs(Instance.connections) do
        pcall(function() conn:Disconnect() end)
    end
    Instance.connections = {}
    if Instance.gui then
        pcall(function() Instance.gui:Destroy() end)
    end
    print("[AutoGrab] Cleanup complete.")
end

GENV.__AutoGrabInstance = Instance

log("========================================")
log("  AUTO GRAB — COMMON TEST BUILD READY")
log("========================================")
