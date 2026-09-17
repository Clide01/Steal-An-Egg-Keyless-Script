--[[
    Steal an Egg — Auto Grab Field Eggs (Catalog Edition)
    For Delta Executor

    Features:
      - Full 167-egg catalog baked in
      - Dropdown grouped by rarity with color coding
      - Search + rarity filter
      - Icon preview per egg
      - Safe zone return
      - Re-execution safe
]]

-- ============================================================
--  RE-EXECUTION GUARD
-- ============================================================
local GENV = getgenv and getgenv() or _G
if GENV.__AutoGrabInstance and GENV.__AutoGrabInstance.cleanup then
    pcall(function() GENV.__AutoGrabInstance.cleanup() end)
    print("[AutoGrab] Previous instance stopped.")
end
GENV.__AutoGrabInstance = nil

-- ============================================================
--  Services
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ===== CONFIG =====
local GRAB_COOLDOWN        = 2.0
local TELEPORT_DELAY       = 0.35
local RETURN_DELAY         = 0.55
local EGG_ARRIVE_OFFSET    = Vector3.new(0, 3, 0)
local RESCAN_INTERVAL      = 30
-- ==================

------------------------------------------------------------
-- CATALOG (compact pipe format)
-- displayName|category|rarity|rarityNum|iconAssetId
------------------------------------------------------------
local CATALOG_RAW = [[
Aetheron|Aetheron|Divine|10|98329267204643
ArchAngel|ArchAngel|Divine|10|85963541672111
Archdemon Dragon|Archdemon Dragon|Divine|10|109846660752456
Cthulhu|Cthulhu|Divine|10|113826857989447
Dreadscale|Dreadscale|Divine|10|99528919442101
Kitsune|Kitsune|Divine|10|136779412524244
Luminous Cthulhu|Depths Cthulhu|Divine|10|103020287697704
Mecha Dreadscale|Mecha Dreadscale|Divine|10|96353647829204
Nightflame|Godzilla|Divine|10|134762388111337
Shattered Colossus|Shattered Colossus|Divine|10|124927737636564
Unicorn|Unicorn|Divine|10|126240842939586
World Burner|World Burner|Divine|10|117970605290776
Balrog|Balrog|Eternal|9|109846660752456
El Maja|El Maja|Eternal|9|86275614169244
Equinox|Equinox|Eternal|9|73572093043918
Eternal Lunar Dragon|Eternal Lunar Dragon|Eternal|9|76095389378180
Gorilla King|King Kong|Eternal|9|140733363307193
Ice Dragon|Ice Dragon|Eternal|9|119489463003928
Krakenoid|Krakenoid|Eternal|9|99528919442101
Lava Dragon|Dragon|Eternal|9|137621122825975
Luminous Electric Eel|Depths Electric Eel|Eternal|9|103020287697704
Luminous Terra Snapper|Depths Terra Snapper|Eternal|9|103020287697704
Mecha Crocodon|Mecha Crocodon|Eternal|9|96353647829204
Mecha Krakenoid|Mecha Krakenoid|Eternal|9|96353647829204
Mosasaurus|Mosasaurus|Eternal|9|110731551346220
Oni Tiger|Oni Tiger|Eternal|9|103494726830799
Pegasus|Pegasus|Eternal|9|79544542526316
Phoenix|Ascended Vermilion Phoenix|Eternal|9|134491333572507
Shattered Drake|Shattered Drake|Eternal|9|124927737636564
Skeleton Horse|Skeleton Horse|Eternal|9|136184113799222
Strawberry Elephant|Strawberry Elephant|Eternal|9|81000367959664
Terra Snapper|Terra Snapper|Eternal|9|113826857989447
Void Dragon|Void Dragon|Eternal|9|124581147164560
Void Serpent|Void Serpent|Eternal|9|97679329738336
World Eater|World Eater|Eternal|9|136340085637939
Abyss Overlord|Abyss Overlord OP|Secret|8|92114389149544
Abyss Overlord|Abyss Overlord|Secret|8|92114389149544
Bombo Croco|Bomboclat Crocolat|Secret|8|81000367959664
Centaur|Centaur|Secret|8|94996357404675
Cerberus|Cerberus|Secret|8|81989677951623
Cosmic Dragon|Cave Dragon|Secret|8|108447968078067
Cosmic Skeleton Boss|Alien Skeleton Boss|Secret|8|102395451894667
Crocodon|Crocodon|Secret|8|99528919442101
Electric Eel|Electric Eel|Secret|8|113826857989447
Ember Dragon|Ember Dragon|Secret|8|124581147164560
Gargoyle|Dark Gargoyle|Secret|8|119732629571247
King Snake|Warden|Secret|8|102674774717128
Kraken|Kraken|Secret|8|74154644445138
Luminous Abyss Shark|Depths Megalodon|Secret|8|103020287697704
Luminous Spike|Depths Spike|Secret|8|103020287697704
Luminous Spirit Manta|Depths Manta Ray|Secret|8|103020287697704
Mawbreaker|Mawbreaker|Secret|8|97679329738336
Mecha Crawler|Mecha Crawler|Secret|8|96353647829204
Mecha Froggo|Mecha Froggo|Secret|8|96353647829204
Mecha Scorpio|Mecha Scorpio|Secret|8|96353647829204
Mutant Shark|Shark|Secret|8|71686040131387
Pure Jellyfish|Jellyfish|Secret|8|128249019051623
RazorFang|RazorFang|Secret|8|78651457785123
Ringlord|Ringlord|Secret|8|126807681611943
Scorched Dragon|ScorchedDragon|Secret|8|114970669202722
Shardwing|Shardwing|Secret|8|124927737636564
Stag|Stag|Secret|8|97036591304998
Tralaledon|Tralaledon|Secret|8|73956313512014
TRex|TyrannosaurusRex|Secret|8|124390268104324
Wendigo|Wendigo|Secret|8|136340085637939
Yeti|Yeti|Secret|8|109969559601816
Abyss Shark|Megalodon|Cosmic|7|113826857989447
Beluga Whale|Alabaster Whale|Cosmic|7|94470939106990
Bronto|Bronto|Cosmic|7|102498197407436
Crawler|Crawler|Cosmic|7|99528919442101
Demon Hound|Demon Hound|Cosmic|7|81200150769664
Demon Imp|Demon Imp|Cosmic|7|109846660752456
Depths Riptide Octopus|Depths Riptide Octopus|Cosmic|7|103020287697704
Dreadclaw|Dreadclaw|Cosmic|7|97679329738336
Drilla|Drill Monster|Cosmic|7|123136809994405
Hellhound|Hellhound|Cosmic|7|109846660752456
Holy Peacock|Peacock|Cosmic|7|129535163831580
Imp|Imp|Cosmic|7|86008838296332
King Mammoth|Colossal Mammoth|Cosmic|7|81868336511715
Koi|Koi|Cosmic|7|107397947617386
La Vacca Saturno Saturnita|La Vacca Saturno Saturnita|Cosmic|7|135566519246226
Leviathan|Basilisk|Cosmic|7|90075842297994
Mangolini Parrochini|Mangolini Parrochini|Cosmic|7|81000367959664
Mantaris|Mantis|Cosmic|7|93443486739123
Rhinotaur|Rhino|Cosmic|7|117685498595422
Ring Guard|Ring Guard|Cosmic|7|105780316822746
Riptide Octopus|Riptide Octopus|Cosmic|7|113826857989447
Royal Sphinx|Irihorus|Cosmic|7|131634678618769
Sacred Moth|Moth|Cosmic|7|104832997526909
Shattered Ram|Shattered Ram|Cosmic|7|85929412992561
Snowy Owl|Snowy Owl|Cosmic|7|110224614368360
Triceratops|Triceratops|Cosmic|7|73329615832715
Ventinal|Ventinal|Cosmic|7|136340085637939
Whale Shark|Whale Shark|Cosmic|7|95374412366370
Ankylosaurus|Ankylosaurus|Mythic|6|103179713771844
Belula Beluga|Belula Beluga|Mythic|6|81000367959664
Bladehide|Blade Head|Mythic|6|94504024229397
Chillin Chilli|Chillin Chilli|Mythic|6|122894089279706
Cosmic Gorilla|Cyclops Gorilla|Mythic|6|116039419189340
Froggo|Froggo|Mythic|6|99528919442101
Mammoth|Mammoth|Mythic|6|99020285854980
Orca|Orca|Mythic|6|99932807273458
Red Panda|Red Panda|Mythic|6|119131393871771
Riftwing|Riftwing|Mythic|6|97679329738336
Sabertooth Tiger|Sabertooth Tiger|Mythic|6|90656359658517
Sand Spider|Sand Spider|Mythic|6|86024313887428
Scorpion|DeathstalkerScorpion|Mythic|6|94810083404486
Shadow Dragon|Shadow Dragon|Mythic|6|124581147164560
Shardling|Shardling|Mythic|6|85929412992561
Spider|Spider|Mythic|6|85241307147394
Spirit Manta|Manta Ray|Mythic|6|113826857989447
Tiger|Tiger|Mythic|6|134641680880560
Toro|Toro|Mythic|6|79033215990120
Voidmaw|Voidmaw|Mythic|6|136340085637939
Winged Lamb|Lamb|Mythic|6|135085221683245
Axolotl|Dream Axolotl|Legendary|5|82740814910149
Baby Aurora Dragon|Baby Aurora Dragon|Legendary|5|124581147164560
Brr Brr Patapim|Brr Brr Patapim|Legendary|5|115540615326236
Cosmic Gecko|Galaxy Gecko|Legendary|5|107132653319667
Crustacia|Crab|Legendary|5|126728057663017
Flame Sprite|Flame Sprite|Legendary|5|120917483549782
Flaming Bull|Flaming Bull|Legendary|5|70883699567304
Gorilla|Gorilla|Legendary|5|83787014176548
Lava Iguana|Lava Iguana|Legendary|5|94119365219057
Light Dove|Dove|Legendary|5|104459545767438
Orangutini Ananassini|Orangutini Ananassini|Legendary|5|78610755295525
Polar Bear|Polar Bear|Legendary|5|129089037074340
Pterodactyl|Pterodactyl|Legendary|5|88209726148785
Rift Eye|Rift Eye|Legendary|5|136340085637939
Salamander|Salamander|Legendary|5|87915294452546
Scorpio|Scorpio|Legendary|5|99528919442101
Shark|Finned Thresher|Legendary|5|71615245424079
Snake|Rattlesnake|Legendary|5|85648596444101
Spideron|Kaiju Spider|Legendary|5|82570250248776
Spike|Spike|Legendary|5|113826857989447
Void Angler|Void Angler|Legendary|5|97679329738336
Bananita Dolphinita|Bananita Dolphinita|Epic|4|81000367959664
Bear|Bear|Epic|4|75135783493246
Centapede|Centapede|Epic|4|131685653579153
Crane|Crane|Epic|4|73259961188044
Crocodile|Crocodile|Epic|4|122378249879058
Fox|Mire Fox|Epic|4|122218902574805
Lava frog|Lava frog|Epic|4|91110146804468
Swan|Swan|Epic|4|125884067432601
Swordfish|Swordfish|Epic|4|108314641239947
Tob Tobi Tob Tob|Tob Tob Tob Tob|Epic|4|100729819199975
Trulimero Trulicina|Trulimero Trulicina|Epic|4|87452659682783
Walrus|Walrus|Epic|4|91972491841412
Burrowing Owl|Burrowing Owl|Rare|3|122807946218302
Camel|Camel|Rare|3|115488818954741
Chimpanzee|Chimpanzee|Rare|3|112484055753399
Dodo|Dodo|Rare|3|81099734295689
Lava Gecko|Ash Gecko|Rare|3|133900489402684
Parrotfish|Parrotfish|Rare|3|140493305582787
Penguin|Penguin|Rare|3|131557069240110
Raccoon|Raccoon|Rare|3|125284294936901
Toucan|Toucan|Rare|3|133240723882442
Tung Tung Sahur|Tung Tung Sahur|Rare|3|81000367959664
Turtle|Turtle|Rare|3|132237234794333
Bird|DesertLark|Uncommon|2|131243362633620
Catfish|Catfish|Uncommon|2|120156933101223
Fennec|FennecFox|Uncommon|2|104249034532190
Chicken|Chicken|Common|1|118146808162748
Dog|Dog|Common|1|123926130544109
Duckling|Duckling|Common|1|120651022174989
Frog|Frog|Common|1|103297453814736
Jerboa|Jerboa|Common|1|116318646770786
]]

