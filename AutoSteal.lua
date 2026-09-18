-- AutoSteal.lua v2.1 — flying + selectable target

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local AutoSteal = {}
AutoSteal.__index = AutoSteal
AutoSteal.VERSION = "2.1.0"

local PROMPT_PART  = "SmartPromptPart"
local PROMPT_CHILD = "CarryAreaEgg"

function AutoSteal.new(detector, opts)
    local self = setmetatable({}, AutoSteal)
    self.detector   = detector
    self.opts       = opts or {}

    self.flySpeed       = self.opts.FlySpeed or 200
    self.returnSpeed    = self.opts.ReturnSpeed or (self.flySpeed * 2)
    self.flyTimeout     = self.opts.FlyTimeout or 6
    self.arriveDist     = self.opts.ArriveDistance or 3
    self.useFly         = self.opts.UseFly ~= false

    self.cooldown       = self.opts.Cooldown or 2
    self.globalCooldown = self.opts.GlobalCooldown or 0.5
    self._lastGlobal    = 0

    self.returnToOrigin = self.opts.ReturnToOrigin ~= false
    self.safePosition   = nil

    -- Selected target
    self.target         = nil   -- egg record or nil

    self.enabled      = false
    self.lastAttempt  = {}
    self.stats        = { attempts = 0, successes = 0, failures = 0, lastStatus = "idle" }
    self._loopRunning = false
    self.log = function(...) print("[AutoSteal]", ...) end
    return self
end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getPrompt()
    local part = workspace:FindFirstChild(PROMPT_PART)
    if not part then return nil, nil end
    local prompt = part:FindFirstChild(PROMPT_CHILD)
    if not prompt or not prompt:IsA("ProximityPrompt") then return part, nil end
    return part, prompt
end

-- =========================================================
-- Enable / safe position
-- =========================================================
function AutoSteal:setEnabled(v)
    self.enabled = v and true or false
    if self.enabled and not self.safePosition then
        local hrp = getHRP()
        if hrp then
            self.safePosition = hrp.CFrame
            self.log("Safe position captured:", tostring(hrp.Position))
        end
    end
    self.stats.lastStatus = self.enabled and "running" or "idle"
end

function AutoSteal:getStats() return self.stats end
function AutoSteal:setSafePosition(cf) self.safePosition = cf end
function AutoSteal:captureSafePosition()
    local hrp = getHRP()
    if hrp then
        self.safePosition = hrp.CFrame
        self.log("Safe position captured at", tostring(hrp.Position))
        return true
    end
    return false
end

-- =========================================================
-- Target selection
-- =========================================================
function AutoSteal:setTarget(rec)
    if not rec then return self:clearTarget() end
    self.target = rec
    self.log("Target set:", rec.name, "|", rec.instance:GetFullName())
end

function AutoSteal:clearTarget()
    self.target = nil
    self.log("Target cleared")
end

function AutoSteal:getTarget() return self.target end

function AutoSteal:_targetIsValid()
    if not self.target then return false end
    if not self.target.instance or not self.target.instance.Parent then
        return false
    end
    return true
end

-- =========================================================
-- Fly movement
-- =========================================================
function AutoSteal:_flyTo(targetPos, speedOverride)
    local hrp = getHRP()
    if not hrp then return false, "no HRP" end

    local speed = speedOverride or self.flySpeed
    local deadline = tick() + self.flyTimeout
    local arrived = false

    local attach = Instance.new("Attachment")
    attach.Name = "__AutoStealFly"
    attach.Parent = hrp

    local bv = Instance.new("BodyVelocity")
    bv.Name = "__AutoStealFlyBV"
    bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bv.P = 12500
    bv.Velocity = Vector3.zero
    bv.Parent = hrp

    local useBodyVel = true

    while tick() < deadline do
        local current = hrp.Position
        local delta = targetPos - current
        local dist = delta.Magnitude

        if dist < self.arriveDist then
            arrived = true
            break
        end

        if useBodyVel and bv.Parent then
            bv.Velocity = delta.Unit * speed
        else
            useBodyVel = false
            local stepDist = math.min(speed / 60, dist)
            hrp.CFrame = CFrame.new(current + delta.Unit * stepDist)
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
        RunService.Heartbeat:Wait()
    end

    if bv.Parent then bv:Destroy() end
    if attach.Parent then attach:Destroy() end
    pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)

    return arrived
end

-- =========================================================
-- Fire prompt
-- =========================================================
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

-- =========================================================
-- Single steal
-- =========================================================
function AutoSteal:_stealOne(rec)
    local now = tick()

    if now - self._lastGlobal < self.globalCooldown then
        return false, "global cooldown"
    end
    if now - (self.lastAttempt[rec.instance] or 0) < self.cooldown then
        return false, "cooldown"
    end

    self.lastAttempt[rec.instance] = now
    self._lastGlobal = now

    local hrp = getHRP()
    if not hrp then return false, "no HRP" end

    local part, prompt = getPrompt()
    if not part or not prompt then
        return false, "SmartPromptPart.CarryAreaEgg not found"
    end

    if not self.safePosition then
        self.safePosition = hrp.CFrame
    end

    local targetPos = part.Position + Vector3.new(0, 4, 0)

    local moved, moveErr
    if self.useFly then
        moved, moveErr = self:_flyTo(targetPos)
    else
        hrp.CFrame = CFrame.new(targetPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.3)
        moved = true
    end

    if not moved then
        self.log("Move failed:", moveErr)
        return false, "move failed: " .. tostring(moveErr)
    end

    task.wait(0.15)

    self.stats.attempts = self.stats.attempts + 1
    local ok, err = self:_firePromptOnPart(part, prompt)

    if ok then
        self.stats.successes = self.stats.successes + 1
        self.stats.lastStatus = "success: " .. rec.name
        self.log("Success:", rec.name)
    else
        self.stats.failures = self.stats.failures + 1
        self.stats.lastStatus = "failed: " .. err
        self.log("Failed:", rec.name, "—", err)
    end

    if self.returnToOrigin then
        task.wait(0.2)
        local dest = self.safePosition
        if self.useFly then
            self:_flyTo(dest.Position, self.returnSpeed)
            pcall(function() hrp.CFrame = CFrame.new(hrp.Position, dest.Position) end)
        else
            hrp.CFrame = dest
        end
    end

    return ok, err
end

-- =========================================================
-- Auto loop with target priority
-- =========================================================
function AutoSteal:startLoop(filters)
    if self._loopRunning then return end
    self._loopRunning = true

    task.spawn(function()
        while self._loopRunning do
            if self.enabled then
                local chosen = nil

                -- 1) Prefer selected target if still valid
                if self:_targetIsValid() then
                    chosen = self.target
                else
                    -- target vanished — auto-clear
                    if self.target then
                        self.log("Target vanished, clearing:", self.target.name)
                        self.target = nil
                    end

                    -- 2) Fall back to nearest matching egg
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
                    local ok, err = self:_stealOne(chosen)
                    if not ok and err ~= "cooldown" and err ~= "global cooldown" then
                        self.log("Failed:", chosen.name, "—", err)
                    end
                end
            end
            task.wait(0.3)
        end
    end)
end

function AutoSteal:stopLoop()
    self._loopRunning = false
end

function AutoSteal:testFire(rec)
    local part, prompt = getPrompt()
    if not part or not prompt then return false, "prompt not found" end
    if not rec then rec = { instance = prompt, name = "(manual test)" } end
    self.lastAttempt[rec.instance] = 0
    self._lastGlobal = 0
    return self:_stealOne(rec)
end

return AutoSteal
