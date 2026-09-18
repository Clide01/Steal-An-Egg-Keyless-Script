-- EggDetector.lua v4.0 — path-aware
-- Eggs live at: Workspace.__OBJECTS.Areas.GuardAreas.<AREA>.Nests.NestModel.Model

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local EggDetector = {}
EggDetector.__index = EggDetector
EggDetector.VERSION = "4.0.0"
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

-- Extract "Desert" / "Volcano" / etc. from
--   Workspace.__OBJECTS.Areas.GuardAreas.<AREA>.Nests...
local function extractArea(inst)
    local p = inst
    while p and p ~= workspace do
        local parent = p.Parent
        if parent and parent.Name == "GuardAreas" then
            return p.Name
        end
        p = parent
    end
    return "Unknown"
end

function EggDetector.new()
    local self = setmetatable({}, EggDetector)
    self.eggs = {}
    self.listeners = {}
    self._scanning = false
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
            for _, nest in ipairs(nests:GetChildren()) do
                -- Live egg is a "Model" child of NestModel
                local eggModel = nest:FindFirstChild("Model")
                if eggModel and eggModel:IsA("Model") then
                    out[eggModel] = true
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

function EggDetector:_buildRecord(inst)
    local pos = self:_getPosition(inst)
    local area = extractArea(inst)
    local displayName = inst.Name

    -- Prefer a TextLabel inside if present
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text and d.Text ~= "" then
            displayName = d.Text
            break
        end
    end

    -- Fallback: nest name might carry rarity
    local parent = inst.Parent
    if parent and parent.Name ~= "" and parent.Name ~= "Nests" then
        if not classifyRarity(displayName) then
            local combo = displayName .. " " .. parent.Name
            local r = classifyRarity(combo)
            if r then displayName = combo end
        end
    end

    return {
        instance = inst,
        target   = inst:FindFirstChildWhichIsA("BasePart", true),
        name     = displayName,
        area     = area,
        rarity   = classifyRarity(displayName),
        position = pos,
        prompt   = nil,
        stealable = true,
    }
end

function EggDetector:_refresh()
    local current = self:_scan()

    for inst in pairs(current) do
        if not self.eggs[inst] then
            local rec = self:_buildRecord(inst)
            if rec.position then
                self.eggs[inst] = rec
                self:_emit("added", rec)
            end
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
        rec.area = extractArea(inst)
    end

    if EggDetector.DEBUG then
        print(string.format("[EggDetector] %d live eggs tracked", #self:getAll()))
    end
end

function EggDetector:start()
    if self._scanning then return end
    self._scanning = true
    print("[EggDetector] v" .. EggDetector.VERSION .. " starting (nest-based)")
    task.spawn(function()
        while self._scanning do
            local ok, err = pcall(function() self:_refresh() end)
            if not ok then warn("[EggDetector] Refresh error:", err) end
            self:_emit("refreshed", nil)
            task.wait(1.5)
        end
    end)
end

function EggDetector:stop()
    self._scanning = false
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
    local all = self:getAll()
    local out = {}
    for _, rec in ipairs(all) do
        local rarityOK = true
        if rarityFilter and rarityFilter ~= "All" then
            rarityOK = rec.rarity and rec.rarity.label == rarityFilter
        end
        local areaOK = true
        if areaFilter and areaFilter ~= "All" then
            areaOK = string.lower(rec.area or "") == string.lower(areaFilter)
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

function EggDetector:getAreas()
    local seen = {}
    local list = {}
    local root = getRoot()
    if root then
        for _, area in ipairs(root:GetChildren()) do
            if not seen[area.Name] then
                seen[area.Name] = true
                table.insert(list, area.Name)
            end
        end
    end
    return list
end

function EggDetector:dump()
    print("[EggDetector] === DUMP (" .. #self:getAll() .. " live eggs) ===")
    for i, rec in ipairs(self:getAll()) do
        print(string.format("  [%d] %s | area=%s | rarity=%s | dist=%.1f",
            i, rec.name, rec.area, rec.rarity and rec.rarity.label or "?",
            self:getDistance(rec)))
    end
end

return EggDetector
