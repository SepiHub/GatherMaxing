-- Skill Book: everything a gathering profession unlocks, by skill level.
--   rows:   skill needed | icon | name                 | price each
--   colors: the skill number uses recipe colors for your current skill
--   a gold "You are here" line sits at your current skill
-- Open it from the minimap right-click menu or /gmax book.

local ADDON, ns = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local ROW_HEIGHT = 22
local CONTENT_WIDTH = 330

local function Money(copper) return ns.FormatMoney(copper, true) end
local function Icon(path) return string.format("|T%s:18:18:0:0:64:64:5:59:5:59|t", path) end
local function Hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end

local function ItemIcon(itemID)
    local texture = select(10, GetItemInfo(itemID))
    if not texture and GetItemInfoInstant then texture = select(5, GetItemInfoInstant(itemID)) end
    return texture or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- The profession shown: the saved pick, else the one gathered with last,
-- else the first one this character knows.
local function SelectedProfession()
    local key = ns.prefs.bookProf or (ns.db and ns.db.lastProf)
    if key and ns.BOOK[key] then return ns.PROF_BY_KEY[key] end
    for _, p in ipairs(ns.PROFESSIONS) do
        if ns.KnowsProfession(p.key) then return p end
    end
    return ns.PROF_BY_KEY.mining
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "GatherMaxingSkillBook", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(380, 460)
frame:SetPoint("CENTER", 40, 0)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetFrameStrata("DIALOG")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()
tinsert(UISpecialFrames, "GatherMaxingSkillBook") -- Escape closes it

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("TOP", 0, -5)
frame.title:SetText("GatherMaxing Skill Book")

local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
header:SetPoint("TOPLEFT", 14, -34)
header:SetJustifyH("LEFT")

local subheader = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subheader:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
subheader:SetJustifyH("LEFT")

local Refresh -- defined below
local jumpToPlayer -- scroll to "You are here" on the next refresh

