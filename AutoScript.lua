-- AutoScript.lua v1.6.0
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local UI_URL         = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/ScreenUI.lua"
local EGG_DETECT_URL = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/EggDetector.lua"
local REMOTE_SPY_URL = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/RemoteSpy.lua"
local AUTO_STEAL_URL = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/AutoSteal.lua"

local AutoUI = loadstring(game:HttpGet(UI_URL, true))()
local ui = AutoUI.new(PlayerGui, {
    Title    = "PlundererHub",
    Subtitle = "Steal An Egg",
})

local EggDetector = loadstring(game:HttpGet(EGG_DETECT_URL, true))()
local detector = EggDetector.new()
detector:start()

local RemoteSpy = loadstring(game:HttpGet(REMOTE_SPY_URL, true))()
local spy = RemoteSpy.new({ Filter = "steal", Verbose = false })

local AutoSteal = loadstring(game:HttpGet(AUTO_STEAL_URL, true))()
local auto = AutoSteal.new(detector, {
    UseFly          = true,
    FlySpeed        = 200,
    ReturnSpeed     = 400,
    Cooldown        = 2,
    GlobalCooldown  = 0.5,
    ReturnToOrigin  = true,
})

local Filters = { Rarity = "All", Area = "All" }
_G.PlundererFilters = Filters

-- Shared UI state for target highlight
local rowRefs = {}     -- [instance] = row frame
local targetListenerId = nil

-- =========================================================
-- Main tab
-- =========================================================
local main = ui:addTab("Main", "🏠")
local autoSection = ui:addSection(main, "Automation")

ui:addToggle(autoSection, "Auto Steal Egg", false, function(v)
    auto:setEnabled(v)
    ui:setStatus(v and "Stealing..." or "Idle", v and "running" or "idle")
end)
ui:addToggle(autoSection, "Use Selected Target Only", false, function(v)
    -- When on, target must be set. If target is nil, auto-steal idles.
    _G.PlundererTargetOnly = v
    print("[AutoUI] Target-only mode:", v)
end)

local filterSection = ui:addSection(main, "Filters")
ui:addDropdown(filterSection, "Areas to Steal", {
    "All", "Desert", "Forest", "Prehistoric", "Volcano", "Light Dark"
}, "All", function(v) Filters.Area = v end)
ui:addDropdown(filterSection, "Egg Rarities to Steal", {
    "All", "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Divine", "Eternal", "Cosmic", "Secret"
}, "All", function(v) Filters.Rarity = v end)
ui:addSlider(filterSection, "Max Pets to Keep", 0, 250, 50, function(v) end)

-- =========================================================
-- Steal tab — live stats + target indicator
-- =========================================================
local stealTab = ui:addTab("Steal", "⚡")
local statsSection = ui:addSection(stealTab, "Live Stats")

local statsRow = Instance.new("Frame")
statsRow.Size = UDim2.new(1, 0, 0, 44)
statsRow.BackgroundTransparency = 1
statsRow.Parent = statsSection

local function makeStat(x, label, id, color)
    local box = Instance.new("Frame")
    box.Position = UDim2.new(x, 0, 0, 0)
    box.Size = UDim2.new(0.33, -6, 1, 0)
    box.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
    box.BorderSizePixel = 0
    box.Parent = statsRow
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)

    local v = Instance.new("TextLabel")
    v.Name = id
    v.BackgroundTransparency = 1
    v.Position = UDim2.fromOffset(0, 4)
    v.Size = UDim2.new(1, 0, 0, 20)
    v.Font = Enum.Font.GothamBold
    v.Text = "0"
    v.TextSize = 18
    v.TextColor3 = color or Color3.fromRGB(128, 255, 160)
    v.Parent = box

    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = UDim2.fromOffset(0, 24)
    l.Size = UDim2.new(1, 0, 0, 14)
    l.Font = Enum.Font.GothamMedium
    l.Text = label
    l.TextSize = 10
    l.TextColor3 = Color3.fromRGB(138, 138, 165)
    l.Parent = box
    return v
end

local statAttempts  = makeStat(0,    "ATTEMPTS", "AttemptsVal")
local statSuccesses = makeStat(0.34, "SUCCESS",  "SuccessVal")
local statFailures  = makeStat(0.67, "FAILED",   "FailedVal", Color3.fromRGB(255, 130, 130))

local statusLabel = ui:addLabel(statsSection, "Status: idle")
local targetLabel = ui:addLabel(statsSection, "Target: (none — using auto-pick)", Color3.fromRGB(128, 255, 160))
local safeLabel   = ui:addLabel(statsSection, "Safe position: none")

ui:addButton(statsSection, "Clear Target (back to auto-pick)", function()
    auto:clearTarget()
    refreshAllRows()
end)
ui:addButton(statsSection, "Set Safe Position Here", function()
    if auto:captureSafePosition() then
        print("[AutoUI] Safe position saved")
    end
end)

