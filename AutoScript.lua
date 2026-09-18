-- AutoScript.lua
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local UI_URL = "https://raw.githubusercontent.com/Clide01/PlundererHub/refs/heads/main/ScreenUI.lua"

local AutoUI = loadstring(game:HttpGet(UI_URL, true))()
local ui = AutoUI.new(PlayerGui, {
    Title    = "PlundererHub",
    Subtitle = "Steal An Egg",
})

-- ===== Main tab =====
local main = ui:addTab("Main", "🏠")

local autoSection = ui:addSection(main, "Automation")
ui:addToggle(autoSection, "Auto Steal Egg", false, function(v)
    print("[Auto] Auto Steal Egg:", v)
    -- your logic here
end)
ui:addToggle(autoSection, "Auto Steal Selected Eggs", false, function(v)
    print("[Auto] Selected Eggs:", v)
end)
ui:addToggle(autoSection, "Auto Steal Secret Egg", false, function(v)
    print("[Auto] Secret Egg:", v)
end)

local filterSection = ui:addSection(main, "Filters")
ui:addDropdown(filterSection, "Areas to Steal", {
    "All", "Starter Island", "Desert", "Snow", "Volcano", "Space"
}, "All", function(v)
    print("[Filter] Area:", v)
end)
ui:addDropdown(filterSection, "Egg Rarities to Steal", {
    "All", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"
}, "Rare", function(v)
    print("[Filter] Rarity:", v)
end)
ui:addSlider(filterSection, "Max Pets to Keep", 0, 250, 50, function(v)
    print("[Filter] Max:", v)
end)

-- ===== Misc tab =====
local misc = ui:addTab("Misc", "⚙️")
local perf = ui:addSection(misc, "Performance")
ui:addToggle(perf, "Low Graphics Mode", false, function(v)
    -- toggle lighting / particles
end)
ui:addToggle(perf, "Silent Mode (no meme)", false, function(v) end)
ui:addSlider(perf, "Walk Speed", 16, 200, 16, function(v)
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char.Humanoid.WalkSpeed = v
    end
end)

local links = ui:addSection(misc, "Links")
ui:addButton(links, "Copy Discord Invite", function()
    if setclipboard then setclipboard("https://discord.gg/yourserver") end
end)
ui:addButton(links, "Reload UI", function()
    ui:destroy()
    loadstring(game:HttpGet("https://.../AutoScript.lua"))()
end)

-- ===== Status =====
ui:setStatus("Idle", "idle")
ui:setBottomStatus("Ready — v1.0.0")
