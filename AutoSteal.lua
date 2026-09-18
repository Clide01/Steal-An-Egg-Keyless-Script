-- AutoSteal.lua v2.4 — MoveTo-based movement (no fly, no anchor)

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local AutoSteal = {}
AutoSteal.__index = AutoSteal
AutoSteal.VERSION = "2.4.0"

local PROMPT_PART  = "SmartPromptPart"
local PROMPT_CHILD = "CarryAreaEgg"

function AutoSteal.new(detector, opts)
    local self = setmetatable({}, AutoSteal)
    self.detector   = detector
    self.opts       = opts or {}

    -- WalkSpeed = how fast to move. Server already allows 112.
    self.walkSpeed      = self.opts.WalkSpeed or 250
    self.moveTimeout    = self.opts.MoveTimeout or 6
    self.arriveDist     = self.opts.ArriveDistance or 3

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

-- Unanchor & clear any leftover state from previous failed attempts
local function resetCharacter()
    local hrp = getHRP()
    local hum = getHum()
    if hrp then
        pcall(function() hrp.Anchored = false end)
        pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
    end
    if hum then
        hum.PlatformStand = false
    end
end

function AutoSteal:setEnabled(v)
    self.enabled = v and true or false
    if self.enabled then
        resetCharacter()
        if not self.safePosition then
            local hrp = getHRP()
            if hrp then
                self.safePosition = hrp.CFrame
                self.log("Safe position captured:", tostring(hrp.Position))
            end
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
-- MoveTo-based walking. Uses the game's own locomotion,
-- so the server has zero reason to flag or reject it.
-- =========================================================
function AutoSteal:_moveTo(targetPos)
    local hrp = getHRP()
    local hum = getHum()
    if not hrp or not hum then return false, "no HRP/hum" end

    resetCharacter()

    local oldWS = hum.WalkSpeed
    hum.WalkSpeed = self.walkSpeed

    local deadline = tick() + self.moveTimeout
    local arrived = false
    local lastDist = math.huge
    local stallCount = 0
    local startPos = hrp.Position
    local startTime = tick()

    while tick() < deadline do
        local current = hrp.Position
        local delta = targetPos - current
        local dist = delta.Magnitude

        if dist < self.arriveDist then
            arrived = true
            break
        end

        -- Stall detection
        if math.abs(dist - lastDist) < 0.2 then
            stallCount = stallCount + 1
            if stallCount > 25 then
                self.log(string.format("Move stalled at dist=%.1f", dist))
                break
            end
        else
            stallCount = 0
        end
        lastDist = dist

        -- Issue a new MoveTo — repeating it helps when the game cancels
        pcall(function() hum:MoveTo(targetPos) end)

        task.wait(0.1)
    end

    -- Stop movement
    pcall(function() hum:MoveTo(hrp.Position) end)
    hum.WalkSpeed = oldWS or 16

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
    local now = tick()
    if now - self._lastGlobal < self.globalCooldown then return false, "global cooldown" end
    if now - (self.lastAttempt[rec.instance] or 0) < self.cooldown then return false, "cooldown" end

    self.lastAttempt[rec.instance] = now
    self._lastGlobal = now

    resetCharacter()

    local hrp = getHRP()
    if not hrp then return false, "no HRP" end

    local part, prompt = getPrompt()
    if not part or not prompt then return false, "prompt not found" end

    if not self.safePosition then
        self.safePosition = hrp.CFrame
    end

    -- Aim slightly above the prompt so we don't collide with its base
    local targetPos = part.Position + Vector3.new(0, 0.5, 0)

    local moved, moveErr = self:_moveTo(targetPos)
    if not moved then
        self.log("Move failed:", moveErr or "timeout")
        if self.safePosition then
            self:_moveTo(self.safePosition.Position)
        end
        return false, "move failed"
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

function AutoSteal:stopLoop()
    self._loopRunning = false
    resetCharacter()
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
