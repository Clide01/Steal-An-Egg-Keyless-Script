--[[
    Steal an Egg — Auto Grab Field Eggs (v4 — Test Mode)
    For Delta Executor

    Test catalog: Common eggs only (5 total)
      · Chicken
      · Dog
      · Duckling
      · Frog
      · Jerboa

    Features:
      - Hardcoded catalog (no AssetDir needed)
      - Search filter in dropdown
      - Safe zone teleport return
      - Re-execution safe (running again restarts)
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

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ===== CONFIG =====
local GRAB_COOLDOWN     = 2.0
local TELEPORT_DELAY    = 0.35
local RETURN_DELAY      = 0.55
local EGG_ARRIVE_OFFSET = Vector3.new(0, 3, 0)
local RESCAN_INTERVAL   = 30
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

-- ============================================================
-- HARDCODED CATALOG — Common eggs only (test mode)
-- ============================================================
local CATALOG = {
    { category = "Chicken",  displayName = "Chicken",  rarity = "Common", rarityNum = 1, eggIcon = "rbxassetid://118146808162748" },
    { category = "Dog",      displayName = "Dog",      rarity = "Common", rarityNum = 1, eggIcon = "rbxassetid://123926130544109" },
    { category = "Duckling", displayName = "Duckling", rarity = "Common", rarityNum = 1, eggIcon = "rbxassetid://120651022174989" },
    { category = "Frog",     displayName = "Frog",     rarity = "Common", rarityNum = 1, eggIcon = "rbxassetid://103297453814736" },
    { category = "Jerboa",   displayName = "Jerboa",   rarity = "Common", rarityNum = 1, eggIcon = "rbxassetid://116318646770786" },
}

------------------------------------------------------------
-- Instance state
------------------------------------------------------------
local Instance = {
    connections = {},
    cleaned     = false,
    state = {
        enabled      = false,
        selectedEgg  = nil,      -- AssetCategory string ("Dog", "Frog", ...)
        safeZone     = nil,
        eggList      = {},
        isCarrying   = false,
        lastGrab     = 0,
        stats        = { grabbed = 0, failed = 0, returned = 0 },
        lastGrabbed  = "—",
        status       = "Idle",
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
    bg      = Color3.fromRGB(15, 15, 22),
    bgAlt   = Color3.fromRGB(22, 22, 32),
    accent  = Color3.fromRGB(120, 255, 160),
    warn    = Color3.fromRGB(255, 180, 100),
    text    = Color3.fromRGB(220, 220, 235),
    textDim = Color3.fromRGB(140, 140, 160),
    border  = Color3.fromRGB(60, 80, 70),
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

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = COLORS.accent
panelStroke.Thickness = 1
panelStroke.Transparency = 0.6

-- Header
local header = Instance.new("Frame", panel)
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = COLORS.bgAlt
header.BorderSizePixel = 0

Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)

local headerTitle = Instance.new("TextLabel", header)
headerTitle.BackgroundTransparency = 1
headerTitle.Position = UDim2.fromOffset(14, 0)
headerTitle.Size = UDim2.new(1, -60, 1, 0)
headerTitle.Font = Enum.Font.GothamBold
headerTitle.TextSize = 14
headerTitle.TextColor3 = COLORS.accent
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Text = "🥚  AUTO GRAB (TEST)"

local minimizeBtn = Instance.new("TextButton", header)
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

Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 6)

local content = Instance.new("Frame", panel)
content.Position = UDim2.fromOffset(0, 36)
content.Size = UDim2.new(1, 0, 1, -36)
content.BackgroundTransparency = 1

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
local targetLbl = Instance.new("TextLabel", content)
targetLbl.BackgroundTransparency = 1
targetLbl.Position = UDim2.fromOffset(14, 8)
targetLbl.Size = UDim2.new(1, -28, 0, 16)
targetLbl.Font = Enum.Font.GothamBold
targetLbl.TextSize = 11
targetLbl.TextColor3 = COLORS.textDim
targetLbl.TextXAlignment = Enum.TextXAlignment.Left
targetLbl.Text = "TARGET EGG (Common)"

------------------------------------------------------------
-- DROPDOWN BUTTON
------------------------------------------------------------
local dropdownBtn = Instance.new("TextButton", content)
dropdownBtn.Position = UDim2.fromOffset(14, 26)
dropdownBtn.Size = UDim2.new(1, -28, 0, 32)
dropdownBtn.BackgroundColor3 = COLORS.bgAlt
dropdownBtn.BorderSizePixel = 0
dropdownBtn.Font = Enum.Font.Gotham
dropdownBtn.TextSize = 13
dropdownBtn.TextColor3 = COLORS.text
dropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
dropdownBtn.Text = "  Any Common"

Instance.new("UICorner", dropdownBtn).CornerRadius = UDim.new(0, 8)

local ddStroke = Instance.new("UIStroke", dropdownBtn)
ddStroke.Color = COLORS.border
ddStroke.Thickness = 1

local ddArrow = Instance.new("TextLabel", dropdownBtn)
ddArrow.BackgroundTransparency = 1
ddArrow.AnchorPoint = Vector2.new(1, 0.5)
ddArrow.Position = UDim2.new(1, -10, 0.5, 0)
ddArrow.Size = UDim2.fromOffset(16, 16)
ddArrow.Font = Enum.Font.GothamBold
ddArrow.TextSize = 12
ddArrow.TextColor3 = COLORS.accent
ddArrow.Text = "▼"

------------------------------------------------------------
-- SEARCH BOX
------------------------------------------------------------
local searchBox = Instance.new("TextBox", content)
searchBox.Position = UDim2.fromOffset(14, 62)
searchBox.Size = UDim2.new(1, -28, 0, 26)
searchBox.BackgroundColor3 = COLORS.bgAlt
searchBox.BorderSizePixel = 0
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 12
searchBox.TextColor3 = COLORS.text
searchBox.PlaceholderText = "  Search..."
searchBox.PlaceholderColor3 = COLORS.textDim
searchBox.Text = ""
searchBox.ClearTextOnFocus = false
searchBox.Visible = false
searchBox.ZIndex = 6

Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 8)

------------------------------------------------------------
-- DROPDOWN LIST
------------------------------------------------------------
local dropdownList = Instance.new("ScrollingFrame", content)
dropdownList.Position = UDim2.fromOffset(14, 62)
dropdownList.Size = UDim2.new(1, -28, 0, 170)
dropdownList.BackgroundColor3 = COLORS.bgAlt
dropdownList.BorderSizePixel = 0
dropdownList.ScrollBarThickness = 6
dropdownList.ScrollBarImageColor3 = COLORS.accent
dropdownList.CanvasSize = UDim2.new(0, 0, 0, 0)
dropdownList.AutomaticCanvasSize = Enum.AutomaticSize.Y
dropdownList.Visible = false
dropdownList.ZIndex = 5

Instance.new("UICorner", dropdownList).CornerRadius = UDim.new(0, 8)

local dlStroke = Instance.new("UIStroke", dropdownList)
dlStroke.Color = COLORS.accent
dlStroke.Thickness = 1
dlStroke.Transparency = 0.4

local dlLayout = Instance.new("UIListLayout", dropdownList)
dlLayout.Padding = UDim.new(0, 2)
dlLayout.SortOrder = Enum.SortOrder.LayoutOrder

local dlPadding = Instance.new("UIPadding", dropdownList)
dlPadding.PaddingTop = UDim.new(0, 4)
dlPadding.PaddingBottom = UDim.new(0, 4)
dlPadding.PaddingLeft = UDim.new(0, 4)
dlPadding.PaddingRight = UDim.new(0, 4)

------------------------------------------------------------
-- REBUILD DROPDOWN from CATALOG
------------------------------------------------------------
local currentFilter = ""

local function rebuildDropdown()
    for _, c in ipairs(dropdownList:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end

    -- Build list: "Any Common" + each catalog entry
    local items = {
        { name = "Any Common", category = nil }
    }
    for _, rec in ipairs(CATALOG) do
        table.insert(items, {
            name = rec.displayName .. "  [" .. rec.rarity .. "]",
            category = rec.category,
            icon = rec.eggIcon,
        })
    end

    -- Apply search filter (matches displayName or category)
    local lf = string.lower(currentFilter)
    local filtered = {}
    for _, it in ipairs(items) do
        if lf == "" or string.find(string.lower(it.name), lf, 1, true) then
            table.insert(filtered, it)
        end
    end

    for i, it in ipairs(filtered) do
        local item = Instance.new("TextButton", dropdownList)
        item.Size = UDim2.new(1, 0, 0, 28)
        item.BackgroundColor3 = COLORS.bg
        item.BackgroundTransparency = 1
        item.BorderSizePixel = 0
        item.Font = Enum.Font.Gotham
        item.TextSize = 12
        item.TextColor3 = COLORS.text
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.Text = "  " .. it.name
        item.LayoutOrder = i

        -- Optional icon
        if it.icon then
            local img = Instance.new("ImageLabel", item)
            img.BackgroundTransparency = 1
            img.Position = UDim2.fromOffset(4, 4)
            img.Size = UDim2.fromOffset(20, 20)
            img.Image = it.icon
            img.ScaleType = Enum.ScaleType.Fit
            item.Text = "        " .. it.name
        end

        track(item.MouseEnter:Connect(function()
            item.BackgroundTransparency = 0.7
        end))
        track(item.MouseLeave:Connect(function()
            item.BackgroundTransparency = 1
        end))
        track(item.MouseButton1Click:Connect(function()
            State.selectedEgg = it.category
            dropdownBtn.Text = "  " .. it.name
            dropdownList.Visible = false
            searchBox.Visible = false
            ddArrow.Text = "▼"
            log("Selected: " .. it.name .. (it.category and (" (" .. it.category .. ")") or ""))
        end))
    end

    if #filtered == 0 then
        local empty = Instance.new("TextLabel", dropdownList)
        empty.Size = UDim2.new(1, 0, 0, 30)
        empty.BackgroundTransparency = 1
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 12
        empty.TextColor3 = COLORS.textDim
        empty.Text = "  No matches"
    end
end

track(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    currentFilter = searchBox.Text or ""
    rebuildDropdown()
end))

track(dropdownBtn.MouseButton1Click:Connect(function()
    local open = not dropdownList.Visible
    dropdownList.Visible = open
    searchBox.Visible = open
    ddArrow.Text = open and "▲" or "▼"
    if open then
        currentFilter = ""
        searchBox.Text = ""
        rebuildDropdown()
    end
end))

------------------------------------------------------------
-- SAFE ZONE
------------------------------------------------------------
local safeBtn = Instance.new("TextButton", content)
safeBtn.Position = UDim2.fromOffset(14, 240)
safeBtn.Size = UDim2.new(1, -28, 0, 30)
safeBtn.BackgroundColor3 = COLORS.bgAlt
safeBtn.BorderSizePixel = 0
safeBtn.Font = Enum.Font.GothamBold
safeBtn.TextSize = 12
safeBtn.TextColor3 = COLORS.accent
safeBtn.Text = "📍  Set Safe Zone"

Instance.new("UICorner", safeBtn).CornerRadius = UDim.new(0, 8)

local safeStroke = Instance.new("UIStroke", safeBtn)
safeStroke.Color = COLORS.accent
safeStroke.Thickness = 1
safeStroke.Transparency = 0.5

local safeStatusLbl = Instance.new("TextLabel", content)
safeStatusLbl.BackgroundTransparency = 1
safeStatusLbl.Position = UDim2.fromOffset(14, 274)
safeStatusLbl.Size = UDim2.new(1, -28, 0, 16)
safeStatusLbl.Font = Enum.Font.Code
safeStatusLbl.TextSize = 11
safeStatusLbl.TextColor3 = COLORS.textDim
safeStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
safeStatusLbl.Text = "Safe Zone: NOT SET"

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
local toggleBtn = Instance.new("TextButton", content)
toggleBtn.Position = UDim2.fromOffset(14, 298)
toggleBtn.Size = UDim2.new(1, -28, 0, 38)
toggleBtn.BackgroundColor3 = COLORS.accent
toggleBtn.BorderSizePixel = 0
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.TextColor3 = COLORS.bg
toggleBtn.Text = "▶  START"

Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 10)

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
local statusLbl = Instance.new("TextLabel", content)
statusLbl.BackgroundTransparency = 1
statusLbl.Position = UDim2.fromOffset(14, 344)
statusLbl.Size = UDim2.new(1, -28, 0, 14)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 11
statusLbl.TextColor3 = COLORS.text
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text = "Status: Idle"