-- Parse catalog
local CATALOG = {}
local CATALOG_BY_CATEGORY = {}

for line in CATALOG_RAW:gmatch("[^\r\n]+") do
    local display, category, rarity, num, iconId =
        line:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)")
    if display and category then
        local rec = {
            displayName = display,
            category    = category,
            rarity      = rarity,
            rarityNum   = tonumber(num) or 0,
            icon        = "rbxassetid://" .. iconId,
        }
        table.insert(CATALOG, rec)
        if not CATALOG_BY_CATEGORY[category] then
            CATALOG_BY_CATEGORY[category] = rec
        end
    end
end

print("[AutoGrab] Loaded " .. #CATALOG .. " eggs from catalog")

------------------------------------------------------------
-- Rarity color palette
------------------------------------------------------------
local RARITY_COLORS = {
    Divine    = Color3.fromRGB(255, 220, 80),
    Eternal   = Color3.fromRGB(120, 220, 255),
    Secret    = Color3.fromRGB(255, 60, 180),
    Cosmic    = Color3.fromRGB(140, 80, 255),
    Mythic    = Color3.fromRGB(255, 80, 80),
    Legendary = Color3.fromRGB(255, 180, 40),
    Epic      = Color3.fromRGB(180, 80, 255),
    Rare      = Color3.fromRGB(80, 150, 255),
    Uncommon  = Color3.fromRGB(80, 200, 120),
    Common    = Color3.fromRGB(150, 150, 170),
}

local RARITY_ORDER = {
    "Divine", "Eternal", "Secret", "Cosmic", "Mythic",
    "Legendary", "Epic", "Rare", "Uncommon", "Common",
}

------------------------------------------------------------
-- Remotes
------------------------------------------------------------
local ok, Remotes = pcall(require, ReplicatedStorage.Shared.Remotes)
if not ok or not Remotes or not Remotes.EggWorld then
    warn("[AutoGrab] Could not load Remotes.EggWorld")
    return
end
local E = Remotes.EggWorld

------------------------------------------------------------
-- Instance state
------------------------------------------------------------
local Instance = {
    connections = {},
    cleaned     = false,
    state = {
        enabled       = false,
        selectedEgg   = nil,   -- { displayName, category, rarity }
        rarityFilter  = nil,   -- e.g. "Rare"
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

local function track(conn)
    if conn then table.insert(Instance.connections, conn) end
    return conn
end

local function getHRP()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 5)
end

------------------------------------------------------------
-- Colors
------------------------------------------------------------
local COLORS = {
    bg       = Color3.fromRGB(15, 15, 22),
    bgAlt    = Color3.fromRGB(22, 22, 32),
    bgRow    = Color3.fromRGB(28, 28, 40),
    accent   = Color3.fromRGB(120, 255, 160),
    warn     = Color3.fromRGB(255, 180, 100),
    text     = Color3.fromRGB(220, 220, 235),
    textDim  = Color3.fromRGB(140, 140, 160),
    border   = Color3.fromRGB(60, 80, 70),
}

------------------------------------------------------------
-- ROOT GUI
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AutoGrabUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99999
gui.Parent = PlayerGui
Instance.gui = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -20, 0, 20)
panel.Size = UDim2.fromOffset(340, 500)
panel.BackgroundColor3 = COLORS.bg
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.accent
panelStroke.Thickness = 1
panelStroke.Transparency = 0.6
panelStroke.Parent = panel

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = COLORS.bgAlt
header.BorderSizePixel = 0
header.Parent = panel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 14)
headerCorner.Parent = header

