-- GatherMaxing (formerly GatheringGoldCalculator)
--   * floating "+ 7s 00c" text under your character for every gather
--   * a text-only Gathering Profit box while you're gathering
--   * sessions and per-profession resource totals for the history window
-- Works for Mining, Herbalism, Skinning and Fishing. One session covers all
-- of them and ends after 10 minutes without gathering anything.
-- Prices come from the source picked in the right-click menu: Auto
-- (Auctionator, then TradeSkillMaster), one of them, a custom TSM price,
-- or vendor price. Vendor sell price fills in when there is no AH price.
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
    -- The skill is the surest sign; the rank spells below are a backup
    -- (Skinning's rank spell isn't always "known" like the others).
    if ns.PlayerSkill and ns.PlayerSkill(key) then return true end
    for _, id in ipairs(p.ranks) do
        if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Prices. The source is picked in the minimap right-click menu
-- (ns.prefs.priceSource); "auto" (the default) uses Auctionator, then TSM.
-- When the picked source has no price, the vendor sell price is used.
---------------------------------------------------------------------------
-- key: "auto", "auctionator", "custom", "vendor", or a TSM price source.
ns.PRICE_SOURCES = {
    { key = "auto", label = "Auto (Auctionator, then TSM)" },
    { key = "auctionator", label = "AN: Auctionator", needs = "auctionator" },
    { key = "DBHistorical", label = "TSM: Historical Price", needs = "tsm" },
    { key = "DBMarket", label = "TSM: Market Value", needs = "tsm" },
    { key = "DBMinBuyout", label = "TSM: Min Buyout", needs = "tsm" },
    { key = "DBRecent", label = "TSM: Recent Value", needs = "tsm" },
    { key = "DBRegionHistorical", label = "TSM: Region Historical Price", needs = "tsm" },
    { key = "DBRegionMarketAvg", label = "TSM: Region Market Value Avg", needs = "tsm" },
    { key = "DBRegionSaleAvg", label = "TSM: Region Sale Avg", needs = "tsm" },
    { key = "custom", label = "TSM: Custom price source", needs = "tsm" },
    { key = "vendor", label = "Vendor price" },
}
local SOURCE_BY_KEY = {}
for _, src in ipairs(ns.PRICE_SOURCES) do SOURCE_BY_KEY[src.key] = src end

function ns.HasAuctionator()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and api.GetAuctionPriceByItemID and true or false
end

function ns.HasTSM()
    return TSM_API and TSM_API.GetCustomPriceValue and true or false
end

-- Is this TSM price string valid? Returns ok, error text.
function ns.IsValidTSMPrice(text)
    if not ns.HasTSM() then return false, "TSM isn't loaded." end
    if TSM_API.IsCustomPriceValid then
        local ok, valid, err = pcall(TSM_API.IsCustomPriceValid, text)
        if not ok then return false, tostring(valid) end
        return valid and true or false, err
    end
    return true -- a TSM without the check: trust it
end

function ns.PriceSource()
    local key = ns.prefs and ns.prefs.priceSource
    return SOURCE_BY_KEY[key] and key or "auto"
end

local function AuctionatorPrice(itemID)
    if not ns.HasAuctionator() then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
end

-- Any TSM price string: a source like "DBMarket" or a formula like
-- "0.5 * DBRegionMarketAvg". TSM works it out.
local function TSMPrice(priceString, itemID)
    if not ns.HasTSM() or not priceString or priceString == "" then return nil end
    local ok, price = pcall(TSM_API.GetCustomPriceValue, priceString, "i:" .. itemID)
    if ok and type(price) == "number" and price > 0 then return price end
end

local AUTO_TSM = { "DBMarket", "DBRecent", "DBMinBuyout" }

-- Auction price from the picked source, or nil when it has none.
local function AuctionPrice(itemID)
    local source = ns.PriceSource()
    if source == "vendor" then return nil end
    if source == "auctionator" then return AuctionatorPrice(itemID) end
    if source == "custom" then return TSMPrice(ns.prefs.customPrice, itemID) end
    if source ~= "auto" then return TSMPrice(source, itemID) end
    local price = AuctionatorPrice(itemID)
    if price then return price end
    for _, tsmSource in ipairs(AUTO_TSM) do
        price = TSMPrice(tsmSource, itemID)
        if price then return price end
    end
end

local function PriceOf(itemID)
    return AuctionPrice(itemID) or select(11, GetItemInfo(itemID)) or 0