-- Stats poll
task.spawn(function()
    while true do
        statAttempts.Text  = tostring(auto.stats.attempts)
        statSuccesses.Text = tostring(auto.stats.successes)
        statFailures.Text  = tostring(auto.stats.failures)
        statusLabel.Text   = "Status: " .. (auto.stats.lastStatus or "idle")

        local t = auto:getTarget()
        if t then
            targetLabel.Text = "Target: " .. t.name
            targetLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
        else
            targetLabel.Text = "Target: (none — using auto-pick)"
            targetLabel.TextColor3 = Color3.fromRGB(138, 138, 165)
        end

        if auto.safePosition then
            local p = auto.safePosition.Position
            safeLabel.Text = string.format("Safe position: (%.0f, %.0f, %.0f)", p.X, p.Y, p.Z)
        else
            safeLabel.Text = "Safe position: none"
        end
        task.wait(0.5)
    end
end)

-- =========================================================
-- Eggs tab — clickable rows
-- =========================================================
local eggsTab = ui:addTab("Eggs", "🥚")
local eggControls = ui:addSection(eggsTab, "Detection")
local eggRarityFilter, eggAreaFilter = "All", "All"

ui:addDropdown(eggControls, "Show Rarity", {
    "All", "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Divine", "Eternal", "Cosmic", "Secret"
}, "All", function(v) eggRarityFilter = v; renderEggList() end)
ui:addDropdown(eggControls, "Show Area", {
    "All", "Desert", "Forest", "Prehistoric", "Volcano", "Light Dark"
}, "All", function(v) eggAreaFilter = v; renderEggList() end)
ui:addButton(eggControls, "Force Rescan", function()
    detector:stop(); task.wait(0.3); detector:start()
end)

local listSection = ui:addSection(eggsTab, "Detected Eggs")
ui:addLabel(listSection, "Click any row to lock it as your steal target")

local countLabel = ui:addLabel(listSection, "0 eggs detected")

local listFrame = Instance.new("Frame")
listFrame.Size = UDim2.new(1, 0, 0, 0)
listFrame.AutomaticSize = Enum.AutomaticSize.Y
listFrame.BackgroundTransparency = 1
listFrame.Parent = listSection
local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
listLayout.Parent = listFrame

local rowIndex = 0
local function clearList()
    for _, c in ipairs(listFrame:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    rowIndex = 0
    rowRefs = {}
end

local function styleRow(row, isTarget)
    if isTarget then
        row.BackgroundColor3 = Color3.fromRGB(35, 55, 45)
        row.BackgroundTransparency = 0.15
    else
        row.BackgroundColor3 = Color3.fromRGB(22, 22, 31)
        row.BackgroundTransparency = 0.3
    end
end

local function makeRow(rec)
    rowIndex = rowIndex + 1

    -- Row is a TextButton so it can be clicked
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = Color3.fromRGB(22, 22, 31)
    row.BackgroundTransparency = 0.3
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.LayoutOrder = rowIndex
    row.Parent = listFrame
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    -- Rarity dot
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(8, 8)
    dot.Position = UDim2.new(0, 10, 0.5, -4)
    dot.BackgroundColor3 = rec.rarity and rec.rarity.color or Color3.fromRGB(100, 100, 110)
    dot.BorderSizePixel = 0
    dot.Parent = row
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    -- Name
    local nameLbl = Instance.new("TextLabel")
    nameLbl.BackgroundTransparency = 1
    nameLbl.Position = UDim2.fromOffset(26, 0)
    nameLbl.Size = UDim2.new(1, -170, 1, 0)
    nameLbl.Font = Enum.Font.GothamMedium
    nameLbl.Text = rec.name or "Unknown Egg"
    nameLbl.TextSize = 12
    nameLbl.TextColor3 = Color3.fromRGB(240, 240, 250)
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.Parent = row

    -- Area tag
    local areaLbl = Instance.new("TextLabel")
    areaLbl.BackgroundTransparency = 1
    areaLbl.Position = UDim2.fromOffset(26, -8)
    areaLbl.Size = UDim2.new(1, -170, 1, 0)
    areaLbl.Font = Enum.Font.GothamMedium
    areaLbl.Text = rec.area or ""
    areaLbl.TextSize = 9
    areaLbl.TextColor3 = Color3.fromRGB(100, 100, 120)
    areaLbl.TextXAlignment = Enum.TextXAlignment.Left
    areaLbl.Parent = row

    -- Rarity pill
    local pill = Instance.new("TextLabel")
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Position = UDim2.new(1, -70, 0.5, 0)
    pill.Size = UDim2.fromOffset(64, 18)
    pill.BackgroundColor3 = rec.rarity and rec.rarity.color or Color3.fromRGB(100, 100, 110)
    pill.BackgroundTransparency = 0.75
    pill.BorderSizePixel = 0
    pill.Font = Enum.Font.GothamBold
    pill.Text = rec.rarity and rec.rarity.label or "?"
    pill.TextSize = 9
    pill.TextColor3 = rec.rarity and rec.rarity.color or Color3.fromRGB(200, 200, 210)
    pill.Parent = row
    Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 9)

    -- Distance
    local distLbl = Instance.new("TextLabel")
    distLbl.AnchorPoint = Vector2.new(1, 0.5)
    distLbl.Position = UDim2.new(1, -6, 0.5, 0)
    distLbl.Size = UDim2.fromOffset(56, 18)
    distLbl.BackgroundTransparency = 1
    distLbl.Font = Enum.Font.GothamMedium
    distLbl.Text = string.format("%.0fm", detector:getDistance(rec))
    distLbl.TextSize = 10
    distLbl.TextColor3 = Color3.fromRGB(138, 138, 165)
    distLbl.TextXAlignment = Enum.TextXAlignment.Right
    distLbl.Parent = row

    -- Highlight if this row's instance is the current target
    local isTarget = (auto:getTarget() and auto:getTarget().instance == rec.instance)
    styleRow(row, isTarget)

    -- Click → set as target
    row.MouseButton1Click:Connect(function()
        auto:setTarget(rec)
        refreshAllRows()
    end)

    -- Hover
    row.MouseEnter:Connect(function()
        if not (auto:getTarget() and auto:getTarget().instance == rec.instance) then
            row.BackgroundTransparency = 0.15
        end
    end)
    row.MouseLeave:Connect(function()
        if not (auto:getTarget() and auto:getTarget().instance == rec.instance) then
            row.BackgroundTransparency = 0.3
        end
    end)

    rowRefs[rec.instance] = row
