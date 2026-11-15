-- Minimap button and history window.
--   Lifetime view:  lifetime total, then every session (newest first)
--   Resources view: profession dropdown + 3 sortable columns
--                   (Resource by tier, Count, Value)

local ADDON, ns = ...

-- Forever only has the C_Item versions of these.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local PICKAXE = "Interface\\Icons\\INV_Pick_02"
local ROW_HEIGHT = 20
local CONTENT_WIDTH = 330
local COUNT_RIGHT = 236  -- right edge of the Count column
local view = "lifetime"

-- Mining skill of the vein each item comes from, so mining sorts
-- Copper < Tin < Iron < Mithril < Thorium. Anything not listed (herbs,
-- leather, fish, Black Vitriol...) sorts by item level, x5 so it lands near
-- the matching skill tier.
local TIER = {
    -- copper veins
    [2770] = 1, [2835] = 1, [774] = 1, [818] = 1,
    -- tin veins
    [2771] = 65, [2836] = 65, [3340] = 65, [1210] = 65, [1206] = 65, [1705] = 65,
    -- silver veins
    [2775] = 75, [4278] = 75, [1529] = 75,
    -- iron veins
    [2772] = 125, [2838] = 125, [3864] = 125,
    [5833] = 150,
    -- gold veins
    [2776] = 155, [7909] = 160,
    -- mithril veins
    [3858] = 175, [7912] = 175, [7910] = 175,
    -- truesilver / dark iron veins
    [7911] = 230, [11370] = 230, [11382] = 230, [12361] = 230, [12799] = 230,
    -- thorium veins
    [10620] = 245, [12365] = 245, [12364] = 245, [12800] = 245, [12363] = 275,
    -- elementium
    [18562] = 300,
}

local function Money(copper) return ns.FormatMoney(copper, true) end

local function LifetimeTotals()
    local db = ns.db
    local total, gathers, count = 0, 0, #db.sessions
    for _, s in ipairs(db.sessions) do
        total = total + s.total
        gathers = gathers + (s.gathers or 0)
    end
    if db.current then
        total = total + db.current.total
        gathers = gathers + db.current.gathers
        count = count + 1
    end
    return total, gathers, count
end

local function Duration(seconds)
    local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
    if minutes < 60 then return minutes .. " min" end
    return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

local function ItemTier(itemID)
    if TIER[itemID] then return TIER[itemID] end
    local ilvl = select(4, GetItemInfo(itemID))
    return (ilvl or 0) * 5
end

local function Icon(path, size)
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", path, size or 14, size or 14)
end

