-- EggDetector.lua v2.0 — strict matching
-- Requires: "steal" in a ProximityPrompt AND "egg" somewhere in the entity's text.
-- Rejects: players, pets, upgrade prompts, SpawnLocations.

local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local EggDetector = {}
EggDetector.__index = EggDetector
EggDetector.VERSION = "2.0.0"

-- Flip to true to print reject reasons in the console.
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

local function gatherAllText(inst)
    local texts = { inst.Name }
    for _, name in ipairs({ "Name", "EggName", "DisplayName", "Title", "Rarity", "Type" }) do
        local v = inst:GetAttribute(name)
        if type(v) == "string" and v ~= "" then table.insert(texts, v) end
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text and d.Text ~= "" then
            table.insert(texts, d.Text)
        elseif d:IsA("TextButton") and d.Text and d.Text ~= "" then
            table.insert(texts, d.Text)
        elseif d:IsA("ProximityPrompt") then
            if d.ActionText and d.ActionText ~= "" then table.insert(texts, d.ActionText) end
            if d.ObjectText and d.ObjectText ~= "" then table.insert(texts, d.ObjectText) end
        end
    end
    return table.concat(texts, " ")
end

local function hasForbiddenAncestor(inst)
    local p = inst
    while p do
        if p:IsA("Player") then return true, "under Player" end
        if p:IsA("Accessory") then return true, "under Accessory" end
        if p:IsA("Tool") then return true, "under Tool" end
        if p:IsA("Model") and p:FindFirstChildOfClass("Humanoid") then
            return true, "under Humanoid model"
        end
        p = p.Parent
    end
    return false, nil
end

local function isEggCandidate(inst)
    if inst:IsA("SpawnLocation") then return false, "SpawnLocation class" end
    if inst.Name == "SpawnLocation" then return false, "named SpawnLocation" end

    local bad, why = hasForbiddenAncestor(inst)
    if bad then return false, why end

    -- Must have a steal-like ProximityPrompt
    local hasSteal = false
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local pa = string.lower(d.ActionText or "")
            local po = string.lower(d.ObjectText or "")
            if string.find(pa, "steal", 1, true) or string.find(po, "steal", 1, true) then
                hasSteal = true
                break
            end
        end
    end
    if not hasSteal then return false, "no steal prompt" end

    -- Reject upgrade prompts (+12/step)
    local allText = gatherAllText(inst)
    local lower = string.lower(allText)
    if string.find(lower, "%+%d") or string.find(lower, "step", 1, true) then
        return false, "upgrade-like text"
    end

    -- Must contain "egg" somewhere OR be under an egg-named ancestor
    if string.find(lower, "egg", 1, true) then
        return true, "ok (egg in text)"
    end
    local p = inst.Parent
    while p and p ~= workspace do
        if string.find(string.lower(p.Name), "egg", 1, true) then
            return true, "ok (under egg-named ancestor)"
        end
        p = p.Parent
    end

    return false, "no 'egg' in text or ancestors"
end

-- =========================================================
-- Constructor
-- =========================================================
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

function EggDetector:_findPromptAndTarget(inst)
    local prompt
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local pa = string.lower(d.ActionText or "")
            local po = string.lower(d.ObjectText or "")
            if string.find(pa, "steal", 1, true) or string.find(po, "steal", 1, true) then
                prompt = d
                break
            end
        end
    end

    local target
    if inst:IsA("BasePart") then target = inst
    elseif inst:IsA("Model") then target = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    else target = inst:FindFirstChildWhichIsA("BasePart", true) end

    return prompt, target
end

function EggDetector:_buildRecord(inst)
    local prompt, target = self:_findPromptAndTarget(inst)
    local allText = gatherAllText(inst)
    local rarity = classifyRarity(allText)

    local displayName = inst.Name
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text and d.Text ~= "" then
            displayName = d.Text
            break
        end
    end

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
-- Workspace-wide scan
-- =========================================================
function EggDetector:_scan()
    local found = {}
    local rejected = {}
    local kept = 0

    for _, inst in ipairs(workspace:GetDescendants()) do
        -- Only check Models, Folders, and Parts — skip every BasePart inside a model
        if inst:IsA("Model") or inst:IsA("Folder") then
            local hasPrompt = false
            for _, d in ipairs(inst:GetDescendants()) do
                if d:IsA("ProximityPrompt") then hasPrompt = true; break end
            end
            if hasPrompt then
                local ok, reason = isEggCandidate(inst)
                if ok then
                    found[inst] = true
                    kept = kept + 1
                elseif EggDetector.DEBUG then
                    table.insert(rejected, { name = inst:GetFullName(), reason = reason })
                end
            end
        elseif inst:IsA("BasePart") and not inst:FindFirstAncestorWhichIsA("Model") then
            -- standalone part with a prompt
            local hasPrompt = false
            for _, d in ipairs(inst:GetDescendants()) do
                if d:IsA("ProximityPrompt") then hasPrompt = true; break end
            end
            if hasPrompt then
                local ok, reason = isEggCandidate(inst)
                if ok then
                    found[inst] = true
                    kept = kept + 1
                elseif EggDetector.DEBUG then
                    table.insert(rejected, { name = inst:GetFullName(), reason = reason })
                end
            end
        end
    end

    if EggDetector.DEBUG then
        print(string.format("[EggDetector] Scan: %d kept, %d rejected", kept, #rejected))
        for i = 1, math.min(#rejected, 40) do
            print(string.format("   ✗ %s — %s", rejected[i].name, rejected[i].reason))
        end
    end

    return found
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
        local _, t = self:_findPromptAndTarget(inst)
        if t then
            rec.target = t
            rec.position = t.Position
        end
    end
end

function EggDetector:start()
    if self._scanning then return end
    self._scanning = true
    print("[EggDetector] v" .. EggDetector.VERSION .. " starting — strict mode")

    task.spawn(function()
        while self._scanning do
            local ok, err = pcall(function() self:_refresh() end)
            if not ok then warn("[EggDetector] Refresh error:", err) end
            self:_emit("refreshed", nil)
            task.wait(2)
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

-- Call this from anywhere to see what the detector currently tracks.
function EggDetector:dump()
    print("[EggDetector] === DUMP ===")
    for i, rec in ipairs(self:getAll()) do
        print(string.format("  [%d] %s | rarity=%s | dist=%.1f | %s",
            i, rec.name, rec.rarity and rec.rarity.label or "?",
            self:getDistance(rec), rec.instance:GetFullName()))
    end
end

return EggDetector
