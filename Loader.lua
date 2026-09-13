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
local function getSave()
    local ok, s = pcall(function() return Save.Get(LocalPlayer, false) end)
    if ok and s then return s end
    local ok2, s2 = pcall(function() return Save.Get() end)
    return ok2 and s2 or nil
end

local function getMoney()
    local d = getSave()
    return (d and type(d.Money) == "number") and d.Money or 0
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
        Remotes.Haul.OfferFullSatchelSale.OnClientInvoke = function(_) return true end
    end)
end
installOverride()
task.spawn(function()
    for _ = 1, 30 do task.wait(0.5); installOverride() end
end)

------------------------------------------------------------
-- 2. Unequip all pets
------------------------------------------------------------
local function unequipAll()
    local d = getSave()
    if not d or type(d.EquippedAssets) ~= "table" or #d.EquippedAssets == 0 then
        log("No equipped pets.")
        return
    end
    log(("Unequipping %d pet(s)..."):format(#d.EquippedAssets))

    local ok, AssetRoster = pcall(require, ReplicatedStorage.Client.AssetRoster)
    for i, uid in ipairs(d.EquippedAssets) do
        if ok and AssetRoster and AssetRoster.DoffAsset then
            pcall(function() AssetRoster.DoffAsset(uid) end)
        else
            pcall(function() Remotes.PenRoster.AskDoff:InvokeServer(uid) end)
        end
        if i % 5 == 0 then task.wait(0.3) end
    end
    task.wait(1.0)
end

------------------------------------------------------------
-- 3. Unfavorite all pets
------------------------------------------------------------
local function getFavoriteUIDs()
    local list = {}
    local d = getSave()
    if not d or type(d.Inventory) ~= "table" then return list end
    for uid, rec in pairs(d.Inventory) do
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
    for i, uid in ipairs(uids) do
        pcall(function() Remotes.PetSatchel.WriteFavourite:FireServer(uid, false) end)
        pcall(function() Remotes.PetSatchel.WriteFavourite:FireServer({ [uid] = false }) end)
        if i % 8 == 0 then task.wait(0.35) end
    end
    task.wait(1.0)
end

------------------------------------------------------------
-- 4. Build the payload as ARRAYS (this is the fix)
------------------------------------------------------------
local function buildPayload()
    local pets = {}  -- array of pet UID strings
    local eggs = {}  -- array of egg UID strings

    local d = getSave()
    if not d then return { Eggs = eggs, Assets = pets } end

    if type(d.Inventory) == "table" then
        for uid, rec in pairs(d.Inventory) do
            local ok, item = TryCall(AssetItems.Decode, rec)
            if ok and item
                and AssetDir[item.Category]
                and item.InFuse ~= true
            then
                table.insert(pets, uid)
            end
        end
    end

    if type(d.EggInventory) == "table" then
        for uid, rec in pairs(d.EggInventory) do
            if type(rec) == "table" and rec.Placement == nil then
                local ok, dec = TryCall(EggRecords.Decode, rec)
                if ok and dec and AssetDir[dec.AssetCategory] then
                    table.insert(eggs, uid)
                end
            end
        end
    end

    return { Eggs = eggs, Assets = pets }
end

------------------------------------------------------------
-- 5. Find sell stand position (SellAll is a Part; prompt is inside)
------------------------------------------------------------
local function findSellPosition()
    local stands = workspace:FindFirstChild("Stands")
    if not stands then return nil end
    local prompts = stands:FindFirstChild("Prompts")
    if not prompts then return nil end

    local sellAll = prompts:FindFirstChild("SellAll")
    if sellAll and sellAll:IsA("BasePart") then
        return sellAll.Position
    end

    -- Fallback: any BasePart in the Prompts folder
    for _, c in ipairs(prompts:GetChildren()) do
        if c:IsA("BasePart") then return c.Position end
    end
    return nil
end

------------------------------------------------------------
-- 6. Teleport, fire, return
------------------------------------------------------------
local function teleportAndSell()
    local payload = buildPayload()
    log(("Payload: %d pets (Assets), %d eggs"):format(
        #payload.Assets, #payload.Eggs
    ))

    if #payload.Assets == 0 and #payload.Eggs == 0 then
        log("Nothing to sell.")
        return
    end

    local hrp = getHRP()
    local pos = findSellPosition()
    if not hrp or not pos then
        warn("[AutoSell] Missing HRP or stand position — firing anyway.")
        Remotes.PetSatchel.SellSelection:FireServer(payload)
        task.wait(1.5)
        return
    end

    local savedCF  = hrp.CFrame
    local savedVel = hrp.AssemblyLinearVelocity

    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.7)

    log("Firing PetSatchel.SellSelection ...")
    local ok, err = pcall(function()
        Remotes.PetSatchel.SellSelection:FireServer(payload)
    end)
    if not ok then warn("[AutoSell] FireServer error:", err) end
    task.wait(1.5)

    hrp.CFrame = savedCF
    pcall(function() hrp.AssemblyLinearVelocity = savedVel end)
    log("Returned.")
end

------------------------------------------------------------
-- 7. Main
------------------------------------------------------------
local function run()
    local before = getMoney()
    log(("Wallet before: %s"):format(tostring(before)))

    unequipAll()
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
        Title = "Auto-Sell";
        Text  = "Unequipped, unfavorited, sold all pets + eggs.";
        Duration = 4;
    })
end)
