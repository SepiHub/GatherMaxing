-- GatheringGoldCalculator (shown in game as "Gathering Gold")
--   * floating "+ 7s 00c" text under your character for every gather
--   * a text-only Gathering Profit box while you're gathering
--   * sessions and per-profession resource totals for the history window
-- Works for Mining, Herbalism, Skinning and Fishing. One session covers all
-- of them and ends after 10 minutes without gathering anything.
-- Prices come from Auctionator (vendor sell price when there is no AH price).
--
-- Mining: a "tap" is one cast, a "node" is all the taps (1 to 4) on one vein.

local ADDON, ns = ...

-- Forever only has the C_Item versions of these.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local LOOT_WINDOW = 2       -- seconds between cast success and loot window
local RISE = 60             -- pixels the floating text travels upward
local DURATION = 2.5        -- seconds until the floating text is gone
local SESSION_TIMEOUT = 600 -- a session ends after 10 minutes without gathering
local BOX_TIMEOUT = 60      -- the box fades after 1 minute without gathering
local NODE_GAP = 10         -- max seconds between taps on the same mining node
local NODE_RANGE = 8        -- max yards between taps on the same mining node

local GOLD_COLOR   = "|cffffd700"
local SILVER_COLOR = "|cffc7c7cf"
local COPPER_COLOR = "|cffeda55f"

-- Gathering professions. `ranks` are the spell IDs of each rank, used to
-- recognise the cast and to tell which professions this character knows.
ns.PROFESSIONS = {
    { key = "mining",    label = "Mining",    icon = "Interface\\Icons\\Trade_Mining",
      ranks = { 2575, 2576, 3564, 10248 } },
    { key = "herbalism", label = "Herbalism", icon = "Interface\\Icons\\Trade_Herbalism",
      ranks = { 2366, 2368, 3570, 11993 } },
    { key = "skinning",  label = "Skinning",  icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
      ranks = { 8613, 8617, 8618, 10768 } },
    { key = "fishing",   label = "Fishing",   icon = "Interface\\Icons\\Trade_Fishing",
      ranks = { 7620, 7731, 7732, 18248 } },
}
ns.PROF_BY_KEY = {}
for _, p in ipairs(ns.PROFESSIONS) do ns.PROF_BY_KEY[p.key] = p end

local castGUID, castTarget, castProf, castDoneAt

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(id)
    elseif GetSpellInfo then
        return (GetSpellInfo(id))
    end
end

-- spellID -> profession key, or nil. Matches by ID, then by spell name so
-- any rank works.
local profByName
local function ProfessionOfSpell(spellID)
    if IsSecret(spellID) or not spellID then return nil end
    for _, p in ipairs(ns.PROFESSIONS) do
        for _, id in ipairs(p.ranks) do
            if id == spellID then return p.key end
        end
    end
    if not profByName then
        profByName = {}
        for _, p in ipairs(ns.PROFESSIONS) do
            local name = SpellName(p.ranks[1])
            if name then profByName[name] = p.key end
        end
    end
    local name = SpellName(spellID)
    return name and profByName[name]
end

-- True if this character knows the profession.
function ns.KnowsProfession(key)
    local p = ns.PROF_BY_KEY[key]
    if not p then return false end
    for _, id in ipairs(p.ranks) do
        if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
            return true
        end
    end
    return false
end

local function PriceOf(itemID)
    if Auctionator and Auctionator.API and Auctionator.API.v1 then
        local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON, itemID)
        if ok and price and price > 0 then return price end
    end
    return select(11, GetItemInfo(itemID)) or 0
end

-- Known ores, stones and gems from mining nodes.
local MINING_ITEMS = {
    -- ores
    [2770] = true, [2771] = true, [2772] = true, [2775] = true, [2776] = true,
    [3858] = true, [7911] = true, [10620] = true, [11370] = true, [18562] = true,
    [3340] = true, [5833] = true, [4278] = true,
    -- stones
    [2835] = true, [2836] = true, [2838] = true, [7912] = true, [12365] = true,
    -- gems
    [774] = true, [818] = true, [1210] = true, [1705] = true, [1206] = true,
    [1529] = true, [3864] = true, [7909] = true, [7910] = true, [12361] = true,
    [12364] = true, [12799] = true, [12800] = true, [12363] = true, [11382] = true,
}
local CLASS_GEM, CLASS_REAGENT, CLASS_TRADEGOODS, CLASS_QUEST = 3, 5, 7, 12

