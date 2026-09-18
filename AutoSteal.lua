-- AutoSteal.lua v1.1.0
-- Directly targets Workspace.SmartPromptPart.CarryAreaEgg.
-- Teleports to the PROMPT (not the egg), holds for the exact duration.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local AutoSteal = {}
AutoSteal.__index = AutoSteal
AutoSteal.VERSION = "1.1.0"

local PROMPT_PATH = { "SmartPromptPart", "CarryAreaEgg" }

function AutoSteal.new(detector, opts)
    local self = setmetatable({}, AutoSteal)
    self.detector    = detector
    self.opts        = opts or {}
    self.cooldown    = self.opts.Cooldown or 3
    self.postFireWait = self.opts.PostFireWait or 0.4
    self.enabled     = false
    self.lastAttempt = {}
    self.stats       = { attempts = 0, successes = 0, failures = 0, lastStatus = "idle" }
    self._loopRunning = false
    self.log = function(...) print("[AutoSteal]", ...) end
    return self
end

function AutoSteal:setEnabled(v)
    self.enabled = v and true or false
    self.stats.lastStatus = self.enabled and "running" or "idle"
    self.log("Enabled:", self.enabled)
end

function AutoSteal:getStats() return self.stats end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getPrompt()
    local part = workspace:FindFirstChild(PROMPT_PATH[1])
    if not part then return nil, nil end
    local prompt = part:FindFirstChild(PROMPT_PATH[2])
    if not prompt or not prompt:IsA("ProximityPrompt") then return part, nil end
    return part, prompt
end

function AutoSteal:_firePromptOnPart(part, prompt)
    if not part or not prompt then return false, "missing prompt" end
    if not prompt.Enabled then return false, "prompt disabled" end

    local hrp = getHRP()
    if not hrp then return false, "no HRP" end

    -- Verify we're within MaxActivationDistance of the prompt's part
    local partPos = part.Position
    local myPos   = hrp.Position
    local dist    = (partPos - myPos).Magnitude
    local maxDist = prompt.MaxActivationDistance or 10

    self.log(string.format("Distance to prompt: %.2f / %.2f", dist, maxDist))

    -- Fire the hold sequence
    local okB, errB = pcall(function() prompt:InputHoldBegin() end)
    if not okB then return false, "InputHoldBegin: " .. tostring(errB) end

    -- Wait EXACTLY the hold duration + small buffer
    task.wait((prompt.HoldDuration or 1.2) + 0.05)

    local okE, errE = pcall(function() prompt:InputHoldEnd() end)
    if not okE then return false, "InputHoldEnd: " .. tostring(errE) end

    return true
end

function AutoSteal:_stealOne(rec)
    local now = tick()
    if now - (self.lastAttempt[rec.instance] or 0) < self.cooldown then
        return false, "cooldown"
    end
    self.lastAttempt[rec.instance] = now

    local hrp = getHRP()
    if not hrp then return false, "no HRP" end

    local part, prompt = getPrompt()
    if not part or not prompt then
        return false, "SmartPromptPart.CarryAreaEgg not found"
    end

    -- Save position
    local savedCF, savedVel = hrp.CFrame, hrp.AssemblyLinearVelocity

    -- Teleport to the PROMPT's position (plus a small Y offset to sit on top)
    local target = part.Position + Vector3.new(0, 4, 0)
    hrp.CFrame = CFrame.new(target)
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.35)

    -- Fire it
    self.stats.attempts = self.stats.attempts + 1
    local ok, err = self:_firePromptOnPart(part, prompt)

    -- Log result and wait for the game's own steal logic to finish
    if ok then
        self.stats.successes = self.stats.successes + 1
        self.stats.lastStatus = "success: " .. rec.name
        self.log("Fired on", rec.name, "— OK")
    else
        self.stats.failures = self.stats.failures + 1
        self.stats.lastStatus = "failed: " .. err
        self.log("Fired on", rec.name, "—", err)
    end

    -- Return to saved position
    task.wait(self.postFireWait)
    hrp.CFrame = savedCF
    pcall(function() hrp.AssemblyLinearVelocity = savedVel end)

    return ok, err
end

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
                                if d < best then
                                    best = d
                                    closest = rec
                                end
                            end
                        end
                    end
                    local ok, err = self:_stealOne(closest)
                    if not ok and err ~= "cooldown" then
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

-- Manual test helper
function AutoSteal:testFire(rec)
    local part, prompt = getPrompt()
    if not part or not prompt then return false, "prompt not found" end
    if not rec then
        local hrp = getHRP()
        if not hrp then return false, "no HRP" end
        rec = { instance = prompt, name = "(manual test)", position = part.Position }
    end
    return self:_stealOne(rec)
end

return AutoSteal