local headerTitle = Instance.new("TextLabel")
headerTitle.BackgroundTransparency = 1
headerTitle.Position = UDim2.fromOffset(14, 0)
headerTitle.Size = UDim2.new(1, -60, 1, 0)
headerTitle.Font = Enum.Font.GothamBold
headerTitle.TextSize = 14
headerTitle.TextColor3 = COLORS.accent
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Text = "🥚  AUTO GRAB"
headerTitle.Parent = header

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.AnchorPoint = Vector2.new(1, 0.5)
minimizeBtn.Position = UDim2.new(1, -10, 0.5, 0)
minimizeBtn.Size = UDim2.fromOffset(22, 22)
minimizeBtn.BackgroundColor3 = COLORS.bg
minimizeBtn.BackgroundTransparency = 0.3
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 14
minimizeBtn.TextColor3 = COLORS.accent
minimizeBtn.Text = "−"
minimizeBtn.Parent = header

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = minimizeBtn

local content = Instance.new("Frame")
content.Position = UDim2.fromOffset(0, 36)
content.Size = UDim2.new(1, 0, 1, -36)
content.BackgroundTransparency = 1
content.Parent = panel

local minimized = false
track(minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    panel.Size = minimized and UDim2.fromOffset(340, 36) or UDim2.fromOffset(340, 500)
    minimizeBtn.Text = minimized and "+" or "−"
end))

