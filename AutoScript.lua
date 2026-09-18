-- PlundererHub Scanner v2 — writes to file
-- Run near eggs. Afterwards, find the file in your executor's workspace folder.

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local RS = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════════
-- Logger — captures to buffer, writes to file at end
-- ═══════════════════════════════════════════════════════════
local BUFFER = {}
local function log(fmt, ...)
    local line
    if select("#", ...) > 0 then
        line = string.format(fmt, ...)
    else
        line = tostring(fmt)
    end
    table.insert(BUFFER, line)
    print(line)  -- also show in console so user sees progress
end

local function sep(t)
    log("")
    log("════════════════════════════════════════════════════")
    log("  " .. t)
    log("════════════════════════════════════════════════════")
end

local function dumpInstance(inst, depth, maxDepth)
    depth = depth or 0
    maxDepth = maxDepth or 3
    if depth > maxDepth then return end
    local ind = string.rep("  ", depth)
    local attrs = ""
    for k, v in pairs(inst:GetAttributes()) do
        attrs = attrs .. string.format(" [%s=%s]", k, tostring(v))
    end
    local meshInfo = ""
    if inst:IsA("MeshPart") and inst.MeshId ~= "" then
        meshInfo = " mesh=" .. (string.match(inst.MeshId, "%d+") or "?")
    elseif inst:IsA("SpecialMesh") and inst.MeshId ~= "" then
        meshInfo = " mesh=" .. (string.match(inst.MeshId, "%d+") or "?")
    end
    log("%s[%s] %s%s%s", ind, inst.ClassName, inst.Name, attrs, meshInfo)
    if depth < maxDepth then
        for _, c in ipairs(inst:GetChildren()) do
            dumpInstance(c, depth + 1, maxDepth)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- HEADER
-- ═══════════════════════════════════════════════════════════
log("PlundererHub Scanner v2")
log("Generated: " .. os.date("%Y-%m-%d %H:%M:%S"))
log("Player   : " .. LP.Name .. " (" .. LP.UserId .. ")")
log("Game     : " .. game.PlaceId)

-- ═══════════════════════════════════════════════════════════
-- A) EGG STRUCTURE
-- ═══════════════════════════════════════════════════════════
sep("A) EGG STRUCTURE")

local root = workspace:FindFirstChild("__OBJECTS")
    and workspace.__OBJECTS:FindFirstChild("Areas")
    and workspace.__OBJECTS.Areas:FindFirstChild("GuardAreas")

local eggs = {}
if root then
    for _, area in ipairs(root:GetChildren()) do
        local nests = area:FindFirstChild("Nests")
        if nests then
            for _, nest in ipairs(nests:GetChildren()) do
                local m = nest:FindFirstChild("Model")
                if m and m:IsA("Model") then
                    table.insert(eggs, { model = m, nest = nest, area = area.Name })
                end
            end
        end
    end
    log("  Total live eggs: %d", #eggs)

    for i = 1, math.min(6, #eggs) do
        local e = eggs[i]
        log("")
        log("--- EGG %d [area=%s] ---", i, e.area)
        log("  Nest path : %s", e.nest:GetFullName())
        log("  Nest class: %s", e.nest.ClassName)
        log("  Nest attrs:")
        for k, v in pairs(e.nest:GetAttributes()) do
            log("    %s = %s", k, tostring(v))
        end
        log("  Model dump:")
        dumpInstance(e.model, 1, 3)
    end
else
    log("  !! GuardAreas not found")
end

-- ═══════════════════════════════════════════════════════════
-- B) MESH IDs
-- ═══════════════════════════════════════════════════════════
sep("B) EGG MESH IDs (unique list)")

local meshIds = {}
for _, e in ipairs(eggs) do
    for _, d in ipairs(e.model:GetDescendants()) do
        local id
        if d:IsA("MeshPart") and d.MeshId ~= "" then
            id = string.match(d.MeshId, "%d+")
        elseif d:IsA("SpecialMesh") and d.MeshId ~= "" then
            id = string.match(d.MeshId, "%d+")
        end
        if id then meshIds[id] = (meshIds[id] or 0) + 1 end
    end
end

local sortedIds = {}
for id, count in pairs(meshIds) do
    table.insert(sortedIds, { id = id, count = count })
end
table.sort(sortedIds, function(a, b) return a.count > b.count end)

for _, e in ipairs(sortedIds) do
    log("  mesh %s — used by %d eggs", e.id, e.count)
end

-- ═══════════════════════════════════════════════════════════
-- C) GAME'S OWN EGG DATABASE
-- ═══════════════════════════════════════════════════════════
sep("C) GAME'S OWN EGG DATABASE")

local function tryRequireModule(pathStr, ...)
    local obj = RS
    for _, part in ipairs({ ... }) do
        obj = obj:FindFirstChild(part)
        if not obj then return nil, "missing " .. part end
    end
    local ok, res = pcall(require, obj)
    if ok then return res else return nil, tostring(res) end
end

