-- AutoSteal.lua v2.0 — flying + return-to-origin
-- Flies to the egg, fires the shared prompt, flies back to your safe position.

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local AutoSteal = {}
AutoSteal.__index = AutoSteal
AutoSteal.VERSION = "2.0.0"

local PROMPT_PART  = "SmartPromptPart"
local PROMPT_CHILD = "CarryAreaEgg"

function AutoSteal.new(detector, opts)
    local self = setmetatable({}, AutoSteal)
    self.detector     = detector
    self.opts         = opts or {}

    -- Movement
    self.flySpeed     = self.opts.FlySpeed or 60        -- studs/second
    self.flyTimeout   = self.opts.FlyTimeout or 5       -- max seconds per hop
    self.arriveDist   = self.opts.ArriveDistance or 3   -- considered "arrived" within N studs
    self.useFly       = self.opts.UseFly ~= false       -- true = fly, false = teleport

    -- Cooldowns
    self.cooldown     = self.opts.Cooldown or 3         -- per-egg cooldown
    self.globalCooldown = self.opts.GlobalCooldown or 1 -- between any two steals
    self._lastGlobal  = 0

    -- Return behavior
    self.returnToOrigin = self.opts.ReturnToOrigin ~= false
    self.safePosition = nil                             -- captured on first steal

    self.enabled      = false
    self.lastAttempt  = {}
    self.stats        = { attempts = 0, successes = 0, failures = 0, lastStatus = "idle" }
    self._loopRunning = false
    self.log = function(...) print("[AutoSteal]", ...) end
    return self
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
    self.log("Enabled:", self.enabled)
end

function AutoSteal:getStats() return self.stats end
function AutoSteal:setSafePosition(cf) self.safePosition = cf end
function AutoSteal:clearSafePosition() self.safePosition = nil end
function AutoSteal:captureSafePosition()
    local hrp = getHRP()
    if hrp then
        self.safePosition = hrp.CFrame
        self.log("Safe position captured at", tostring(hrp.Position))
        return true
    end
    return false
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
-- Fly movement
-- =========================================================
function AutoSteal:_flyTo(targetPos, speedOverride)
    local hrp = getHRP()
    if not hrp then return false, "no HRP" end

    local speed = speedOverride or self.flySpeed
    local deadline = tick() + self.flyTimeout
    local arrived = false

    -- Use BodyVelocity for smooth physics-based motion.
    -- Falls back to CFrame stepping if the constraint is stripped by the game.
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
            -- fallback: step CFrame directly
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

function AutoSteal:_teleportTo(targetPos)
    local hrp = getHRP()
    if not hrp then return false, "no HRP" end
    hrp.CFrame = CFrame.new(targetPos)
    hrp.AssemblyLinearVelocity = Vector3.zero
    return true
end

-- =========================================================
-- Fire the prompt
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

    task.wait((prompt.HoldDuration or 1.2) + 0.10)

    local okE, errE = pcall(function() prompt:InputHoldEnd() end)
    if not okE then return false, "InputHoldEnd: " .. tostring(errE) end

    return true
end

-- =========================================================
-- Single steal cycle
-- =========================================================
function AutoSteal:_stealOne(rec)
    local now = tick()

    -- Global cooldown
    if now - self._lastGlobal < self.globalCooldown then
        return false, "global cooldown"
    end

    -- Per-egg cooldown
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

    -- Ensure we have a safe position to return to
    if not self.safePosition then
        self.safePosition = hrp.CFrame
    end

    -- Aim at the prompt (it hovers over the target egg)
    local targetPos = part.Position + Vector3.new(0, 4, 0)

    -- Save current state for potential fallback return
    local beforeCF = hrp.CFrame

    -- Move to the egg
    local moved, moveErr
    if self.useFly then
        moved, moveErr = self:_flyTo(targetPos)
    else
        moved, moveErr = self:_teleportTo(targetPos)
        task.wait(0.3)
    end

    if not moved then
        self.log("Move failed:", moveErr)
        return false, "move failed: " .. tostring(moveErr)
    end

    -- Small settle so the SmartPromptPart locks onto us
    task.wait(0.15)

    -- Fire the prompt
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

    -- Immediately retreat to safety
    if self.returnToOrigin then
        -- brief wait to let the egg attach to the character (game-specific)
        task.wait(0.25)

        local dest = self.safePosition
        local flyBackOK
        if self.useFly then
            flyBackOK = self:_flyTo(dest.Position, self.flySpeed * 1.35)
        else
            flyBackOK = self:_teleportTo(dest.Position)
        end
        if flyBackOK and self.useFly then
            pcall(function() hrp.CFrame = CFrame.new(hrp.Position, dest.Position) end)
        end
    end

    return ok, err
end

-- =========================================================
-- Auto loop
-- =========================================================
function AutoSteal:startLoop(filters)
    if self._loopRunning then return end
    self._loopRunning = true

    task.spawn(function()
        while self._loopRunning do
            if self.enabled then
                local matches = self.detector:getMatching(filters.Rarity, filters.Area)
                if #matches > 0 then
                    local hrp = getHRP()
                    local closest = matches[1]
                    if hrp then
                        local best = math.huge
                        for _, rec in ipairs(matches) do
                            if rec.position then
                                local d = (rec.position - hrp.Position).Magnitude
                                if d < best then best = d; closest = rec end
                            end
                        end
                    end
                    local ok, err = self:_stealOne(closest)
                    if not ok and err ~= "cooldown" and err ~= "global cooldown" then
                        self.log("Failed:", closest.name, "—", err)
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
    if not rec then
        rec = { instance = prompt, name = "(manual test)" }
    end
    -- Bypass the per-egg cooldown for a manual test
    self.lastAttempt[rec.instance] = 0
    self._lastGlobal = 0
    return self:_stealOne(rec)
end

return AutoSteal
