-- AutoSteal.lua v3.1 — Heartbeat WalkSpeed (no metatable hook)

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local AutoSteal = {}
AutoSteal.__index = AutoSteal
AutoSteal.VERSION = "3.1.0"

local PROMPT_PART  = "SmartPromptPart"
local PROMPT_CHILD = "CarryAreaEgg"
local FORCED_WS    = 400

-- =========================================================
-- Heartbeat WalkSpeed — safe, doesn't touch metatables
-- =========================================================
local wsConn = nil
local wsEnabled = false

local function startWalkSpeedLoop()
    if wsConn then return end
    wsEnabled = true
    wsConn = RunService.Heartbeat:Connect(function()
        if not wsEnabled then return end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.WalkSpeed < FORCED_WS then
            pcall(function() hum.WalkSpeed = FORCED_WS end)
        end
    end)
    print("[AutoSteal] WalkSpeed loop started (target " .. FORCED_WS .. ")")
end

local function stopWalkSpeedLoop()
    wsEnabled = false
    if wsConn then wsConn:Disconnect(); wsConn = nil end
    print("[AutoSteal] WalkSpeed loop stopped")
end

function AutoSteal.new(detector, opts)
    local self = setmetatable({}, AutoSteal)
    self.detector   = detector
    self.opts       = opts or {}

    self.walkSpeed      = self.opts.WalkSpeed or FORCED_WS
    self.moveTimeout    = self.opts.MoveTimeout or 10
    self.arriveDist     = self.opts.ArriveDistance or 4
    self.stallTolerance = self.opts.StallTolerance or 60   -- frames before giving up

    self.cooldown       = self.opts.Cooldown or 1.5
    self.globalCooldown = self.opts.GlobalCooldown or 0.3
    self._lastGlobal    = 0

    self.returnToOrigin = self.opts.ReturnToOrigin ~= false
    self.safePosition   = nil
    self.target         = nil

    self.enabled      = false
    self.lastAttempt  = {}
    self.stats        = { attempts = 0, successes = 0, failures = 0, lastStatus = "idle" }
    self._loopRunning = false
    self._busy        = false     -- prevents overlapping moves
    self.log = function(...) print("[AutoSteal]", ...) end
    return self
end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getPrompt()
    local part = workspace:FindFirstChild(PROMPT_PART)
    if not part then return nil, nil end
    local prompt = part:FindFirstChild(PROMPT_CHILD)
    if not prompt or not prompt:IsA("ProximityPrompt") then return part, nil end
    return part, prompt
end

function AutoSteal:setEnabled(v)
    self.enabled = v and true or false
    if self.enabled then
        startWalkSpeedLoop()
        if not self.safePosition then
            local hrp = getHRP()
            if hrp then
                self.safePosition = hrp.CFrame
                self.log("Safe position captured:", tostring(hrp.Position))
            end
        end
    else
        stopWalkSpeedLoop()
    end
    self.stats.lastStatus = self.enabled and "running" or "idle"
end

function AutoSteal:getStats() return self.stats end
function AutoSteal:setSafePosition(cf) self.safePosition = cf end
function AutoSteal:captureSafePosition()
    local hrp = getHRP()
    if hrp then
        self.safePosition = hrp.CFrame
        self.log("Safe position saved at", tostring(hrp.Position))
        return true
    end
    return false
end

function AutoSteal:setTarget(rec)
    if not rec then return self:clearTarget() end
    self.target = rec
    self.log("Target set:", rec.name)
end
function AutoSteal:clearTarget()
    self.target = nil
    self.log("Target cleared")
end
function AutoSteal:getTarget() return self.target end
function AutoSteal:_targetIsValid()
    if not self.target or not self.target.instance or not self.target.instance.Parent then
        return false
    end
    return true
end

-- =========================================================
-- MoveTo — repeats until arrived or hard timeout
-- =========================================================
function AutoSteal:_moveTo(targetPos)
    local hrp = getHRP()
    local hum = getHum()
    if not hrp or not hum then return false end

    -- Make sure humanoid isn't stuck in a weird state
    pcall(function() hum.PlatformStand = false end)
    pcall(function() hum.WalkSpeed = FORCED_WS end)

    local deadline = tick() + self.moveTimeout
    local startPos = hrp.Position
    local startTime = tick()
    local arrived = false
    local lastDist = math.huge
    local stallCount = 0
    local bestDist = math.huge

    while tick() < deadline do
        local current = hrp.Position
        local delta = targetPos - current
        local dist = delta.Magnitude

        if dist < self.arriveDist then
            arrived = true
            break
        end

        -- Track best progress; bail only if we're truly stuck for a long time
        if dist < bestDist - 0.5 then
            bestDist = dist
            stallCount = 0
        else
            stallCount = stallCount + 1
            if stallCount > self.stallTolerance then
                self.log(string.format("Move stalled at %.1f studs (from %.1f)",
                    dist, lastDist))
                break
            end
        end
        lastDist = dist

        -- Re-set WalkSpeed (in case something reset it)
        pcall(function() hum.WalkSpeed = FORCED_WS end)
        -- Re-issue MoveTo
        pcall(function() hum:MoveTo(targetPos) end)

        task.wait(0.1)
    end

    -- Stop movement
    pcall(function() hum:MoveTo(hrp.Position) end)

    local traveled = (hrp.Position - startPos).Magnitude
    local elapsed = tick() - startTime
    if traveled > 1 then
        self.log(string.format("Moved %.1f studs in %.2fs (%.0f studs/s)",
            traveled, elapsed, traveled / math.max(elapsed, 0.001)))
    end

    return arrived