local testPaths = {
    {"Data", "Assets"},
    {"Shared", "Data", "Assets"},
    {"Shared", "Util", "EggRecords"},
    {"Shared", "Util", "AssetItems"},
    {"Data", "Eggs"},
    {"Modules", "Assets"},
    {"Shared", "Assets"},
    {"Assets"},
}

for _, path in ipairs(testPaths) do
    local mod, err = tryRequireModule(table.concat(path, "."), unpack(path))
    log("  Path '%s' — %s", table.concat(path, "."), mod and "LOADED" or ("fail: " .. tostring(err)))
    if mod and type(mod) == "table" then
        local keys = {}
        for k in pairs(mod) do table.insert(keys, tostring(k)) end
        table.sort(keys)
        log("    keys: %s", table.concat(keys, ", "):sub(1, 800))

        if mod.Directory and type(mod.Directory) == "table" then
            local count = 0
            for _ in pairs(mod.Directory) do count = count + 1 end
            log("    .Directory has %d entries", count)

            -- Dump every single entry — this is the naming database
            local entries = {}
            for k, v in pairs(mod.Directory) do
                table.insert(entries, { key = tostring(k), val = v })
            end
            table.sort(entries, function(a, b) return a.key < b.key end)

            for i, e in ipairs(entries) do
                if i > 300 then
                    log("    ... (%d more entries truncated)", #entries - 300)
                    break
                end
                local name = "?"
                local rar = "?"
                local category = "?"
                if type(e.val) == "table" then
                    name = e.val.DisplayName or e.val.Name or "?"
                    category = e.val.Category or e.val.Type or "?"
                    if e.val.Rarity then
                        rar = e.val.Rarity.DisplayName or tostring(e.val.Rarity)
                    end
                end
                log("      %s => %s | cat=%s | rarity=%s",
                    e.key, tostring(name), tostring(category), tostring(rar))
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- D) CHARACTER STATE
-- ═══════════════════════════════════════════════════════════
sep("D) CHARACTER STATE")

local char = LP.Character
if char then
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hrp then
        log("  HRP pos       : %s", tostring(hrp.Position))
        log("  HRP anchored  : %s", tostring(hrp.Anchored))
        log("  HRP velocity  : %s", tostring(hrp.AssemblyLinearVelocity))
        log("  HRP massless  : %s", tostring(hrp.Massless))
        log("  HRP canCollide: %s", tostring(hrp.CanCollide))
        log("  HRP constraints:")
        for _, c in ipairs(hrp:GetChildren()) do
            if c:IsA("BodyVelocity") or c:IsA("BodyGyro") or c:IsA("BodyPosition")
            or c:IsA("LinearVelocity") or c:IsA("AlignPosition")
            or c:IsA("AlignOrientation") or c:IsA("Attachment") then
                log("    %s %s", c.ClassName, c.Name)
            end
        end
    end
    if hum then
        log("  WalkSpeed     : %d", hum.WalkSpeed)
        log("  PlatformStand : %s", tostring(hum.PlatformStand))
        log("  JumpPower     : %d", hum.JumpPower)
        log("  MaxHealth     : %d", hum.MaxHealth)
        log("  Health        : %d", hum.Health)
        pcall(function() log("  State         : %s", tostring(hum:GetState())) end)
    end
    log("  Character scripts:")
    for _, c in ipairs(char:GetDescendants()) do
        if c:IsA("LocalScript") or c:IsA("Script") then
            log("    [%s] %s", c.ClassName, c.Name)
        end
    end
else
    log("  No character")
end

-- ═══════════════════════════════════════════════════════════
-- E) WALKSPEED REMOTE ANALYSIS
-- ═══════════════════════════════════════════════════════════
sep("E) WALKSPEED REMOTE")

local writeWS = RS:FindFirstChild("Packages")
    and RS.Packages:FindFirstChild("Networking")
    and RS.Packages.Networking:FindFirstChild("RE")
    and RS.Packages.Networking.RE:FindFirstChild("StaffConsole")
    and RS.Packages.Networking.RE.StaffConsole:FindFirstChild("WriteWalkSpeed")