local lastLbl = Instance.new("TextLabel", content)
lastLbl.BackgroundTransparency = 1
lastLbl.Position = UDim2.fromOffset(14, 360)
lastLbl.Size = UDim2.new(1, -28, 0, 14)
lastLbl.Font = Enum.Font.Gotham
lastLbl.TextSize = 11
lastLbl.TextColor3 = COLORS.text
lastLbl.TextXAlignment = Enum.TextXAlignment.Left
lastLbl.Text = "Last: —"

local statsLbl = Instance.new("TextLabel", content)
statsLbl.BackgroundTransparency = 1
statsLbl.Position = UDim2.fromOffset(14, 376)
statsLbl.Size = UDim2.new(1, -28, 0, 14)
statsLbl.Font = Enum.Font.Code
statsLbl.TextSize = 10
statsLbl.TextColor3 = COLORS.accent
statsLbl.TextXAlignment = Enum.TextXAlignment.Left
statsLbl.Text = "Grabbed: 0 · Failed: 0 · Returns: 0"

local fieldLbl = Instance.new("TextLabel", content)
fieldLbl.BackgroundTransparency = 1
fieldLbl.Position = UDim2.fromOffset(14, 392)
fieldLbl.Size = UDim2.new(1, -28, 0, 14)
fieldLbl.Font = Enum.Font.Code
fieldLbl.TextSize = 10
fieldLbl.TextColor3 = COLORS.textDim
fieldLbl.TextXAlignment = Enum.TextXAlignment.Left
fieldLbl.Text = "Field eggs (matching): 0"

