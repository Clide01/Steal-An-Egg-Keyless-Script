-- AutoScript.lua
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local UI_URL         = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/ScreenUI.lua"
local EGG_DETECT_URL = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/EggDetector.lua"
local REMOTE_SPY_URL = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/RemoteSpy.lua"

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

local Filters = { Rarity = "All", Area = "All" }
_G.PlundererFilters = Filters

-- ===== Main tab =====
local main = ui:addTab("Main", "🏠")
local autoSection = ui:addSection(main, "Automation")
ui:addToggle(autoSection, "Auto Steal Egg", false, function(v)
    print("[Auto] Auto Steal Egg:", v)
end)
ui:addToggle(autoSection, "Auto Steal Selected Eggs", false, function(v) end)
ui:addToggle(autoSection, "Auto Steal Secret Egg", false, function(v) end)

local filterSection = ui:addSection(main, "Filters")
ui:addDropdown(filterSection, "Areas to Steal", {
    "All", "Starter Island", "Desert", "Snow", "Volcano", "Space"
}, "All", function(v) Filters.Area = v end)
ui:addDropdown(filterSection, "Egg Rarities to Steal", {
    "All", "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Divine", "Eternal", "Cosmic", "Secret"
}, "All", function(v) Filters.Rarity = v end)
ui:addSlider(filterSection, "Max Pets to Keep", 0, 250, 50, function(v) end)

-- ===== Eggs tab =====
local eggsTab = ui:addTab("Eggs", "🥚")
local eggControls = ui:addSection(eggsTab, "Detection")

local eggRarityFilter, eggAreaFilter = "All", "All"

ui:addDropdown(eggControls, "Show Rarity", {
    "All", "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Divine", "Eternal", "Cosmic", "Secret"
}, "All", function(v) eggRarityFilter = v; renderEggList() end)
ui:addDropdown(eggControls, "Show Area", {
    "All", "Starter Island", "Desert", "Snow", "Volcano", "Space"
}, "All", function(v) eggAreaFilter = v; renderEggList() end)
ui:addButton(eggControls, "Force Rescan", function()
    detector:stop(); task.wait(0.3); detector:start()
    ui:setBottomStatus("Rescanning...")
end)

local listSection = ui:addSection(eggsTab, "Detected Eggs")
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
        if c:IsA("Frame") then c:Destroy() end
    end
    rowIndex = 0
end

local function makeRow(rec)
    rowIndex = rowIndex + 1
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.BackgroundColor3 = Color3.fromRGB(22, 22, 31)
    row.BackgroundTransparency = 0.3
    row.BorderSizePixel = 0
    row.LayoutOrder = rowIndex
    row.Parent = listFrame
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(8, 8)
    dot.Position = UDim2.new(0, 10, 0.5, -4)
    dot.BackgroundColor3 = rec.rarity and rec.rarity.color or Color3.fromRGB(100, 100, 110)
    dot.BorderSizePixel = 0
    dot.Parent = row
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local nameLbl = Instance.new("TextLabel")
    nameLbl.BackgroundTransparency = 1
    nameLbl.Position = UDim2.fromOffset(26, 0)
    nameLbl.Size = UDim2.new(1, -150, 1, 0)
    nameLbl.Font = Enum.Font.GothamMedium
    nameLbl.Text = rec.name or "Unknown Egg"
    nameLbl.TextSize = 12
    nameLbl.TextColor3 = Color3.fromRGB(240, 240, 250)
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.Parent = row

    local pill = Instance.new("TextLabel")
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Position = UDim2.new(1, -66, 0.5, 0)
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

    local distLbl = Instance.new("TextLabel")
    distLbl.AnchorPoint = Vector2.new(1, 0.5)
    distLbl.Position = UDim2.new(1, -6, 0.5, 0)
    distLbl.Size = UDim2.fromOffset(46, 18)
    distLbl.BackgroundTransparency = 1
    distLbl.Font = Enum.Font.GothamMedium
    distLbl.Text = string.format("%.0fm", detector:getDistance(rec))
    distLbl.TextSize = 10
    distLbl.TextColor3 = Color3.fromRGB(138, 138, 165)
    distLbl.TextXAlignment = Enum.TextXAlignment.Right
    distLbl.Parent = row
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