if writeWS then
    log("  Found: %s", writeWS:GetFullName())
    log("  Class: %s", writeWS.ClassName)
    log("  Attaching logger for 6 seconds...")

    local captured = {}
    local tempConn
    tempConn = writeWS.OnClientEvent:Connect(function(...)
        local args = {...}
        local parts = {}
        for _, v in ipairs(args) do
            table.insert(parts, tostring(v))
        end
        table.insert(captured, table.concat(parts, ", "))
    end)

    task.wait(6)
    tempConn:Disconnect()

    if #captured > 0 then
        log("  Captured %d events:", #captured)
        for i, c in ipairs(captured) do
            if i > 20 then
                log("    ... (%d more)", #captured - 20)
                break
            end
            log("    [%d] %s", i, c)
        end
    else
        log("  No events captured (server doesn't push WalkSpeed)")
    end
else
    log("  WriteWalkSpeed remote not found")
end

-- ═══════════════════════════════════════════════════════════
-- F) SPEED TEST
-- ═══════════════════════════════════════════════════════════
sep("F) SPEED TEST")

local hrp = char and char:FindFirstChild("HumanoidRootPart")
local hum = char and char:FindFirstChildOfClass("Humanoid")

if hrp and hum then
    local startPos = hrp.Position
    local startTime = tick()
    local oldWS = hum.WalkSpeed

    hum.WalkSpeed = 200
    pcall(function() hum:MoveTo(startPos + Vector3.new(100, 0, 0)) end)
    task.wait(2)

    local endPos = hrp.Position
    local dist = (endPos - startPos).Magnitude
    local elapsed = tick() - startTime

    log("  Requested WalkSpeed: 200 for 2s")
    log("  Actually traveled  : %.1f studs (%.1f studs/s)", dist, dist / elapsed)
    log("  WalkSpeed after    : %d (was %d)", hum.WalkSpeed, oldWS)
    log("  (If the value reverted to ~100, the server is clamping)")
end

-- ═══════════════════════════════════════════════════════════
-- G) FLIGHT TEST — try LinearVelocity
-- ═══════════════════════════════════════════════════════════
sep("G) FLIGHT TEST — LinearVelocity")

if hrp and hum then
    local startPos = hrp.Position
    local targetPos = startPos + Vector3.new(0, 50, 0)  -- straight up

    hum.PlatformStand = true
    hum.WalkSpeed = 0

    local attach = Instance.new("Attachment")
    attach.Name = "ScanAttach"
    attach.Parent = hrp

    local lv = Instance.new("LinearVelocity")
    lv.Name = "ScanLV"
    lv.Attachment0 = attach
    lv.MaxForce = math.huge
    lv.VectorVelocity = Vector3.new(0, 100, 0)  -- 100 studs/sec up
    lv.RelativeTo = Enum.ActuatorRelativeTo.World
    lv.Parent = hrp

    log("  Applying LinearVelocity up at 100 studs/s for 1.5s...")
    task.wait(1.5)

    local endPos = hrp.Position
    local verticalGain = endPos.Y - startPos.Y

    lv:Destroy()
    attach:Destroy()
    hum.PlatformStand = false
    hum.WalkSpeed = 16

    log("  Vertical gain: %.1f studs", verticalGain)
    log("  Expected     : ~150 studs (100 studs/s for 1.5s)")
    if verticalGain > 50 then
        log("  ✓ LinearVelocity WORKS on this game")
    else
        log("  ✗ LinearVelocity was blocked/reverted")
    end
end

-- ═══════════════════════════════════════════════════════════
-- H) FLIGHT TEST — CFrame stepping
-- ═══════════════════════════════════════════════════════════
sep("H) FLIGHT TEST — CFrame Stepping")

if hrp then
    local RunService = game:GetService("RunService")
    local startPos = hrp.Position
    local targetPos = startPos + Vector3.new(0, 30, 0)

    local deadline = tick() + 1.5
    local steps = 0
    while tick() < deadline do
        local current = hrp.Position
        local delta = targetPos - current
        local dist = delta.Magnitude
        if dist < 1 then break end
        local step = math.min(5, dist)
        pcall(function()
            hrp.CFrame = CFrame.new(current + delta.Unit * step)
        end)
        steps = steps + 1
        RunService.Heartbeat:Wait()
    end

    local endPos = hrp.Position
    local verticalGain = endPos.Y - startPos.Y
    log("  Steps: %d", steps)
    log("  Vertical gain: %.1f studs (expected ~30)", verticalGain)
    if verticalGain > 20 then
        log("  ✓ CFrame stepping WORKS")
    else
        log("  ✗ CFrame stepping was blocked/reverted")
    end
end

-- ═══════════════════════════════════════════════════════════
-- WRITE TO FILE
-- ═══════════════════════════════════════════════════════════
sep("SCAN COMPLETE — WRITING FILE")

local fileName = string.format("plundererhub_scan_%d.txt", os.time())
local content = table.concat(BUFFER, "\n")

local writeOK, writeErr = pcall(function()
    writefile(fileName, content)
end)

if writeOK then
    local fullPath = "?"
    pcall(function() fullPath = getcustomasset(fileName) end)
    -- getcustomasset returns an rbasset:// path; actual OS path depends on executor
    log("  ✓ File written: %s", fileName)
    log("  Bytes: %d", #content)
    log("")
    log("  Find it in your executor's workspace folder. Common locations:")
    log("    - Same folder as your executor .exe")
    log("    - %%LOCALAPPDATA%%\\<ExecutorName>\\workspace\\")
    log("    - %%APPDATA%%\\<ExecutorName>\\workspace\\")
    log("")
    log("  Paste the file contents into chat.")
else
    log("  ✗ writefile failed: %s", tostring(writeErr))
    log("")
    log("  Falling back: dumping last 200 lines to console...")
    local start = math.max(1, #BUFFER - 200)
    for i = start, #BUFFER do
        print(BUFFER[i])
    end
    log("  (Copy from console — the earlier part is above this line)")
end
