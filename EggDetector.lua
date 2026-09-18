-- EggDetector.lua
-- Finds eggs in a "Steal An Egg"-style Roblox game.
--
-- Detection strategy (in order):
--   1. CollectionService tag "Egg"
--   2. Known container names (workspace.Eggs, workspace.SpawnedEggs, ...)
--   3. Auto-scan: find the folder that has the most steal-like ProximityPrompts
--
-- Each egg is normalized into:
--   {
--     instance   = <raw instance>,
--     target     = <Model or BasePart to teleport to>,
--     name       = "Legendary Dragon Egg",
--     rarity     = { label = "Legendary", color = Color3, rank = 6 } or nil,
--     position   = Vector3,
--     stealable  = true/false,
--     prompt     = <ProximityPrompt or nil>,
--   }

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local EggDetector = {}
EggDetector.__index = EggDetector

-- Rarity keywords, ordered high → low (so "Legendary" matches before "Rare")
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

-- Container name candidates (checked in order)
local EGG_CONTAINER_NAMES = {
    "Eggs", "SpawnedEggs", "EggSpawns", "EggContainer", "ActiveEggs",
    "Spawned", "Active", "Spawners",
}

-- Prompt action keywords
local STEAL_PROMPT_KEYWORDS = { "steal", "take", "grab", "collect", "pick", "capture" }

-- =========================================================
-- Classification helpers
-- =========================================================
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
    -- 1) Attributes
    for _, attr in ipairs({ "Name", "EggName", "DisplayName", "Title" }) do
        local v = inst:GetAttribute(attr)
        if type(v) == "string" and v ~= "" then return v end
    end

    -- 2) BillboardGui TextLabel
    local billboard = inst:FindFirstChildWhichIsA("BillboardGui", true)
    if billboard then
        local label = billboard:FindFirstChildWhichIsA("TextLabel", true)
        if label and label.Text and label.Text ~= "" then return label.Text end
    end

    -- 3) Instance name (underscores → spaces)
    local n = inst.Name:gsub("_", " "):gsub("%s+", " ")
    return n
end

local function getStealPrompt(inst)
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") and promptIsStealLike(d) then
            return d
        end
    end
    -- fall back to any prompt
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

-- =========================================================
-- Container discovery
-- =========================================================
function EggDetector:_findContainer()
    -- Fast path: known names
    for _, name in ipairs(EGG_CONTAINER_NAMES) do
        local c = workspace:FindFirstChild(name)
        if c and #c:GetChildren() > 0 then return c end
    end

    -- Slow path: find folder with most steal-like prompts
    local counts = {}
    local sample = {}
    local scanned = 0

    for _, d in ipairs(workspace:GetDescendants()) do
        scanned = scanned + 1
        if d:IsA("ProximityPrompt") and promptIsStealLike(d) then
            local parent = d.Parent
            local container = parent and parent.Parent
            if container then
                counts[container] = (counts[container] or 0) + 1
                if not sample[container] then sample[container] = parent end
            end
        end
    end

    local best, bestCount = nil, 0
    for container, count in pairs(counts) do
        if count > bestCount then
            best, bestCount = container, count
        end
    end

    return best
end

-- =========================================================
-- Constructor
-- =========================================================
function EggDetector.new()
    local self = setmetatable({}, EggDetector)
    self.container = nil
    self.eggs = {}          -- [instance] = eggRecord
    self.listeners = {}
    self.connections = {}
    self._scanning = false
    return self
end

-- =========================================================
-- Event emitter
-- =========================================================
function EggDetector:onChange(fn)
    table.insert(self.listeners, fn)
    return function()
        for i, l in ipairs(self.listeners) do
            if l == fn then table.remove(self.listeners, i); break end
        end
    end
end

function EggDetector:_emit(event, payload)
    for _, fn in ipairs(self.listeners) do
        task.spawn(function()
            local ok, err = pcall(fn, event, payload)
            if not ok then warn("[EggDetector] Listener error:", err) end
        end)
    end
end

-- =========================================================
-- Egg record builder
-- =========================================================
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

-- =========================================================
-- Container binding
-- =========================================================
function EggDetector:_bindContainer(container)
    self:_unbindContainer()
    self.container = container
    if not container then return end

    -- Track existing
    for _, child in ipairs(container:GetChildren()) do
        self:_addEgg(child)
    end

    -- Track future
    self.connections.added = container.ChildAdded:Connect(function(child)
        self:_addEgg(child)
    end)
    self.connections.removed = container.ChildRemoved:Connect(function(child)
        self:_removeEgg(child)
    end)
end

function EggDetector:_unbindContainer()
    for _, c in pairs(self.connections) do
        if c then c:Disconnect() end
    end
    self.connections = {}
end

function EggDetector:_addEgg(inst)
    if not inst or self.eggs[inst] then return end
    local rec = self:_buildRecord(inst)
    if not rec.position then return end  -- not a valid egg
    self.eggs[inst] = rec
    self:_emit("added", rec)
end

function EggDetector:_removeEgg(inst)
    if not self.eggs[inst] then return end
    local rec = self.eggs[inst]
    self.eggs[inst] = nil
    self:_emit("removed", rec)
end

-- =========================================================
-- Start / stop
-- =========================================================
function EggDetector:start()
    if self._scanning then return end
    self._scanning = true

    task.spawn(function()
        -- find container
        local container = self:_findContainer()
        if not container then
            warn("[EggDetector] No egg container found. Retrying...")
        else
            print("[EggDetector] Container:", container:GetFullName())
            self:_bindContainer(container)
        end

        -- periodic revalidation
        while self._scanning do
            -- if container lost, try again
            if self.container and not self.container.Parent then
                self.container = nil
                self:_unbindContainer()
            end

            -- if we never found one, keep looking
            if not self.container then
                local c = self:_findContainer()
                if c then
                    print("[EggDetector] Container found:", c:GetFullName())
                    self:_bindContainer(c)
                end
            end

            -- refresh positions (in case eggs move)
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

            self:_emit("refreshed", nil)
            task.wait(1)
        end
    end)
end

function EggDetector:stop()
    self._scanning = false
    self:_unbindContainer()
end

-- =========================================================
-- Queries
-- =========================================================
function EggDetector:getAll()
    local list = {}
    for _, rec in pairs(self.eggs) do
        table.insert(list, rec)
    end
    -- sort by rarity rank desc, then distance asc
    local lp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local function dist(rec)
        if not lp or not rec.position then return math.huge end
        return (rec.position - lp.Position).Magnitude
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
    local all = self:getAll()
    local out = {}
    for _, rec in ipairs(all) do
        local rarityOK = true
        if rarityFilter and rarityFilter ~= "All" then
            rarityOK = rec.rarity and rec.rarity.label == rarityFilter
        end
        local areaOK = true
        if areaFilter and areaFilter ~= "All" then
            local ancestor = rec.instance
            while ancestor and ancestor ~= workspace do
                if string.find(string.lower(ancestor.Name), string.lower(areaFilter), 1, true) then
                    areaOK = true
                    break
                end
                ancestor = ancestor.Parent
            end
            areaOK = areaOK and ancestor ~= nil
            -- simpler: check full name
            local full = rec.instance:GetFullName()
            areaOK = string.find(string.lower(full), string.lower(areaFilter), 1, true) ~= nil
        end
        if rarityOK and areaOK then
            table.insert(out, rec)
        end
    end
    return out
end

function EggDetector:getDistance(rec)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not rec.position then return math.huge end
    return (rec.position - hrp.Position).Magnitude
end

return EggDetector