-- Professions for the dropdown: the ones this character knows, plus any
-- this character has saved loot for (e.g. a profession it dropped).
local function DropdownProfessions()
    local list = {}
    for _, p in ipairs(ns.PROFESSIONS) do
        if ns.KnowsProfession(p.key) or next(ns.db.loot[p.key]) then
            list[#list + 1] = p
        end
    end
    if #list == 0 then list[1] = ns.PROF_BY_KEY.mining end
    return list
end

local function SelectedProfession()
    local list = DropdownProfessions()
    for _, p in ipairs(list) do
        if p.key == ns.prefs.resProf then return p end
    end
    return list[1]
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "GatheringGoldCalculatorHistory", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(380, 440)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetFrameStrata("DIALOG")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()
tinsert(UISpecialFrames, "GatheringGoldCalculatorHistory") -- Escape closes it

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("TOP", 0, -5)
frame.title:SetText("Gathering Gold")

local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
header:SetPoint("TOPLEFT", 14, -34)
header:SetJustifyH("LEFT")

local subheader = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subheader:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
subheader:SetJustifyH("LEFT")

local toggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
toggle:SetSize(110, 22)
toggle:SetPoint("BOTTOM", 0, 10)

local Refresh -- defined below
local scroll_reset -- set when the list should jump back to the top

-- Profession dropdown (Resources view only), top right
local dropdown = CreateFrame("Frame", "GatheringGoldCalculatorProfDropDown", frame, "UIDropDownMenuTemplate")
dropdown:SetPoint("TOPRIGHT", 4, -28)
UIDropDownMenu_SetWidth(dropdown, 110)
-- UIDropDownMenu_Initialize runs this right away while the file loads,
-- before saved data exists, so do nothing until the data is ready.
UIDropDownMenu_Initialize(dropdown, function(self, level)
    if not ns.db then return end
    local selected = SelectedProfession()
    for _, p in ipairs(DropdownProfessions()) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = p.label
        info.icon = p.icon
        info.checked = (p.key == selected.key)
        info.func = function()
            ns.prefs.resProf = p.key
            CloseDropDownMenus()
            scroll_reset = true
            Refresh()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end)

-- Column headers (above the scroll list)
local columns = CreateFrame("Frame", nil, frame)
columns:SetPoint("TOPLEFT", 12, -76)
columns:SetSize(CONTENT_WIDTH, 20)

local divider = columns:CreateTexture(nil, "ARTWORK")
divider:SetPoint("BOTTOMLEFT", 0, 0)
divider:SetPoint("BOTTOMRIGHT", 0, 0)
divider:SetHeight(1)
divider:SetColorTexture(1, 0.82, 0, 0.35)

local ARROW_UP = "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t"
local ARROW_DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t"

local headerButtons = {}

local function MakeHeader(key, label, justify, left, right)
    local b = CreateFrame("Button", nil, columns)
    b:SetPoint("TOPLEFT", left, 0)
    b:SetSize(right - left, 20)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint(justify == "LEFT" and "LEFT" or "RIGHT", justify == "LEFT" and 4 or -4, 0)
    b.label, b.key = label, key
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b:SetScript("OnClick", function()
        local db = ns.prefs
        if db.sortKey == key then
            db.sortAsc = not db.sortAsc
        else
            db.sortKey = key
            db.sortAsc = (key == "tier") -- tier low->high, count/value high->low
        end
        Refresh()
    end)
    headerButtons[#headerButtons + 1] = b
    return b
end

MakeHeader("tier", "Resource", "LEFT", 0, COUNT_RIGHT - 60)
MakeHeader("count", "Count", "RIGHT", COUNT_RIGHT - 60, COUNT_RIGHT)
MakeHeader("value", "Value", "RIGHT", COUNT_RIGHT, CONTENT_WIDTH)

local function UpdateHeaders()
    local db = ns.prefs
    for _, b in ipairs(headerButtons) do
        local arrow = ""
        if db.sortKey == b.key then arrow = " " .. (db.sortAsc and ARROW_UP or ARROW_DOWN) end
        b.text:SetText(b.label .. arrow)
    end
end

local scroll = CreateFrame("ScrollFrame", "GatheringGoldCalculatorHistoryScroll", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("BOTTOMRIGHT", -32, 40)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(CONTENT_WIDTH, 1)
scroll:SetScrollChild(content)

local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("TOP", 0, -20)

local rows = {}

local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetWidth(CONTENT_WIDTH)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.left:SetJustifyH("LEFT")
    row.left:SetWordWrap(false)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", row, "LEFT", COUNT_RIGHT - 4, 0)
    row.count:SetJustifyH("RIGHT")

    row.right = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")

    rows[i] = row
    return row
end

-- count = nil means a two-column row (lifetime view)
local function SetRow(i, iconPath, left, count, right)
    local row = GetRow(i)
    row.left:ClearAllPoints()
    if iconPath then
        row.icon:SetTexture(iconPath)
        row.icon:Show()
        row.left:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    else
        row.icon:Hide()
        row.left:SetPoint("LEFT", 4, 0)
    end
    if count then
        row.left:SetPoint("RIGHT", row, "LEFT", COUNT_RIGHT - 64, 0)
        row.count:SetText(count)
        row.count:Show()
    else
        row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        row.count:Hide()
    end
    row.left:SetText(left)
    row.right:SetText(right)
    row:Show()
end

-- Small profession icons for the professions a session used.
local function SessionIcons(s)
    local out = ""
    for _, p in ipairs(ns.PROFESSIONS) do
        if s.byProf and s.byProf[p.key] then out = out .. Icon(p.icon, 12) end
    end
    return out
end

local function ShowLifetime()
    local db = ns.db
    local total, gathers, count = LifetimeTotals()
    header:SetText("Lifetime: " .. Money(total))
    subheader:SetText(string.format("%d sessions, %d gathers", count, gathers))
    toggle:SetText("Resources")
    columns:Hide()
    dropdown:Hide()
    scroll:SetPoint("TOPLEFT", 12, -76)

    local list = {}
    if db.current then
        list[1] = { s = db.current, live = true }
    end
    for i = #db.sessions, 1, -1 do
        list[#list + 1] = { s = db.sessions[i] }
    end

    for i, entry in ipairs(list) do
        local s = entry.s
        local finish = entry.live and time() or s.finish
        local left = string.format("%s %s  |cff999999%s, %d gathers|r%s", SessionIcons(s),
            date("%b %d  %H:%M", s.start), Duration(finish - s.start), s.gathers or 0,
            entry.live and "  |cff40ff40(now)|r" or "")
        SetRow(i, nil, left, nil, Money(s.total))
    end
    empty:SetText(#list == 0 and "No sessions yet. Go gather something!" or "")
    return #list
end

local function ShowResources()
    local db, prefs = ns.db, ns.prefs
    prefs.sortKey = prefs.sortKey or "value"
    if prefs.sortAsc == nil then prefs.sortAsc = false end
    local prof = SelectedProfession()

    local list, total = {}, 0
    for itemID, r in pairs(db.loot[prof.key]) do
        local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
        if not texture and GetItemInfoInstant then
            texture = select(5, GetItemInfoInstant(itemID))
        end
        list[#list + 1] = {
            id = itemID, count = r.count, value = r.value, tier = ItemTier(itemID),
            name = name or ("Item #" .. itemID), quality = quality, texture = texture,
        }
        total = total + r.value
    end

    local key, asc = prefs.sortKey, prefs.sortAsc
    table.sort(list, function(a, b)
        if a[key] ~= b[key] then
            if asc then return a[key] < b[key] end
            return a[key] > b[key]
        end
        return a.name < b.name
    end)

    header:SetText(Icon(prof.icon, 18) .. " " .. Money(total))
    subheader:SetText(string.format("%d different %s resources", #list, prof.label:lower()))
    toggle:SetText("Lifetime")
    UIDropDownMenu_SetText(dropdown, prof.label)
    dropdown:Show()
    columns:Show()
    UpdateHeaders()
    scroll:SetPoint("TOPLEFT", 12, -98)

    for i, r in ipairs(list) do
        local color = r.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality]
        local label = (color and color.hex or "|cffffffff") .. r.name .. "|r"
        SetRow(i, r.texture, label, tostring(r.count), Money(r.value))
    end
    empty:SetText(#list == 0 and ("Nothing from " .. prof.label .. " yet.") or "")
    return #list
end

Refresh = function()
    if not frame:IsShown() or not ns.db then return end
    for _, row in ipairs(rows) do row:Hide() end
    if scroll_reset then scroll:SetVerticalScroll(0); scroll_reset = nil end
    local count = view == "lifetime" and ShowLifetime() or ShowResources()
    content:SetHeight(math.max(count * ROW_HEIGHT, 1))
end
ns.RefreshHistory = Refresh

-- Opening Resources picks the profession this character gathered with last.
-- The dropdown can still switch it afterwards.
local function SelectLastProfession()
    if ns.db and ns.db.lastProf then ns.prefs.resProf = ns.db.lastProf end
end

toggle:SetScript("OnClick", function()
    view = view == "lifetime" and "resources" or "lifetime"
    if view == "resources" then SelectLastProfession() end
    scroll:SetVerticalScroll(0)
    Refresh()
end)

frame:SetScript("OnShow", function()
    if view == "resources" then SelectLastProfession() end
    Refresh()
end)
-- Item names and icons can arrive from the server after the window is drawn.
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function()
    if view == "resources" then Refresh() end
end)

function ns.ToggleHistory()
    frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button (drag it around the minimap edge)
---------------------------------------------------------------------------
local button = CreateFrame("Button", "GatheringGoldCalculatorMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local bg = button:CreateTexture(nil, "BACKGROUND")
bg:SetSize(20, 20)
bg:SetPoint("TOPLEFT", 7, -5)
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

-- Three small icons in a triangle inside the round button:
-- pickaxe on top, a herb (Peacebloom) bottom left, Light Leather bottom right.
local function ItemIcon(itemID, fallback)
    local icon = GetItemInfoInstant and select(5, GetItemInfoInstant(itemID))
    return icon or fallback
end

local MINI_ICONS = {
    { texture = PICKAXE, x = 17, y = -10 },
    { texture = ItemIcon(2447, "Interface\\Icons\\INV_Misc_Flower_02"), x = 12, y = -19 },     -- Peacebloom
    { texture = ItemIcon(2318, "Interface\\Icons\\INV_Misc_LeatherScrap_03"), x = 22, y = -19 }, -- Light Leather
}
for _, m in ipairs(MINI_ICONS) do
    local t = button:CreateTexture(nil, "ARTWORK")
    t:SetSize(10, 10)
    t:SetPoint("CENTER", button, "TOPLEFT", m.x, m.y)
    t:SetTexture(m.texture)
    t:SetTexCoord(0.1, 0.9, 0.1, 0.9)
end

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function PlaceButton()
    local angle = math.rad(ns.prefs.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.prefs.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    PlaceButton()
end

button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", DragUpdate) end)
button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
-- Right-click menu
local menu = CreateFrame("Frame", "GatheringGoldCalculatorMinimapMenu", UIParent, "UIDropDownMenuTemplate")
UIDropDownMenu_Initialize(menu, function(self, level)
    if not ns.prefs then return end -- runs once while the file loads
    local info = UIDropDownMenu_CreateInfo()
    info.text = "Gathering Gold"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Toggle session tracker"
    info.isNotRadio = true
    info.checked = ns.IsTrackerOn()
    info.func = function() ns.SetTrackerOn(not ns.IsTrackerOn()) end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Combined mode"
    info.tooltipTitle = "Combined mode"
    info.tooltipText = "Checked: one floating line with the value of everything you looted.\n"
        .. "Unchecked: one line per item, with its count, icon and value."
    info.tooltipOnButton = true
    info.isNotRadio = true
    info.checked = ns.IsCombinedFloat()
    info.func = function() ns.SetCombinedFloat(not ns.IsCombinedFloat()) end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Start new session"
    info.notCheckable = true
    info.func = function() ns.StartNewSession() end
    UIDropDownMenu_AddButton(info, level)
end, "MENU")

button:SetScript("OnClick", function(self, mouse)
    if mouse == "RightButton" then
        GameTooltip:Hide()
        ToggleDropDownMenu(1, nil, menu, self, 0, 0)
    else
        CloseDropDownMenus()
        ns.ToggleHistory()
    end
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Gathering Gold")
    local total, gathers, count = LifetimeTotals()
    GameTooltip:AddDoubleLine("Lifetime", Money(total), 1, 1, 1)
    GameTooltip:AddDoubleLine("Sessions / gathers", count .. " / " .. gathers, 1, 1, 1, 1, 1, 1)
    if ns.db.current then
        GameTooltip:AddDoubleLine("This session", Money(ns.db.current.total), 0.25, 1, 0.25)
    end
    GameTooltip:AddLine("Click to open the history. Right-click for options.\nDrag to move.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    ns.InitDB()
    PlaceButton()
    self:UnregisterEvent("ADDON_LOADED")
end)
