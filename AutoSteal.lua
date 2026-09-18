-- AutoSteal.lua v2.3 — anchored flight (real speed, no rubber-band)

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local AutoSteal = {}
AutoSteal.__index = AutoSteal
AutoSteal.VERSION = "2.3.0"

local PROMPT_PART  = "SmartPromptPart"
local PROMPT_CHILD = "CarryAreaEgg"

function AutoSteal.new(detector, opts)
    local self = setmetatable({}, AutoSteal)
    self.detector   = detector
    self.opts       = opts or {}

    self.flySpeed       = self.opts.FlySpeed or 600         -- studs/sec
    self.returnSpeed    = self.opts.ReturnSpeed or 900      -- studs/sec
    self.stepMax        = self.opts.StepMax or 40           -- hard cap: studs/frame
    self.flyTimeout     = self.opts.FlyTimeout or 8
    self.arriveDist     = self.opts.ArriveDistance or 4

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
    if not self.target then return false end
    if not self.target.instance or not self.target.instance.Parent then return false end
    return true
end

-- =========================================================
-- Anchored flight — the humanoid can't fight an anchored part,
-- so CFrame moves land exactly. No rubber-band possible.
-- =========================================================
function AutoSteal:_flyTo(targetPos, speedOverride)
    local hrp = getHRP()
    local hum = getHum()
    if not hrp then return false, "no HRP" end

    local speed = speedOverride or self.flySpeed
    local deadline = tick() + self.flyTimeout
    local frames = 0
    local startTime = tick()
    local startPos = hrp.Position

    -- Save & freeze humanoid
    local oldAnchored = hrp.Anchored
    local oldWS, oldJP, oldPS
    if hum then
        oldWS = hum.WalkSpeed
        oldJP = hum.JumpPower
        oldPS = hum.PlatformStand
        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.PlatformStand = true
    end

    -- Anchor the HRP — this is what makes CFrame movement stick
    hrp.Anchored = true

    -- Zero velocities
    pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
    pcall(function() hrp.AssemblyAngularVelocity = Vector3.zero end)

    local arrived = false
    local lastDist = math.huge
    local stalledFrames = 0

    while tick() < deadline do
        local current = hrp.Position
        local delta = targetPos - current
        local dist = delta.Magnitude

        if dist < self.arriveDist then
            arrived = true
            break
        end

        -- Stall detection (only triggers if truly stuck)
        if math.abs(dist - lastDist) < 0.1 then
            stalledFrames = stalledFrames + 1
            if stalledFrames > 30 then
                self.log("Flight stalled — bailing")
                break
            end
        else
            stalledFrames = 0
        end
        lastDist = dist

        -- Speed is in studs/sec; assume ~60fps for the per-frame step
        local stepDist = math.min(speed / 60, self.stepMax, dist)
        local newPos = current + delta.Unit * stepDist

        -- Face the direction of travel
        local lookTarget = newPos + (targetPos - newPos).Unit
        hrp.CFrame = CFrame.lookAt(newPos, lookTarget)

        frames = frames + 1
        RunService.Heartbeat:Wait()
    end

    -- Restore
    hrp.Anchored = oldAnchored
    if hum then
        hum.PlatformStand = oldPS or false
        hum.WalkSpeed = oldWS or 16
        hum.JumpPower = oldJP or 50
    end

    local elapsed = tick() - startTime
    local traveled = (hrp.Position - startPos).Magnitude
    self.log(string.format("Flight: %.1f studs in %.2fs (%.0f studs/s, %d frames)",
        traveled, elapsed, traveled / math.max(elapsed, 0.001), frames))

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
    local now = tick()
    if now - self._lastGlobal < self.globalCooldown then return false, "global cooldown" end
    if now - (self.lastAttempt[rec.instance] or 0) < self.cooldown then return false, "cooldown" end

    self.lastAttempt[rec.instance] = now
    self._lastGlobal = now

    local hrp = getHRP()
    if not hrp then return false, "no HRP" end

    local part, prompt = getPrompt()
    if not part or not prompt then return false, "prompt not found" end

    if not self.safePosition then
        self.safePosition = hrp.CFrame
    end

    -- Aim at the prompt (which hovers over the target egg)
    local targetPos = part.Position + Vector3.new(0, 3, 0)

    local moved = self:_flyTo(targetPos, self.flySpeed)
    if not moved then
        self.log("Move failed — returning to safe")
        if self.safePosition then
            self:_flyTo(self.safePosition.Position, self.returnSpeed)
        end
        return false, "move failed"
    end

    task.wait(0.12)

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
        self:_flyTo(self.safePosition.Position, self.returnSpeed)
    end

    return ok, fireErr
end

function AutoSteal:startLoop(filters)
    if self._loopRunning then return end
    self._loopRunning = true

    task.spawn(function()
        while self._loopRunning do
            if self.enabled then
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
                    local ok, err = self:_stealOne(chosen)
                    if not ok and err ~= "cooldown" and err ~= "global cooldown" then
                        self.log("Failed:", chosen.name, "—", err)
                    end
                end
            end
            task.wait(0.2)
        end
    end)
end

function AutoSteal:stopLoop() self._loopRunning = false end

function AutoSteal:testFire(rec)
    local part, prompt = getPrompt()
    if not part or not prompt then return false, "prompt not found" end
    if not rec then rec = { instance = prompt, name = "(manual test)" } end
    self.lastAttempt[rec.instance] = 0
    self._lastGlobal = 0
    return self:_stealOne(rec)
end

return AutoSteal
