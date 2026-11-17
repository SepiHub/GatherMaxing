-- Where to train, for the Skill Book's Trainers view, plus a map pin.
--   ns.TrainerGroups(prof) -> { { title, note, trainers = { ... } }, ... }
--       trainers for the player's faction (and neutral ones), closest first
--       (capital cities first when distances aren't available)
--   ns.PinTrainer(t)       -> opens the world map on the trainer's zone with
--                             a pin; clicking the pin removes it
-- Trainer list from Warcraft Tavern's WoW Forever profession trainer guide.
-- On Forever, every Mining, Herbalism and Skinning trainer outside the
-- starting areas teaches all ranks up to Artisan; the starting-area ones
-- stop at Apprentice. There are no Journeyman- or Expert-only trainers.

local ADDON, ns = ...

-- name, faction ("A", "H" or "B" for both), zone, spot, x, y
local GATHER_TRAINERS = {
    mining = {
        { "Brock Stoneseeker", "A", "Loch Modan", "Thelsamar", 37.2, 46.9 },
        { "Dank Drizzlecut", "A", "Dun Morogh", "Gol'Bolar Quarry", 69.1, 55.5 },
        { "Gelman Stonehand", "A", "Stormwind City", "Dwarven District", 59.1, 37.7 },
        { "Geofram Bouldertoe", "A", "Ironforge", "The Great Forge", 50.3, 28.0 },
        { "Kurdram Stonehammer", "A", "Darkshore", "Auberdine", 38.2, 41.0 },
        { "Matt Johnson", "A", "Duskwood", "Darkshire", 74.0, 49.6 },
        { "Yarr Hammerstone", "A", "Dun Morogh", "Kharanos", 50.0, 50.4 },
        { "Brek Stonehoof", "H", "Thunder Bluff", "Middle Rise", 34.5, 57.5 },
        { "Brom Killian", "H", "Undercity", "The War Quarter", 55.9, 36.0 },
        { "Johan Focht", "H", "Silverpine Forest", "The Sepulcher", 43.3, 40.6 },
        { "Krunn", "H", "Durotar", "Razor Hill", 51.8, 40.7 },
        { "Makaru", "H", "Orgrimmar", "Valley of Honor", 73.0, 27.0 },
        { "Grungle", "B", "Riverglades", "Powderfuse Port", 77.7, 51.9 },
        { "Halavuul Cragwind", "B", "Zephras Isle", "Valanaar", 65.4, 80.4 },
        { "Messana Crestwind", "B", "Zephras Isle", "Shen'dar Village", 44.7, 44.5 },
        { "Pikkle", "B", "Tanaris", "Gadgetzan", 51.0, 28.0 },
    },
    herbalism = {
        { "Alma Jainrose", "A", "Redridge Mountains", "Lakeshire", 16.8, 46.8 },
        { "Brant Jasperbloom", "A", "Dustwallow Marsh", "Theramore Isle", 64.1, 47.5 },
        { "Cylania Rootstalker", "A", "Ashenvale", "Silverwind Refuge", 50.6, 67.0 },
        { "Edward Egan", "A", "Alterac Mountains", "Dalaran", 18.4, 63.4 },
        { "Firodren Mooncaller", "A", "Darnassus", "Temple Gardens", 47.9, 68.6 },
        { "Herbalist Pomeroy", "A", "Elwynn Forest", "Outside Stormwind", 39.9, 48.3 },
        { "Kali Healtouch", "A", "Loch Modan", "Thelsamar", 36.6, 48.4 },
        { "Malorne Bladeleaf", "A", "Teldrassil", "Dolanaar", 57.7, 60.6 },
        { "Reyna Stonebranch", "A", "Ironforge", "The Great Forge", 55.6, 58.0 },
        { "Shylamiir", "A", "Stormwind City", "The Park", 31.4, 62.9 },
        { "Tannysa", "A", "Stormwind City", "Mage Quarter", 54.5, 83.9 },
        { "Telurinon Moonshadow", "A", "Wetlands", "Menethil Harbor", 8.0, 55.9 },
        { "Angrun", "H", "Stranglethorn Vale", "Grom'gol Base Camp", 32.2, 27.6 },
        { "Aranae Venomblood", "H", "Hillsbrad Foothills", "Tarren Mill", 61.8, 19.7 },
        { "Faruza", "H", "Tirisfal Glades", "Brill", 59.9, 52.1 },
        { "Jandi", "H", "Orgrimmar", "The Drag", 55.6, 40.0 },
        { "Komin Winterhoof", "H", "Thunder Bluff", "Middle Rise", 49.7, 39.6 },
        { "Martha Alliestar", "H", "Undercity", "The Apothecarium", 54.8, 50.1 },
        { "Mishiki", "H", "Durotar", "Sen'jin Village", 55.4, 75.1 },
        { "Ruw", "H", "Feralas", "Camp Mojache", 76.0, 43.4 },
        { "Flora Silverwind", "B", "Stranglethorn Vale", "Booty Bay", 27.6, 77.8 },
        { "Halassa Fernbreeze", "B", "Zephras Isle", "Shen'dar Village", 43.1, 43.5 },
        { "Malvor", "B", "Moonglade", "Nighthaven", 45.6, 46.8 },
        { "Syriel Nightrain", "B", "Zephras Isle", "Valanaar", 57.9, 75.5 },
    },
    skinning = {
        { "Balthus Stoneflayer", "A", "Ironforge", "The Great Forge", 39.6, 32.8 },
        { "Eladriel", "A", "Darnassus", "Craftsmen's Terrace", 64.2, 21.7 },
        { "Helene Peltskinner", "A", "Elwynn Forest", "Goldshire", 46.3, 62.2 },
        { "Jayla", "A", "Ashenvale", "Silverwind Refuge", 50.1, 67.2 },
        { "Maris Granger", "A", "Stormwind City", "Old Town", 72.3, 62.3 },
        { "Radnaal Maneweaver", "A", "Teldrassil", "Outside Darnassus", 42.1, 50.0 },
        { "Wilma Ranthal", "A", "Redridge Mountains", "Shalewind Canyon", 83.6, 71.1 },
        { "Dranh", "H", "The Barrens", "Camp Taurajo", 45.1, 59.0 },
        { "Killian Hagey", "H", "Undercity", "Rogues' Quarter", 71.0, 59.5 },
        { "Kulleg Stonehorn", "H", "Feralas", "Camp Mojache", 74.4, 43.0 },
        { "Malux", "H", "Desolace", "Shadowprey Village", 23.2, 69.8 },
        { "Mooranta", "H", "Thunder Bluff", "Middle Rise", 44.7, 43.3 },
        { "Rand Rhobart", "H", "Tirisfal Glades", "Camp near Undercity", 65.6, 60.1 },
        { "Thuwd", "H", "Orgrimmar", "The Drag", 63.1, 45.3 },
        { "Yonn Deepcut", "H", "Mulgore", "Bloodhoof Village", 45.0, 61.4 },
        { "Ishlee Breezewhisper", "B", "Zephras Isle", "Valanaar", 59.6, 75.9 },
        { "Mendalass Tattermend", "B", "Zephras Isle", "Shen'dar Village", 43.2, 43.4 },
    },
}

-- Starting-area trainers: Apprentice only.
local GATHER_APPRENTICE = {
    mining = {
        { "Fanorran Stilloak", "A", "Teldrassil", "Shadowglen", 58.2, 41.3 },
        { "Kelsey Fargo", "A", "Elwynn Forest", "Northshire", 47.1, 32.3 },
        { "Sally Swiftwrench", "A", "Dun Morogh", "Coldridge Valley", 28.7, 67.8 },
        { "Norzsh", "H", "Durotar", "Valley of Trials", 40.5, 68.0 },
        { "Vartha Rockmane", "H", "Mulgore", "Red Cloud Mesa", 44.2, 78.2 },
        { "Walter Mason", "H", "Tirisfal Glades", "Deathknell", 32.3, 65.7 },
    },
    herbalism = {
        { "Eleyna Duskbreeze", "A", "Teldrassil", "Shadowglen", 59.8, 41.3 },
        { "Emrys Flintbeard", "A", "Dun Morogh", "Coldridge Valley", 28.8, 66.7 },
        { "Nancy Songflower", "A", "Elwynn Forest", "Northshire", 52.4, 43.8 },
        { "Florence Nightshade", "H", "Tirisfal Glades", "Deathknell", 32.4, 65.2 },
        { "Garan Sunstrider", "H", "Mulgore", "Red Cloud Mesa", 44.2, 77.8 },
        { "Zor'la", "H", "Durotar", "Valley of Trials", 42.7, 67.4 },
    },
    skinning = {
        { "Brighid Stormflayer", "A", "Dun Morogh", "Coldridge Valley", 29.2, 67.7 },
        { "Riley Peltskinner", "A", "Elwynn Forest", "Northshire", 47.0, 39.8 },
        { "Terunne Bearshaper", "A", "Teldrassil", "Shadowglen", 59.4, 38.7 },
        { "Kagil", "H", "Durotar", "Valley of Trials", 40.8, 68.0 },
        { "Margaret Weaver", "H", "Tirisfal Glades", "Deathknell", 32.6, 65.7 },
        { "Nawka Wildsong", "H", "Mulgore", "Red Cloud Mesa", 44.8, 76.8 },
    },
}

-- Fishing trainers only teach up to Journeyman; Expert and Artisan come
-- from a book and a quest.
local FISHING_JOURNEYMAN = {
    { "Androl Oakhand", "A", "Teldrassil", "Rut'theran Village", 55.8, 93.5 },
    { "Arnold Leland", "A", "Stormwind City", "Trade District", 55.1, 69.6 },
    { "Astaia", "A", "Darnassus", "Temple Gardens", 47.5, 56.5 },
    { "Brannock", "A", "Feralas", "Feathermoon Stronghold", 32.2, 41.4 },
    { "Donald Rabonne", "A", "Hillsbrad Foothills", "Southshore", 50.3, 64.3 },
    { "Grimnur Stonebrand", "A", "Ironforge", "The Forlorn Cavern", 48.5, 6.2 },
    { "Harold Riggs", "A", "Wetlands", "Menethil Harbor", 8.2, 58.3 },
    { "Hunter Moore", "A", "Hillsbrad Foothills", "Island off the coast", 54.0, 80.6 },
    { "Lee Brown", "A", "Elwynn Forest", "Goldshire", 47.6, 62.3 },
    { "Matthew Hooper", "A", "Redridge Mountains", "Lakeshire", 21.5, 51.0 },
    { "Paxton Ganter", "A", "Dun Morogh", "Iceflow Lake", 35.6, 40.4 },
    { "Warg Deepwater", "A", "Loch Modan", "The Loch", 40.5, 39.4 },
    { "Armand Cromwell", "H", "Undercity", "The Magic Quarter", 81.0, 29.5 },
    { "Clyde Kellen", "H", "Tirisfal Glades", "Brightwater Lake", 67.1, 51.0 },
    { "Kah Mistrunner", "H", "Thunder Bluff", "Middle Rise", 56.4, 47.6 },
    { "Katoom the Angler", "H", "The Hinterlands", "Revantusk Village", 80.5, 81.5 },
    { "Kil'Hiwana", "H", "Ashenvale", "Zoram Strand", 10.7, 33.5 },
    { "Lau'Tiki", "H", "Durotar", "Sen'jin Village", 53.2, 81.5 },
    { "Lui'Mala", "H", "Desolace", "Shadowprey Village", 22.7, 72.7 },
    { "Lumak", "H", "Orgrimmar", "Valley of Honor", 69.7, 29.3 },
    { "Uthan Stillwater", "H", "Mulgore", "Bloodhoof Village", 44.2, 63.9 },
    { "Baelann Swiftcurrent", "B", "Zephras Isle", "Valanaar", 63.2, 75.7 },
    { "Fenn Fairweather", "B", "Zephras Isle", "Shen'dar Village", 45.0, 48.4 },
    { "Krix", "B", "Riverglades", "Powderfuse Port", 79.3, 54.7 },
    { "Myizz Luckycatch", "B", "Stranglethorn Vale", "Booty Bay", 27.5, 77.2 },
}
local FISHING_EXPERT = {
    { "Old Man Heming", "B", "Stranglethorn Vale", "Booty Bay", 27.5, 77.0 },
}
local FISHING_ARTISAN = {
    { "Nat Pagle", "B", "Dustwallow Marsh", "Nat Pagle's camp", 58.5, 59.8 },
}

---------------------------------------------------------------------------
-- Zone name -> map ID. Looked up from the game's own map list so Forever's
-- custom zones work too; the classic IDs below are the backup.
---------------------------------------------------------------------------
local FALLBACK_MAP = {
    ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413, ["Alterac Mountains"] = 1416,
    ["Tirisfal Glades"] = 1420, ["Silverpine Forest"] = 1421, ["Hillsbrad Foothills"] = 1424,
    ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426, ["Elwynn Forest"] = 1429,
    ["Duskwood"] = 1431, ["Loch Modan"] = 1432, ["Redridge Mountains"] = 1433,
    ["Stranglethorn Vale"] = 1434, ["Wetlands"] = 1437, ["Teldrassil"] = 1438,
    ["Darkshore"] = 1439, ["Ashenvale"] = 1440, ["Desolace"] = 1443, ["Feralas"] = 1444,
    ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446, ["Moonglade"] = 1450,
    ["Stormwind City"] = 1453, ["Orgrimmar"] = 1454, ["Ironforge"] = 1455,
    ["Thunder Bluff"] = 1456, ["Darnassus"] = 1457, ["Undercity"] = 1458,
}

local mapByName
local function MapID(zone)
    if not mapByName then
        mapByName = {}
        if C_Map and C_Map.GetMapChildrenInfo then
            for _, root in ipairs({ 946, 947 }) do
                local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
                if ok and list then
                    for _, info in ipairs(list) do
                        -- Prefer zones and cities over dungeons with the same name.
                        if info.name and (not mapByName[info.name] or info.mapType == 3) then
                            mapByName[info.name] = info.mapID
                        end
                    end
                end
            end
        end
    end
    return mapByName[zone] or FALLBACK_MAP[zone]
end

local function Trainer(row)
    return { name = row[1], faction = row[2], zone = row[3], spot = row[4],
             x = row[5], y = row[6], mapID = MapID(row[3]) }
end

-- Capital cities: shown in gold, and listed first when distances aren't available.
local CITIES = {
    ["Stormwind City"] = true, ["Ironforge"] = true, ["Darnassus"] = true,
    ["Orgrimmar"] = true, ["Thunder Bluff"] = true, ["Undercity"] = true,
}

-- World position (continent, x, y) of a spot on a map, or nil. The player's
-- position goes through the same call, so distances always line up.
local function WorldPos(mapID, x, y)
    if not (mapID and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not continent or not pos then return nil end
    local wx, wy = pos:GetXY()
    if ns.IsSecret(wx) or ns.IsSecret(wy) then return nil end
    return continent, wx, wy
end

local function PlayerWorldPos()
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not here or not C_Map.GetPlayerMapPosition then return here end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, here, "player")
    if not ok or not pos then return here end
    local x, y = pos:GetXY()
    if ns.IsSecret(x) or ns.IsSecret(y) then return here end
    return here, WorldPos(here, x, y)
end

-- Trainers for the player's faction plus neutral ones.
-- Order: on your continent by distance, closest first; then the rest with
-- capital cities first. If distances can't be worked out, everything is
-- capitals first.
local function ForPlayer(rows)
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local here, myCont, myX, myY = PlayerWorldPos()
    local list = {}
    for _, row in ipairs(rows) do
        if row[2] == faction or row[2] == "B" then
            local t = Trainer(row)
            t.sameZone = here ~= nil and t.mapID == here
            t.city = CITIES[t.zone] or false
            if myCont then
                local cont, tx, ty = WorldPos(t.mapID, t.x / 100, t.y / 100)
                if cont == myCont then
                    t.yards = math.sqrt((tx - myX) ^ 2 + (ty - myY) ^ 2)
                end
            end
            list[#list + 1] = t
        end
    end
    table.sort(list, function(a, b)
        if (a.yards ~= nil) ~= (b.yards ~= nil) then return a.yards ~= nil end
        if a.yards and a.yards ~= b.yards then return a.yards < b.yards end
        if a.city ~= b.city then return a.city end
        if a.zone ~= b.zone then return a.zone < b.zone end
        return a.name < b.name
    end)
    return list
end

function ns.TrainerGroups(prof)
    if prof == "fishing" then
        return {
            { title = "Journeyman trainers (up to 150)", trainers = ForPlayer(FISHING_JOURNEYMAN) },
            { title = "Expert (up to 225): a book",
              note = "Buy the Expert Fishing book from Old Man Heming and read it. Needs skill 125.",
              trainers = ForPlayer(FISHING_EXPERT) },
            { title = "Artisan (up to 300): a quest",
              note = "Do Nat Pagle's quest \"Nat Pagle, Angler Extreme\". Needs skill 225.",
              trainers = ForPlayer(FISHING_ARTISAN) },
        }
    end
    return {
        { title = "Artisan trainers (teach every rank)",
          trainers = ForPlayer(GATHER_TRAINERS[prof]) },
        { title = "Apprentice trainers (starting areas)",
          note = "Only teaches Apprentice. Go to an Artisan trainer for Journeyman and up.",
          trainers = ForPlayer(GATHER_APPRENTICE[prof]) },
    }
end

---------------------------------------------------------------------------
-- Map pin: one at a time, drawn on the world map when it shows the
-- trainer's zone. Click it to remove it. Kept across reloads.
---------------------------------------------------------------------------
local pinFrame

local function Say(msg) print("|cffe0a030GatherMaxing|r: " .. msg) end

local function ClearPin()
    ns.prefs.trainerPin = nil
    if pinFrame then pinFrame:Hide() end
end

local function UpdatePin()
    local pin = ns.prefs and ns.prefs.trainerPin
    if not pinFrame or not pin or not WorldMapFrame:IsShown() or WorldMapFrame:GetMapID() ~= pin.mapID then
        if pinFrame then pinFrame:Hide() end
        return
    end
    local canvas = WorldMapFrame:GetCanvas()
    local scale = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.GetCanvasScale
        and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
    pinFrame:SetScale(1 / scale) -- same size at any zoom
    pinFrame:ClearAllPoints()
    pinFrame:SetPoint("CENTER", canvas, "TOPLEFT",
        canvas:GetWidth() * pin.x / 100 * scale, -canvas:GetHeight() * pin.y / 100 * scale)
    pinFrame.label:SetText(pin.name)
    pinFrame:Show()
end

local function MakePin()
    if pinFrame or not (WorldMapFrame and WorldMapFrame.GetCanvas) then return end
    local canvas = WorldMapFrame:GetCanvas()
    pinFrame = CreateFrame("Button", "GatherMaxingTrainerPin", canvas)
    pinFrame:SetSize(32, 32)
    pinFrame:SetFrameStrata("DIALOG") -- above the map's own pins
    pinFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- A gold circle with an X, see-through in between (Textures/pin.tga).
    pinFrame.icon = pinFrame:CreateTexture(nil, "ARTWORK")
    pinFrame.icon:SetAllPoints()
    pinFrame.icon:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Textures\\pin")

    pinFrame.label = pinFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pinFrame.label:SetPoint("TOP", pinFrame, "BOTTOM", 0, -2)

    pinFrame:SetScript("OnClick", function()
        GameTooltip:Hide()
        ClearPin()
    end)
    pinFrame:SetScript("OnEnter", function(self)
        local pin = ns.prefs.trainerPin
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(pin.name)
        GameTooltip:AddLine(string.format("%s, %s (%.1f, %.1f)", pin.spot, pin.zone, pin.x, pin.y), 1, 1, 1)
        GameTooltip:AddLine("Click to remove the pin.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    pinFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pinFrame:Hide()

    -- Follow map changes, zoom and resizing.
    local watcher = CreateFrame("Frame", nil, WorldMapFrame)
    watcher:SetScript("OnUpdate", UpdatePin)
    WorldMapFrame:HookScript("OnHide", function() pinFrame:Hide() end)
end

-- t: a trainer from ns.TrainerGroups; icon: the profession's icon.
function ns.PinTrainer(t, icon)
    if not t.mapID then
        Say(string.format("%s is in %s, %s at %.1f, %.1f (couldn't find that zone's map).",
            t.name, t.spot, t.zone, t.x, t.y))
        return
    end
    MakePin()
    if not pinFrame then
        Say(string.format("%s is in %s, %s at %.1f, %.1f.", t.name, t.spot, t.zone, t.x, t.y))
        return
    end
    ns.prefs.trainerPin = { name = t.name, zone = t.zone, spot = t.spot, x = t.x, y = t.y,
                            mapID = t.mapID, icon = icon }
    -- Never call WorldMapFrame:SetMapID / ToggleWorldMap from here: running
    -- Blizzard's map code from an addon taints it, and the map then gets
    -- ADDON_ACTION_BLOCKED errors in combat. C_Map.OpenWorldMap asks the
    -- game to open it instead, which keeps the map's code clean.
    local opened = false
    if C_Map and C_Map.OpenWorldMap and not InCombatLockdown() then
        opened = pcall(C_Map.OpenWorldMap, t.mapID)
    end
    UpdatePin()
    if opened then
        Say(string.format("pinned %s on your map (%s, %.1f, %.1f). Click the pin to remove it.",
            t.name, t.zone, t.x, t.y))
    else
        Say(string.format("pinned %s on your map (%s, %.1f, %.1f). Press M and go to %s to see it.",
            t.name, t.zone, t.x, t.y, t.zone))
    end
end

-- True if this trainer is the one pinned right now.
function ns.IsPinned(t)
    local pin = ns.prefs and ns.prefs.trainerPin
    return pin and pin.name == t.name and pin.zone == t.zone or false
end

function ns.ClearTrainerPin() ClearPin() end

-- A pin saved before a reload shows again the next time the map opens.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if ns.prefs and ns.prefs.trainerPin then MakePin() end
end)