end
ns.PriceOf = PriceOf
ns.AuctionPrice = AuctionPrice -- nil when there is no auction price (price history)
ns.IsSecret = IsSecret

-- Is there any auction data to use? Probes common gathering items:
--   "ok"         auction prices are available (or vendor price was picked)
--   "missing"    the addon the picked source needs isn't installed or enabled
--   "badcustom"  the custom TSM price is empty or not valid
--   "noscan"     the addon is there but has no prices yet (no scan done)
local PRICE_PROBES = { 2770, 2771, 2772, 2835, 2836, 2447, 765, 785, 2318, 2319, 6303, 2589 }
local function PriceStatus()
    local source = ns.PriceSource()
    if source == "vendor" then return "ok" end
    local needs = SOURCE_BY_KEY[source].needs
    if needs == "auctionator" and not ns.HasAuctionator() then return "missing" end
    if needs == "tsm" and not ns.HasTSM() then return "missing" end
    if source == "auto" and not ns.HasAuctionator() and not ns.HasTSM() then return "missing" end
    if source == "custom" then
        local text = ns.prefs.customPrice
        if not text or text == "" or not ns.IsValidTSMPrice(text) then return "badcustom" end
    end
    for _, itemID in ipairs(PRICE_PROBES) do
        if AuctionPrice(itemID) then return "ok" end
    end
    return "noscan"
end
ns.PriceStatus = PriceStatus

local RED = "|cffff4040"
-- Red note for the Gathering Profit box and the login message, or nil.
local function PriceWarning()
    local status = PriceStatus()
    if status == "ok" then return nil end
    local needs = SOURCE_BY_KEY[ns.PriceSource()].needs
    if status == "missing" then
        if needs == "auctionator" then
            return "Auctionator isn't loaded: using vendor prices.\nInstall it or pick another price source."
        elseif needs == "tsm" then
            return "TSM isn't loaded: using vendor prices.\nInstall it or pick another price source."
        end
        return "No auction prices: using vendor prices.\nInstall Auctionator or TSM and scan the auction house."
    elseif status == "badcustom" then
        return "Custom TSM price isn't valid: using vendor prices.\nFix it in the minimap right-click menu."
    end
    return "No auction prices: using vendor prices.\nScan the auction house or pick another price source."
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
--   ns.db (per character, GatherMaxingCharDB):
--     sessions: finished sessions
--               { start, finish, total, gathers, nodes, taps, byProf = { [prof] = copper } }
--     current:  the running session, kept so a /reload doesn't lose it
--     loot:     [prof][itemID] = { count, value } summed over all time
--     nodes:    [node or creature name] = { count, prof, items = { [itemID] = count } }
--               what each kind of node dropped, for the tooltip's average value
--   ns.prefs (whole account, GatherMaxingDB):
--     window positions, minimap button angle, Resources sort and profession,
--     and `legacy`: data saved before tracking was per character, waiting
--     for /gmax claim on the character who gathered it.
---------------------------------------------------------------------------

-- Fills in missing fields and upgrades data from older versions.
local function Normalize(d)
    d.sessions = d.sessions or {}
    d.loot = d.loot or {}
    d.nodes = d.nodes or {}
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
    GatherMaxingDB = GatherMaxingDB or {}
    GatherMaxingCharDB = GatherMaxingCharDB or {}
    local prefs = GatherMaxingDB
    prefs.pos = nil -- position of an old window, no longer used
    prefs.floatIndividual = nil -- old setting; individual mode is now the default

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
    ns.db = Normalize(GatherMaxingCharDB)
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

-- Floating text area: where the text starts and how big it is. It's
-- invisible until edit mode (minimap right-click menu or /gmax edit), which
-- shows it as a box you can drag, with a corner grip to resize it. A
-- bigger box means bigger text that rises further.
local AREA_W, AREA_H = 220, 90 -- default size; text scale 1
local AREA_START = 15          -- text starts this far above the area's bottom

local area = CreateFrame("Frame", "GatherMaxingFloatArea", UIParent, "BackdropTemplate")
area:SetSize(AREA_W, AREA_H)
area:SetPoint("CENTER", UIParent, "CENTER", 0, -170) -- just under your character
area:SetFrameStrata("MEDIUM") -- below the text (HIGH), so samples show on top
area:SetMovable(true)
area:SetClampedToScreen(true)
area:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
area:SetBackdropColor(0.1, 0.4, 0.8, 0.25)
area:SetBackdropBorderColor(0.3, 0.6, 1, 0.9)
area:EnableMouse(false)
area:RegisterForDrag("LeftButton")

