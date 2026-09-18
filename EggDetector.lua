-- EggDetector.lua v4.3 — numbered eggs + game DB
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggDetector = {}
EggDetector.__index = EggDetector
EggDetector.VERSION = "4.3.0"
EggDetector.DEBUG = false

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

local function extractArea(inst)
    local p = inst
    while p and p ~= workspace do
        local parent = p.Parent
        if parent and parent.Name == "GuardAreas" then return p.Name end
        p = parent
    end
    return "Unknown"
end

-- Load the game's own egg directory for reference
local eggDatabase = nil
local function loadEggDatabase()
    if eggDatabase then return eggDatabase end
    eggDatabase = {}

    local ok, assets = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Assets"))
    end)
    if ok and assets and assets.Directory then
        for key, entry in pairs(assets.Directory) do
            local name = (type(entry) == "table" and (entry.DisplayName or entry.Name)) or tostring(key)
            local rarity = nil
            if type(entry) == "table" and entry.Rarity then
                rarity = entry.Rarity.DisplayName or tostring(entry.Rarity)
            end
            table.insert(eggDatabase, { key = key, name = name, rarity = rarity })
        end
        table.sort(eggDatabase, function(a, b) return a.name < b.name end)
    end
    return eggDatabase
end

function EggDetector.new()
    local self = setmetatable({}, EggDetector)
    self.eggs = {}
    self.listeners = {}
    self._scanning = false
    self.maxDistance = math.huge
    return self
end

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

local function getRoot()
    local objs = workspace:FindFirstChild("__OBJECTS")
    if not objs then return nil end
    local areas = objs:FindFirstChild("Areas")
    if not areas then return nil end
    return areas:FindFirstChild("GuardAreas")
end

function EggDetector:_scan()
    local out = {}
    local root = getRoot()
    if not root then return out end
    for _, area in ipairs(root:GetChildren()) do
        local nests = area:FindFirstChild("Nests")
        if nests then
            local idx = 0
            for _, nest in ipairs(nests:GetChildren()) do
                local eggModel = nest:FindFirstChild("Model")
                if eggModel and eggModel:IsA("Model") then
                    idx = idx + 1
                    out[eggModel] = { index = idx, area = area.Name }
                end
            end
        end
    end
    return out
end

function EggDetector:_getPosition(inst)
    if inst:IsA("BasePart") then return inst.Position end
    local pp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    return pp and pp.Position or nil
end

function EggDetector:_buildRecord(inst, meta)
    local pos = self:_getPosition(inst)
    return {
        instance = inst,
        target   = inst:FindFirstChildWhichIsA("BasePart", true),
        name     = string.format("%s Egg #%d", meta.area or "Unknown", meta.index or 0),
        area     = meta.area or "Unknown",
        index    = meta.index or 0,
        rarity   = nil,  -- unknown per-egg
        position = pos,
    }
end

function EggDetector:_refresh()
    local current = self:_scan()
    for inst, meta in pairs(current) do
        if not self.eggs[inst] then
            local rec = self:_buildRecord(inst, meta)
            if rec.position then
                self.eggs[inst] = rec
                self:_emit("added", rec)
            end
        else
            -- refresh index/area
            self.eggs[inst].index = meta.index
            self.eggs[inst].area = meta.area
            self.eggs[inst].name = string.format("%s Egg #%d", meta.area or "Unknown", meta.index or 0)
        end
    end
    for inst in pairs(self.eggs) do
        if not current[inst] or not inst.Parent then
            local rec = self.eggs[inst]
            self.eggs[inst] = nil
            self:_emit("removed", rec)
        end
    end
    for inst, rec in pairs(self.eggs) do
        rec.position = self:_getPosition(inst)
    end
end

function EggDetector:start()
    if self._scanning then return end
    self._scanning = true
    print("[EggDetector] v" .. EggDetector.VERSION .. " starting")
    task.spawn(function()
        while self._scanning do
            local ok, err = pcall(function() self:_refresh() end)
            if not ok then warn("[EggDetector] Refresh error:", err) end
            self:_emit("refreshed", nil)
            task.wait(1.5)
        end
    end)
end

function EggDetector:stop() self._scanning = false end

function EggDetector:getDistance(rec)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not rec.position then return math.huge end
    return (rec.position - hrp.Position).Magnitude
end

function EggDetector:getAll()
    local list = {}
    for _, rec in pairs(self.eggs) do table.insert(list, rec) end
    local function dist(rec) return self:getDistance(rec) end
    table.sort(list, function(a, b) return dist(a) < dist(b) end)
    return list
end

function EggDetector:getMatching(rarityFilter, areaFilter)
    local out = {}
    for _, rec in ipairs(self:getAll()) do
        local areaOK = true
        if areaFilter and areaFilter ~= "All" then
            areaOK = string.lower(rec.area or "") == string.lower(areaFilter)
        end
        local distOK = true
        if self.maxDistance and self.maxDistance < math.huge then
            distOK = self:getDistance(rec) <= self.maxDistance
        end
        if areaOK and distOK then table.insert(out, rec) end
    end
    return out
end

function EggDetector:getAreas()
    local seen, list = {}, {}
    local root = getRoot()
    if root then
        for _, area in ipairs(root:GetChildren()) do
            if not seen[area.Name] then
                seen[area.Name] = true
                table.insert(list, area.Name)
            end
        end
    end
    table.sort(list)
    return list
end

function EggDetector:getEggDatabase()
    return loadEggDatabase()
end

function EggDetector:dump()
    print("[EggDetector] === DUMP (" .. #self:getAll() .. " live eggs) ===")
    for i, rec in ipairs(self:getAll()) do
        print(string.format("  [%d] %s | area=%s | dist=%.1f",
            i, rec.name, rec.area, self:getDistance(rec)))
    end
end

return EggDetector
