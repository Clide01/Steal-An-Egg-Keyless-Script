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
local function count(t)
    local n = 0; for _ in pairs(t) do n = n + 1 end; return n
end

local function getSave()
    return Save.Get(LocalPlayer, false) or Save.Get()
end

local function getMoney()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    -- The wallet is not in leaderstats here; read the raw save
    local data = getSave()
    if data and type(data.Money) == "number" then return data.Money end
    return 0
end

local function getHRP()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 5)
end

------------------------------------------------------------
-- 1. Auto-accept full-satchel prompt from server
------------------------------------------------------------
local function installOverride()
    pcall(function()
        Remotes.Haul.OfferFullSatchelSale.OnClientInvoke = function(_)
            log("Auto-accepting server's full-satchel sale offer.")
            return true
        end
    end)
end
installOverride()
task.spawn(function()
    for _ = 1, 20 do task.wait(0.5); installOverride() end
end)

------------------------------------------------------------
-- 2. Favorite clearing
------------------------------------------------------------
local function isFav(uid)
    local data = getSave()
    if not data or type(data.Inventory) ~= "table" then return false end
    local rec = data.Inventory[uid]
    if type(rec) ~= "table" then return false end
    local ok, item = TryCall(AssetItems.Decode, rec)
    return (ok and item and item.IsFavorite == true) and true or false
end

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

local function fireWriteFavourite(uid, mode)
    if mode == "set"    then Remotes.PetSatchel.WriteFavourite:FireServer(uid, false)
    elseif mode == "toggle" then Remotes.PetSatchel.WriteFavourite:FireServer(uid)
    elseif mode == "batch"  then Remotes.PetSatchel.WriteFavourite:FireServer({ [uid] = false })
    end
end

local function discoverFavouriteMode(probeUID)
    for _, mode in ipairs({ "set", "toggle", "batch" }) do
        fireWriteFavourite(probeUID, mode)
        task.wait(0.8)
        if not isFav(probeUID) then
            log(("WriteFavourite mode = '%s'"):format(mode))
            return mode
        end
        if mode == "toggle" then
            Remotes.PetSatchel.WriteFavourite:FireServer(probeUID)
            task.wait(0.5)
        end
    end
    return nil
end

local function unfavoriteAll()
    local uids = getFavoriteUIDs()
    if #uids == 0 then
        log("No favorited pets to clear.")
        return true
    end
    log(("Clearing %d favorited pet(s)..."):format(#uids))

    local mode = discoverFavouriteMode(uids[1])
    if not mode then
        warn("[AutoSell] WriteFavourite signature unknown — aborting.")
        return false
    end

    for i = 2, #uids do
        fireWriteFavourite(uids[i], mode)
        if i % 8 == 0 then task.wait(0.4) end
    end
    task.wait(1.2)

    local left = getFavoriteUIDs()
    if #left > 0 then
        warn(("[AutoSell] %d favorites still set — aborting."):format(#left))
        return false
    end
    log("All favorites cleared.")
    return true
end

------------------------------------------------------------
-- 3. Locate the sell stand
------------------------------------------------------------
local function findSellPrompt()
    local stands = workspace:FindFirstChild("Stands")
    if not stands then return nil end
    local prompts = stands:FindFirstChild("Prompts")
    if not prompts then return nil end
    -- Try SellAll first, fall back to SellHeldAsset
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
            local prim = adornee.PrimaryPart or adornee:FindFirstChildWhichIsA("BasePart")
            if prim then return prim.Position end
        end
    end
    return nil
end

------------------------------------------------------------
-- 4. Selection builders
------------------------------------------------------------
local function buildPetSelection()
    local sel = {}
    local data = getSave()
    if not data or type(data.Inventory) ~= "table" then return sel end

    local equipped = {}
    if type(data.EquippedAssets) == "table" then
        for _, uid in ipairs(data.EquippedAssets) do equipped[uid] = true end
    end

    for uid, rec in pairs(data.Inventory) do
        local ok, item = TryCall(AssetItems.Decode, rec)
        if ok and item
            and AssetDir[item.Category]
            and item.InFuse ~= true
        then
            -- Include equipped ones too — they'll just be skipped by server
            -- if it enforces the rule, no harm if we include them.
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
-- 5. Teleport + trigger sell
------------------------------------------------------------
local function teleportAndSell()
    local prompt = findSellPrompt()
    if not prompt then
        warn("[AutoSell] Could not find sell stand. Firing remotes anyway.")
        return false
    end
    log(("Found sell prompt: %s"):format(prompt:GetFullName()))

    local pos = getPromptWorldPos(prompt)
    if not pos then
        warn("[AutoSell] Sell prompt has no world position.")
        return false
    end

    local hrp = getHRP()
    if not hrp then
        warn("[AutoSell] No HumanoidRootPart.")
        return false
    end

    -- Save current location
    local savedCF = hrp.CFrame
    local savedVel = hrp.AssemblyLinearVelocity

    -- Teleport next to the stand (a few studs up so we don't clip)
    local target = CFrame.new(pos + Vector3.new(0, 4, 0))
    hrp.CFrame = target
    hrp.AssemblyLinearVelocity = Vector3.zero
    log("Teleported to sell stand.")

    -- Let the server register our new position
    task.wait(0.6)

    -- Ask the server to sell everything (position-checked on server)
    local pets = buildPetSelection()
    local eggs = buildEggSelection()
    log(("Selection: %d pets, %d eggs"):format(count(pets), count(eggs)))

    -- First: no-arg "sell every pet" remote
    pcall(function()
        Remotes.PetSatchel.SellEveryPet:FireServer()
    end)
    task.wait(0.8)

    -- Second: explicit selection of pets
    if count(pets) > 0 then
        pcall(function()
            Remotes.PetSatchel.SellSelection:FireServer(pets)
        end)
        task.wait(0.8)
    end

    -- Third: explicit selection of eggs
    if count(eggs) > 0 then
        pcall(function()
            Remotes.PetSatchel.SellSelection:FireServer(eggs)
        end)
        task.wait(0.8)
    end

    -- Try triggering the ProximityPrompt as a final fallback.
    -- Some servers only sell when the prompt itself fires.
    pcall(function()
        if prompt:IsA("ProximityPrompt") then
            prompt.Enabled = true
            prompt:InputHoldBegin()
            task.wait(math.max(0.3, prompt.HoldDuration + 0.1))
            prompt:InputHoldEnd()
        end
    end)
    task.wait(1.2)

    -- Teleport back
    hrp.CFrame = savedCF
    pcall(function() hrp.AssemblyLinearVelocity = savedVel end)
    log("Teleported back.")
    return true
end

------------------------------------------------------------
-- 6. Main
------------------------------------------------------------
local function runAutoSell()
    local before = getMoney()
    log(("Wallet before: %s"):format(tostring(before)))

    local favs = getFavoriteUIDs()
    log(("Favorited pets detected: %d"):format(#favs))
    if #favs > 0 then
        if not unfavoriteAll() then
            warn("[AutoSell] Aborting — could not clear favorites.")
            return
        end
    end

    teleportAndSell()
    task.wait(1.0)

    local after = getMoney()
    log(("Wallet after:  %s"):format(tostring(after)))
    log(("Delta:         %s"):format(tostring(after - before)))
end

runAutoSell()

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title    = "Auto-Sell";
        Text     = "Cleared favorites + sold from the stand.";
        Duration = 4;
    })
end)
