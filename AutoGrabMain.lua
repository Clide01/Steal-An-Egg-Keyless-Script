--[[
    Steal an Egg — Auto Grab Field Eggs (main logic)
    Requires AutoGrabUI module.

    For Delta Executor:
      Save both files as separate scripts.
      AutoGrabMain references AutoGrabUI by path — adjust the require() below
      to match your executor's workspace layout.
]]

-- ============================================================
-- RE-EXECUTION GUARD
-- ============================================================
local GENV = getgenv and getgenv() or _G
if GENV.__AutoGrabInstance and GENV.__AutoGrabInstance.cleanup then
    pcall(function()
        GENV.__AutoGrabInstance.cleanup()
    end)
    print("[AutoGrab] Previous instance stopped.")
end
GENV.__AutoGrabInstance = nil

-- ============================================================
-- Services
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- Require UI module (adjust path to match your setup)
-- ============================================================
-- If you saved AutoGrabUI.lua as a file in your executor workspace:
local UI_LIBRARY_PATH = "AutoGrabUI.lua"

local AutoGrabUI = nil
do
    -- Try loading from file
    local ok, module = pcall(function()
        if readfile and loadstring then
            local src = readfile(UI_LIBRARY_PATH)
            return loadstring(src)()
        end
        return nil
    end)
    if ok and module then
        AutoGrabUI = module
    else
        warn("[AutoGrab] Could not load AutoGrabUI.lua — falling back to embedded require")
        warn("[AutoGrab] Make sure the file is saved in the executor workspace.")
        return
    end
end

-- ============================================================
-- CONFIG
-- ============================================================
local GRAB_COOLDOWN     = 2.0
local TELEPORT_DELAY    = 0.35
local RETURN_DELAY      = 0.55
local EGG_ARRIVE_OFFSET = Vector3.new(0, 3, 0)
local RESCAN_INTERVAL   = 30

-- Common eggs only (for testing) — expand later from EggCatalog.json
local EGG_GROUPS = {
    {
        name = "Common",
        eggs = {
            { category = "Chicken",  display = "Chicken",  icon = "rbxassetid://87733160598688" },
            { category = "Dog",      display = "Dog",      icon = "rbxassetid://128470938015055" },
            { category = "Duckling", display = "Duckling", icon = "rbxassetid://81116137079823" },
            { category = "Frog",     display = "Frog",     icon = "rbxassetid://114669220150056" },
            { category = "Jerboa",   display = "Jerboa",   icon = "rbxassetid://139650837807677" },
        },
    },
}

-- ============================================================
-- Remotes
-- ============================================================
local ok, Remotes = pcall(require, ReplicatedStorage.Shared.Remotes)
if not ok or not Remotes or not Remotes.EggWorld then
    warn("[AutoGrab] Could not load Remotes.EggWorld")
    return
end
local E = Remotes.EggWorld

local log = function(...) print("[AutoGrab]", ...) end

-- ============================================================
-- State
-- ============================================================
local Instance = {
    connections = {},
    cleaned     = false,
    ui          = nil,
    state = {
        selectedEgg   = nil,
        safeZone      = nil,
        eggList       = {},
        isCarrying    = false,
        lastGrab      = 0,
        stats         = { grabbed = 0, failed = 0, returned = 0 },
        lastGrabbed   = "—",
        status        = "Idle",
    },
}
local State = Instance.state

local function track(c)
    if c then table.insert(Instance.connections, c) end
    return c
end

local function getHRP()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 5)
end

-- ============================================================
-- BUILD UI (module handles all layout)
-- ============================================================
Instance.ui = AutoGrabUI.new({
    parent    = PlayerGui,
    eggGroups = EGG_GROUPS,

    onTargetChange = function(category)
        State.selectedEgg = category
        log("Target set: " .. (category or "Any"))
    end,

    onSetSafeZone = function()
        local hrp = getHRP()
        if hrp then
            State.safeZone = hrp.CFrame
            log("Safe zone set")
            return true
        end
        return false
    end,

    onStart = function()
        -- Auto-set safe zone if not set
        if not State.safeZone then
            local hrp = getHRP()
            if hrp then
                State.safeZone = hrp.CFrame
                log("Safe zone auto-set from current position")
            end
        end
        log("STARTED")
        task.spawn(fetchSnapshot)
    end,

    onStop = function()
        log("STOPPED")
    end,
})

local UI = Instance.ui

-- UI refresh loop
track(task.spawn(function()
    while not Instance.cleaned and UI._gui and UI._gui.Parent do
        UI:setStatus(UI:isRunning() and State.status or "Idle")
        UI:setLastGrabbed(State.lastGrabbed)
        UI:setStats(State.stats)
        local n = 0
        for _ in pairs(State.eggList) do n = n + 1 end
        UI:setFieldCount(n)
        task.wait(0.4)
    end
end))