------------------------------------------------------------
-- TARGET DROPDOWN
------------------------------------------------------------
local targetLbl = Instance.new("TextLabel")
targetLbl.BackgroundTransparency = 1
targetLbl.Position = UDim2.fromOffset(14, 8)
targetLbl.Size = UDim2.new(1, -28, 0, 16)
targetLbl.Font = Enum.Font.GothamBold
targetLbl.TextSize = 11
targetLbl.TextColor3 = COLORS.textDim
targetLbl.TextXAlignment = Enum.TextXAlignment.Left
targetLbl.Text = "TARGET EGG"
targetLbl.Parent = content

local dropdownBtn = Instance.new("TextButton")
dropdownBtn.Position = UDim2.fromOffset(14, 26)
dropdownBtn.Size = UDim2.new(1, -28, 0, 36)
dropdownBtn.BackgroundColor3 = COLORS.bgAlt
dropdownBtn.BorderSizePixel = 0
dropdownBtn.Font = Enum.Font.Gotham
dropdownBtn.TextSize = 13
dropdownBtn.TextColor3 = COLORS.text
dropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
dropdownBtn.Text = "  Any (grab everything)"
dropdownBtn.Parent = content

local ddCorner = Instance.new("UICorner")
ddCorner.CornerRadius = UDim.new(0, 8)
ddCorner.Parent = dropdownBtn

