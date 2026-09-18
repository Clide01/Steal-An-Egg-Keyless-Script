-- RemoteSpy.lua v1.0.0
-- Hooks __namecall to log every RemoteEvent:FireServer and RemoteFunction:InvokeServer.
-- Also logs ProximityPrompt triggers as a secondary signal.
-- Passive — does not affect gameplay.

local ProximityPromptService = game:GetService("ProximityPromptService")

local RemoteSpy = {}
RemoteSpy.__index = RemoteSpy
RemoteSpy.VERSION = "1.0.0"

local DEFAULT_MAX = 500

-- =========================================================
-- Constructor
-- =========================================================
function RemoteSpy.new(opts)
    local self = setmetatable({}, RemoteSpy)
    self.opts        = opts or {}
    self.filter      = self.opts.Filter or ""       -- lowercase substring
    self.verbose     = self.opts.Verbose or false   -- true = log everything
    self.enabled     = false
    self.captures    = {}
    self.maxCaptures = self.opts.MaxCaptures or DEFAULT_MAX
    self.listeners   = {}
    self.promptConn  = nil
    return self
end

-- =========================================================
-- Events
-- =========================================================
function RemoteSpy:onCapture(fn)
    table.insert(self.listeners, fn)
    return function()
        for i, l in ipairs(self.listeners) do
            if l == fn then table.remove(self.listeners, i); break end
        end
    end
end

function RemoteSpy:_emit(entry)
    for _, fn in ipairs(self.listeners) do
        task.spawn(function()
            local ok, err = pcall(fn, entry)
            if not ok then warn("[RemoteSpy] Listener error:", err) end
        end)
    end
end

function RemoteSpy:_addCapture(entry)
    table.insert(self.captures, entry)
    if #self.captures > self.maxCaptures then
        table.remove(self.captures, 1)
    end
    self:_emit(entry)
end

function RemoteSpy:getCaptures() return self.captures end
function RemoteSpy:clearCaptures() self.captures = {} end

function RemoteSpy:setFilter(s)
    self.filter = string.lower(s or "")
    print("[RemoteSpy] Filter set to:", self.filter == "" and "(none)" or self.filter)
end

function RemoteSpy:setVerbose(v)
    self.verbose = v and true or false
    print("[RemoteSpy] Verbose:", self.verbose)
end

-- =========================================================
-- Helpers
-- =========================================================
local function getPath(inst)
    if not inst then return "<nil>" end
    local ok, p = pcall(function() return inst:GetFullName() end)
    if ok and p then return p end
    local ok2, n = pcall(function() return inst.Name end)
    return ok2 and n or "<unknown>"
end

local function formatArgs(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        local v = select(i, ...)
        local t = typeof(v)
        if t == "Instance" then
            table.insert(parts, string.format("<%s> %s", v.ClassName, getPath(v)))
        elseif t == "table" then
            local ok, enc = pcall(function()
                return game:GetService("HttpService"):JSONEncode(v)
            end)
            if ok and enc then
                if #enc > 240 then enc = string.sub(enc, 1, 240) .. "..." end
                table.insert(parts, enc)
            else
                table.insert(parts, "<table>")
            end
        elseif t == "string" then
            local s = v
            if #s > 240 then s = string.sub(s, 1, 240) .. "..." end
            table.insert(parts, string.format("%q", s))
        else
            table.insert(parts, tostring(v))
        end
    end
    return table.concat(parts, ", ")
end

-- =========================================================
-- Start / stop
-- =========================================================
function RemoteSpy:start()
    if self.enabled then return end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        warn("[RemoteSpy] Executor lacks hookmetamethod / getnamecallmethod")
        return
    end

    self.enabled = true
    print("[RemoteSpy] v" .. RemoteSpy.VERSION .. " hooked __namecall")

    local spy = self
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if spy.enabled and (method == "FireServer" or method == "InvokeServer") then
            local path = getPath(self)
            local args = formatArgs(...)

            local matched = spy.verbose
            if not matched and spy.filter ~= "" then
                matched = string.find(string.lower(path), spy.filter, 1, true) ~= nil
            end

            if matched then
                local entry = {
                    time   = os.time(),
                    source = "remote",
                    path   = path,
                    method = method,
                    args   = args,
                    remote = self,
                }
                spy:_addCapture(entry)
                print(string.format("[RemoteSpy] %s:%s(%s)", path, method, args))
            end
        end
        return oldNamecall(self, ...)
    end)

    -- Secondary signal: prompt triggers (fires when YOU steal manually)
    self.promptConn = ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if not spy.enabled then return end
        if player ~= nil and player ~= game:GetService("Players").LocalPlayer then return end
        local entry = {
            time   = os.time(),
            source = "prompt",
            path   = prompt:GetFullName(),
            method = "PromptTriggered",
            args   = string.format("Action=%q Object=%q", prompt.ActionText or "", prompt.ObjectText or ""),
        }
        spy:_addCapture(entry)
        print(string.format("[RemoteSpy] PROMPT: %s (%s)", entry.path, entry.args))
    end)
end

function RemoteSpy:stop()
    if not self.enabled then return end
    self.enabled = false
    if self.promptConn then self.promptConn:Disconnect(); self.promptConn = nil end
    print("[RemoteSpy] disabled")
end

function RemoteSpy:dump(limit)
    limit = limit or 50
    print("[RemoteSpy] === DUMP (" .. #self.captures .. " total) ===")
    for i = math.max(1, #self.captures - limit + 1), #self.captures do
        local c = self.captures[i]
        print(string.format("  [%d] %s %s:%s(%s)", i, c.source, c.path, c.method, c.args))
    end
end

return RemoteSpy