-- ============================================================
-- FILTER
-- ============================================================
local function matchesFilter(egg)
    if not egg or type(egg) ~= "table" then return false end
    if egg.State ~= "Slot" then return false end
    if not egg.Uid then return false end
    if not State.selectedEgg then return true end
    return egg.AssetCategory == State.selectedEgg
end

-- ============================================================
-- GRAB LOGIC
-- ============================================================
local function teleportBack()
    if not State.safeZone then return end
    local hrp = getHRP()
    if not hrp then return end
    hrp.CFrame = State.safeZone
    State.stats.returned = State.stats.returned + 1
end

local function tryGrab(egg)
    if Instance.cleaned then return end
    if not UI:isRunning() then return end
    if State.isCarrying then return end
    if not matchesFilter(egg) then return end

    local now = tick()
    if now - State.lastGrab < GRAB_COOLDOWN then return end
    State.lastGrab = now

    local cframe = egg.BottomCFrame or egg.BoundsCFrame
    if not cframe then return end
    local position = cframe.Position or cframe

    State.status = "Grabbing " .. (egg.AssetCategory or "?")
    log(("Grab: %s @ %s"):format(egg.AssetCategory or "?", egg.AreaId or "?"))

    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(position + EGG_ARRIVE_OFFSET)
        task.wait(TELEPORT_DELAY)
    end

    if Instance.cleaned then return end

    local args = { Uid = egg.Uid }
    if type(egg.Uid) == "string" and string.find(egg.Uid, "^FirstAreaEgg_") then
        args.FirstAreaSlotKey = (egg.AreaId or "") .. ":" .. (egg.NestId or "")
    end

    local success, err = pcall(function()
        E.AskFieldEggCarry:InvokeServer(args)
    end)

    if success then
        State.stats.grabbed = State.stats.grabbed + 1
        State.lastGrabbed = (egg.AssetCategory or "?") .. " @ " .. (egg.AreaId or "?")
    else
        State.stats.failed = State.stats.failed + 1
        log("Grab failed: " .. tostring(err))
    end

    task.wait(RETURN_DELAY)
    if Instance.cleaned then return end
    teleportBack()
    State.status = "Running"
end

-- ============================================================
-- EVENTS
-- ============================================================
track(E.FieldEggShifted.OnClientEvent:Connect(function(egg)
    if Instance.cleaned then return end
    if type(egg) ~= "table" or not egg.Uid then return end
    State.eggList[egg.Uid] = egg
    if egg.State == "Slot" then tryGrab(egg) end
end))

track(E.FieldEggBatchShifted.OnClientEvent:Connect(function(batch)
    if Instance.cleaned then return end
    if type(batch) ~= "table" then return end
    for _, egg in ipairs(batch) do
        if type(egg) == "table" and egg.Uid then
            State.eggList[egg.Uid] = egg
            if egg.State == "Slot" then tryGrab(egg) end
        end
    end
end))

track(E.FieldEggGone.OnClientEvent:Connect(function(uid)
    if type(uid) == "string" then State.eggList[uid] = nil end
end))

track(E.FieldEggCarry.OnClientEvent:Connect(function(info)
    if type(info) == "table" then
        State.isCarrying = info.IsCarrying == true
        State.status = State.isCarrying and "Carrying" or "Running"
    end
end))

-- ============================================================
-- SNAPSHOT
-- ============================================================
function fetchSnapshot()
    if Instance.cleaned then return end
    local okSnap, snapshot = pcall(function()
        return E.AskFieldEggSnapshot:InvokeServer()
    end)
    if okSnap and snapshot and snapshot.Records then
        local count = 0
        for _, egg in ipairs(snapshot.Records) do
            if egg.Uid then
                State.eggList[egg.Uid] = egg
                count = count + 1
            end
        end
        log(("Snapshot: %d eggs on field"):format(count))
        if UI:isRunning() then
            for _, egg in ipairs(snapshot.Records) do
                if Instance.cleaned then return end
                tryGrab(egg)
            end
        end
    else
        warn("[AutoGrab] Snapshot failed")
    end
end

-- Periodic refresh
track(task.spawn(function()
    task.wait(2)
    if Instance.cleaned then return end
    fetchSnapshot()

    while not Instance.cleaned and UI._gui and UI._gui.Parent do
        task.wait(RESCAN_INTERVAL)
        if UI:isRunning() and not Instance.cleaned then fetchSnapshot() end
    end
end))

-- ============================================================
-- CLEANUP
-- ============================================================
function Instance.cleanup()
    if Instance.cleaned then return end
    Instance.cleaned = true

    -- Destroy UI
    if UI and UI.destroy then
        pcall(function() UI:destroy() end)
    end

    -- Disconnect connections
    for _, c in ipairs(Instance.connections) do
        pcall(function() c:Disconnect() end)
    end
    Instance.connections = {}

    print("[AutoGrab] Cleanup complete.")
end

GENV.__AutoGrabInstance = Instance

log("========================================")
log("  AUTO GRAB READY")
log("  UI loaded · 5 common eggs available")
log("========================================")
