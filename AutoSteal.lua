-- AutoSteal.lua v1.0.0
-- Triggers the shared Workspace.SmartPromptPart.CarryAreaEgg prompt.
-- Teleports to the target egg, fires the prompt, returns to origin.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local AutoSteal = {}
AutoSteal.__index = AutoSteal
AutoSteal.VERSION = "1.0.0"

function AutoSteal.new(detector, opts)
    local self = setmetatable({}, AutoSteal)
    self.detector    = detector
    self.opts        = opts or {}
    self.teleportFirst = self.opts.TeleportFirst ~= false
    self.cooldown    = self.opts.Cooldown or 3
    self.postFireWait = self.opts.PostFireWait or 0.35
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

local function findSharedPrompts()
    local out = {}
    local seen = {}
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("ProximityPrompt") then
            local n = string.lower(inst.Name or "")
            local a = string.lower(inst.ActionText or "")
            local o = string.lower(inst.ObjectText or "")
            if string.find(n, "carry", 1, true)
               or string.find(n, "steal", 1, true)
               or string.find(a, "steal", 1, true)
               or string.find(o, "egg", 1, true) then
                local parent = inst.Parent
                if parent and not seen[parent] then
                    seen[parent] = true
                    table.insert(out, inst)
                end
            end
        end
    end
    return out
end

function AutoSteal:_firePrompt(prompt)
    if not prompt or not prompt.Parent then return false, "no prompt" end
    if not prompt.Enabled then return false, "prompt disabled" end

    local okBegin, errBegin = pcall(function() prompt:InputHoldBegin() end)
    if not okBegin then return false, "holdBegin: " .. tostring(errBegin) end

    task.wait(math.max(0.1, prompt.HoldDuration or 0.4))

    local okEnd, errEnd = pcall(function() prompt:InputHoldEnd() end)
    if not okEnd then return false, "holdEnd: " .. tostring(errEnd) end

    return true
end

function AutoSteal:_stealOne(rec)
    local now = tick()
    if now - (self.lastAttempt[rec.instance] or 0) < self.cooldown then
        return false, "cooldown"
    end
    self.lastAttempt[rec.instance] = now

    local hrp = getHRP()
    if not hrp then return false, "no hrp" end
    if not rec.position then return false, "no position" end

    local savedCF, savedVel
    if self.teleportFirst then
        savedCF  = hrp.CFrame
        savedVel = hrp.AssemblyLinearVelocity
        hrp.CFrame = CFrame.new(rec.position + Vector3.new(0, 4, 0))
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.35)
    end

    local prompts = findSharedPrompts()
    if #prompts == 0 then
        if savedCF then hrp.CFrame = savedCF end
        return false, "no prompt in workspace"
    end

    -- Pick the prompt whose parent part is closest to us
    local best, bestDist = nil, math.huge
    for _, p in ipairs(prompts) do
        local part = p.Parent
        if part and part:IsA("BasePart") then
            local d = (part.Position - hrp.Position).Magnitude
            if d < bestDist then best, bestDist = p, d end
        end
    end
    if not best then
        if savedCF then hrp.CFrame = savedCF end
        return false, "no valid prompt parent"
    end

    self.stats.attempts = self.stats.attempts + 1
    local ok, err = self:_firePrompt(best)

    if ok then
        self.stats.successes = self.stats.successes + 1
        self.stats.lastStatus = "success: " .. rec.name
    else
        self.stats.failures = self.stats.failures + 1
        self.stats.lastStatus = "failed: " .. err
    end

    if self.teleportFirst and savedCF then
        task.wait(self.postFireWait)
        hrp.CFrame = savedCF
        pcall(function() hrp.AssemblyLinearVelocity = savedVel end)
    end

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
                    -- Pick closest target
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

return AutoSteal
