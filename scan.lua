--[[
    Steal an Egg — Field Egg Scanner
    Goal: capture the exact structure of field eggs, spawn events,
          and the grab/drop remote args.

    Usage:
      1. Run this in-game
      2. Walk near field eggs (or just play normally for 30-60 seconds)
      3. Try to manually grab an egg
      4. Copy everything from the console OR check the saved file

    Output file: EggScan.txt (in executor workspace)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Load remotes table
-- ============================================================
local ok, Remotes = pcall(require, ReplicatedStorage.Shared.Remotes)
if not ok or not Remotes or not Remotes.EggWorld then
    warn("[EggScan] Could not load EggWorld remotes")
    return
end

local E = Remotes.EggWorld

-- ============================================================
-- Output buffer
-- ============================================================
local out = {}
local function log(line)
    table.insert(out, line)
    print(line)
end

log("=================================================")
log("  FIELD EGG SCANNER STARTED")
log("=================================================")
log("Date: " .. os.date("%Y-%m-%d %H:%M:%S"))
log("")

-- ============================================================
-- Recursive dumper
-- ============================================================
local function dumpValue(v, indent, depth, seen)
    indent = indent or ""
    depth  = depth or 0
    seen   = seen or {}

    local t = typeof(v)

    if t == "Instance" then
        log(indent .. "(Instance) " .. v:GetFullName())
        return
    end

    if t ~= "table" then
        log(indent .. "(" .. t .. ") " .. tostring(v))
        return
    end

    if depth > 4 then
        log(indent .. "... (max depth)")
        return
    end

    if seen[v] then
        log(indent .. "(cycle)")
        return
    end
    seen[v] = true

    -- Count entries
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    log(indent .. "(table) size=" .. n)

    local shown = 0
    for k, val in pairs(v) do
        shown = shown + 1
        if shown > 30 then
            log(indent .. "  ...(" .. (n - 30) .. " more)")
            break
        end

        local kt = typeof(k)
        if typeof(val) == "table" then
            log(indent .. "  [" .. tostring(k) .. "](" .. kt .. ") = table:")
            dumpValue(val, indent .. "    ", depth + 1, seen)
        elseif typeof(val) == "Instance" then
            log(indent .. "  [" .. tostring(k) .. "] = Instance: " .. val:GetFullName())
        else
            log(indent .. "  [" .. tostring(k) .. "](" .. kt .. ") = (" .. typeof(val) .. ") " .. tostring(val))
        end
    end
end

-- ============================================================
-- Log call (both directions)
-- ============================================================
local callCount = 0
local function logCall(direction, remoteName, args)
    callCount = callCount + 1
    log("")
    log("########## CAPTURE #" .. callCount .. " ##########")
    log("Direction: " .. direction)
    log("Remote:    EggWorld." .. remoteName)
    log("Arg count: " .. #args)
    for i = 1, #args do
        log("--- arg[" .. i .. "] ---")
        dumpValue(args[i], "  ")
    end
    log("########## END #" .. callCount .. " ##########")
    log("")
end

-- ============================================================
-- Hook outgoing FireServer / InvokeServer
-- ============================================================
local OUT_REMOTES = {
    { name = "AskFieldEggCarry",       remote = E.AskFieldEggCarry },
    { name = "AskFieldEggDrop",        remote = E.AskFieldEggDrop },
    { name = "AskFieldEggSnapshot",    remote = E.AskFieldEggSnapshot },
    { name = "AskFieldEggRarityShows", remote = E.AskFieldEggRarityShows },
    { name = "AskEggRecord",           remote = E.AskEggRecord },
    { name = "AskHatch",               remote = E.AskHatch },
    { name = "AskFinishHatch",         remote = E.AskFinishHatch },
    { name = "AskSkipGrowth",          remote = E.AskSkipGrowth },
    { name = "AskPlaceEgg",            remote = E.AskPlaceEgg },
    { name = "AskLiveSnapshot",        remote = E.AskLiveSnapshot },
}

local lookupOut = {}
for _, r in ipairs(OUT_REMOTES) do
    if r.remote then
        lookupOut[r.remote] = r.name
    end
end

local hookInstalled = false
if typeof(hookmetamethod) == "function" and typeof(getnamecallmethod) == "function" then
    local ok2 = pcall(function()
        local old
        old = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then
                local friendly = lookupOut[self]
                if friendly then
                    logCall("OUTGOING (" .. method .. ")", friendly, { ... })
                end
            end
            return old(self, ...)
        end)
    end)
    hookInstalled = ok2
end

if not hookInstalled then
    warn("[EggScan] Could not install __namecall hook. Falling back to OnClientEvent only.")
end

-- ============================================================
-- Listen for INCOMING server → client events
-- ============================================================
local IN_REMOTES = {
    { name = "FieldEggShifted",        remote = E.FieldEggShifted },
    { name = "FieldEggBatchShifted",   remote = E.FieldEggBatchShifted },
    { name = "FieldEggRaritiesShown",  remote = E.FieldEggRaritiesShown },
    { name = "FieldEggGone",           remote = E.FieldEggGone },
    { name = "FieldEggCycleCountdown", remote = E.FieldEggCycleCountdown },
    { name = "OwnerDropped",           remote = E.OwnerDropped },
    { name = "OwnerShifted",           remote = E.OwnerShifted },
    { name = "FieldEggCarry",          remote = E.FieldEggCarry },
    { name = "FieldEggRedeemVerdict",  remote = E.FieldEggRedeemVerdict },
}

for _, r in ipairs(IN_REMOTES) do
    if r.remote then
        pcall(function()
            r.remote.OnClientEvent:Connect(function(...)
                logCall("INCOMING", r.name, { ... })
            end)
        end)
    end
end

-- ============================================================
-- Scan Workspace for visible egg objects
-- ============================================================
log("")
log("=================================================")
log("  WORKSPACE SCAN — egg-like instances")
log("=================================================")

local eggMatches = 0
for _, obj in ipairs(Workspace:GetDescendants()) do
    local lower = string.lower(obj.Name)
    if string.find(lower, "egg", 1, true) then
        eggMatches = eggMatches + 1
        if eggMatches <= 60 then
            log(string.format("  [%s] %s", obj.ClassName, obj:GetFullName()))
        end
    end
end
log("")
log("Total egg-named instances: " .. eggMatches)
if eggMatches > 60 then
    log("  (showing first 60)")
end

-- ============================================================
-- Scan for typical field egg folders
-- ============================================================
log("")
log("=================================================")
log("  FOLDER SCAN — common containers")
log("=================================================")

local commonPaths = {
    "Workspace.Stands",
    "Workspace.Eggs",
    "Workspace.FieldEggs",
    "Workspace.SpawnedEggs",
    "Workspace.__OBJECTS",
    "Workspace.__OBJECTS.Areas",
    "Workspace.__OBJECTS.Eggs",
    "Workspace.__OBJECTS.Areas.EggWorld",
}

for _, path in ipairs(commonPaths) do
    local obj = Workspace
    for part in string.gmatch(path, "[^%.]+") do
        if obj then obj = obj:FindFirstChild(part) end
    end
    if obj then
        log(string.format("  ✓ %s  [%s]", path, obj.ClassName))
        local children = obj:GetChildren()
        if #children > 0 and #children <= 20 then
            for _, c in ipairs(children) do
                log(string.format("      → %s [%s]", c.Name, c.ClassName))
            end
        else
            log(string.format("      (%d children)", #children))
        end
    end
end

-- ============================================================
-- Optionally, inspect a sample egg instance if found
-- ============================================================
log("")
log("=================================================")
log("  SAMPLE EGG INSPECTION")
log("=================================================")

local sampleEgg
for _, obj in ipairs(Workspace:GetDescendants()) do
    if obj:IsA("BasePart") or obj:IsA("Model") then
        local lower = string.lower(obj.Name)
        if string.find(lower, "egg", 1, true) then
            sampleEgg = obj
            break
        end
    end
end

if sampleEgg then
    log("Found sample: " .. sampleEgg:GetFullName() .. " [" .. sampleEgg.ClassName .. "]")
    log("Children:")
    for _, c in ipairs(sampleEgg:GetChildren()) do
        log(string.format("  → %s [%s]", c.Name, c.ClassName))
        if c:IsA("StringValue") or c:IsA("NumberValue") or c:IsA("BoolValue") then
            log("       value = " .. tostring(c.Value))
        end
    end
    log("")
    log("Attributes:")
    for k, v in pairs(sampleEgg:GetAttributes()) do
        log(string.format("  %s = (%s) %s", k, typeof(v), tostring(v)))
    end
else
    log("No sample egg found nearby.")
end

-- ============================================================
-- Snapshot on demand
-- ============================================================
log("")
log("=================================================")
log("  FETCHING LIVE SNAPSHOT")
log("=================================================")

if E.AskFieldEggSnapshot then
    task.spawn(function()
        local ok3, result = pcall(function()
            return E.AskFieldEggSnapshot:InvokeServer()
        end)
        if ok3 and result then
            log("Snapshot result:")
            dumpValue(result, "  ")
        else
            log("Snapshot failed or returned nil: " .. tostring(result))
        end
    end)
end

-- ============================================================
-- Save to file
-- ============================================================
task.delay(15, function()
    log("")
    log("=================================================")
    log("  SCAN COMPLETE")
    log("=================================================")
    log("Total captures: " .. callCount)
    log("Total lines: " .. #out)

    local full = table.concat(out, "\n")

    if writefile then
        local okSave, err = pcall(writefile, "EggScan.txt", full)
        if okSave then
            print("[EggScan] Saved to workspace/EggScan.txt")
        else
            warn("[EggScan] Could not save file: " .. tostring(err))
        end
    else
        warn("[EggScan] writefile not available — copy console output manually")
    end
end)

log("")
log("=================================================")
log("  SCANNER ACTIVE — 15 seconds to collect data")
log("=================================================")
log("  What to do now:")
log("    1. Walk toward a field egg (visible in world)")
log("    2. Stand near it or click to grab it")
log("    3. Try dropping it if you can (hold + drop)")
log("    4. Watch the console for CAPTURE lines")
log("")
log("  After 15 seconds, the file EggScan.txt will save.")
log("=================================================")
log("")
