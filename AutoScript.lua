-- AutoScript.lua
-- PlundererHub — Steal An Egg automation
-- v1.1.0 — adds live egg detection

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local LocalPlayer       = Players.LocalPlayer
local PlayerGui         = LocalPlayer:WaitForChild("PlayerGui")

-- =========================================================
-- CONFIG
-- =========================================================
local UI_URL = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/ScreenUI.lua"

-- Container name candidates for egg detection
local EGG_CONTAINER_NAMES = {
    "Eggs", "SpawnedEggs", "EggSpawns", "EggContainer",
    "ActiveEggs", "Spawned", "Active", "Spawners",
}

-- Rarity keyword table (high → low priority)
local RARITY_TABLE = {
    { key = "secret",    label = "Secret",    color = Color3.fromRGB(255, 60, 180), rank = 10 },
    { key = "cosmic",    label = "Cosmic",    color = Color3.fromRGB(140, 80, 255), rank = 9  },
    { key = "eternal",   label = "Eternal",   color = Color3.fromRGB(120, 220, 255), rank = 8 },
    { key = "divine",    label = "Divine",    color = Color3.fromRGB(255, 220, 80), rank = 7  },
    { key = "mythic",    label = "Mythic",    color = Color3.fromRGB(255, 80, 80), rank = 6   },
    { key = "legendary", label = "Legendary", color = Color3.fromRGB(255, 180, 40), rank = 5 },
    { key = "legend",    label = "Legendary", color = Color3.fromRGB(255, 180, 40), rank = 5 },
    { key = "epic",      label = "Epic",      color = Color3.fromRGB(180, 80, 255), rank = 4  },
    { key = "rare",      label = "Rare",      color = Color3.fromRGB(80, 150, 255), rank = 3  },
    { key = "uncommon",  label = "Uncommon",  color = Color3.fromRGB(80, 200, 120), rank = 2  },
    { key = "common",    label = "Common",    color = Color3.fromRGB(150, 150, 170), rank = 1 },
}

local STEAL_PROMPT_KEYWORDS = { "steal", "take", "grab", "collect", "pick", "capture" }
-- =========================================================

-- =========================================================
-- LOAD UI MODULE
-- =========================================================
local AutoUI = loadstring(game:HttpGet(UI_URL, true))()
local ui = AutoUI.new(PlayerGui, {
    Title    = "PlundererHub",
    Subtitle = "Steal An Egg",
})

-- =========================================================
-- EGG DETECTOR (inline)
-- =========================================================
local EggDetector = {}
EggDetector.__index = EggDetector

local function classifyRarity(text)
    if not text or text == "" then return nil end
    local lower = string.lower(text)
    for _, r in ipairs(RARITY_TABLE) do
        if string.find(lower, r.key, 1, true) then
            return { label = r.label, color = r.color, rank = r.rank }
        end
    end
    return nil
end

local function promptIsStealLike(prompt)
    local action = string.lower(prompt.ActionText or "")
    local object = string.lower(prompt.ObjectText or "")
    for _, kw in ipairs(STEAL_PROMPT_KEYWORDS) do
        if string.find(action, kw, 1, true) or string.find(object, kw, 1, true) then
            return true
        end
    end
    return false
end

local function getDisplayName(inst)
    for _, attr in ipairs({ "Name", "EggName", "DisplayName", "Title" }) do
        local v = inst:GetAttribute(attr)
        if type(v) == "string" and v ~= "" then return v end
    end
    local billboard = inst:FindFirstChildWhichIsA("BillboardGui", true)
    if billboard then
        local label = billboard:FindFirstChildWhichIsA("TextLabel", true)
        if label and label.Text and label.Text ~= "" then return label.Text end
    end
    return inst.Name:gsub("_", " "):gsub("%s+", " ")
end

local function getStealPrompt(inst)
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") and promptIsStealLike(d) then
            return d
        end
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
    return nil
end