local ddStroke = Instance.new("UIStroke")
ddStroke.Color = COLORS.border
ddStroke.Thickness = 1
ddStroke.Parent = dropdownBtn

local ddArrow = Instance.new("TextLabel")
ddArrow.BackgroundTransparency = 1
ddArrow.AnchorPoint = Vector2.new(1, 0.5)
ddArrow.Position = UDim2.new(1, -10, 0.5, 0)
ddArrow.Size = UDim2.fromOffset(16, 16)
ddArrow.Font = Enum.Font.GothamBold
ddArrow.TextSize = 12
ddArrow.TextColor3 = COLORS.accent
ddArrow.Text = "▼"
ddArrow.Parent = dropdownBtn

------------------------------------------------------------
-- SEARCH
------------------------------------------------------------
local searchBox = Instance.new("TextBox")
searchBox.Position = UDim2.fromOffset(14, 66)
searchBox.Size = UDim2.new(1, -28, 0, 26)
searchBox.BackgroundColor3 = COLORS.bgAlt
searchBox.BorderSizePixel = 0
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 12
searchBox.TextColor3 = COLORS.text
searchBox.PlaceholderText = "  Search..."
searchBox.PlaceholderColor3 = COLORS.textDim
searchBox.Text = ""
searchBox.ClearTextOnFocus = false
searchBox.Visible = false
searchBox.ZIndex = 6
searchBox.Parent = content

local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 8)
sbCorner.Parent = searchBox

------------------------------------------------------------
-- RARITY FILTER TABS
------------------------------------------------------------
local rarityTabRow = Instance.new("ScrollingFrame")
rarityTabRow.Position = UDim2.fromOffset(14, 66)
rarityTabRow.Size = UDim2.new(1, -28, 0, 26)
rarityTabRow.BackgroundTransparency = 1
rarityTabRow.BorderSizePixel = 0
rarityTabRow.ScrollBarThickness = 0
rarityTabRow.CanvasSize = UDim2.new(0, 0, 0, 0)
rarityTabRow.AutomaticCanvasSize = Enum.AutomaticSize.X
rarityTabRow.ScrollingDirection = Enum.ScrollingDirection.X
rarityTabRow.Visible = false
rarityTabRow.ZIndex = 6
rarityTabRow.Parent = content

local rarityTabsLayout = Instance.new("UIListLayout")
rarityTabsLayout.FillDirection = Enum.FillDirection.Horizontal
rarityTabsLayout.Padding = UDim.new(0, 4)
rarityTabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rarityTabsLayout.Parent = rarityTabRow