end

-- Refreshes just the highlight styling of existing rows (no rebuild)
function refreshAllRows()
    for _, row in pairs(rowRefs) do
        if row and row.Parent then
            styleRow(row, false)
        end
    end
    local t = auto:getTarget()
    if t and rowRefs[t.instance] and rowRefs[t.instance].Parent then
        styleRow(rowRefs[t.instance], true)
    end
end

function renderEggList()
    if not listFrame or not listFrame.Parent then return end
    clearList()
    local matches = detector:getMatching(eggRarityFilter, eggAreaFilter)
    countLabel.Text = string.format("%d egg%s detected", #matches, #matches == 1 and "" or "s")
    if #matches == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 40)
        empty.BackgroundTransparency = 1
        empty.Font = Enum.Font.GothamMedium
        empty.Text = "No eggs match your filters."
        empty.TextSize = 12
        empty.TextColor3 = Color3.fromRGB(138, 138, 165)
        empty.TextXAlignment = Enum.TextXAlignment.Left
        empty.LayoutOrder = 1
        empty.Parent = listFrame
        return
    end
    for _, rec in ipairs(matches) do makeRow(rec) end
end

detector:onChange(function()
    renderEggList()
    local total = #detector:getAll()
    ui:setBottomStatus(string.format("EggDetector: %d egg%s tracked", total, total == 1 and "" or "s"))
end)

renderEggList()

-- =========================================================
-- Dev tab
-- =========================================================
local dev = ui:addTab("Dev", "🔧")
local detectorDev = ui:addSection(dev, "Egg Detector")
ui:addToggle(detectorDev, "Detector Debug", false, function(v) EggDetector.DEBUG = v end)
ui:addButton(detectorDev, "Dump Current Eggs", function() detector:dump() end)

local spySection = ui:addSection(dev, "Remote Spy")
ui:addToggle(spySection, "Enable Remote Spy", false, function(v)
    if v then spy:start() else spy:stop() end
end)
ui:addDropdown(spySection, "Filter", {
    "steal", "egg", "pet", "sell", "hatch", "buy", "all"
}, "steal", function(v)
    if v == "all" then spy:setVerbose(true); spy:setFilter("")
    else spy:setVerbose(false); spy:setFilter(v) end
end)
ui:addButton(spySection, "Clear Captures", function() spy:clearCaptures() end)
ui:addButton(spySection, "Dump Captures", function() spy:dump(50) end)

-- =========================================================
-- Misc tab
-- =========================================================
local misc = ui:addTab("Misc", "⚙️")
local perf = ui:addSection(misc, "Performance")
ui:addToggle(perf, "Low Graphics Mode", false, function(v) end)
ui:addToggle(perf, "Silent Mode (no meme)", false, function(v) end)
ui:addSlider(perf, "Walk Speed", 16, 200, 16, function(v)
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char.Humanoid.WalkSpeed = v
    end
end)

local movement = ui:addSection(misc, "Movement")
ui:addToggle(movement, "Fly Mode (no teleport)", true, function(v)
    auto.useFly = v
end)
ui:addSlider(movement, "Fly Speed", 20, 500, 200, function(v)
    auto.flySpeed = v
    auto.returnSpeed = v * 2
end)
ui:addToggle(movement, "Return to Origin After Steal", true, function(v)
    auto.returnToOrigin = v
end)

local links = ui:addSection(misc, "Links")
ui:addButton(links, "Copy Discord Invite", function()
    if setclipboard then setclipboard("https://discord.gg/yourserver") end
end)
ui:addButton(links, "Reload UI", function()
    ui:destroy()
    detector:stop()
    spy:stop()
    auto:stopLoop()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/AutoScript.lua"))()
end)

ui:setStatus("Idle", "idle")
ui:setBottomStatus("Ready — v1.6.0")

auto:startLoop(Filters)
