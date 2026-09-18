-- EggDetector.lua v4.2 — tries game's own egg database first
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggDetector = {}
EggDetector.__index = EggDetector
EggDetector.VERSION = "4.2.0"
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

-- Try loading the game's own egg directory. Returns { meshIdKey -> name }
local eggDirectoryCache = nil
local function loadEggDirectory()
    if eggDirectoryCache ~= nil then return eggDirectoryCache end
    eggDirectoryCache = {}

    -- Try the module path we saw in earlier game scripts
    local paths = {
        { ReplicatedStorage, "Data", "Assets" },
        { ReplicatedStorage, "Shared", "Data", "Assets" },
        { ReplicatedStorage, "Shared", "Util", "EggRecords" },
        { ReplicatedStorage, "Data", "Eggs" },
    }
    for _, path in ipairs(paths) do
        local ok, mod = pcall(function()
            local obj = path[1]
            for i = 2, #path do
                obj = obj:FindFirstChild(path[i])
                if not obj then return nil end
            end
            return require(obj)
        end)
        if ok and mod then
            print("[EggDetector] Loaded module:", table.concat(path, "."))
            return eggDirectoryCache
        end
    end
    return eggDirectoryCache
end

-- Extract best-guess name for a Model, walking many sources
local function extractEggName(model, area)
    -- 1) Attributes on model
    for _, attr in ipairs({ "Name", "EggName", "DisplayName", "Title", "EggType", "Rarity", "Egg" }) do
        local v = model:GetAttribute(attr)
        if type(v) == "string" and v ~= "" then return v, "attr:"..attr end
    end
    -- 2) Attributes on nest (parent)
    if model.Parent then
        for _, attr in ipairs({ "Name", "EggName", "DisplayName", "Rarity", "EggType" }) do
            local v = model.Parent:GetAttribute(attr)
            if type(v) == "string" and v ~= "" then return v, "nestAttr:"..attr end
        end
    end
    -- 3) StringValue descendants
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("StringValue") and d.Value and d.Value ~= "" then
            return d.Value, "stringValue:"..d.Name
        end
    end
    -- 4) TextLabels
    for _, d in ipairs(model:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text and d.Text ~= "" then
            -- skip common UI words
            local t = d.Text
            if #t > 2 and not t:match("^%s*$") then
                return t, "textLabel"
            end
        end
    end

    -- 5) Look for the game's own egg-name mapping from mesh ID
    local ids = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("MeshPart") and d.MeshId and d.MeshId ~= "" then
            local n = string.match(d.MeshId, "%d+")
            if n then table.insert(ids, n) end
        elseif d:IsA("SpecialMesh") and d.MeshId and d.MeshId ~= "" then
            local n = string.match(d.MeshId, "%d+")
            if n then table.insert(ids, n) end
        end
    end
    if #ids > 0 then
        table.sort(ids)
        -- Look up in the loaded directory
        local dir = loadEggDirectory()
        if dir then
            for _, id in ipairs(ids) do
                if dir[id] then return dir[id], "directory" end
            end
        end
        -- Otherwise use a readable 4-digit signature
        local sig = ids[1]:sub(-4)
        return string.format("%s Egg (%s)", area or "Unknown", sig), "meshId"
    end

    -- 6) Fallback
    return "Unidentified " .. area .. " Egg", "fallback"
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
            for _, nest in ipairs(nests:GetChildren()) do
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
    local name, source = extractEggName(inst, area)
    local rarity = classifyRarity(name)
    if not rarity then rarity = classifyRarity(inst:GetFullName()) end

    return {
        instance = inst,
        target   = inst:FindFirstChildWhichIsA("BasePart", true),
        name     = name,
        nameSource = source,
        area     = area,
        rarity   = rarity,
        position = pos,
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
            areaOK = string.lower(rec.area or "") == string.lower(areaFilter)
        end
        local distOK = true
        if self.maxDistance and self.maxDistance < math.huge then
            distOK = self:getDistance(rec) <= self.maxDistance
        end
        if rarityOK and areaOK and distOK then table.insert(out, rec) end
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

function EggDetector:dump()
    print("[EggDetector] === DUMP (" .. #self:getAll() .. " live eggs) ===")
    for i, rec in ipairs(self:getAll()) do
        print(string.format("  [%d] %s | area=%s | rarity=%s | dist=%.1f | src=%s",
            i, rec.name, rec.area,
            rec.rarity and rec.rarity.label or "?",
            self:getDistance(rec), rec.nameSource or "?"))
    end
end

return EggDetector
