-- AutoScript.lua
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local UI_URL         = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/ScreenUI.lua"
local EGG_DETECT_URL = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/EggDetector.lua"

local AutoUI = loadstring(game:HttpGet(UI_URL, true))()
local ui = AutoUI.new(PlayerGui, {
    Title    = "PlundererHub",
    Subtitle = "Steal An Egg",
})

-- Load EggDetector
local EggDetector = loadstring(game:HttpGet(EGG_DETECT_URL, true))()
local detector = EggDetector.new()
detector:start()

-- Shared filter state (read by both the Eggs tab and later the steal logic)
local Filters = {
    Rarity = "All",
    Area   = "All",
}
_G.PlundererFilters = Filters  -- exposed for the future steal module

-- ===== Main tab =====
local main = ui:addTab("Main", "🏠")

local autoSection = ui:addSection(main, "Automation")
ui:addToggle(autoSection, "Auto Steal Egg", false, function(v)
    print("[Auto] Auto Steal Egg:", v)
    -- wired to steal module later
end)
ui:addToggle(autoSection, "Auto Steal Selected Eggs", false, function(v)
    print("[Auto] Selected Eggs:", v)
end)
ui:addToggle(autoSection, "Auto Steal Secret Egg", false, function(v)
    print("[Auto] Secret Egg:", v)
end)

local filterSection = ui:addSection(main, "Filters")
ui:addDropdown(filterSection, "Areas to Steal", {
    "All", "Starter Island", "Desert", "Snow", "Volcano", "Space"
}, "All", function(v)
    Filters.Area = v
end)
ui:addDropdown(filterSection, "Egg Rarities to Steal", {
    "All", "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Divine", "Eternal", "Cosmic", "Secret"
}, "All", function(v)
    Filters.Rarity = v
end)
ui:addSlider(filterSection, "Max Pets to Keep", 0, 250, 50, function(v)
    -- placeholder for future inventory management
end)

-- ===== Eggs tab =====
local eggsTab = ui:addTab("Eggs", "🥚")

local eggControls = ui:addSection(eggsTab, "Detection")

local eggRarityFilter = "All"
local eggAreaFilter   = "All"

ui:addDropdown(eggControls, "Show Rarity", {
    "All", "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Divine", "Eternal", "Cosmic", "Secret"
}, "All", function(v)
    eggRarityFilter = v
    renderEggList()
end)

ui:addDropdown(eggControls, "Show Area", {
    "All", "Starter Island", "Desert", "Snow", "Volcano", "Space"
}, "All", function(v)
    eggAreaFilter = v
    renderEggList()
end)

ui:addButton(eggControls, "Force Rescan", function()
    detector:stop()
    task.wait(0.3)
    detector:start()
    ui:setBottomStatus("Rescanning for eggs...")
end)

-- Live list section
local listSection = ui:addSection(eggsTab, "Detected Eggs")

local countRow = Instance.new("Frame")
countRow.Size = UDim2.new(1, 0, 0, 18)
countRow.BackgroundTransparency = 1
countRow.Parent = listSection

local countLabel = Instance.new("TextLabel")
countLabel.BackgroundTransparency = 1
countLabel.Size = UDim2.new(1, 0, 1, 0)
countLabel.Font = Enum.Font.GothamMedium
countLabel.Text = "0 eggs detected"
countLabel.TextSize = 11
countLabel.TextColor3 = Color3.fromRGB(138, 138, 165)
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = countRow

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
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
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

    -- Rarity dot
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(8, 8)
    dot.Position = UDim2.new(0, 10, 0.5, -4)
    dot.BackgroundColor3 = rec.rarity and rec.rarity.color or Color3.fromRGB(100, 100, 110)
    dot.BorderSizePixel = 0
    dot.Parent = row
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    -- Egg name
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

    -- Rarity pill
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

    -- Distance
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

-- Forward declaration so the dropdown callbacks above can call this
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

    for _, rec in ipairs(matches) do
        makeRow(rec)
    end
end

-- Subscribe to detector events
detector:onChange(function()
    renderEggList()
    local total = #detector:getAll()
    ui:setBottomStatus(string.format("EggDetector: %d egg%s tracked", total, total == 1 and "" or "s"))
end)

-- Initial render
renderEggList()
ui:setBottomStatus("Egg detector running")

-- ===== Misc tab =====
local misc = ui:addTab("Misc", "⚙️")
local perf = ui:addSection(misc, "Performance")
ui:addToggle(perf, "Low Graphics Mode", false, function(v)
    -- toggle lighting / particles
end)
ui:addToggle(perf, "Silent Mode (no meme)", false, function(v) end)
ui:addSlider(perf, "Walk Speed", 16, 200, 16, function(v)
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char.Humanoid.WalkSpeed = v
    end
end)

local links = ui:addSection(misc, "Links")
ui:addButton(links, "Copy Discord Invite", function()
    if setclipboard then setclipboard("https://discord.gg/yourserver") end
end)
ui:addButton(links, "Reload UI", function()
    ui:destroy()
    detector:stop()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/AutoScript.lua"))()
end)

-- ===== Status =====
ui:setStatus("Idle", "idle")
ui:setBottomStatus("Ready — v1.1.0")