local dropdown = CreateFrame("Frame", "GatherMaxingBookDropDown", frame, "UIDropDownMenuTemplate")
dropdown:SetPoint("TOPRIGHT", 4, -28)
UIDropDownMenu_SetWidth(dropdown, 110)
UIDropDownMenu_Initialize(dropdown, function(self, level)
    if not ns.prefs then return end -- runs once while the file loads
    local selected = SelectedProfession()
    for _, p in ipairs(ns.PROFESSIONS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = p.label
        info.icon = p.icon
        info.checked = (p.key == selected.key)
        info.func = function()
            ns.prefs.bookProf = p.key
            CloseDropDownMenus()
            jumpToPlayer = true
            Refresh()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end)

local legend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
legend:SetPoint("BOTTOM", 0, 14)
legend:SetText(Hex(1, 0.25, 0.25) .. "can't yet|r   " .. Hex(1, 0.5, 0.25) .. "orange|r   "
    .. Hex(1, 1, 0) .. "yellow|r   " .. Hex(0.25, 0.75, 0.25) .. "green|r   "
    .. Hex(0.5, 0.5, 0.5) .. "no skill-ups|r")

local scroll = CreateFrame("ScrollFrame", "GatherMaxingSkillBookScroll", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -78)
scroll:SetPoint("BOTTOMRIGHT", -32, 34)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(CONTENT_WIDTH, 1)
scroll:SetScrollChild(content)

local rows = {}

local function RowEnter(self)
    local e = self.entry
    if not e or e.here then return end
    self.hover:Show()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if e.item then
        GameTooltip:SetItemByID(e.item)
    else
        GameTooltip:SetText(e.name)
    end
    GameTooltip:AddLine("Requires " .. self.profLabel .. " " .. e.skill, ns.SkillColor(self.playerSkill, e.skill))
    if e.note then GameTooltip:AddLine(e.note, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function RowLeave(self)
    self.hover:Hide()
    GameTooltip:Hide()
end

local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetWidth(CONTENT_WIDTH)
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.hover = row:CreateTexture(nil, "BORDER")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 0.82, 0, 0.12)
    row.hover:Hide()

    row.skill = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.skill:SetPoint("LEFT", 2, 0)
    row.skill:SetWidth(34)
    row.skill:SetJustifyH("RIGHT")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 42, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.right = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    rows[i] = row
    return row
end

-- The gold "You are here" line.
local function SetHereRow(row, label, skill)
    row.bg:SetColorTexture(1, 0.82, 0, 0.25)
    row.skill:SetText("")
    row.icon:Hide()
    row.name:SetText(string.format("|cffffd100>> You are here: %s %d|r", label, skill))
    row.right:SetText("")
end

local function SetEntryRow(row, i, e, skill)
    row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    row.skill:SetText(Hex(ns.SkillColor(skill, e.skill)) .. e.skill .. "|r")
    row.icon:SetTexture(e.item and ItemIcon(e.item) or e.icon)
    row.icon:Show()
    if e.rank then
        row.name:SetText("|cffffd100" .. e.name .. "|r  |cff999999" .. (e.note or "") .. "|r")
    else
        row.name:SetText(e.name)
    end
    local price = e.item and ns.PriceOf(e.item) or 0
    row.right:SetText(price > 0 and Money(price) or "")
end

Refresh = function()
    if not frame:IsShown() or not ns.prefs then return end
    local prof = SelectedProfession()
    local skill, max = ns.PlayerSkill(prof.key)
    UIDropDownMenu_SetText(dropdown, prof.label)

    if skill then
        header:SetText(string.format("%s %s %d / %d", Icon(prof.icon), prof.label, skill, max or skill))
        local nextUp
        for _, e in ipairs(ns.BOOK[prof.key]) do
            if e.skill > skill and not e.rank then nextUp = e; break end
        end
        subheader:SetText(nextUp and string.format("Next: %s at %d (%d to go)", nextUp.name, nextUp.skill,
            nextUp.skill - skill) or "Nothing left to unlock. Nice!")
    else
        header:SetText(Icon(prof.icon) .. " " .. prof.label)
        subheader:SetText("|cffff4040You haven't learned " .. prof.label .. ".|r Visit a trainer to start.")
    end

    -- Entries, with the "You are here" line after the last one you've reached.
    local list, hereIndex = {}, nil
    for _, e in ipairs(ns.BOOK[prof.key]) do
        if skill and not hereIndex and e.skill > skill then
            list[#list + 1] = { here = true }
            hereIndex = #list
        end
        list[#list + 1] = e
    end
    if skill and not hereIndex then
        list[#list + 1] = { here = true }
        hereIndex = #list
    end

    for _, row in ipairs(rows) do row:Hide() end
    for i, e in ipairs(list) do
        local row = GetRow(i)
        row.entry, row.playerSkill, row.profLabel = e, skill, prof.label
        if e.here then SetHereRow(row, prof.label, skill) else SetEntryRow(row, i, e, skill) end
        row:Show()
    end
    content:SetHeight(math.max(#list * ROW_HEIGHT, 1))

    if jumpToPlayer then
        jumpToPlayer = nil
        local target = hereIndex and (hereIndex - 4) * ROW_HEIGHT or 0
        C_Timer.After(0, function()
            scroll:SetVerticalScroll(math.max(0, math.min(target, scroll:GetVerticalScrollRange())))
        end)
    end
end

frame:SetScript("OnShow", function()
    jumpToPlayer = true
    Refresh()
end)
-- Skill-ups and item icons arriving from the server redraw the list.
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function() Refresh() end)

function ns.ToggleSkillBook()
    frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Chat message when a skill-up unlocks something new to gather, like
--   GatherMaxing: Mining 155 - you can now mine [icon] Gold Vein!
-- Only nodes, herbs and corpse levels; not ranks or smelting.
---------------------------------------------------------------------------
local known = {} -- [prof] = skill last seen (nil until the first check)
local VERB = { mining = "mine", herbalism = "harvest", skinning = "skin" }

local function CheckUnlocks(announce)
    for _, p in ipairs(ns.PROFESSIONS) do
        local skill = ns.PlayerSkill(p.key)
        local old = known[p.key]
        if announce and skill and old and skill > old then
            local names = {}
            for _, e in ipairs(ns.BOOK[p.key]) do
                if e.gather and e.skill > old and e.skill <= skill then
                    local icon = e.item and ItemIcon(e.item) or e.icon
                    -- "Corpses up to level 30" reads as "skin corpses up to level 30"
                    local name = p.key == "skinning" and e.name:gsub("^%u", string.lower) or e.name
                    names[#names + 1] = string.format("|T%s:14:14|t |cffffffff%s|r", icon, name)
                end
            end
            if #names > 0 then
                print(string.format("|cffe0a030GatherMaxing|r: %s %d - you can now %s %s!",
                    p.label, skill, VERB[p.key] or "gather", table.concat(names, ", ")))
            end
        end
        known[p.key] = skill
    end
end

local skillWatch = CreateFrame("Frame")
skillWatch:RegisterEvent("PLAYER_LOGIN")
skillWatch:RegisterEvent("SKILL_LINES_CHANGED")
skillWatch:RegisterEvent("CHAT_MSG_SKILL") -- "Your skill in X has increased to N."
skillWatch:SetScript("OnEvent", function(_, event)
    -- On login just remember the current skills; announce from then on.
    CheckUnlocks(event ~= "PLAYER_LOGIN")
end)