local catalogLbl = Instance.new("TextLabel", content)
catalogLbl.BackgroundTransparency = 1
catalogLbl.Position = UDim2.fromOffset(14, 408)
catalogLbl.Size = UDim2.new(1, -28, 0, 14)
catalogLbl.Font = Enum.Font.Code
catalogLbl.TextSize = 10
catalogLbl.TextColor3 = COLORS.textDim
catalogLbl.TextXAlignment = Enum.TextXAlignment.Left
catalogLbl.Text = "Catalog: 5 common eggs"

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

        -- Count only matching field eggs
        local n = 0
        for _, egg in pairs(State.eggList) do
            if egg.State == "Slot" and matchesFilterSafe(egg) then
                n = n + 1
            end
        end
        fieldLbl.Text = "Field eggs (matching): " .. n

        task.wait(0.4)
    end
end))

-- Declared here so refresh loop can call it before tryGrab is defined
function matchesFilterSafe(egg)
    if not egg or type(egg) ~= "table" then return false end
    if not State.selectedEgg then
        -- In test mode with no selection, only count common eggs from catalog
        for _, rec in ipairs(CATALOG) do
            if rec.category == egg.AssetCategory then return true end
        end
        return false
    end
    return egg.AssetCategory == State.selectedEgg
end

------------------------------------------------------------
-- FILTER
------------------------------------------------------------
local function matchesFilter(egg)
    if not egg or type(egg) ~= "table" then return false end
    if egg.State ~= "Slot" then return false end
    if not egg.Uid then return false end

    -- If a specific egg is selected, match that
    if State.selectedEgg then
        return egg.AssetCategory == State.selectedEgg
    end

    -- Otherwise match any catalog egg (test mode = commons only)
    for _, rec in ipairs(CATALOG) do
        if rec.category == egg.AssetCategory then
            return true
        end
    end
    return false
end

------------------------------------------------------------
-- GRAB LOGIC
------------------------------------------------------------
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

    -- Build args — First Area eggs need FirstAreaSlotKey
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
    log(string.format("Loaded catalog: %d common eggs", #CATALOG))
    rebuildDropdown()

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
log("  AUTO GRAB v4 — TEST MODE (Common eggs)")
log("========================================")
log("  Catalog: Chicken, Dog, Duckling, Frog, Jerboa")
log("  Default target: ANY common egg")
log("========================================")