local function rebuildRarityTabs()
    for _, c in ipairs(rarityTabRow:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end

    -- "All" tab
    local allBtn = Instance.new("TextButton")
    allBtn.Size = UDim2.fromOffset(50, 24)
    allBtn.BackgroundColor3 = COLORS.bgRow
    allBtn.BorderSizePixel = 0
    allBtn.Font = Enum.Font.GothamBold
    allBtn.TextSize = 11
    allBtn.TextColor3 = State.rarityFilter == nil and COLORS.accent or COLORS.text
    allBtn.Text = "All"
    allBtn.LayoutOrder = 1
    allBtn.Parent = rarityTabRow
    local ac = Instance.new("UICorner")
    ac.CornerRadius = UDim.new(0, 6)
    ac.Parent = allBtn
    track(allBtn.MouseButton1Click:Connect(function()
        State.rarityFilter = nil
        rebuildRarityTabs()
        rebuildDropdown()
    end))

    for i, rarity in ipairs(RARITY_ORDER) do
        local color = RARITY_COLORS[rarity] or COLORS.text
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.fromOffset(70, 24)
        btn.BackgroundColor3 = State.rarityFilter == rarity
            and color
            or COLORS.bgRow
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 10
        btn.TextColor3 = State.rarityFilter == rarity
            and COLORS.bg
            or color
        btn.Text = rarity
        btn.LayoutOrder = i + 1
        btn.Parent = rarityTabRow
        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(0, 6)
        rc.Parent = btn
        track(btn.MouseButton1Click:Connect(function()
            State.rarityFilter = (State.rarityFilter == rarity) and nil or rarity
            rebuildRarityTabs()
            rebuildDropdown()
        end))
    end
end

rebuildRarityTabs()

------------------------------------------------------------
-- DROPDOWN LIST
------------------------------------------------------------
local dropdownList = Instance.new("ScrollingFrame")
dropdownList.Position = UDim2.fromOffset(14, 100)
dropdownList.Size = UDim2.new(1, -28, 0, 230)
dropdownList.BackgroundColor3 = COLORS.bgAlt
dropdownList.BorderSizePixel = 0
dropdownList.ScrollBarThickness = 6
dropdownList.ScrollBarImageColor3 = COLORS.accent
dropdownList.CanvasSize = UDim2.new(0, 0, 0, 0)
dropdownList.AutomaticCanvasSize = Enum.AutomaticSize.Y
dropdownList.Visible = false
dropdownList.ZIndex = 5
dropdownList.Parent = content

local dlCorner = Instance.new("UICorner")
dlCorner.CornerRadius = UDim.new(0, 8)
dlCorner.Parent = dropdownList

local dlStroke = Instance.new("UIStroke")
dlStroke.Color = COLORS.accent
dlStroke.Thickness = 1
dlStroke.Transparency = 0.4
dlStroke.Parent = dropdownList

local dlLayout = Instance.new("UIListLayout")
dlLayout.Padding = UDim.new(0, 2)
dlLayout.SortOrder = Enum.SortOrder.LayoutOrder
dlLayout.Parent = dropdownList

local dlPadding = Instance.new("UIPadding")
dlPadding.PaddingTop = UDim.new(0, 4)
dlPadding.PaddingBottom = UDim.new(0, 4)
dlPadding.PaddingLeft = UDim.new(0, 4)
dlPadding.PaddingRight = UDim.new(0, 4)
dlPadding.Parent = dropdownList

------------------------------------------------------------
-- DROPDOWN BUILDER
------------------------------------------------------------
local currentSearch = ""

local function makeHeader(text, color)
    local h = Instance.new("Frame")
    h.Size = UDim2.new(1, 0, 0, 22)
    h.BackgroundColor3 = color
    h.BackgroundTransparency = 0.85
    h.BorderSizePixel = 0
    h.Parent = dropdownList
    local hc = Instance.new("UICorner")
    hc.CornerRadius = UDim.new(0, 4)
    hc.Parent = h
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.fromOffset(8, 0)
    lbl.Size = UDim2.new(1, -16, 1, 0)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextColor3 = color
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = text
    lbl.Parent = h
end

local function makeItem(displayName, category, rarity, icon)
    local rarityColor = RARITY_COLORS[rarity] or COLORS.text
    local item = Instance.new("TextButton")
    item.Size = UDim2.new(1, 0, 0, 26)
    item.BackgroundColor3 = COLORS.bg
    item.BackgroundTransparency = 1
    item.BorderSizePixel = 0
    item.Text = ""
    item.Parent = dropdownList

    -- Rarity color dot
    local dot = Instance.new("Frame")
    dot.Position = UDim2.fromOffset(6, 8)
    dot.Size = UDim2.fromOffset(10, 10)
    dot.BackgroundColor3 = rarityColor
    dot.BorderSizePixel = 0
    dot.Parent = item
    local dc = Instance.new("UICorner")
    dc.CornerRadius = UDim.new(1, 0)
    dc.Parent = dot

    -- Display name
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(22, 0)
    label.Size = UDim2.new(1, -28, 1, 0)
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextColor3 = COLORS.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = displayName
    label.Parent = item

    track(item.MouseEnter:Connect(function()
        item.BackgroundTransparency = 0.7
    end))
    track(item.MouseLeave:Connect(function()
        item.BackgroundTransparency = 1
    end))
    track(item.MouseButton1Click:Connect(function()
        State.selectedEgg = {
            displayName = displayName,
            category = category,
            rarity = rarity,
        }
        dropdownBtn.Text = "  " .. displayName
        dropdownBtn.TextColor3 = rarityColor
        dropdownList.Visible = false
        searchBox.Visible = false
        rarityTabRow.Visible = false
        ddArrow.Text = "▼"
        log("Selected: " .. displayName .. " (" .. rarity .. ")")
    end))
end

local function rebuildDropdown()
    for _, c in ipairs(dropdownList:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
    end

    -- "Any" option
    local anyItem = Instance.new("TextButton")
    anyItem.Size = UDim2.new(1, 0, 0, 26)
    anyItem.BackgroundColor3 = COLORS.bg
    anyItem.BackgroundTransparency = 1
    anyItem.BorderSizePixel = 0
    anyItem.Text = "  ⭐ Any (grab everything)"
    anyItem.Font = Enum.Font.GothamBold
    anyItem.TextSize = 12
    anyItem.TextColor3 = COLORS.accent
    anyItem.TextXAlignment = Enum.TextXAlignment.Left
    anyItem.LayoutOrder = 1
    anyItem.Parent = dropdownList
    track(anyItem.MouseButton1Click:Connect(function()
        State.selectedEgg = nil
        dropdownBtn.Text = "  Any (grab everything)"
        dropdownBtn.TextColor3 = COLORS.text
        dropdownList.Visible = false
        searchBox.Visible = false
        rarityTabRow.Visible = false
        ddArrow.Text = "▼"
        log("Selected: Any")
    end))

    local searchLower = string.lower(currentSearch)

    -- Iterate rarities in order
    for _, rarity in ipairs(RARITY_ORDER) do
        if not State.rarityFilter or State.rarityFilter == rarity then
            local entriesInRarity = {}
            for _, rec in ipairs(CATALOG) do
                if rec.rarity == rarity then
                    if searchLower == ""
                       or string.find(string.lower(rec.displayName), searchLower, 1, true)
                       or string.find(string.lower(rec.category), searchLower, 1, true)
                    then
                        table.insert(entriesInRarity, rec)
                    end
                end
            end

            if #entriesInRarity > 0 then
                makeHeader(rarity .. " (" .. #entriesInRarity .. ")", RARITY_COLORS[rarity] or COLORS.text)
                for _, rec in ipairs(entriesInRarity) do
                    makeItem(rec.displayName, rec.category, rec.rarity, rec.icon)
                end
            end
        end
    end
end

track(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    currentSearch = searchBox.Text or ""
    rebuildDropdown()
end))

track(dropdownBtn.MouseButton1Click:Connect(function()
    local open = not dropdownList.Visible
    dropdownList.Visible = open
    searchBox.Visible = open
    rarityTabRow.Visible = open
    ddArrow.Text = open and "▲" or "▼"
    if open then
        currentSearch = ""
        searchBox.Text = ""
        rebuildRarityTabs()
        rebuildDropdown()
    end
end))

------------------------------------------------------------
-- SAFE ZONE
------------------------------------------------------------
local safeBtn = Instance.new("TextButton")
safeBtn.Position = UDim2.fromOffset(14, 340)
safeBtn.Size = UDim2.new(1, -28, 0, 30)
safeBtn.BackgroundColor3 = COLORS.bgAlt
safeBtn.BorderSizePixel = 0
safeBtn.Font = Enum.Font.GothamBold
safeBtn.TextSize = 12
safeBtn.TextColor3 = COLORS.accent
safeBtn.Text = "📍  Set Safe Zone"
safeBtn.Parent = content

local safeCorner = Instance.new("UICorner")
safeCorner.CornerRadius = UDim.new(0, 8)
safeCorner.Parent = safeBtn

local safeStroke = Instance.new("UIStroke")
safeStroke.Color = COLORS.accent
safeStroke.Thickness = 1
safeStroke.Transparency = 0.5
safeStroke.Parent = safeBtn

local safeStatusLbl = Instance.new("TextLabel")
safeStatusLbl.BackgroundTransparency = 1
safeStatusLbl.Position = UDim2.fromOffset(14, 374)
safeStatusLbl.Size = UDim2.new(1, -28, 0, 16)
safeStatusLbl.Font = Enum.Font.Code
safeStatusLbl.TextSize = 11
safeStatusLbl.TextColor3 = COLORS.textDim
safeStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
safeStatusLbl.Text = "Safe Zone: NOT SET"
safeStatusLbl.Parent = content

track(safeBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        State.safeZone = hrp.CFrame
        safeStatusLbl.Text = "Safe Zone: SET"
        safeStatusLbl.TextColor3 = COLORS.accent
        log("Safe zone set")
    end
end))

------------------------------------------------------------
-- TOGGLE
------------------------------------------------------------
local toggleBtn = Instance.new("TextButton")
toggleBtn.Position = UDim2.fromOffset(14, 398)
toggleBtn.Size = UDim2.new(1, -28, 0, 40)
toggleBtn.BackgroundColor3 = COLORS.accent
toggleBtn.BorderSizePixel = 0
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.TextColor3 = COLORS.bg
toggleBtn.Text = "▶  START"
toggleBtn.Parent = content

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 10)
toggleCorner.Parent = toggleBtn

