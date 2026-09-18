local TweenService    = game:GetService("TweenService")
local RunService      = game:GetService("RunService")
local StarterGui      = game:GetService("StarterGui")
local ContentProvider = game:GetService("ContentProvider")

local LoaderUI = {}
LoaderUI.__index = LoaderUI
LoaderUI.VERSION = "1.0.0"

-- =========================================================
-- Constructor
-- =========================================================
function LoaderUI.new(playerGui, config)
    local self = setmetatable({}, LoaderUI)
    self.playerGui       = playerGui
    self.config          = config or {}
    self.currentProgress = 0
    self.dotsAlive       = true

    self.memeImageId  = self.config.MEME_IMAGE_ID  or "rbxassetid://82403642047427"
    self.laughSoundId = self.config.LAUGH_SOUND_ID or "rbxassetid://133312610824902"
    self.memeSize     = self.config.MEME_SIZE      or 380

    self:_hideExtras()
    self:_buildScreen()
    self:_startDots()
    self:_fadeIn()

    return self
end

-- =========================================================
-- CoreGui hide / restore
-- =========================================================
function LoaderUI:_hideExtras()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
    end)
    local notif = self.playerGui:FindFirstChild("Notifications")
    if notif then notif.Enabled = false end
    local topbar = self.playerGui:FindFirstChild("TopbarStandard")
    if topbar then topbar.Enabled = false end
end

function LoaderUI:restoreExtras()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
    end)
    local notif = self.playerGui:FindFirstChild("Notifications")
    if notif then notif.Enabled = true end
    local topbar = self.playerGui:FindFirstChild("TopbarStandard")
    if topbar then topbar.Enabled = true end
end

-- =========================================================
-- Build the full-screen loading cover
-- =========================================================
function LoaderUI:_buildScreen()
    local screen = Instance.new("ScreenGui")
    screen.Name = "SystemBoot"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 999999
    screen.Parent = self.playerGui
    self.screen = screen

    local cover = Instance.new("Frame")
    cover.Name = "Cover"
    cover.Size = UDim2.fromScale(1, 1)
    cover.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
    cover.BorderSizePixel = 0
    cover.Active = true
    cover.Parent = screen
    self.cover = cover

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
    self.content = content

    local dotRow = Instance.new("Frame")
    dotRow.Name = "Dots"
    dotRow.AnchorPoint = Vector2.new(0.5, 0)
    dotRow.Position = UDim2.new(0.5, 0, 0, 0)
    dotRow.Size = UDim2.fromOffset(100, 20)
    dotRow.BackgroundTransparency = 1
    dotRow.Parent = content

    self.dots = {}
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
        self.dots[i] = dot
    end

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
    self.statusLabel = status

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
    self.barFill = barFill

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
    self.pctLabel = pct
end

-- =========================================================
-- Dots animation
-- =========================================================
function LoaderUI:_startDots()
    task.spawn(function()
        local idx = 1
        while self.dotsAlive do
            for j, dot in ipairs(self.dots) do
                local active = (j == idx)
                TweenService:Create(dot, TweenInfo.new(0.18), {
                    BackgroundTransparency = active and 0 or 0.75,
                    Size = active and UDim2.fromOffset(11, 11) or UDim2.fromOffset(9, 9),
                }):Play()
            end
            idx = (idx % #self.dots) + 1
            task.wait(0.28)
        end
    end)
end

-- =========================================================
-- Fade in
-- =========================================================
function LoaderUI:_fadeIn()
    self.cover.BackgroundTransparency = 1
    self.content.Visible = false
    TweenService:Create(self.cover, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
    task.wait(0.35)
    self.content.Visible = true
end

-- =========================================================
-- Status setter
-- =========================================================
function LoaderUI:setStatus(text, targetPct, duration)
    self.statusLabel.Text = text
    duration = duration or 0.4

    TweenService:Create(self.barFill,
        TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.fromScale(targetPct, 1) }
    ):Play()

    task.spawn(function()
        local start = self.currentProgress
        local goal  = targetPct
        local t0    = os.clock()
        while os.clock() - t0 < duration do
            local a = (os.clock() - t0) / duration
            self.pctLabel.Text = math.floor((start + (goal - start) * a) * 100) .. "%"
            RunService.RenderStepped:Wait()
        end
        self.pctLabel.Text = math.floor(goal * 100) .. "%"
        self.currentProgress = goal
    end)
end

-- =========================================================
-- Boot sequence (customizable via config.BOOT_STEPS)
--   config.BOOT_STEPS = { {text, pct, duration, waitAfter}, ... }
-- =========================================================
function LoaderUI:boot()
    local steps = self.config.BOOT_STEPS or {
        { "Initializing...",          0.08, 0.5, 0.7 },
        { "Loading resources...",     0.22, 0.5, 0.7 },
        { "Fetching session data...", 0.40, 0.5, 0.6 },
        { "Syncing profile...",       0.58, 0.5, 0.6 },
        { "Preparing environment...", 0.78, 0.5, 0.5 },
        { "Almost ready...",          1.00, 0.6, 0.7 },
    }
    for _, s in ipairs(steps) do
        self:setStatus(s[1], s[2], s[3])
        task.wait(s[4] or 0.7)
    end
end

-- =========================================================
-- Fade out + cleanup
-- =========================================================
function LoaderUI:fadeOutAndCleanup()
    self.dotsAlive = false
    TweenService:Create(self.cover,   TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
    TweenService:Create(self.content, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
    task.wait(0.5)
    if self.screen then
        self.screen:Destroy()
        self.screen = nil
    end
    self:restoreExtras()
end

-- =========================================================
-- Meme popup
-- =========================================================
function LoaderUI:showMemePopup()
    local gui = Instance.new("ScreenGui")
    gui.Name = "MemePop"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999999
    gui.Parent = self.playerGui

    local img = Instance.new("ImageLabel")
    img.Name = "Cat"
    img.AnchorPoint = Vector2.new(0.5, 0.5)
    img.Position = UDim2.fromScale(0.5, 0.5)
    img.Size = UDim2.fromOffset(self.memeSize, self.memeSize)
    img.BackgroundTransparency = 1
    img.Image = self.memeImageId
    img.ScaleType = Enum.ScaleType.Fit
    img.ImageTransparency = 1
    img.Rotation = -6
    img.Parent = gui

    pcall(function() ContentProvider:PreloadAsync({ img }) end)

    local t0 = os.clock()
    while not img.IsLoaded and os.clock() - t0 < 3 do
        task.wait(0.05)
    end
    if not img.IsLoaded then
        warn("[LoaderUI] Meme image failed to load — check the texture ID.")
    end

    local sound = Instance.new("Sound")
    sound.SoundId = self.laughSoundId
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

return LoaderUI
