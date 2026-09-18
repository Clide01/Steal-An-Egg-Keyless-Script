-- PlundererHub — Full Scanner
-- Stand near an egg, then run this. Paste ALL output.

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local function sep(title)
    print("\n═══════════════════════════════════════")
    print("  " .. title)
    print("═══════════════════════════════════════")
end

local function dumpInstance(inst, depth, maxDepth)
    depth = depth or 0
    maxDepth = maxDepth or 3
    if depth > maxDepth then return end
    local indent = string.rep("  ", depth)
    local attrs = ""
    for k, v in pairs(inst:GetAttributes()) do
        attrs = attrs .. string.format(" [%s=%s]", k, tostring(v))
    end
    print(string.format("%s[%s] %s%s", indent, inst.ClassName, inst.Name, attrs))
    if depth < maxDepth then
        for _, c in ipairs(inst:GetChildren()) do
            dumpInstance(c, depth + 1, maxDepth)
        end
    end
end

------------------------------------------------------------
-- 1) SmartPromptPart — full structure
------------------------------------------------------------
sep("1) SmartPromptPart")
local spp = workspace:FindFirstChild("SmartPromptPart")
if spp then
    dumpInstance(spp, 0, 2)
    local prompt = spp:FindFirstChild("CarryAreaEgg")
    if prompt then
        print("\n  Prompt properties:")
        print("    ActionText         =", prompt.ActionText)
        print("    ObjectText         =", prompt.ObjectText)
        print("    HoldDuration       =", prompt.HoldDuration)
        print("    MaxActivationDist  =", prompt.MaxActivationDistance)
        print("    Enabled            =", prompt.Enabled)
        print("    RequiresLineOfSight=", prompt.RequiresLineOfSight)
        print("    KeyboardKeyCode    =", prompt.KeyboardKeyCode)
    end
else
    warn("  SmartPromptPart NOT FOUND")
end

------------------------------------------------------------
-- 2) All live eggs — full structure of first 3
------------------------------------------------------------
sep("2) Live eggs — first 3 detailed")
local root = workspace:FindFirstChild("__OBJECTS")
    and workspace.__OBJECTS:FindFirstChild("Areas")
    and workspace.__OBJECTS.Areas:FindFirstChild("GuardAreas")

local eggCount = 0
local shown = 0
local eggs = {}
if root then
    for _, area in ipairs(root:GetChildren()) do
        local nests = area:FindFirstChild("Nests")
        if nests then
            for _, nest in ipairs(nests:GetChildren()) do
                local m = nest:FindFirstChild("Model")
                if m and m:IsA("Model") then
                    eggCount = eggCount + 1
                    table.insert(eggs, { model = m, nest = nest, area = area.Name })
                end
            end
        end
    end
end
print(string.format("  Total live eggs: %d", eggCount))

for i, e in ipairs(eggs) do
    if shown >= 3 then break end
    shown = shown + 1
    print(string.format("\n--- Egg %d (Area=%s) ---", i, e.area))
    print("  Nest path:", e.nest:GetFullName())
    dumpInstance(e.model, 1, 3)
end

------------------------------------------------------------
-- 3) Which egg is closest to the SmartPromptPart right now
------------------------------------------------------------
sep("3) Nearest egg to prompt")
if spp and #eggs > 0 then
    local sppPos = spp.Position
    local closest, bestDist = nil, math.huge
    for _, e in ipairs(eggs) do
        local pp = e.model.PrimaryPart or e.model:FindFirstChildWhichIsA("BasePart", true)
        if pp then
            local d = (pp.Position - sppPos).Magnitude
            if d < bestDist then bestDist = d; closest = e end
        end
    end
    if closest then
        print(string.format("  Closest: %s (%.1f studs away)",
            closest.nest:GetFullName(), bestDist))
        local pp = closest.model.PrimaryPart or closest.model:FindFirstChildWhichIsA("BasePart", true)
        if pp then
            print("  Prompt pos  :", tostring(spp.Position))
            print("  Egg pos     :", tostring(pp.Position))
        end
    end
end

------------------------------------------------------------
-- 4) Player state
------------------------------------------------------------
sep("4) Player state")
local char = LP.Character
local hrp = char and char:FindFirstChild("HumanoidRootPart")
local hum = char and char:FindFirstChildOfClass("Humanoid")
if hrp then
    print("  HRP position    :", tostring(hrp.Position))
    print("  HRP anchored    :", hrp.Anchored)
    print("  HRP velocity    :", tostring(hrp.AssemblyLinearVelocity))
end
if hum then
    print("  WalkSpeed       :", hum.WalkSpeed)
    print("  PlatformStand   :", hum.PlatformStand)
    print("  JumpPower       :", hum.JumpPower)
end

------------------------------------------------------------
-- 5) Any stealth/anti-cheat signs
------------------------------------------------------------
sep("5) Scripts on character (anti-cheat detection)")
if char then
    for _, c in ipairs(char:GetDescendants()) do
        if c:IsA("Script") or c:IsA("LocalScript") then
            print("  ", c.ClassName, c:GetFullName())
        end
    end
end

------------------------------------------------------------
-- 6) Movement-related remotes on ReplicatedStorage
------------------------------------------------------------
sep("6) Movement/position remotes (for reference)")
local RS = game:GetService("ReplicatedStorage")
for _, d in ipairs(RS:GetDescendants()) do
    if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent")) then
        local n = string.lower(d.Name)
        if string.find(n, "move", 1, true)
           or string.find(n, "pos", 1, true)
           or string.find(n, "walk", 1, true)
           or string.find(n, "speed", 1, true)
           or string.find(n, "teleport", 1, true)
           or string.find(n, "character", 1, true)
           or string.find(n, "humanoid", 1, true) then
            print("  ", d.ClassName, ":", d:GetFullName())
        end
    end
end

------------------------------------------------------------
-- Done
------------------------------------------------------------
print("\n═══════════════════════════════════════")
print("  Scan complete — copy this whole log")
print("═══════════════════════════════════════")
