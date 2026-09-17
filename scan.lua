--[[
    Steal an Egg — Auto Grab Field Eggs (UI Edition)
    For Delta Executor

    Flow:
      1. Open UI (auto-loads on run)
      2. Pick target egg from dropdown
      3. Stand in your safe zone
      4. Click "Set Safe Zone" (or it auto-saves on START)
      5. Click START
      6. Walk around freely — the script grabs and returns you to the safe zone
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ===== CONFIG =====
local GRAB_COOLDOWN        = 2.0    -- seconds between grab attempts
local TELEPORT_DELAY       = 0.35   -- delay before firing carry (after teleport)
local RETURN_DELAY         = 0.55   -- delay after grab before teleporting back
local SAFE_RETURN_OFFSET   = Vector3.new(0, 3, 0)
local EGG_ARRIVE_OFFSET    = Vector3.new(0, 3, 0)
local RESCAN_INTERVAL      = 30     -- full snapshot every N seconds
-- ==================

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
-- State
------------------------------------------------------------
local State = {
    enabled        = false,
    selectedEgg    = nil,        -- AssetCategory string
    safeZone       = nil,        -- CFrame
    eggList        = {},         -- uid -> egg data
    knownEggNames  = {},         -- set of "Raccoon", "Dog", etc.
    isCarrying     = false,
    lastGrab       = 0,
    stats          = { grabbed = 0, failed = 0, returned = 0 },
    lastGrabbed    = "—",
    status         = "Idle",
}

local function getHRP()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 5)
end

------------------------------------------------------------
-- BUILD UI
------------------------------------------------------------
local COLORS = {
    bg       = Color3.fromRGB(15, 15, 22),
    bgAlt    = Color3.fromRGB(22, 22, 32),
    accent   = Color3.fromRGB(120, 255, 160),
    accentHi = Color3.fromRGB(160, 255, 190),
    warn     = Color3.fromRGB(255, 180, 100),
    err      = Color3.fromRGB(255, 120, 120),
    text     = Color3.fromRGB(220, 220, 235),
    textDim  = Color3.fromRGB(140, 140, 160),
    border   = Color3.fromRGB(60, 80, 70),
}

local gui = Instance.new("ScreenGui")
gui.Name = "AutoGrabUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99999
gui.Parent = PlayerGui

-- Main panel
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -20, 0, 20)
panel.Size = UDim2.fromOffset(300, 420)
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
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = COLORS.bgAlt
header.BorderSizePixel = 0
header.Parent = panel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 14)
headerCorner.Parent = header

local headerClip = Instance.new("Frame")
headerClip.Size = UDim2.new(1, 0, 0, 18)
headerClip.Position = UDim2.new(0, 0, 1, -18)
headerClip.BackgroundColor3 = COLORS.bgAlt
headerClip.BorderSizePixel = 0
headerClip.Parent = header

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

-- Content container
local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.fromOffset(0, 36)
content.Size = UDim2.new(1, 0, 1, -36)
content.BackgroundTransparency = 1
content.Parent = panel

-- Minimize toggle
local minimized = false
minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    panel.Size = minimized and UDim2.fromOffset(300, 36) or UDim2.fromOffset(300, 420)
    minimizeBtn.Text = minimized and "+" or "−"
end)

------------------------------------------------------------
-- Dropdown label
------------------------------------------------------------
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

------------------------------------------------------------
-- Dropdown trigger
------------------------------------------------------------
local dropdownBtn = Instance.new("TextButton")
dropdownBtn.Name = "DropdownBtn"
dropdownBtn.Position = UDim2.fromOffset(14, 26)
dropdownBtn.Size = UDim2.new(1, -28, 0, 32)
dropdownBtn.BackgroundColor3 = COLORS.bgAlt
dropdownBtn.BorderSizePixel = 0
dropdownBtn.Font = Enum.Font.Gotham
dropdownBtn.TextSize = 13
dropdownBtn.TextColor3 = COLORS.text
dropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
dropdownBtn.Text = "  Select an egg..."
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
-- Dropdown list
------------------------------------------------------------
local dropdownList = Instance.new("ScrollingFrame")
dropdownList.Name = "DropdownList"
dropdownList.Position = UDim2.fromOffset(14, 60)
dropdownList.Size = UDim2.new(1, -28, 0, 160)
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