local areaLabel = area:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
areaLabel:SetPoint("TOP", 0, -6)
areaLabel:SetText("Floating text\n|cffffffffDrag to move, corner to resize|r")

local grip = CreateFrame("Button", nil, area)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -1, 1)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

-- Checkmark in the top-right corner: click it to leave edit mode.
local done = CreateFrame("Button", nil, area)
done:SetSize(22, 22)
done:SetPoint("TOPRIGHT", -2, -2)
done:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Check")
done:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
done:SetScript("OnClick", function()
    GameTooltip:Hide()
    ns.SetFloatEditMode(false)
end)
done:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Done")
    GameTooltip:AddLine("Save and leave edit mode.", 1, 1, 1)
    GameTooltip:Show()
end)
done:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function ApplyAreaScale()
    holder:SetScale(math.max(area:GetHeight() / AREA_H, 0.1))
end

local SNAP = 25 -- pixels from the screen's middle line that snap to it

-- The box is always stored as an offset of its center from the screen's
-- center, so x = 0 means "centered" on any resolution.
local function PlaceArea(x, y)
    area:ClearAllPoints()
    area:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function AreaOffset()
    local ax, ay = area:GetCenter()
    local mx, my = UIParent:GetCenter()
    return ax - mx, ay - my
end

local function SaveArea()
    local x, y = AreaOffset()
    if math.abs(x) < 0.5 then x = 0 end
    PlaceArea(x, y)
    ns.prefs.floatPos = { "CENTER", "CENTER", x, y }
    ns.prefs.floatSize = { area:GetWidth(), area:GetHeight() }
end

-- Middle line shown while dragging; it lights up when the box snaps to it.
local guideFrame = CreateFrame("Frame", nil, UIParent)
guideFrame:SetAllPoints(UIParent)
guideFrame:SetFrameStrata("HIGH")
local guide = guideFrame:CreateTexture(nil, "OVERLAY")
guide:SetColorTexture(1, 1, 1, 0.25)
guide:SetWidth(2)
guide:SetPoint("TOP", guideFrame, "TOP")
guide:SetPoint("BOTTOM", guideFrame, "BOTTOM")
guide:Hide()

local function Cursor()
    local s = area:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return cx / s, cy / s
end

-- Dragging is done by hand (instead of StartMoving) so the box can snap
-- to the middle of the screen, left to right.
local grabX, grabY
local function FollowDrag()
    local cx, cy = Cursor()
    local mx, my = UIParent:GetCenter()
    local x, y = cx + grabX - mx, cy + grabY - my
    local snapped = math.abs(x) < SNAP
    if snapped then x = 0 end
    PlaceArea(x, y)
    if snapped then
        guide:SetColorTexture(1, 0.82, 0, 0.9)
    else
        guide:SetColorTexture(1, 1, 1, 0.25)
    end
end

area:SetScript("OnDragStart", function(self)
    local cx, cy = Cursor()
    local ax, ay = self:GetCenter()
    grabX, grabY = ax - cx, ay - cy
    guide:Show()
    self:SetScript("OnUpdate", FollowDrag)
end)
area:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    guide:Hide()
    SaveArea()
end)

area:SetScript("OnSizeChanged", ApplyAreaScale)

-- Resizing follows the cursor by hand (instead of StartSizing) so the box
-- keeps its shape and the text scales evenly. The top edge stays put; a
-- centered box grows on both sides so it stays centered, any other box
-- keeps its top-left corner.
local centeredResize, fixedX
local function FollowResize()
    local cx, cy = Cursor()
    local w = centeredResize and 2 * (cx - fixedX) or (cx - fixedX)
    local h = area:GetTop() - cy
    local scale = math.max(w / AREA_W, h / AREA_H)
    scale = math.min(math.max(scale, 0.5), 3)
    area:SetSize(AREA_W * scale, AREA_H * scale)
end

grip:SetScript("OnMouseDown", function()
    local x = AreaOffset()
    centeredResize = math.abs(x) < 0.5
    local top = area:GetTop()
    area:ClearAllPoints()
    if centeredResize then
        fixedX = UIParent:GetCenter()
        area:SetPoint("TOP", UIParent, "BOTTOMLEFT", fixedX, top)
    else
        fixedX = area:GetLeft()
        area:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", fixedX, top)
    end
    grip:SetScript("OnUpdate", FollowResize)
end)
grip:SetScript("OnMouseUp", function()
    grip:SetScript("OnUpdate", nil)
    SaveArea()
end)

