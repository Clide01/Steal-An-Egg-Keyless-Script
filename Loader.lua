local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Remotes     = require(ReplicatedStorage.Shared.Remotes)
local Save        = require(ReplicatedStorage.Shared.Save)
local AssetItems  = require(ReplicatedStorage.Shared.Util.AssetItems)
local EggRecords  = require(ReplicatedStorage.Shared.Util.EggRecords)
local AssetDir    = require(ReplicatedStorage.Data.Assets).Directory
local TryCall     = require(ReplicatedStorage.Shared.Utils.TryCall)

local log = function(...) print("[AutoSell]", ...) end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end

local function getSave()
    return Save.Get(LocalPlayer, false) or Save.Get()
end

local function getMoney()
    local data = getSave()
    return (data and type(data.Money) == "number") and data.Money or 0
end

local function getHRP()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 5)
end

------------------------------------------------------------
-- 1. Auto-accept server's full-satchel offer
------------------------------------------------------------
local function installOverride()
    pcall(function()
        Remotes.Haul.OfferFullSatchelSale.OnClientInvoke = function(_)
            return true
        end
    end)
end
installOverride()
task.spawn(function()
    for _ = 1, 30 do task.wait(0.5); installOverride() end
end)

------------------------------------------------------------
-- 2. Scan + unfavorite
------------------------------------------------------------
local function getFavoriteUIDs()
    local list = {}
    local data = getSave()
    if not data or type(data.Inventory) ~= "table" then return list end
    for uid, rec in pairs(data.Inventory) do
        local ok, item = TryCall(AssetItems.Decode, rec)
        if ok and item and item.IsFavorite == true then
            table.insert(list, uid)
        end
    end
    return list
end

local function unfavoriteAll()
    local uids = getFavoriteUIDs()
    log(("Favorited pets found: %d"):format(#uids))
    if #uids == 0 then return end

    for i, uid in ipairs(uids) do
        -- Most likely signature: setter (uid, false)
        pcall(function()
            Remotes.PetSatchel.WriteFavourite:FireServer(uid, false)
        end)
        -- Belt-and-braces: also try batch-table form
        pcall(function()
            Remotes.PetSatchel.WriteFavourite:FireServer({ [uid] = false })
        end)
        if i % 8 == 0 then task.wait(0.35) end
    end
    task.wait(1.0)
    log("Unfavorite pass complete.")
end

------------------------------------------------------------
-- 3. Selection builders
------------------------------------------------------------
local function buildPetSelection()
    local sel = {}
    local data = getSave()
    if not data or type(data.Inventory) ~= "table" then return sel end
    for uid, rec in pairs(data.Inventory) do
        local ok, item = TryCall(AssetItems.Decode, rec)
        if ok and item and AssetDir[item.Category] and item.InFuse ~= true then
            sel[uid] = true
        end
    end
    return sel
end

local function buildEggSelection()
    local sel = {}
    local data = getSave()
    if not data or type(data.EggInventory) ~= "table" then return sel end
    for uid, rec in pairs(data.EggInventory) do
        if type(rec) == "table" and rec.Placement == nil then
            local ok, dec = TryCall(EggRecords.Decode, rec)
            if ok and dec and AssetDir[dec.AssetCategory] then
                sel[uid] = true
            end
        end
    end
    return sel
end

------------------------------------------------------------
-- 4. Find the sell stand prompt
------------------------------------------------------------
local function findSellPrompt()
    local stands = workspace:FindFirstChild("Stands")
    if not stands then return nil end
    local prompts = stands:FindFirstChild("Prompts")
    if not prompts then return nil end
    return prompts:FindFirstChild("SellAll")
        or prompts:FindFirstChild("SellHeldAsset")
end

local function getPromptWorldPos(prompt)
    if not prompt then return nil end
    local host = prompt.Parent
    if host and host:IsA("BasePart") then return host.Position end
    local adornee = prompt.Adornee
    if adornee then
        if adornee:IsA("BasePart") then return adornee.Position end
        if adornee:IsA("Model") then
            local prim = adornee.PrimaryPart
                or adornee:FindFirstChildWhichIsA("BasePart")
            if prim then return prim.Position end
        end
    end
    return nil
end

------------------------------------------------------------
-- 5. Teleport, sell, teleport back
------------------------------------------------------------
local function teleportAndSell()
    local prompt = findSellPrompt()
    if not prompt then
        warn("[AutoSell] Sell stand not found — firing remotes anyway.")
        Remotes.PetSatchel.SellEveryPet:FireServer()
        task.wait(0.8)
        Remotes.PetSatchel.SellSelection:FireServer(buildPetSelection())
        task.wait(0.8)
        Remotes.PetSatchel.SellSelection:FireServer(buildEggSelection())
        return
    end

    local pos = getPromptWorldPos(prompt)
    local hrp = getHRP()
    if not pos or not hrp then
        warn("[AutoSell] Missing position or HumanoidRootPart.")
        return
    end

    local savedCF  = hrp.CFrame
    local savedVel = hrp.AssemblyLinearVelocity

    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.6) -- let server see our new position

    -- Fire everything
    pcall(function() Remotes.PetSatchel.SellEveryPet:FireServer() end)
    task.wait(0.8)
    pcall(function() Remotes.PetSatchel.SellSelection:FireServer(buildPetSelection()) end)
    task.wait(0.8)
    pcall(function() Remotes.PetSatchel.SellSelection:FireServer(buildEggSelection()) end)
    task.wait(0.8)

    -- Final fallback: trigger the actual ProximityPrompt
    pcall(function()
        if prompt:IsA("ProximityPrompt") then
            prompt.Enabled = true
            prompt:InputHoldBegin()
            task.wait(math.max(0.3, prompt.HoldDuration + 0.1))
            prompt:InputHoldEnd()
        end
    end)
    task.wait(1.2)

    hrp.CFrame = savedCF
    pcall(function() hrp.AssemblyLinearVelocity = savedVel end)
    log("Done. Returned to original position.")
end

------------------------------------------------------------
-- 6. Main
------------------------------------------------------------
local function run()
    local before = getMoney()
    log(("Wallet before: %s"):format(tostring(before)))

    unfavoriteAll()
    teleportAndSell()
    task.wait(1.0)

    local after = getMoney()
    log(("Wallet after:  %s"):format(tostring(after)))
    log(("Delta:         %s"):format(tostring(after - before)))
end

run()

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title    = "Auto-Sell";
        Text     = "Unfavorited and sold all pets + eggs.";
        Duration = 4;
    })
end)