-- Populate list — start with "Any"
local function rebuildDropdown()
    -- Clear existing items
    for _, c in ipairs(dropdownList:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end

    -- Collect all names
    local names = { "Any" }
    for name, _ in pairs(State.knownEggNames) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b)
        if a == "Any" then return true end
        if b == "Any" then return false end
        return a < b
    end)

    for i, name in ipairs(names) do
        local item = Instance.new("TextButton")
        item.Name = "Item"
        item.Size = UDim2.new(1, 0, 0, 26)
        item.BackgroundColor3 = COLORS.bg
        item.BackgroundTransparency = 1
        item.BorderSizePixel = 0
        item.Font = Enum.Font.Gotham
        item.TextSize = 12
        item.TextColor3 = COLORS.text
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.Text = "  " .. name
        item.LayoutOrder = i
        item.Parent = dropdownList

        item.MouseEnter:Connect(function()
            item.BackgroundTransparency = 0.7
        end)
        item.MouseLeave:Connect(function()
            item.BackgroundTransparency = 1
        end)
        item.MouseButton1Click:Connect(function()
            State.selectedEgg = (name == "Any") and nil or name
            dropdownBtn.Text = "  " .. name
            dropdownList.Visible = false
            ddArrow.Text = "▼"
            log("Selected target: " .. name)
        end)
    end
end

rebuildDropdown()

-- Dropdown toggle
dropdownBtn.MouseButton1Click:Connect(function()
    dropdownList.Visible = not dropdownList.Visible
    ddArrow.Text = dropdownList.Visible and "▲" or "▼"
end)

------------------------------------------------------------
-- Safe zone section
------------------------------------------------------------
local safeBtn = Instance.new("TextButton")
safeBtn.Name = "SetSafeZone"
safeBtn.Position = UDim2.fromOffset(14, 230)
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

safeBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        State.safeZone = hrp.CFrame
        log("Safe zone set")
        safeStatusLbl.Text = "Safe Zone: SET"
        safeStatusLbl.TextColor3 = COLORS.accent
    end
end)

local safeStatusLbl = Instance.new("TextLabel")
safeStatusLbl.Name = "SafeStatus"
safeStatusLbl.BackgroundTransparency = 1
safeStatusLbl.Position = UDim2.fromOffset(14, 264)
safeStatusLbl.Size = UDim2.new(1, -28, 0, 16)
safeStatusLbl.Font = Enum.Font.Code
safeStatusLbl.TextSize = 11
safeStatusLbl.TextColor3 = COLORS.textDim
safeStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
safeStatusLbl.Text = "Safe Zone: NOT SET"
safeStatusLbl.Parent = content

------------------------------------------------------------
-- Start / Stop toggle
------------------------------------------------------------
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "Toggle"
toggleBtn.Position = UDim2.fromOffset(14, 288)
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

toggleBtn.MouseButton1Click:Connect(function()
    if not State.enabled then
        -- Enable: auto-save safe zone if not set
        if not State.safeZone then
            local hrp = getHRP()
            if hrp then
                State.safeZone = hrp.CFrame
                safeStatusLbl.Text = "Safe Zone: AUTO-SET"
                safeStatusLbl.TextColor3 = COLORS.warn
                log("Safe zone auto-set from current position")
            end
        end
        State.enabled = true
        log("STARTED")
        -- Immediate snapshot + grab attempt
        task.spawn(function()
            fetchSnapshot()
        end)
    else
        State.enabled = false
        log("STOPPED")
    end
end)

------------------------------------------------------------
-- Status / stats display
------------------------------------------------------------
local statusLbl = Instance.new("TextLabel")
statusLbl.Name = "Status"
statusLbl.BackgroundTransparency = 1
statusLbl.Position = UDim2.fromOffset(14, 334)
statusLbl.Size = UDim2.new(1, -28, 0, 14)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 11
statusLbl.TextColor3 = COLORS.text
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text = "Status: Idle"
statusLbl.Parent = content