-- Right-click the box to put it back where it started.
area:SetScript("OnMouseUp", function(self, mouse)
    if mouse ~= "RightButton" then return end
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    self:SetSize(AREA_W, AREA_H)
    ns.prefs.floatPos, ns.prefs.floatSize = nil, nil
end)

function ns.RestoreFloatArea()
    local pos, size = ns.prefs.floatPos, ns.prefs.floatSize
    if pos then
        area:ClearAllPoints()
        area:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    if size then area:SetSize(size[1], size[2]) end
    ApplyAreaScale()
end

local ShowFloat -- defined below; edit mode plays samples with it
local editTicker

function ns.IsFloatEditMode()
    return area:IsShown()
end

function ns.SetFloatEditMode(on)
    if editTicker then editTicker:Cancel(); editTicker = nil end
    if on then
        area:SetAlpha(1)
        area:EnableMouse(true)
        area:Show()
        -- Play a sample every few seconds so you can see the result.
        local function Sample()
            ShowFloat(2193, { [2772] = { count = 2, value = 1020 }, [2838] = { count = 3, value = 1173 } },
                { 2772, 2838 })
        end
        Sample()
        editTicker = C_Timer.NewTicker(3, Sample)
    else
        area:EnableMouse(false)
        area:Hide()
    end
end
area:Hide()

local pool = {}
local ICON_SIZE = 18    -- item icon size in individual mode
local ICON_GAP = 2      -- pixels between the icon and the text beside it

local function GetFloater()
    for _, f in ipairs(pool) do
        if not f.anim:IsPlaying() then return f end
    end
    local f = CreateFrame("Frame", nil, holder)
    f:SetSize(200, 24)
    -- Individual lines are "2x[icon]money". The icon is a real
    -- texture (not a |T|t text code) so it rises and fades with the text.
    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    f.count:SetShadowOffset(1, -1)
    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetSize(ICON_SIZE, ICON_SIZE)
    f.text = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
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

local LINE_DELAY = 0.2  -- seconds between lines in individual mode
local LINE_GAP = 18     -- pixels between lines in individual mode

-- count and icon are only given in individual mode
local function PlayFloat(text, offset, count, icon)
    local f = GetFloater()
    f:ClearAllPoints()
    -- holder's scale (from the area's size) scales the text, rise and offsets.
    f:SetPoint("CENTER", area, "BOTTOM", 0, AREA_START - (offset or 0))
    f.text:SetText(text)
    f.text:ClearAllPoints()
    if icon then
        f.count:SetText(count)
        f.icon:SetTexture(icon)
        -- Center the whole line: count, gap, icon, gap, money.
        local width = f.count:GetStringWidth() + ICON_SIZE + f.text:GetStringWidth() + 2 * ICON_GAP
        f.count:ClearAllPoints()
        f.count:SetPoint("LEFT", f, "CENTER", -width / 2, 0)
        f.icon:ClearAllPoints()
        f.icon:SetPoint("LEFT", f.count, "RIGHT", ICON_GAP, 0)
        f.text:SetPoint("LEFT", f.icon, "RIGHT", ICON_GAP, 0)
        f.count:Show()
        f.icon:Show()
    else
        f.text:SetPoint("CENTER")
        f.count:Hide()
        f.icon:Hide()
    end
    f:SetAlpha(1)
    f:Show()
    f.anim:Stop()
    f.anim:Play()
end

