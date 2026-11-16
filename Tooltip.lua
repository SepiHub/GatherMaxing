-- Tooltip lines for gathering nodes and skinnable corpses:
--   Requires Mining 125                   colored like a recipe: red, orange,
--                                         yellow, green or gray
--   ~12s 40c per node (8 gathered)        average of what that kind of node
--                                         dropped for you, at today's prices

local ADDON, ns = ...

-- Node skills, PlayerSkill and SkillColor live in SkillData.lua.
local NODES = ns.NODES

-- Corpse tooltip lines that say a creature can be gathered.
local CORPSE_LINES = {}
if UNIT_SKINNABLE_LEATHER then CORPSE_LINES[UNIT_SKINNABLE_LEATHER] = "skinning" end
if UNIT_SKINNABLE_HERB then CORPSE_LINES[UNIT_SKINNABLE_HERB] = "herbalism" end
if UNIT_SKINNABLE_ROCK then CORPSE_LINES[UNIT_SKINNABLE_ROCK] = "mining" end

local PER = { mining = "per node", herbalism = "per herb", skinning = "per corpse" }

local function IsSecret(v)
    return ns.IsSecret and ns.IsSecret(v)
end

-- Average value of one node of this name at today's prices.
local function AverageValue(name)
    local n = ns.db and ns.db.nodes and ns.db.nodes[name]
    if not n or n.count < 1 then return nil end
    local total = 0
    for itemID, count in pairs(n.items) do
        total = total + count * ns.PriceOf(itemID)
    end
    return total / n.count, n.count
end

local function AddLines(tt, name, prof, need)
    local label = ns.PROF_BY_KEY[prof].label
    local skill = ns.PlayerSkill(prof)
    local text = string.format("Requires %s %d", label, need)
    tt:AddLine(text, ns.SkillColor(skill, need))
    tt.gmaxText = text -- lets the node check see if the game wiped our lines

    local avg, count = AverageValue(name)
    if avg then
        tt:AddLine(string.format("~%s %s (%d gathered)",
            ns.FormatMoney(avg, true), PER[prof], count), 1, 1, 1)
    end
end

-- Gathering nodes: world objects with no unit or item on the tooltip,
-- matched by the first line (the node's name). The game can fill the
-- tooltip after it shows, so this checks on show, after the tooltip data
-- is set, and every frame while it's open, adding the lines again whenever
-- the game redraws the tooltip without them.
local function Debug(...)
    if ns.tooltipDebug then print("|cffe0a030GatherMaxing tooltip|r:", ...) end
end

-- True while our "Requires ..." line is still on the tooltip.
local function HasOurLines(tt)
    if not tt.gmaxText then return false end
    for i = 2, tt:NumLines() do
        local line = _G[tt:GetName() .. "TextLeft" .. i]
        if line and line:GetText() == tt.gmaxText then return true end
    end
    return false
end

local function TryNode(tt, source)
    -- The game redraws node tooltips, wiping added lines; add them again.
    if tt.gmaxDone and (tt.gmaxSecret or HasOurLines(tt)) then return end
    local ok, err = pcall(function()
        local line = _G[tt:GetName() .. "TextLeft1"]
        local name = line and line:GetText()
        if not name then return end
        if IsSecret(name) then
            Debug(source, "first line is a secret value")
            tt.gmaxDone, tt.gmaxSecret = true, true
            return
        end
        local node = NODES[name]
        if not node then
            if ns.tooltipDebug and tt.gmaxLast ~= name then
                tt.gmaxLast = name
                Debug(source, "not a known node:", name)
            end
            return
        end
        if tt.GetUnit and tt:GetUnit() then Debug(source, name, "has a unit"); return end
        if tt.GetItem and tt:GetItem() then return end -- e.g. Peacebloom the item
        tt.gmaxDone = true
        Debug(source, "adding lines for", name)
        tt.gmaxText = nil
        AddLines(tt, name, node.prof, node.skill)
        tt:Show() -- resize to fit the new lines
    end)
    if not ok then Debug(source, "error:", err) end
end

local function Reset(tt) tt.gmaxDone, tt.gmaxLast, tt.gmaxText, tt.gmaxSecret = nil, nil, nil, nil end
GameTooltip:HookScript("OnTooltipCleared", Reset)
GameTooltip:HookScript("OnHide", Reset)
GameTooltip:HookScript("OnShow", function(tt) TryNode(tt, "OnShow") end)
-- Every frame, so a redraw is fixed before you can see the lines missing.
-- Cheap: once the lines are on, this only looks at the tooltip's few lines.
GameTooltip:HookScript("OnUpdate", function(tt) TryNode(tt, "OnUpdate") end)
if TooltipDataProcessor and TooltipDataProcessor.AllTypes then
    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tt)
        if tt == GameTooltip then TryNode(tt, "TooltipData") end
    end)
end

-- Skinnable (or herb/mining) corpses: units with a "Skinnable" line.
local function OnUnit(tt)
    if tt ~= GameTooltip then return end
    pcall(function()
        local unit = "mouseover"
        if not UnitExists(unit) or not UnitIsDead(unit) then return end
        local prof
        for i = 2, tt:NumLines() do
            local line = _G[tt:GetName() .. "TextLeft" .. i]
            local text = line and line:GetText()
            if text and not IsSecret(text) and CORPSE_LINES[text] then
                prof = CORPSE_LINES[text]
                break
            end
        end
        if not prof then return end
        local level, name = UnitLevel(unit), UnitName(unit)
        if IsSecret(level) or IsSecret(name) or not level or level < 1 then return end
        AddLines(tt, name, prof, ns.CorpseSkill(level))
        tt:Show()
    end)
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
else
    GameTooltip:HookScript("OnTooltipSetUnit", OnUnit)
end