local lastLbl = Enum  -- dummy to avoid warning
lastLbl = Instance.new("TextLabel")
lastLbl.Name = "Last"
lastLbl.BackgroundTransparency = 1
lastLbl.Position = UDim2.fromOffset(14, 350)
lastLbl.Size = UDim2.new(1, -28, 0, 14)
lastLbl.Font = Enum.Font.Gotham
lastLbl.TextSize = 11
lastLbl.TextColor3 = COLORS.text
lastLbl.TextXAlignment = Enum.TextXAlignment.Left
lastLbl.Text = "Last: —"
lastLbl.Parent = content

local statsLbl = Instance.new("TextLabel")
statsLbl.Name = "Stats"
statsLbl.BackgroundTransparency = 1
statsLbl.Position = UDim2.fromOffset(14, 366)
statsLbl.Size = UDim2.new(1, -28, 0, 14)
statsLbl.Font = Enum.Font.Code
statsLbl.TextSize = 10
statsLbl.TextColor3 = COLORS.accent
statsLbl.TextXAlignment = Enum.TextXAlignment.Left
statsLbl.Text = "Grabbed: 0 · Failed: 0 · Returns: 0"
statsLbl.Parent = content

local fieldLbl = Instance.new("TextLabel")
fieldLbl.Name = "Field"
fieldLbl.BackgroundTransparency = 1
fieldLbl.Position = UDim2.fromOffset(14, 382)
fieldLbl.Size = UDim2.new(1, -28, 0, 14)
fieldLbl.Font = Enum.Font.Code
fieldLbl.TextSize = 10
fieldLbl.TextColor3 = COLORS.textDim
fieldLbl.TextXAlignment = Enum.TextXAlignment.Left
fieldLbl.Text = "Field eggs tracked: 0"
fieldLbl.Parent = content

------------------------------------------------------------
-- UI refresh loop
------------------------------------------------------------
local function refreshUI()
    -- Toggle button
    if State.enabled then
        toggleBtn.Text = "■  STOP"
        toggleBtn.BackgroundColor3 = COLORS.warn
    else
        toggleBtn.Text = "▶  START"
        toggleBtn.BackgroundColor3 = COLORS.accent
    end

    -- Status
    local statusText = State.enabled and (State.status or "Running") or "Idle"
    statusLbl.Text = "Status: " .. statusText
    statusLbl.TextColor3 = State.enabled and COLORS.accent or COLORS.textDim

    -- Last grabbed
    lastLbl.Text = "Last: " .. State.lastGrabbed

    -- Stats
    statsLbl.Text = string.format(
        "Grabbed: %d · Failed: %d · Returns: %d",
        State.stats.grabbed, State.stats.failed, State.stats.returned
    )

    -- Field egg count
    local n = 0
    for _ in pairs(State.eggList) do n = n + 1 end
    fieldLbl.Text = "Field eggs tracked: " .. n
end

task.spawn(function()
    while gui.Parent do
        refreshUI()
        task.wait(0.4)
    end
end)

------------------------------------------------------------
-- Filter
------------------------------------------------------------
local function matchesFilter(egg)
    if not egg or type(egg) ~= "table" then return false end
    if egg.State ~= "Slot" then return false end
    if not egg.Uid then return false end

    -- Track egg name for dropdown
    if egg.AssetCategory and type(egg.AssetCategory) == "string" then
        State.knownEggNames[egg.AssetCategory] = true
    end

    -- No target = grab anything
    if not State.selectedEgg then return true end

    return egg.AssetCategory == State.selectedEgg
end

------------------------------------------------------------
-- Grab logic
------------------------------------------------------------
local function teleportBack()
    if not State.safeZone then return end
    local hrp = getHRP()
    if not hrp then return end
    hrp.CFrame = State.safeZone
    State.stats.returned = State.stats.returned + 1
end

