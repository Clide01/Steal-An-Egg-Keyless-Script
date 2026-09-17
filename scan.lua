--[[
    Steal an Egg — Egg Catalog Scanner
    Goal: extract every egg-type asset from the game with metadata
    Output: EggCatalog.json (executor workspace)

    Run this once, then use the JSON as a static dropdown source.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

local out = {}
local function log(line)
    table.insert(out, line)
    print(line)
end

log("=================================================")
log("  EGG CATALOG SCANNER")
log("=================================================")
log("Date: " .. os.date("%Y-%m-%d %H:%M:%S"))
log("")

-- ============================================================
-- SAFE REQUIRES
-- ============================================================
local function safeRequire(inst)
    if not inst then return nil end
    local ok, result = pcall(function() return require(inst) end)
    if ok then return result end
    return nil
end

local AssetDir      = nil
local RarityModule  = nil
local AssetsModule  = nil
local EggRecords    = nil

do
    local ok, data = pcall(function()
        return require(ReplicatedStorage.Data.Assets)
    end)
    if ok and data then
        AssetsModule = data
        AssetDir = data.Directory
        log("✓ Loaded Assets.Directory (" .. (function()
            local n = 0
            for _ in pairs(AssetDir or {}) do n = n + 1 end
            return n
        end)() .. " entries)")
    else
        log("✗ Failed to load Assets.Directory")
    end
end

do
    local m = ReplicatedStorage.Data:FindFirstChild("Rarity")
    RarityModule = safeRequire(m)
    if RarityModule then
        log("✓ Loaded Data.Rarity")
    end
end

do
    local m = ReplicatedStorage.Shared.Util:FindFirstChild("EggRecords")
    EggRecords = safeRequire(m)
    if EggRecords then
        log("✓ Loaded Shared.Util.EggRecords")
    end
end

log("")

-- ============================================================
-- COLLECT ALL EGG-TYPE ASSETS
-- ============================================================
-- An "egg type" is any asset entry that:
--   1. Has an Egg config (i.e., can spawn as a field egg)
--   2. OR has a Rarity with a name containing "Egg"

local eggs = {}
local allNames = {}
local rarityNames = {}

for category, entry in pairs(AssetDir or {}) do
    if type(entry) == "table" then
        local isEgg = false
        local eggConf = entry.Egg

        if type(eggConf) == "table" then
            isEgg = true
        end

        -- Also include if ItemType or tags suggest egg
        if entry.ItemType == "PetEgg" or entry.ItemType == "AssetEgg" then
            isEgg = true
        end

        -- Also include anything where rarity DisplayName contains "Egg"
        local rarity = entry.Rarity
        local rarityName = rarity and rarity.DisplayName or nil
        if rarityName and string.find(string.lower(rarityName), "egg", 1, true) then
            isEgg = true
        end

        if isEgg then
            local display = entry.DisplayName or category
            local rarityNum = (rarity and rarity.RarityNumber) or 0
            local record = {
                category = category,
                displayName = display,
                rarity = rarityName or "Unknown",
                rarityNum = rarityNum,
                hasEggConfig = (type(eggConf) == "table"),
                eggIcon = (type(eggConf) == "table" and eggConf.Icon) or entry.Icon or nil,
                icon = entry.Icon or nil,
                description = entry.Description or nil,
                sources = {},
            }
            table.insert(eggs, record)
            allNames[display] = true
            allNames[category] = true
            if rarityName then rarityNames[rarityName] = (rarityNum or 0) end
        end
    end
end

log(string.format("Found %d egg-type assets", #eggs))
log("")

-- ============================================================
-- ENRICH WITH AREA SOURCES
-- ============================================================
-- Crawl Data.Areas to map which areas spawn which eggs
local Areas = safeRequire(ReplicatedStorage.Data:FindFirstChild("Areas"))
if Areas and type(Areas) == "table" then
    log("Crawling Data.Areas for source info...")
    local sourceCount = 0
    for areaName, areaConf in pairs(Areas) do
        if type(areaConf) == "table" then
            -- The config may have a list of spawnable eggs
            local eggPool = areaConf.Eggs or areaConf.EggPool or areaConf.FieldEggs
            if type(eggPool) == "table" then
                for _, eggCategory in ipairs(eggPool) do
                    if type(eggCategory) == "string" then
                        for _, rec in ipairs(eggs) do
                            if rec.category == eggCategory or rec.displayName == eggCategory then
                                table.insert(rec.sources, areaName)
                                sourceCount = sourceCount + 1
                            end
                        end
                    end
                end
            end
        end
    end
    log(string.format("  Mapped %d area sources", sourceCount))
else
    log("(Skipped area mapping — Data.Areas not available)")
end
log("")

-- ============================================================
-- FIND LIVE FIELD EGGS (from workspace nests)
-- ============================================================
-- Some field eggs may not be in AssetDir — catch them from the world
local nestAreas = {}
local areasRoot = workspace:FindFirstChild("__OBJECTS")
    and workspace.__OBJECTS:FindFirstChild("Areas")
    and workspace.__OBJECTS.Areas:FindFirstChild("GuardAreas")

if areasRoot then
    for _, area in ipairs(areasRoot:GetChildren()) do
        nestAreas[area.Name] = true
    end
end

log("Areas with nest slots:")
for areaName, _ in pairs(nestAreas) do
    log("  · " .. areaName)
end
log("")

-- ============================================================
-- SORT + OUTPUT
-- ============================================================
table.sort(eggs, function(a, b)
    if a.rarityNum ~= b.rarityNum then
        return a.rarityNum > b.rarityNum
    end
    return string.lower(a.displayName) < string.lower(b.displayName)
end)

log("=================================================")
log("  EGG CATALOG")
log("=================================================")
for i, rec in ipairs(eggs) do
    local sourceStr = #rec.sources > 0 and (" [" .. table.concat(rec.sources, ", ") .. "]") or ""
    log(string.format("%3d. %-30s  %-15s%s",
        i,
        rec.displayName,
        rec.rarity,
        sourceStr))
end
log("")

-- Rarity summary
log("=================================================")
log("  RARITY SUMMARY")
log("=================================================")
local rarityList = {}
for name, num in pairs(rarityNames) do
    table.insert(rarityList, { name = name, num = num })
end
table.sort(rarityList, function(a, b) return a.num > b.num end)
for _, r in ipairs(rarityList) do
    local count = 0
    for _, e in ipairs(eggs) do
        if e.rarity == r.name then count = count + 1 end
    end
    log(string.format("  %-15s (num=%3d)  %d entries", r.name, r.num, count))
end
log("")

-- ============================================================
-- BUILD JSON
-- ============================================================
local catalog = {
    generated = os.date("%Y-%m-%d %H:%M:%S"),
    totalEggs = #eggs,
    eggs = eggs,
    rarities = rarityList,
    areas = (function()
        local a = {}
        for name, _ in pairs(nestAreas) do table.insert(a, name) end
        table.sort(a)
        return a
    end)(),
}

local json = HttpService:JSONEncode(catalog)

log("=================================================")
log("  JSON READY")
log("=================================================")
log("Byte size: " .. #json)
log("")

-- Save to file
if writefile then
    local okSave, err = pcall(writefile, "EggCatalog.json", json)
    if okSave then
        print("[Scanner] Saved to workspace/EggCatalog.json")
    else
        warn("[Scanner] Could not save: " .. tostring(err))
    end
end

-- Also dump human-readable txt
local full = table.concat(out, "\n")
if writefile then
    pcall(writefile, "EggCatalog_Readable.txt", full)
    print("[Scanner] Also saved readable report to EggCatalog_Readable.txt")
end

log("")
log("=================================================")
log("  SCAN COMPLETE")
log("=================================================")
log("Send back the contents of EggCatalog.json.")
log("We'll use it as the static dropdown source.")
