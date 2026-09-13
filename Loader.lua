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

local function moneyPerSec()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local v  = ls and ls:FindFirstChild("Money/s")
    return v and v.Value or 0
end

-- Returns true if this pet UID is flagged favorite in the current save
local function isFav(uid)
    local data = getSave()
    if not data or type(data.Inventory) ~= "table" then return false end
    local rec = data.Inventory[uid]
    if type(rec) ~= "table" then return false end
    local ok, item = TryCall(AssetItems.Decode, rec)
    return (ok and item and item.IsFavorite == true) and true or false
end

-- Returns a flat list of every favorited pet UID
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

------------------------------------------------------------
-- 1. Auto-accept the server's full-satchel sale prompt
------------------------------------------------------------
local function installOverride()
    pcall(function()
        Remotes.Haul.OfferFullSatchelSale.OnClientInvoke = function(_)
            log("Server offered full-satchel sale — auto-accepting.")
            return true
        end
    end)
end
installOverride()
task.spawn(function()
    for _ = 1, 20 do task.wait(0.5); installOverride() end
end)

------------------------------------------------------------
-- 2. Unfavorite pass
------------------------------------------------------------
-- Fires the remote with whichever arg shape the game expects.
local function fireWriteFavourite(uid, mode)
    if mode == "set"    then Remotes.PetSatchel.WriteFavourite:FireServer(uid, false)
    elseif mode == "toggle" then Remotes.PetSatchel.WriteFavourite:FireServer(uid)
    elseif mode == "batch"  then Remotes.PetSatchel.WriteFavourite:FireServer({ [uid] = false })
    end
end

-- Probe: figure out which arg shape actually clears the flag.
-- Returns the working mode string, or nil.
local function discoverMode(probeUID)
    for _, mode in ipairs({ "set", "toggle", "batch" }) do
        fireWriteFavourite(probeUID, mode)
        task.wait(0.8)
        if not isFav(probeUID) then
            log(("WriteFavourite arg shape confirmed: '%s'"):format(mode))
            return mode
        end
        -- If toggle didn't work, it may have flipped something else.
        -- Re-toggle to restore state before trying the next shape.
        if mode == "toggle" then
            Remotes.PetSatchel.WriteFavourite:FireServer(probeUID)
            task.wait(0.5)
        end
    end
    return nil
end

-- Returns true if, after this function, no favorited pets remain.
local function unfavoriteAll()
    local uids = getFavoriteUIDs()
    if #uids == 0 then
        log("No favorited pets found — skipping unfavorite pass.")
        return true
    end

    log(("Found %d favorited pet(s). Clearing them now..."):format(#uids))

    -- Discover the arg shape with the first UID
    local mode = discoverMode(uids[1])
    if not mode then
        warn("[AutoSell] Could not determine WriteFavourite signature.")
        warn("  Favorited pets would be skipped by the sell — aborting.")
        return false
    end

    -- Apply to the rest, throttled so we don't trip the anti-spam
    for i = 2, #uids do
        fireWriteFavourite(uids[i], mode)
        if i % 8 == 0 then task.wait(0.4) end
    end

    -- Settle, then verify nothing is left favorited
    task.wait(1.2)
    local remaining = getFavoriteUIDs()
    if #remaining > 0 then
        warn(("[AutoSell] %d favorites still set after pass — not selling."):format(#remaining))
        return false
    end

    log("All favorites cleared. Proceeding to sell.")
    return true
end

------------------------------------------------------------
-- 3. Selection builders (no favorite filter now — they're cleared)
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
            and not equipped[uid]
        then
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

local function sellSelection(tbl, label)
    local n = count(tbl)
    if n == 0 then
        log(("Nothing to sell (%s)."):format(label))
        return
    end
    log(("SellSelection -> %d %s"):format(n, label))
    Remotes.PetSatchel.SellSelection:FireServer(tbl)
end

------------------------------------------------------------
-- 4. Main
------------------------------------------------------------
local function runAutoSell()
    local before = moneyPerSec()
    log(("Money/s before: %s"):format(tostring(before)))

    -- CHECK: are there any favorites?
    local favs = getFavoriteUIDs()
    log(("Favorited pets detected: %d"):format(#favs))

    -- UNFAVORITE: only proceed if we successfully cleared them
    if #favs > 0 then
        if not unfavoriteAll() then
            warn("[AutoSell] Aborting sell because favorites could not be cleared.")
            return
        end
    end

    -- SELL: server-side "sell every pet" first
    log("Firing PetSatchel.SellEveryPet ...")
    Remotes.PetSatchel.SellEveryPet:FireServer()
    task.wait(1.2)

    -- SELL: explicit selection covers pets + eggs (incl. formerly-favorited)
    sellSelection(buildPetSelection(), "pets")
    task.wait(0.8)
    sellSelection(buildEggSelection(), "eggs")
    task.wait(1.0)

    local after = moneyPerSec()
    log(("Money/s after:  %s"):format(tostring(after)))
    log(("Delta:          %s"):format(tostring(after - before)))
end

runAutoSell()

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title    = "Auto-Sell";
        Text     = "Favorites cleared and pets + eggs sold.";
        Duration = 4;
    })
end)