end

function AutoSteal:_firePromptOnPart(part, prompt)
    if not part or not prompt then return false, "missing prompt" end
    if not prompt.Enabled then return false, "prompt disabled" end

    local hrp = getHRP()
    if not hrp then return false, "no HRP" end

    local dist = (part.Position - hrp.Position).Magnitude
    local maxDist = prompt.MaxActivationDistance or 10
    self.log(string.format("Distance to prompt: %.2f / %.2f", dist, maxDist))

    if dist > maxDist then
        return false, string.format("too far (%.1f > %.1f)", dist, maxDist)
    end

    local okB, errB = pcall(function() prompt:InputHoldBegin() end)
    if not okB then return false, "InputHoldBegin: " .. tostring(errB) end

    task.wait((prompt.HoldDuration or 1.2) + 0.05)

    local okE, errE = pcall(function() prompt:InputHoldEnd() end)
    if not okE then return false, "InputHoldEnd: " .. tostring(errE) end

    return true
end

function AutoSteal:_stealOne(rec)
    if self._busy then return false, "busy" end

    local now = tick()
    if now - self._lastGlobal < self.globalCooldown then return false, "global cooldown" end
    if now - (self.lastAttempt[rec.instance] or 0) < self.cooldown then return false, "cooldown" end

    self.lastAttempt[rec.instance] = now
    self._lastGlobal = now
    self._busy = true

    local hrp = getHRP()
    if not hrp then
        self._busy = false
        return false, "no HRP"
    end

    local part, prompt = getPrompt()
    if not part or not prompt then
        self._busy = false
        return false, "prompt not found"
    end

    if not self.safePosition then self.safePosition = hrp.CFrame end

    local targetPos = part.Position + Vector3.new(0, 0.5, 0)

    local moved = self:_moveTo(targetPos)

    if not moved then
        self.log("Could not reach egg")
        if self.safePosition then
            self:_moveTo(self.safePosition.Position)
        end
        self._busy = false
        return false, "unreachable"
    end

    task.wait(0.1)

    self.stats.attempts = self.stats.attempts + 1
    local ok, fireErr = self:_firePromptOnPart(part, prompt)

    if ok then
        self.stats.successes = self.stats.successes + 1
        self.stats.lastStatus = "success: " .. rec.name
        self.log("Success:", rec.name)
    else
        self.stats.failures = self.stats.failures + 1
        self.stats.lastStatus = "failed: " .. fireErr
        self.log("Failed:", rec.name, "—", fireErr)
    end

    if self.returnToOrigin and self.safePosition then
        task.wait(0.15)
        self:_moveTo(self.safePosition.Position)
    end

    self._busy = false
    return ok, fireErr
end

function AutoSteal:startLoop(filters)
    if self._loopRunning then return end
    self._loopRunning = true

    task.spawn(function()
        while self._loopRunning do
            if self.enabled and not self._busy then
                local chosen = nil
                if self:_targetIsValid() then
                    chosen = self.target
                else
                    if self.target then
                        self.log("Target vanished, clearing:", self.target.name)
                        self.target = nil
                    end
                    local matches = self.detector:getMatching(filters.Rarity, filters.Area)
                    if #matches > 0 then
                        local hrp = getHRP()
                        chosen = matches[1]
                        if hrp then
                            local best = math.huge
                            for _, rec in ipairs(matches) do
                                if rec.position then
                                    local d = (rec.position - hrp.Position).Magnitude
                                    if d < best then best = d; chosen = rec end
                                end
                            end
                        end
                    end
                end
                if chosen then
                    self:_stealOne(chosen)
                end
            end
            task.wait(0.5)
        end
    end)
end

function AutoSteal:stopLoop()
    self._loopRunning = false
    self._busy = false
    stopWalkSpeedLoop()
end

function AutoSteal:testFire(rec)
    local part, prompt = getPrompt()
    if not part or not prompt then return false, "prompt not found" end
    if not rec then rec = { instance = prompt, name = "(manual test)" } end
    self.lastAttempt[rec.instance] = 0
    self._lastGlobal = 0
    self._busy = false
    return self:_stealOne(rec)
end

return AutoSteal