local function getTargetPart(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

function EggDetector.new()
    return setmetatable({
        container = nil,
        eggs = {},
        listeners = {},
        connections = {},
        _scanning = false,
    }, EggDetector)
end

function EggDetector:onChange(fn)
    table.insert(self.listeners, fn)
end

function EggDetector:_emit(event, payload)
    for _, fn in ipairs(self.listeners) do
        task.spawn(function()
            local ok, err = pcall(fn, event, payload)
            if not ok then warn("[EggDetector] Listener error:", err) end
        end)
    end
end

function EggDetector:_findContainer()
    for _, name in ipairs(EGG_CONTAINER_NAMES) do
        local c = workspace:FindFirstChild(name)
        if c and #c:GetChildren() > 0 then return c end
    end

    local counts = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and promptIsStealLike(d) then
            local parent = d.Parent
            local container = parent and parent.Parent
            if container then
                counts[container] = (counts[container] or 0) + 1
            end
        end
    end
    local best, bestCount = nil, 0
    for container, count in pairs(counts) do
        if count > bestCount then best, bestCount = container, count end
    end
    return best
end

function EggDetector:_buildRecord(inst)
    local target = getTargetPart(inst)
    local displayName = getDisplayName(inst)
    local rarity = classifyRarity(displayName) or classifyRarity(inst.Name)
    local prompt = getStealPrompt(inst)
    return {
        instance  = inst,
        target    = target,
        name      = displayName,
        rarity    = rarity,
        prompt    = prompt,
        position  = target and target.Position or nil,
        stealable = prompt ~= nil and prompt.Enabled ~= false,
    }
end

function EggDetector:_addEgg(inst)
    if not inst or self.eggs[inst] then return end
    local rec = self:_buildRecord(inst)
    if not rec.position then return end
    self.eggs[inst] = rec
    self:_emit("added", rec)
end

function EggDetector:_removeEgg(inst)
    if not self.eggs[inst] then return end
    local rec = self.eggs[inst]
    self.eggs[inst] = nil
    self:_emit("removed", rec)
end

function EggDetector:_bindContainer(container)
    for _, c in pairs(self.connections) do if c then c:Disconnect() end end
    self.connections = {}
    self.container = container
    if not container then return end

    for _, child in ipairs(container:GetChildren()) do
        self:_addEgg(child)
    end
    table.insert(self.connections, container.ChildAdded:Connect(function(c) self:_addEgg(c) end))
    table.insert(self.connections, container.ChildRemoved:Connect(function(c) self:_removeEgg(c) end))
end

function EggDetector:start()
    if self._scanning then return end
    self._scanning = true

    task.spawn(function()
        local container = self:_findContainer()
        if container then
            print("[EggDetector] Container:", container:GetFullName())
            self:_bindContainer(container)
        else
            warn("[EggDetector] No container found yet — retrying...")
        end

        while self._scanning do
            if self.container and not self.container.Parent then
                self.container = nil
            end
            if not self.container then
                local c = self:_findContainer()
                if c then
                    print("[EggDetector] Container found:", c:GetFullName())
                    self:_bindContainer(c)
                end
            end
            for inst, rec in pairs(self.eggs) do
                if not inst.Parent then
                    self:_removeEgg(inst)
                else
                    local t = getTargetPart(inst)
                    rec.target = t
                    rec.position = t and t.Position or nil
                    if not rec.position then self:_removeEgg(inst) end
                end
            end
            self:_emit("refreshed")
            task.wait(1)
        end
    end)
end

function EggDetector:stop()
    self._scanning = false
    for _, c in pairs(self.connections) do if c then c:Disconnect() end end
    self.connections = {}
end

function EggDetector:getAll()
    local list = {}
    for _, rec in pairs(self.eggs) do table.insert(list, rec) end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local function dist(rec)
        if not hrp or not rec.position then return math.huge end
        return (rec.position - hrp.Position).Magnitude
    end
    table.sort(list, function(a, b)
        local ra = a.rarity and a.rarity.rank or 0
        local rb = b.rarity and b.rarity.rank or 0
        if ra ~= rb then return ra > rb end
        return dist(a) < dist(b)
    end)
    return list
end

function EggDetector:getMatching(rarityFilter, areaFilter)
    local out = {}
    for _, rec in ipairs(self:getAll()) do
        local rarityOK = true
        if rarityFilter and rarityFilter ~= "All" then
            rarityOK = rec.rarity and rec.rarity.label == rarityFilter
        end
        local areaOK = true
        if areaFilter and areaFilter ~= "All" then
            local full = string.lower(rec.instance:GetFullName())
            areaOK = string.find(full, string.lower(areaFilter), 1, true) ~= nil
        end
        if rarityOK and areaOK then table.insert(out, rec) end
    end
    return out
end

function EggDetector:getDistance(rec)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not rec.position then return math.huge end
    return (rec.position - hrp.Position).Magnitude
end

-- =========================================================
-- MAIN TAB
-- =========================================================
local main = ui:addTab("Main", "🏠")

local autoSection = ui:addSection(main, "Automation")
local toggleAutoSteal
local toggleAutoSelected
local toggleAutoSecret

toggleAutoSteal = ui:addToggle(autoSection, "Auto Steal Egg", false, function(v)
    print("[Auto] Auto Steal Egg:", v)
    -- TODO: hook into steal loop (next module)
end)
toggleAutoSelected = ui:addToggle(autoSection, "Auto Steal Selected Eggs", false, function(v)
    print("[Auto] Auto Steal Selected Eggs:", v)
end)
toggleAutoSecret = ui:addToggle(autoSection, "Auto Steal Secret Egg", false, function(v)
    print("[Auto] Auto Steal Secret Egg:", v)
end)

local filterSection = ui:addSection(main, "Filters")
local areaFilter = "All"
local rarityFilter = "Rare"

ui:addDropdown(filterSection, "Areas to Steal", {
    "All", "Starter Island", "Desert", "Snow", "Volcano", "Space"
}, "All", function(v)
    areaFilter = v
    print("[Filter] Area:", v)
    if _G.__renderEggList then _G.__renderEggList() end
end)

ui:addDropdown(filterSection, "Egg Rarities to Steal", {
    "All", "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Divine", "Eternal", "Cosmic", "Secret"
}, "Rare", function(v)
    rarityFilter = v
    print("[Filter] Rarity:", v)
    if _G.__renderEggList then _G.__renderEggList() end
end)

ui:addSlider(filterSection, "Max Pets to Keep", 0, 250, 50, function(v)
    print("[Filter] Max Pets:", v)
end)

-- =========================================================
-- EGGS TAB
-- =========================================================
local eggsTab = ui:addTab("Eggs", "🥚")

local statusSection = ui:addSection(eggsTab, "Detector")
local statusLabel = ui:addLabel(statusSection, "Searching for eggs...")

ui:addButton(statusSection, "Force Rescan", function()
    detector:stop()
    task.wait(0.3)
    detector:start()
end)

local listSection = ui:addSection(eggsTab, "Detected Eggs")
local listFrame = Instance.new("Frame")
listFrame.Size = UDim2.new(1, 0, 0, 0)
listFrame.AutomaticSize = Enum.AutomaticSize.Y
listFrame.BackgroundTransparency = 1
listFrame.Parent = listSection
local ll = Instance.new("UIListLayout")
ll.SortOrder = Enum.SortOrder.LayoutOrder
ll.Padding = UDim.new(0, 4)
ll.Parent = listFrame

local rowCount = 0

local function clearList()
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    rowCount = 0
end

local function renderEggList()
    clearList()
    local matches = detector:getMatching(rarityFilter, areaFilter)

    statusLabel.Text = string.format("Tracking %d eggs · %d matching filters",
        #detector:getAll(), #matches)

    if #matches == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 40)
        empty.BackgroundTransparency = 1
        empty.Font = Enum.Font.GothamMedium
        empty.Text = "No eggs match your filters."
        empty.TextSize = 12
        empty.TextColor3 = Color3.fromRGB(138, 138, 165)
        empty.Parent = listFrame
        return
    end

    for _, rec in ipairs(matches) do
        rowCount = rowCount + 1

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 32)
        row.BackgroundColor3 = Color3.fromRGB(22, 22, 31)
        row.BackgroundTransparency = 0.3
        row.BorderSizePixel = 0
        row.LayoutOrder = rowCount
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
        nameLbl.Text = rec.name
        nameLbl.TextSize = 12
        nameLbl.TextColor3 = Color3.fromRGB(240, 240, 250)
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.Parent = row

        local pill = Instance.new("TextLabel")
        pill.AnchorPoint = Vector2.new(1, 0.5)
        pill.Position = UDim2.new(1, -60, 0.5, 0)
        pill.Size = UDim2.fromOffset(72, 18)
        pill.BackgroundColor3 = rec.rarity and rec.rarity.color or Color3.fromRGB(100, 100, 110)
        pill.BackgroundTransparency = 0.75
        pill.BorderSizePixel = 0
        pill.Font = Enum.Font.GothamBold
        pill.Text = rec.rarity and rec.rarity.label or "Unknown"
        pill.TextSize = 9
        pill.TextColor3 = rec.rarity and rec.rarity.color or Color3.fromRGB(200, 200, 210)
        pill.Parent = row
        Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 9)

        local distLbl = Instance.new("TextLabel")
        distLbl.AnchorPoint = Vector2.new(1, 0.5)
        distLbl.Position = UDim2.new(1, -6, 0.5, 0)
        distLbl.Size = UDim2.fromOffset(50, 18)
        distLbl.BackgroundTransparency = 1
        distLbl.Font = Enum.Font.GothamMedium
        distLbl.Text = string.format("%.0fm", detector:getDistance(rec))
        distLbl.TextSize = 10
        distLbl.TextColor3 = Color3.fromRGB(138, 138, 165)
        distLbl.TextXAlignment = Enum.TextXAlignment.Right
        distLbl.Parent = row
    end
end

-- =========================================================
-- MISC TAB
-- =========================================================
local misc = ui:addTab("Misc", "⚙️")
local perf = ui:addSection(misc, "Performance")
ui:addToggle(perf, "Low Graphics Mode", false, function(v)
    -- stub
end)
ui:addToggle(perf, "Silent Mode (no meme)", false, function(v)
    _G.__SilentMode = v
end)
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
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/AutoScript.lua"))()
end)

-- =========================================================
-- START DETECTOR
-- =========================================================
local detector = EggDetector.new()
detector:start()

_G.__renderEggList = renderEggList

detector:onChange(function()
    renderEggList()
end)

renderEggList()
ui:setStatus("Idle", "idle")
ui:setBottomStatus("Ready — v1.1.0")