-- Which drops count:
--   Mining / Herbalism / Skinning: gems, trade goods (ore, stone, herbs,
--     leather, Black Vitriol...) and reagents. Gear and quest items don't.
--   Fishing: everything you fish up except quest items (fish, clams,
--     junk, crates all have a price).
local function Counts(prof, itemID)
    if not GetItemInfoInstant then return true end
    local classID = select(6, GetItemInfoInstant(itemID))
    if prof == "fishing" then return classID ~= CLASS_QUEST end
    if prof == "mining" and MINING_ITEMS[itemID] then return true end
    return classID == CLASS_GEM or classID == CLASS_REAGENT or classID == CLASS_TRADEGOODS
end

-- 70000 -> "+ 7s 00c", 15000 -> "+ 1g 50s 00c", 10 -> "+ 10c".
-- Units above the value's highest unit are left out; lower ones are padded.
-- Pass plain = true to leave out the "+ ".
local function FormatMoney(copper, plain)
    copper = math.floor((copper or 0) + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local c = copper % 100
    local W = "|r"
    local out
    if g > 0 then
        out = string.format("%d%sg%s %02d%ss%s %02d%sc%s",
            g, GOLD_COLOR, W, s, SILVER_COLOR, W, c, COPPER_COLOR, W)
    elseif s > 0 then
        out = string.format("%d%ss%s %02d%sc%s", s, SILVER_COLOR, W, c, COPPER_COLOR, W)
    else
        out = string.format("%d%sc%s", c, COPPER_COLOR, W)
    end
    return plain and out or ("+ " .. out)
end
ns.FormatMoney = FormatMoney

---------------------------------------------------------------------------
-- Saved data
--   ns.db (per character, GatheringGoldCalculatorCharDB):
--     sessions: finished sessions
--               { start, finish, total, gathers, nodes, taps, byProf = { [prof] = copper } }
--     current:  the running session, kept so a /reload doesn't lose it
--     loot:     [prof][itemID] = { count, value } summed over all time
--   ns.prefs (whole account, GatheringGoldCalculatorDB):
--     window positions, minimap button angle, Resources sort and profession,
--     and `legacy`: data saved before tracking was per character, waiting
--     for /ggc claim on the character who gathered it.
---------------------------------------------------------------------------

-- Fills in missing fields and upgrades data from older versions.
local function Normalize(d)
    d.sessions = d.sessions or {}
    d.loot = d.loot or {}
    for _, p in ipairs(ns.PROFESSIONS) do d.loot[p.key] = d.loot[p.key] or {} end
    -- Older versions only tracked mining, in d.resources.
    if d.resources then
        for itemID, r in pairs(d.resources) do d.loot.mining[itemID] = r end
        d.resources = nil
    end
    local function upgrade(s)
        s.taps = s.taps or s.nodes or 0
        s.nodes = s.nodes or s.taps
        s.gathers = s.gathers or s.taps
        s.byProf = s.byProf or { mining = s.total }
    end
    for _, s in ipairs(d.sessions) do upgrade(s) end
    if d.current then upgrade(d.current) end
    return d
end

function ns.InitDB()
    if ns.db then return ns.db end
    GatheringGoldCalculatorDB = GatheringGoldCalculatorDB or {}
    GatheringGoldCalculatorCharDB = GatheringGoldCalculatorCharDB or {}
    local prefs = GatheringGoldCalculatorDB
    prefs.pos = nil -- position of an old window, no longer used

    -- Data from before per-character tracking lives at the top of the
    -- account table. Park it in prefs.legacy until someone claims it.
    if prefs.sessions or prefs.loot or prefs.resources or prefs.current then
        prefs.legacy = Normalize({
            sessions = prefs.sessions, loot = prefs.loot,
            resources = prefs.resources, current = prefs.current,
        })
        prefs.sessions, prefs.loot, prefs.resources, prefs.current = nil, nil, nil, nil
    end

    ns.prefs = prefs
    ns.db = Normalize(GatheringGoldCalculatorCharDB)
    return ns.db
end

-- Moves the parked pre-per-character data onto this character.
function ns.ClaimLegacy()
    local legacy = ns.prefs.legacy
    if not legacy then return false end
    local db = ns.db
    local function add(s) db.sessions[#db.sessions + 1] = s end
    for _, s in ipairs(legacy.sessions) do add(s) end
    if legacy.current and legacy.current.gathers > 0 then
        local c = legacy.current
        add({ start = c.start, finish = c.last, total = c.total, gathers = c.gathers,
              nodes = c.nodes, taps = c.taps, byProf = c.byProf })
    end
    table.sort(db.sessions, function(a, b) return a.start < b.start end)
    for prof, items in pairs(legacy.loot) do
        db.loot[prof] = db.loot[prof] or {}
        for itemID, r in pairs(items) do
            local mine = db.loot[prof][itemID]
            if mine then
                mine.count = mine.count + r.count
                mine.value = mine.value + r.value
            else
                db.loot[prof][itemID] = { count = r.count, value = r.value }
            end
        end
    end
    ns.prefs.legacy = nil
    return true
end

---------------------------------------------------------------------------
-- Floating text under the character
---------------------------------------------------------------------------
local holder = CreateFrame("Frame", nil, UIParent)
holder:SetSize(1, 1)
holder:SetFrameStrata("HIGH")

local pool = {}

local function GetFloater()
    for _, f in ipairs(pool) do
        if not f.anim:IsPlaying() then return f end
    end
    local f = CreateFrame("Frame", nil, holder)
    f:SetSize(200, 24)
    f.text = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    f.text:SetPoint("CENTER")
    f.text:SetShadowOffset(1, -1)

    f.anim = f:CreateAnimationGroup()
    local move = f.anim:CreateAnimation("Translation")
    move:SetOffset(0, RISE)
    move:SetDuration(DURATION)
    move:SetSmoothing("OUT")
    local fade = f.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(DURATION * 0.4)
    fade:SetDuration(DURATION * 0.6)
    f.anim:SetScript("OnFinished", function() f:Hide() end)

    pool[#pool + 1] = f
    return f
end

local function ShowFloat(copper)
    local f = GetFloater()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -200) -- just under your character
    f.text:SetText(FormatMoney(copper))
    f:SetAlpha(1)
    f:Show()
    f.anim:Stop()
    f.anim:Play()
end

---------------------------------------------------------------------------
-- Mining tap -> node grouping. Taps on the same vein (same name, same spot,
-- within NODE_GAP seconds of the previous tap) add up to one node.
---------------------------------------------------------------------------
local lastValue, lastProf = 0, nil
local node -- { name, value, taps, time, x, y }

local function PlayerPosition()
    if UnitPosition then
        local ok, y, x = pcall(UnitPosition, "player")
        if ok and x and y and not IsSecret(x) and not IsSecret(y) then return x, y end
    end
end

-- Returns true when this tap starts a new node.
local function TrackNode(name, tapValue)
    local now = GetTime()
    local x, y = PlayerPosition()
    local same = node and name and node.name == name and now - node.time <= NODE_GAP
    if same and x and node.x then
        same = math.sqrt((x - node.x) ^ 2 + (y - node.y) ^ 2) <= NODE_RANGE
    end
    if same then
        node.value = node.value + tapValue
        node.taps = node.taps + 1
        node.time = now
        return false
    end
    node = { name = name, value = tapValue, taps = 1, time = now, x = x, y = y }
    return true
end

---------------------------------------------------------------------------
-- Gathering Profit box: text only, draggable, shown while gathering.
---------------------------------------------------------------------------
local box = CreateFrame("Frame", "GatheringGoldCalculatorBox", UIParent)
box:SetSize(250, 92)
box:SetMovable(true)
box:EnableMouse(true)
box:RegisterForDrag("LeftButton")
box:SetClampedToScreen(true)
box:SetPoint("CENTER", UIParent, "CENTER", 300, 150)
box:Hide()

local boxTitle = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
boxTitle:SetPoint("TOPLEFT", 8, -7)
boxTitle:SetText("Gathering Profit")
boxTitle:SetShadowOffset(1, -1)

local boxText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
boxText:SetPoint("TOPLEFT", boxTitle, "BOTTOMLEFT", 0, -4)
boxText:SetJustifyH("LEFT")
boxText:SetSpacing(2)
boxText:SetShadowOffset(1, -1)

box:SetScript("OnDragStart", box.StartMoving)
box:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ns.prefs.boxPos = { point, relPoint, x, y }
end)

local fadeIn = box:CreateAnimationGroup()
fadeIn:SetToFinalAlpha(true)
local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
fadeInAlpha:SetFromAlpha(0)
fadeInAlpha:SetToAlpha(1)
fadeInAlpha:SetDuration(0.4)

local fadeOut = box:CreateAnimationGroup()
fadeOut:SetToFinalAlpha(true)
local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
fadeOutAlpha:SetFromAlpha(1)
fadeOutAlpha:SetToAlpha(0)
fadeOutAlpha:SetDuration(1.5)
fadeOut:SetScript("OnFinished", function() box:Hide() end)

local function ShowBox()
    if fadeOut:IsPlaying() then fadeOut:Stop() end
    if not box:IsShown() or box:GetAlpha() < 1 then
        box:Show()
        fadeIn:Play()
    end
end

local function HideBox()
    if not box:IsShown() then return end
    fadeIn:Stop()
    fadeOut:Play()
end

-- Show the box now and fade it out after `seconds` without a new gather.
-- The session itself keeps running; the next gather brings the box back.
local boxTimer
local function ShowBoxFor(seconds)
    ShowBox()
    if boxTimer then boxTimer:Cancel() end
    boxTimer = C_Timer.NewTimer(math.max(seconds, 1), function()
        boxTimer = nil
        HideBox()
    end)
end

local function UpdateBox()
    local current = ns.db and ns.db.current
    if not current then return end
    local M = function(v) return FormatMoney(v, true) end
    local hours = math.max((time() - current.start) / 3600, 1 / 60)
    local lines = {}
    local p = lastProf and ns.PROF_BY_KEY[lastProf]
    lines[#lines + 1] = string.format("Last loot%s: %s",
        p and (" (" .. p.label .. ")") or "", M(lastValue))
    if lastProf == "mining" and node then
        lines[#lines + 1] = string.format("Last node: %s (%d %s)",
            M(node.value), node.taps, node.taps == 1 and "tap" or "taps")
    end
    lines[#lines + 1] = string.format("Session (%d gathers): %s", current.gathers, M(current.total))
    lines[#lines + 1] = "Per hour: " .. M(current.total / hours)
    boxText:SetText(table.concat(lines, "\n"))
    box:SetHeight(28 + #lines * 14)
end

box:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t > 5 then self.t = 0; UpdateBox() end
end)

---------------------------------------------------------------------------
-- Sessions: start on the first gather (any profession), end after
-- SESSION_TIMEOUT seconds without gathering anything.
---------------------------------------------------------------------------
local sessionTimer

local function Changed()
    if ns.RefreshHistory then ns.RefreshHistory() end
end

local function EndSession()
    if sessionTimer then sessionTimer:Cancel() end
    sessionTimer = nil
    local db = ns.db
    local current = db.current
    db.current = nil
    if current and current.gathers > 0 then
        table.insert(db.sessions, {
            start = current.start, finish = current.last, total = current.total,
            gathers = current.gathers, nodes = current.nodes, taps = current.taps,
            byProf = current.byProf,
        })
    end
    lastValue, lastProf, node = 0, nil, nil
    HideBox()
    Changed()
end
ns.EndSession = EndSession

local function StartTimer(seconds)
    if sessionTimer then sessionTimer:Cancel() end
    sessionTimer = C_Timer.NewTimer(math.max(seconds, 1), EndSession)
end

-- items: { [itemID] = { count, value } } from one loot window
local function RecordGather(prof, value, items, targetName)
    local db = ns.db
    local now = time()
    if db.current and now - db.current.last >= SESSION_TIMEOUT then
        EndSession()
    end
    if not db.current then
        db.current = { start = now, last = now, total = 0, gathers = 0,
                       nodes = 0, taps = 0, byProf = {} }
    end
    local current = db.current
    if prof == "mining" then
        if TrackNode(targetName, value) then current.nodes = current.nodes + 1 end
        current.taps = current.taps + 1
    end
    current.gathers = current.gathers + 1
    current.total = current.total + value
    current.byProf[prof] = (current.byProf[prof] or 0) + value
    current.last = now
    lastValue, lastProf = value, prof
    db.lastProf = prof -- Resources opens on this profession

    local loot = db.loot[prof]
    for itemID, info in pairs(items) do
        local r = loot[itemID]
        if not r then
            r = { count = 0, value = 0 }
            loot[itemID] = r
        end
        r.count = r.count + info.count
        r.value = r.value + info.value
    end

    StartTimer(SESSION_TIMEOUT)
    UpdateBox()
    ShowBoxFor(BOX_TIMEOUT)
    Changed()
end

---------------------------------------------------------------------------
-- Loot detection
---------------------------------------------------------------------------
local function ReadLoot(prof)
    local total, items, found = 0, {}, false
    local itemType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
    for slot = 1, GetNumLootItems() do
        if not GetLootSlotType or GetLootSlotType(slot) == itemType then
            local link = GetLootSlotLink(slot)
            if link and not IsSecret(link) then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID and Counts(prof, itemID) then
                    local quantity = select(3, GetLootSlotInfo(slot)) or 1
                    local value = PriceOf(itemID) * quantity
                    local entry = items[itemID] or { count = 0, value = 0 }
                    entry.count = entry.count + quantity
                    entry.value = entry.value + value
                    items[itemID] = entry
                    total = total + value
                    found = true
                end
            end
        end
    end
    if found then return total, items end
end

local function IsFishing()
    if not IsFishingLoot then return false end
    local ok, result = pcall(IsFishingLoot)
    return ok and result and not IsSecret(result)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("UNIT_SPELLCAST_SENT")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("LOOT_OPENED")

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        local db = ns.InitDB()
        local pos = ns.prefs.boxPos
        if pos then
            box:ClearAllPoints()
            box:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        end
        if ns.prefs.legacy then
            C_Timer.After(5, function()
                if not ns.prefs.legacy then return end
                print("|cffe0a030Gathering Gold|r: gathering is now tracked per character. "
                    .. "Your older history is set aside: type |cffffd200/ggc claim|r on the "
                    .. "character who gathered it to add it to that character.")
            end)
        end
        -- Pick the running session back up after a /reload or relog,
        -- or close it if more than 10 minutes have passed.
        if db.current then
            local left = SESSION_TIMEOUT - (time() - db.current.last)
            if left > 0 then
                StartTimer(left)
                local boxLeft = BOX_TIMEOUT - (time() - db.current.last)
                if boxLeft > 0 then
                    UpdateBox()
                    ShowBoxFor(boxLeft)
                end
            else
                EndSession()
            end
        end
        events:UnregisterEvent("ADDON_LOADED")
        return
    end

    if event == "LOOT_OPENED" then
        local prof, target
        if IsFishing() then
            prof = "fishing"
        elseif castProf == "fishing" and castDoneAt and GetTime() - castDoneAt < 32 then
            prof = "fishing" -- backup if IsFishingLoot isn't available
        elseif castProf and castProf ~= "fishing" and castDoneAt
            and GetTime() - castDoneAt < LOOT_WINDOW then
            prof, target = castProf, castTarget
        end
        if prof then
            local value, items = ReadLoot(prof)
            if value then
                ShowFloat(value)
                RecordGather(prof, value, items, target)
            end
        end
        castGUID, castTarget, castProf, castDoneAt = nil, nil, nil, nil
        return
    end

    local unit = ...
    if IsSecret(unit) or unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_SENT" then
        local _, target, guid, spellID = ...
        local prof = ProfessionOfSpell(spellID)
        if prof and not IsSecret(guid) then
            castGUID, castProf, castDoneAt = guid, prof, nil
            castTarget = not IsSecret(target) and target or nil
        end
    else
        local _, guid = ...
        if not castGUID or IsSecret(guid) or guid ~= castGUID then return end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            castDoneAt = GetTime()
        else
            castGUID, castTarget, castProf, castDoneAt = nil, nil, nil, nil
        end
    end
end)

-- /ggc            open or close the history window   (/mgc also works)
-- /ggc box        show or hide the Gathering Profit box
-- /ggc test [c]   play a test float (not saved), e.g. /ggc test 70000
-- /ggc end        end the current session now
-- /ggc claim      add the history saved before per-character tracking
--                 to this character
SLASH_MININGGOLDCALC1 = "/ggc"
SLASH_MININGGOLDCALC2 = "/mgc"
SlashCmdList.MININGGOLDCALC = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "end" then
        if ns.db.current then EndSession() end
    elseif cmd == "claim" then
        if ns.ClaimLegacy() then
            print("|cffe0a030Gathering Gold|r: older history added to " .. UnitName("player") .. ".")
            Changed()
        else
            print("|cffe0a030Gathering Gold|r: there is no older history left to claim.")
        end
    elseif cmd == "test" then
        ShowFloat(tonumber(arg) or 70000)
    elseif cmd == "box" then
        if box:IsShown() then HideBox() else UpdateBox(); ShowBoxFor(BOX_TIMEOUT) end
    elseif ns.ToggleHistory then
        ns.ToggleHistory()
    end
end