-- Floating text mode: individual (one line per item: "2x[icon]5s 10c",
-- the default) or combined (one line with the whole loot's value).
function ns.IsCombinedFloat()
    return ns.prefs.floatCombined == true
end

function ns.SetCombinedFloat(on)
    ns.prefs.floatCombined = on or nil
end

-- items: { [itemID] = { count, value } }, order: itemIDs in loot order
function ShowFloat(copper, items, order)
    if not items or not order or ns.IsCombinedFloat() then
        PlayFloat(FormatMoney(copper))
        return
    end
    for i, itemID in ipairs(order) do
        local info = items[itemID]
        local icon = select(5, GetItemInfoInstant(itemID)) or 134400 -- question mark
        local count = info.count .. "x"
        local text = FormatMoney(info.value, true)
        -- Each line starts a bit lower than the one before, so they stack
        -- instead of overlapping while they rise.
        local offset = (i - 1) * LINE_GAP
        if i == 1 then
            PlayFloat(text, offset, count, icon)
        else
            C_Timer.After((i - 1) * LINE_DELAY, function() PlayFloat(text, offset, count, icon) end)
        end
    end
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
local box = CreateFrame("Frame", "GatherMaxingBox", UIParent)
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
-- When the session tracker is turned off (minimap right-click menu) the box
-- stays hidden unless `force` is set; tracking carries on as normal.
local boxTimer
local function ShowBoxFor(seconds, force)
    if ns.prefs and ns.prefs.trackerOff and not force then return end
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
    local warning = PriceWarning()
    if warning then
        for line in warning:gmatch("[^\n]+") do
            lines[#lines + 1] = RED .. line .. "|r"
        end
    end
    boxText:SetText(table.concat(lines, "\n"))
    box:SetHeight(28 + #lines * 14)
end

box:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t > 5 then self.t = 0; UpdateBox() end
end)

-- Picked in the minimap right-click menu. Saved values (history, totals)
-- keep the price they had; tooltips, the Skill Book and new gathers use
-- the new source.
function ns.SetPriceSource(key, customPrice)
    ns.prefs.priceSource = key
    if customPrice then ns.prefs.customPrice = customPrice end
    UpdateBox()
    if ns.RefreshSkillBook then ns.RefreshSkillBook() end
    local warning = PriceWarning()
    if warning then print(RED .. "GatherMaxing: " .. warning:gsub("\n", " ") .. "|r") end
end

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
            byProf = current.byProf, items = current.items,
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

local function NewSession()
    ns.db.current = { start = time(), last = time(), total = 0, gathers = 0,
                      nodes = 0, taps = 0, byProf = {}, items = {} }
end

-- Ends the running session (saving it if anything was gathered) and starts
-- a fresh one right away. Like any session, it ends after 10 minutes
-- without gathering; an empty one isn't saved to history.
function ns.StartNewSession()
    EndSession()
    NewSession()
    StartTimer(SESSION_TIMEOUT)
    UpdateBox()
    ShowBoxFor(BOX_TIMEOUT)
    Changed()
end

-- Session tracker = the Gathering Profit box. Turning it off only hides
-- the box; sessions, history and floating text keep working.
function ns.IsTrackerOn()
    return not ns.prefs.trackerOff
end

function ns.SetTrackerOn(on)
    ns.prefs.trackerOff = not on or nil
    if on then
        if ns.db.current then
            local left = BOX_TIMEOUT - (time() - ns.db.current.last)
            UpdateBox()
            ShowBoxFor(math.max(left, 5))
        end
    else
        HideBox()
    end
end

-- items: { [itemID] = { count, value } } from one loot window
local function RecordGather(prof, value, items, targetName)
    local db = ns.db
    local now = time()
    if db.current and now - db.current.last >= SESSION_TIMEOUT then
        EndSession()
    end
    if not db.current then NewSession() end
    local current = db.current
    local newNode = true
    if prof == "mining" then
        newNode = TrackNode(targetName, value)
        if newNode then current.nodes = current.nodes + 1 end
        current.taps = current.taps + 1
    end
    current.gathers = current.gathers + 1
    current.total = current.total + value
    current.byProf[prof] = (current.byProf[prof] or 0) + value
    current.last = now
    lastValue, lastProf = value, prof
    db.lastProf = prof -- Resources opens on this profession

    local loot = db.loot[prof]
    -- Per-session breakdown: what was gathered and what it was worth at the
    -- time. Sessions from before this was added have no `items`.
    current.items = current.items or {}
    for itemID, info in pairs(items) do
        local r = loot[itemID]
        if not r then
            r = { count = 0, value = 0 }
            loot[itemID] = r
        end
        r.count = r.count + info.count
        r.value = r.value + info.value

        local s = current.items[itemID]
        if not s then
            s = { count = 0, value = 0, prof = prof }
            current.items[itemID] = s
        end
        s.count = s.count + info.count
        s.value = s.value + info.value
    end

    -- What this kind of node (or creature, for skinning) drops, so the
    -- tooltip can show its average value at today's prices. A mining node
    -- counts once for all its taps.
    if targetName and prof ~= "fishing" then
        local n = db.nodes[targetName]
        if not n then
            n = { count = 0, prof = prof, items = {} }
            db.nodes[targetName] = n
        end
        if newNode then n.count = n.count + 1 end
        for itemID, info in pairs(items) do
            n.items[itemID] = (n.items[itemID] or 0) + info.count
        end
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
    local total, items, order, found = 0, {}, {}, false
    local itemType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
    for slot = 1, GetNumLootItems() do
        if not GetLootSlotType or GetLootSlotType(slot) == itemType then
            local link = GetLootSlotLink(slot)
            if link and not IsSecret(link) then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID and Counts(prof, itemID) then
                    local quantity = select(3, GetLootSlotInfo(slot)) or 1
                    local value = PriceOf(itemID) * quantity
                    local entry = items[itemID]
                    if not entry then
                        entry = { count = 0, value = 0 }
                        order[#order + 1] = itemID
                    end
                    entry.count = entry.count + quantity
                    entry.value = entry.value + value
                    items[itemID] = entry
                    total = total + value
                    found = true
                end
            end
        end
    end
    if found then return total, items, order end
end

local function IsFishing()
    if not IsFishingLoot then return false end
    local ok, result = pcall(IsFishingLoot)
    return ok and result and not IsSecret(result)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UNIT_SPELLCAST_SENT")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("LOOT_OPENED")

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        local db = ns.InitDB()
        ns.RestoreFloatArea()
        local pos = ns.prefs.boxPos
        if pos then
            box:ClearAllPoints()
            box:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        end
        if ns.prefs.legacy then
            C_Timer.After(5, function()
                if not ns.prefs.legacy then return end
                print("|cffe0a030GatherMaxing|r: gathering is now tracked per character. "
                    .. "Your older history is set aside: type |cffffd200/gmax claim|r on the "
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

    if event == "PLAYER_LOGIN" then
        -- Give Auctionator / TSM a few seconds to load its prices, then warn
        -- in chat if there are none.
        C_Timer.After(5, function()
            local warning = PriceWarning()
            if warning then
                print(RED .. "GatherMaxing: " .. warning:gsub("\n", " ") .. "|r")
            end
        end)
        events:UnregisterEvent("PLAYER_LOGIN")
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
            local value, items, order = ReadLoot(prof)
            if value then
                ShowFloat(value, items, order)
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

-- /gmax            open or close the history window   (/ggc and /mgc also work)
-- /gmax tipdebug   print why node tooltips do or don't get GatherMaxing lines
-- /gmax book       open or close the Skill Book
-- /gmax edit       move or resize the floating text (edit mode on/off)
-- /gmax box        show or hide the Gathering Profit box
-- /gmax test [c]   play a test float (not saved), e.g. /gmax test 70000
-- /gmax end        end the current session now
-- /gmax new        end the current session and start a new one
-- /gmax tracker    turn the Gathering Profit box on or off
-- /gmax claim      add the history saved before per-character tracking
--                 to this character
SLASH_GATHERMAXING1 = "/gmax"
SLASH_GATHERMAXING2 = "/ggc" -- older names, still work
SLASH_GATHERMAXING3 = "/mgc"
SlashCmdList.GATHERMAXING = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "end" then
        if ns.db.current then EndSession() end
    elseif cmd == "claim" then
        if ns.ClaimLegacy() then
            print("|cffe0a030GatherMaxing|r: older history added to " .. UnitName("player") .. ".")
            Changed()
        else
            print("|cffe0a030GatherMaxing|r: there is no older history left to claim.")
        end
    elseif cmd == "test" then
        local value = tonumber(arg) or 70000
        -- In individual mode, pretend it was 2 Iron Ore and 3 Heavy Stone.
        local half = math.floor(value / 2)
        ShowFloat(value, { [2772] = { count = 2, value = half }, [2838] = { count = 3, value = value - half } },
            { 2772, 2838 })
    elseif cmd == "tipdebug" then
        ns.tooltipDebug = not ns.tooltipDebug
        print("|cffe0a030GatherMaxing|r: tooltip debug " .. (ns.tooltipDebug and "on." or "off."))
        if ns.tooltipDebug and ns.DebugSkills then ns.DebugSkills() end
    elseif cmd == "book" then
        ns.ToggleSkillBook()
    elseif cmd == "edit" then
        ns.SetFloatEditMode(not ns.IsFloatEditMode())
    elseif cmd == "box" then
        if box:IsShown() then HideBox() else UpdateBox(); ShowBoxFor(BOX_TIMEOUT, true) end
    elseif cmd == "tracker" then
        ns.SetTrackerOn(not ns.IsTrackerOn())
        print("|cffe0a030GatherMaxing|r: session tracker "
            .. (ns.IsTrackerOn() and "on." or "off (still tracking in the background)."))
    elseif cmd == "new" then
        ns.StartNewSession()
        print("|cffe0a030GatherMaxing|r: started a new session.")
    elseif ns.ToggleHistory then
        ns.ToggleHistory()
    end
end