-- ===== Misc tab =====
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

-- ===== Developer tab =====
local dev = ui:addTab("Dev", "🔧")

local detectorDev = ui:addSection(dev, "Egg Detector")
ui:addToggle(detectorDev, "Detector Debug", false, function(v)
    EggDetector.DEBUG = v
end)
ui:addButton(detectorDev, "Dump Current Eggs", function()
    detector:dump()
end)

local spySection = ui:addSection(dev, "Remote Spy (Hook)")
ui:addToggle(spySection, "Enable Remote Spy", false, function(v)
    if v then spy:start() else spy:stop() end
end)
ui:addDropdown(spySection, "Filter", {
    "steal", "egg", "pet", "sell", "hatch", "buy", "all"
}, "steal", function(v)
    if v == "all" then
        spy:setVerbose(true)
        spy:setFilter("")
    else
        spy:setVerbose(false)
        spy:setFilter(v)
    end
end)
ui:addButton(spySection, "Clear Captures", function()
    spy:clearCaptures()
    print("[AutoUI] Remote spy captures cleared.")
end)
ui:addButton(spySection, "Dump Captures", function()
    spy:dump(50)
end)

-- Live capture feed in the Dev tab
local feedSection = ui:addSection(dev, "Live Capture Feed")
local feedCount = ui:addLabel(feedSection, "0 captures")

local feedFrame = Instance.new("Frame")
feedFrame.Size = UDim2.new(1, 0, 0, 0)
feedFrame.AutomaticSize = Enum.AutomaticSize.Y
feedFrame.BackgroundTransparency = 1
feedFrame.Parent = feedSection

local feedLayout = Instance.new("UIListLayout")
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Padding = UDim.new(0, 3)
feedLayout.Parent = feedFrame

local feedIndex = 0
local MAX_FEED_ROWS = 20

local function addFeedRow(entry)
    feedIndex = feedIndex + 1

    local row = Instance.new("TextLabel")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = Color3.fromRGB(22, 22, 31)
    row.BackgroundTransparency = 0.3
    row.BorderSizePixel = 0
    row.Font = Enum.Font.Code
    row.TextSize = 10
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.TextWrapped = true
    row.LayoutOrder = feedIndex
    row.TextColor3 = (entry.source == "prompt") and Color3.fromRGB(255, 200, 80)
                     or Color3.fromRGB(180, 230, 255)
    row.Text = string.format("  %s%s:%s(%s)",
        (entry.source == "prompt") and "◈ " or "▸ ",
        entry.path, entry.method, entry.args)
    row.Parent = feedFrame
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    -- Trim old rows
    local rows = {}
    for _, c in ipairs(feedFrame:GetChildren()) do
        if c:IsA("TextLabel") then table.insert(rows, c) end
    end
    while #rows > MAX_FEED_ROWS do
        local old = table.remove(rows, 1)
        old:Destroy()
    end
end

spy:onCapture(function(entry)
    addFeedRow(entry)
    feedCount.Text = string.format("%d captures (last 20 shown)", #spy:getCaptures())
end)

-- ===== Links =====
local links = ui:addSection(misc, "Links")
ui:addButton(links, "Copy Discord Invite", function()
    if setclipboard then setclipboard("https://discord.gg/yourserver") end
end)
ui:addButton(links, "Reload UI", function()
    ui:destroy()
    detector:stop()
    spy:stop()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/AutoScript.lua"))()
end)

ui:setStatus("Idle", "idle")
ui:setBottomStatus("Ready — v1.3.0")