local function tryGrab(egg)
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

    log(("Attempting: %s @ %s (uid=%s)"):format(
        egg.AssetCategory or "?",
        egg.AreaId or "?",
        tostring(egg.Uid)
    ))

    -- Teleport to egg
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(position + EGG_ARRIVE_OFFSET)
        task.wait(TELEPORT_DELAY)
    end

    -- Build args
    local args = { Uid = egg.Uid }
    if type(egg.Uid) == "string" and string.find(egg.Uid, "^FirstAreaEgg_") then
        args.FirstAreaSlotKey = (egg.AreaId or "") .. ":" .. (egg.NestId or "")
    end

    -- Fire carry
    local success, err = pcall(function()
        E.AskFieldEggCarry:InvokeServer(args)
    end)

    if success then
        State.stats.grabbed = State.stats.grabbed + 1
        State.lastGrabbed = (egg.AssetCategory or "?") .. " @ " .. (egg.AreaId or "?")
        log("Grab fired")
    else
        State.stats.failed = State.stats.failed + 1
        log("Grab failed: " .. tostring(err))
    end

    -- Wait then teleport back
    task.wait(RETURN_DELAY)
    teleportBack()
    State.status = "Returned · waiting"
    task.wait(0.3)
    State.status = "Running"

    refreshUI()
end

------------------------------------------------------------
-- Event listeners
------------------------------------------------------------
E.FieldEggShifted.OnClientEvent:Connect(function(egg)
    if type(egg) ~= "table" or not egg.Uid then return end
    State.eggList[egg.Uid] = egg
    if egg.AssetCategory then
        State.knownEggNames[egg.AssetCategory] = true
    end
    if egg.State == "Slot" then
        tryGrab(egg)
    end
end)

E.FieldEggBatchShifted.OnClientEvent:Connect(function(batch)
    if type(batch) ~= "table" then return end
    for _, egg in ipairs(batch) do
        if type(egg) == "table" and egg.Uid then
            State.eggList[egg.Uid] = egg
            if egg.AssetCategory then
                State.knownEggNames[egg.AssetCategory] = true
            end
            if egg.State == "Slot" then
                tryGrab(egg)
            end
        end
    end
end)

E.FieldEggGone.OnClientEvent:Connect(function(uid)
    if type(uid) == "string" then
        State.eggList[uid] = nil
    end
end)

E.FieldEggCarry.OnClientEvent:Connect(function(info)
    if type(info) == "table" then
        State.isCarrying = info.IsCarrying == true
        if State.isCarrying then
            log("Carrying egg")
            State.status = "Carrying"
        else
            State.status = "Running"
        end
    end
end)

E.FieldEggRedeemVerdict.OnClientEvent:Connect(function(info)
    if type(info) == "table" then
        log(("Redeemed: %s (%s)"):format(
            info.DisplayName or info.AssetCategory or "?",
            info.Rarity or "?"
        ))
    end
end)

------------------------------------------------------------
-- Snapshot
------------------------------------------------------------
function fetchSnapshot()
    local okSnap, snapshot = pcall(function()
        return E.AskFieldEggSnapshot:InvokeServer()
    end)
    if okSnap and snapshot and snapshot.Records then
        local count = 0
        for _, egg in ipairs(snapshot.Records) do
            if egg.Uid then
                State.eggList[egg.Uid] = egg
                if egg.AssetCategory then
                    State.knownEggNames[egg.AssetCategory] = true
                end
                count = count + 1
            end
        end
        log(("Snapshot: %d eggs on field"):format(count))
        rebuildDropdown()

        if State.enabled then
            for _, egg in ipairs(snapshot.Records) do
                tryGrab(egg)
            end
        end
    else
        warn("[AutoGrab] Snapshot failed")
    end
end

task.spawn(function()
    task.wait(2)
    fetchSnapshot()
    while gui.Parent do
        task.wait(RESCAN_INTERVAL)
        if State.enabled then
            fetchSnapshot()
        end
    end
end)

------------------------------------------------------------
-- Startup log
------------------------------------------------------------
log("========================================")
log("  AUTO GRAB — UI EDITION")
log("========================================")
log("  1. Pick target egg from dropdown")
log("  2. Stand in your safe zone")
log("  3. Click 'Set Safe Zone' (or auto-saves on START)")
log("  4. Click START")
log("========================================")
