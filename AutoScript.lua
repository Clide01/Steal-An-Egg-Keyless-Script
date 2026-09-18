-- PlundererHub Full Scanner
-- Stand near eggs, then run. Paste ALL output.

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local RS = game:GetService("ReplicatedStorage")

local function sep(t)
    print("\n═══ " .. t .. " ═══")
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
        meshInfo = " mesh=" .. string.match(inst.MeshId, "%d+")
    elseif inst:IsA("SpecialMesh") and inst.MeshId ~= "" then
        meshInfo = " mesh=" .. string.match(inst.MeshId, "%d+")
    end
    print(string.format("%s[%s] %s%s%s", ind, inst.ClassName, inst.Name, attrs, meshInfo))
    if depth < maxDepth then
        for _, c in ipairs(inst:GetChildren()) do
            dumpInstance(c, depth + 1, maxDepth)
        end
    end
end

------------------------------------------------------------
sep("A) EGG STRUCTURE")
local root = workspace:FindFirstChild("__OBJECTS")
    and workspace.__OBJECTS:FindFirstChild("Areas")
    and workspace.__OBJECTS.Areas:FindFirstChild("GuardAreas")

if not root then warn("GuardAreas not found") return end

-- Build list of all live eggs
local eggs = {}
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
print(string.format("  Total live eggs: %d", #eggs))

-- Dump first 6 eggs in detail
for i = 1, math.min(6, #eggs) do
    local e = eggs[i]
    print(string.format("\n--- EGG %d [area=%s] ---", i, e.area))
    print("  Nest path :", e.nest:GetFullName())
    print("  Nest class:", e.nest.ClassName)
    print("  Nest attrs:")
    for k, v in pairs(e.nest:GetAttributes()) do
        print("    ", k, "=", tostring(v))
    end
    print("  Model dump:")
    dumpInstance(e.model, 1, 3)
end

------------------------------------------------------------
sep("B) EGG MESH IDs (unique list)")
local meshIds = {}
for _, e in ipairs(eggs) do
    for _, d in ipairs(e.model:GetDescendants()) do
        if d:IsA("MeshPart") and d.MeshId ~= "" then
            local n = string.match(d.MeshId, "%d+")
            if n then meshIds[n] = (meshIds[n] or 0) + 1 end
        elseif d:IsA("SpecialMesh") and d.MeshId ~= "" then
            local n = string.match(d.MeshId, "%d+")
            if n then meshIds[n] = (meshIds[n] or 0) + 1 end
        end
    end
end
for id, count in pairs(meshIds) do
    print(string.format("  mesh %s — used by %d eggs", id, count))
end

------------------------------------------------------------
sep("C) GAME'S OWN EGG DATABASE")
local function tryRequire(pathStr, ...)
    local obj = RS
    for _, part in ipairs({ ... }) do
        obj = obj:FindFirstChild(part)
        if not obj then return nil, "missing " .. part end
    end
    local ok, res = pcall(require, obj)
    if ok then return res else return nil, tostring(res) end
end

-- Try a few known locations
local testPaths = {
    {"Data", "Assets"},
    {"Shared", "Data", "Assets"},
    {"Shared", "Util", "EggRecords"},
    {"Shared", "Util", "AssetItems"},
    {"Data", "Eggs"},
    {"Modules", "Assets"},
}

for _, path in ipairs(testPaths) do
    local mod, err = tryRequire(table.concat(path, "."), unpack(path))
    print(string.format("  Path '%s' — %s", table.concat(path, "."), mod and "LOADED" or ("fail: " .. tostring(err))))
    if mod and type(mod) == "table" then
        local keys = {}
        for k in pairs(mod) do table.insert(keys, tostring(k)) end
        table.sort(keys)
        print("    keys: " .. table.concat(keys, ", "):sub(1, 500))
        if mod.Directory and type(mod.Directory) == "table" then
            local count = 0
            for _ in pairs(mod.Directory) do count = count + 1 end
            print("    .Directory has " .. count .. " entries")
            -- sample 5 entries
            local sampled = 0
            for k, v in pairs(mod.Directory) do
                if sampled >= 5 then break end
                sampled = sampled + 1
                print("      ", tostring(k), "=>", type(v), v and (v.DisplayName or v.Name) or "?")
            end
        end
    end
end

------------------------------------------------------------
sep("D) CHARACTER STATE & CONSTRAINTS")
local char = LP.Character
if char then
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hrp then
        print("  HRP pos       :", tostring(hrp.Position))
        print("  HRP anchored  :", hrp.Anchored)
        print("  HRP velocity  :", tostring(hrp.AssemblyLinearVelocity))
        print("  HRP massless  :", hrp.Massless)
        print("  HRP canCollide:", hrp.CanCollide)
        print("  HRP constraints:")
        for _, c in ipairs(hrp:GetChildren()) do
            if c:IsA("BodyVelocity") or c:IsA("BodyGyro") or c:IsA("BodyPosition")
            or c:IsA("LinearVelocity") or c:IsA("AlignPosition")
            or c:IsA("AlignOrientation") or c:IsA("Attachment") then
                print("    ", c.ClassName, c.Name)
            end
        end
    end
    if hum then
        print("  WalkSpeed     :", hum.WalkSpeed)
        print("  PlatformStand :", hum.PlatformStand)
        print("  JumpPower     :", hum.JumpPower)
        print("  MaxHealth     :", hum.MaxHealth)
        print("  Health        :", hum.Health)
        print("  State         :", tostring(hum:GetState()))
    end
    print("  Character children:")
    for _, c in ipairs(char:GetDescendants()) do
        if c:IsA("LocalScript") or c:IsA("Script") then
            print("    [script]", c.ClassName, c.Name)
        end
    end
else
    print("  No character")
end

------------------------------------------------------------
sep("E) WALKSPEED WRITE REMOTE ANALYSIS")
-- See what fires when WalkSpeed changes
local writeWS = RS:FindFirstChild("Packages")
    and RS.Packages:FindFirstChild("Networking")
    and RS.Packages.Networking:FindFirstChild("RE")
    and RS.Packages.Networking.RE:FindFirstChild("StaffConsole")
    and RS.Packages.Networking.RE.StaffConsole:FindFirstChild("WriteWalkSpeed")

if writeWS then
    print("  Found:", writeWS:GetFullName())
    print("  Class:", writeWS.ClassName)
    print("  (Note: this is server→client. We can hook OnClientEvent to see calls.)")
    -- Attach a temporary logger
    local tempConn
    tempConn = writeWS.OnClientEvent:Connect(function(...)
        print("  [WriteWalkSpeed fired]", ...)
    end)
    print("  Logger attached for 8s...")
    task.wait(8)
    tempConn:Disconnect()
    print("  Logger detached")
else
    print("  WriteWalkSpeed remote not found — different path")
end

------------------------------------------------------------
sep("F) SPEED TEST — walk normally, see what fires")
print("  Walking 100 studs forward for 2s...")
local hrp = char and char:FindFirstChild("HumanoidRootPart")
local hum = char and char:FindFirstChildOfClass("Humanoid")
if hrp and hum then
    local startPos = hrp.Position
    local startTime = tick()
    hum.WalkSpeed = 200
    hum:MoveTo(startPos + Vector3.new(100, 0, 0))
    task.wait(2)
    local endPos = hrp.Position
    local dist = (endPos - startPos).Magnitude
    print(string.format("  Requested WalkSpeed=200 for 2s"))
    print(string.format("  Actually traveled: %.1f studs (%.1f studs/s)", dist, dist / (tick() - startTime)))
    print(string.format("  Current WalkSpeed setting: %d", hum.WalkSpeed))
end

------------------------------------------------------------
sep("G) GAME'S OWN MOVEMENT CONSTRAINTS")
-- Look for anything attached to HRP by the game
if hrp then
    for _, c in ipairs(hrp:GetChildren()) do
        print("  HRP child:", c.ClassName, c.Name)
    end
end

------------------------------------------------------------
sep("SCAN COMPLETE")
print("Copy this entire log back.")