track(toggleBtn.MouseButton1Click:Connect(function()
    if not State.enabled then
        if not State.safeZone then
            local hrp = getHRP()
            if hrp then
                State.safeZone = hrp.CFrame
                safeStatusLbl.Text = "Safe Zone: AUTO-SET"
                safeStatusLbl.TextColor3 = COLORS.warn
                log("Safe zone auto-set")
            end
        end
        State.enabled = true
        log("STARTED")
        task.spawn(fetchSnapshot)
    else
        State.enabled = false
        log("STOPPED")
    end
end))

------------------------------------------------------------
-- STATUS LABELS
------------------------------------------------------------
local statusLbl = Instance.new("TextLabel")
statusLbl.BackgroundTransparency = 1
statusLbl.Position = UDim2.fromOffset(14, 444)
statusLbl.Size = UDim2.new(1, -28, 0, 14)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 11
statusLbl.TextColor3 = COLORS.text
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text = "Status: Idle"
statusLbl.Parent = content

local lastLbl = Instance.new("TextLabel")
lastLbl.BackgroundTransparency = 1
lastLbl.Position = UDim2.fromOffset(14, 460)
lastLbl.Size = UDim2.new(1, -28, 0, 14)
lastLbl.Font = Enum.Font.Gotham
lastLbl.TextSize = 11
lastLbl.TextColor3 = COLORS.text
lastLbl.TextXAlignment = Enum.TextXAlignment.Left
lastLbl.Text = "Last: —"
lastLbl.Parent = content

local statsLbl = Instance.new("TextLabel")
statsLbl.BackgroundTransparency = 1
statsLbl.Position = UDim2.fromOffset(14, 476)
statsLbl.Size = UDim2.new(1, -28, 0, 14)
statsLbl.Font = Enum.Font.Code
statsLbl.TextSize = 10
statsLbl.TextColor3 = COLORS.accent
statsLbl.TextXAlignment = Enum.TextXAlignment.Left
statsLbl.Text = "Grabbed: 0 · Failed: 0 · Returns: 0"
statsLbl.Parent = content

------------------------------------------------------------
-- REFRESH LOOP
------------------------------------------------------------
track(task.spawn(function()
    while not Instance.cleaned and gui.Parent do
        if State.enabled then
            toggleBtn.Text = "■  STOP"
            toggleBtn.BackgroundColor3 = COLORS.warn
        else
            toggleBtn.Text = "▶  START"
            toggleBtn.BackgroundColor3 = COLORS.accent
        end

        statusLbl.Text = "Status: " .. (State.enabled and State.status or "Idle")
        statusLbl.TextColor3 = State.enabled and COLORS.accent or COLORS.textDim
        lastLbl.Text = "Last: " .. State.lastGrabbed

        statsLbl.Text = string.format(
            "Grabbed: %d · Failed: %d · Returns: %d",
            State.stats.grabbed, State.stats.failed, State.stats.returned
        )

        task.wait(0.4)
    end
end))

------------------------------------------------------------
-- FILTER
------------------------------------------------------------
local function matchesFilter(egg)
    if not egg or type(egg) ~= "table" then return false end
    if egg.State ~= "Slot" then return false end
    if not egg.Uid then return false end
    if not State.selectedEgg then return true end
    return egg.AssetCategory == State.selectedEgg.category
end

------------------------------------------------------------
-- GRAB LOGIC
------------------------------------------------------------
local function teleportBack()
    if not State.safeZone then return end
    local hrp = getHRP()
    if not hrp then return end
    hrp.CFrame = State.safeZone
    State.stats.returned = State.stats.returned + 1
end

local function tryGrab(egg)
    if Instance.cleaned then return end
    if not State.enabled then return end
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

------------------------------------------------------------
-- EVENTS
------------------------------------------------------------
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

------------------------------------------------------------
-- SNAPSHOT
------------------------------------------------------------
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
        if State.enabled then
            for _, egg in ipairs(snapshot.Records) do
                if Instance.cleaned then return end
                tryGrab(egg)
            end
        end
    end
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------
track(task.spawn(function()
    task.wait(2)
    if Instance.cleaned then return end
    fetchSnapshot()

    while not Instance.cleaned and gui.Parent do
        task.wait(RESCAN_INTERVAL)
        if State.enabled and not Instance.cleaned then fetchSnapshot() end
    end
end))

------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------
function Instance.cleanup()
    if Instance.cleaned then return end
    Instance.cleaned = true
    State.enabled = false
    for _, conn in ipairs(Instance.connections) do
        pcall(function() conn:Disconnect() end)
    end
    Instance.connections = {}
    if Instance.gui then pcall(function() Instance.gui:Destroy() end) end
    print("[AutoGrab] Cleanup complete.")
end

GENV.__AutoGrabInstance = Instance

log("========================================")
log("  AUTO GRAB — CATALOG EDITION")
log("========================================")
log(("  Catalog: %d eggs loaded"):format(#CATALOG))
log("========================================")
