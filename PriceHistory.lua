-- Price history: click a resource (Skill Book, Resources, a session) to
-- see how its price changed over time.
--   * one auction price per item per day, saved account-wide in
--     GatherMaxingDB.priceHistory[itemID][day] = copper, recorded at login,
--     every 15 minutes and after closing the auction house
--   * days before that come from what your sessions saved: each gathered
--     item's value / count is the price it had that day
--   * a line graph (hover it for exact prices) with 7 days / 30 days / all,
--     plus change, lowest, highest, average and TSM's own values

local ADDON, ns = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local DAY = 86400
local KEEP_DAYS = 400
local GRAPH_W, GRAPH_H = 360, 150
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

local function Money(copper) return ns.FormatMoney(copper, true) end

-- Noon (local time) of the day `t` falls on: one key per day, good for plotting.
local function DayKey(t)
    local d = date("*t", t)
    return time({ year = d.year, month = d.month, day = d.day, hour = 12 })
end

local function History()
    if not ns.prefs then return nil end
    ns.prefs.priceHistory = ns.prefs.priceHistory or {}
    return ns.prefs.priceHistory
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- Every item the addon knows about: nodes, the Skill Book and your loot.
local function TrackedItems()
    local items = {}
    for _, node in pairs(ns.NODES or {}) do
        if node.item then items[node.item] = true end
    end
    for _, list in pairs(ns.BOOK or {}) do
        for _, e in ipairs(list) do
            if e.item then items[e.item] = true end
        end
    end
    if ns.db and ns.db.loot then
        for _, loot in pairs(ns.db.loot) do
            for itemID in pairs(loot) do items[itemID] = true end
        end
    end
    return items
end

local function Snapshot()
    local hist = History()
    if not hist or not ns.AuctionPrice then return end
    local today = DayKey(time())
    local oldest = today - KEEP_DAYS * DAY
    for itemID in pairs(TrackedItems()) do
        local price = ns.AuctionPrice(itemID) -- nil when there's no auction price
        if price then
            local days = hist[itemID] or {}
            hist[itemID] = days
            days[today] = math.floor(price + 0.5)
            for day in pairs(days) do
                if day < oldest then days[day] = nil end
            end
        end
    end
    if ns.RefreshPriceHistory then ns.RefreshPriceHistory() end
end

local recorder = CreateFrame("Frame")
recorder:RegisterEvent("PLAYER_LOGIN")
recorder:RegisterEvent("AUCTION_HOUSE_CLOSED")
recorder:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Give Auctionator / TSM time to load their prices first.
        C_Timer.After(15, Snapshot)
        C_Timer.NewTicker(15 * 60, Snapshot)
    else
        C_Timer.After(3, Snapshot) -- prices from a scan just made
    end
end)

-- Points for one item, oldest first: { t = day, price = copper, gathered = bool }
local function PricePoints(itemID)
    local byDay = {}
    -- Sessions: the price each gather was valued at.
    local sessions = {}
    if ns.db then
        for _, s in ipairs(ns.db.sessions or {}) do sessions[#sessions + 1] = s end
        if ns.db.current then sessions[#sessions + 1] = ns.db.current end
    end
    local sums = {}
    for _, s in ipairs(sessions) do
        local r = s.items and s.items[itemID]
        if r and r.count and r.count > 0 and r.value and r.value > 0 then
            local day = DayKey(s.start)
            local sum = sums[day] or { value = 0, count = 0 }
            sums[day] = sum
            sum.value = sum.value + r.value
            sum.count = sum.count + r.count
        end
    end
    for day, sum in pairs(sums) do
        byDay[day] = { t = day, price = sum.value / sum.count, gathered = true }
    end
    -- Daily snapshots win over session prices for the same day.
    local hist = History()
    for day, price in pairs(hist and hist[itemID] or {}) do
        byDay[day] = { t = day, price = price }
    end
    local points = {}
    for _, p in pairs(byDay) do points[#points + 1] = p end
    table.sort(points, function(a, b) return a.t < b.t end)
    return points
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "GatherMaxingPriceHistory", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(450, 470) -- room on the left for the price labels
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetFrameStrata("DIALOG")
frame:SetFrameLevel(100) -- above the Skill Book (50)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()
tinsert(UISpecialFrames, "GatherMaxingPriceHistory") -- Escape closes it

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("TOP", 0, -5)
frame.title:SetText("Price History")

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetSize(30, 30)
icon:SetPoint("TOPLEFT", 14, -32)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
nameText:SetPoint("RIGHT", -14, 0)
nameText:SetJustifyH("LEFT")
nameText:SetWordWrap(false)

local currentText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
currentText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 0)
currentText:SetJustifyH("LEFT")

-- Range buttons: 7 days, 30 days, everything.
local RANGES = { { key = 7, label = "7 days" }, { key = 30, label = "30 days" }, { key = 0, label = "All" } }
local rangeButtons = {}
local Refresh -- defined below
for i, r in ipairs(RANGES) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(64, 20)
    b:SetPoint("TOPRIGHT", -14 - (#RANGES - i) * 66, -72)
    b:SetText(r.label)
    b:SetScript("OnClick", function()
        ns.prefs.priceRange = r.key
        Refresh()
    end)
    rangeButtons[i] = b
end

local function Range()
    local key = ns.prefs and ns.prefs.priceRange
    if key == nil then key = 30 end
    return key
end

-- Graph area
local graph = CreateFrame("Frame", nil, frame)
graph:SetSize(GRAPH_W, GRAPH_H)
graph:SetPoint("TOPRIGHT", -16, -100)
graph:EnableMouse(true)

local graphBg = graph:CreateTexture(nil, "BACKGROUND")
graphBg:SetPoint("TOPLEFT", -2, 2)
graphBg:SetPoint("BOTTOMRIGHT", 2, -2)
graphBg:SetColorTexture(0, 0, 0, 0.45)

local grid, yLabels = {}, {}
for i = 0, 2 do
    local g = graph:CreateTexture(nil, "BORDER")
    g:SetColorTexture(1, 1, 1, i == 0 and 0.18 or 0.07)
    g:SetHeight(1)
    g:SetPoint("BOTTOMLEFT", 0, i * GRAPH_H / 2)
    g:SetPoint("BOTTOMRIGHT", 0, i * GRAPH_H / 2)
    grid[i] = g
    local label = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    label:SetPoint("RIGHT", graph, "BOTTOMLEFT", -4, i * GRAPH_H / 2)
    label:SetJustifyH("RIGHT")
    yLabels[i] = label
end

local xLeft = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
xLeft:SetPoint("TOPLEFT", graph, "BOTTOMLEFT", 0, -4)
local xRight = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
xRight:SetPoint("TOPRIGHT", graph, "BOTTOMRIGHT", 0, -4)

local graphEmpty = graph:CreateFontString(nil, "OVERLAY", "GameFontDisable")
graphEmpty:SetPoint("CENTER")
graphEmpty:SetWidth(GRAPH_W - 30)
graphEmpty:SetJustifyH("CENTER")

-- Pools: lines between points, dots on points.
local lines, dots = {}, {}
local function GetLine(i)
    if not lines[i] then
        local l = graph:CreateLine(nil, "ARTWORK")
        l:SetThickness(2)
        l:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
        lines[i] = l
    end
    return lines[i]
end
local function GetDot(i)
    if not dots[i] then
        local d = graph:CreateTexture(nil, "OVERLAY")
        d:SetSize(5, 5)
        d:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
        dots[i] = d
    end
    return dots[i]
end

-- Hover: a vertical line and a bigger dot on the nearest point.
local hoverLine = graph:CreateTexture(nil, "ARTWORK")
hoverLine:SetColorTexture(1, 1, 1, 0.25)
hoverLine:SetWidth(1)
hoverLine:Hide()
local hoverDot = graph:CreateTexture(nil, "OVERLAY", nil, 2)
hoverDot:SetSize(9, 9)
hoverDot:SetColorTexture(1, 1, 1, 1)
hoverDot:Hide()

local plotted = {} -- { x, y, point } of what's drawn now

graph:SetScript("OnUpdate", function(self)
    if #plotted == 0 or not self:IsMouseOver() then
        if hoverDot:IsShown() then
            hoverDot:Hide(); hoverLine:Hide()
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end
        return
    end
    local cx = GetCursorPosition() / self:GetEffectiveScale() - self:GetLeft()
    local best, bestDist
    for _, p in ipairs(plotted) do
        local dist = math.abs(p.x - cx)
        if not bestDist or dist < bestDist then best, bestDist = p, dist end
    end
    if self.hovered == best and hoverDot:IsShown() then return end
    self.hovered = best
    hoverDot:ClearAllPoints()
    hoverDot:SetPoint("CENTER", self, "BOTTOMLEFT", best.x, best.y)
    hoverDot:Show()
    hoverLine:ClearAllPoints()
    hoverLine:SetPoint("BOTTOM", self, "BOTTOMLEFT", best.x, 0)
    hoverLine:SetPoint("TOP", self, "TOPLEFT", best.x, 0)
    hoverLine:Show()
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(date("%a %b %d, %Y", best.point.t))
    GameTooltip:AddLine(Money(best.point.price), 1, 1, 1)
    if best.point.gathered then
        GameTooltip:AddLine("Price your gathers were valued at that day", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end)

-- Stats below the graph, two columns of label / value.
local stats = {}
local function StatLine(i)
    if stats[i] then return stats[i] end
    local col = (i - 1) % 2
    local rowIndex = math.floor((i - 1) / 2)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 16 + col * 215, -284 - rowIndex * 18)
    label:SetJustifyH("LEFT")
    local value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", 16 + col * 215 + 92, -284 - rowIndex * 18)
    value:SetJustifyH("LEFT")
    stats[i] = { label = label, value = value }
    return stats[i]
end

local tip = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
tip:SetPoint("BOTTOMLEFT", 16, 14)
tip:SetPoint("BOTTOMRIGHT", -16, 14)
tip:SetJustifyH("LEFT")
tip:SetSpacing(2)
tip:SetText("Tip: TSM is better at tracking prices than Auctionator. Its prices update "
    .. "through the TSM app, without you having to scan the auction house.")

local currentItem

local function Percent(from, to)
    if not from or from <= 0 then return "|cff999999-|r" end
    local change = (to - from) / from * 100
    local color = change > 0.5 and "|cff40ff40" or change < -0.5 and "|cffff4040" or "|cffffffff"
    return string.format("%s%+.1f%%|r", color, change)
end

local function TSMValue(source, itemID)
    if not ns.HasTSM or not ns.HasTSM() then return nil end
    local ok, price = pcall(TSM_API.GetCustomPriceValue, source, "i:" .. itemID)
    if ok and type(price) == "number" and price > 0 then return price end
end

local function SourceLabel()
    local key = ns.PriceSource and ns.PriceSource() or "auto"
    for _, src in ipairs(ns.PRICE_SOURCES or {}) do
        if src.key == key then return src.label end
    end
    return key
end

Refresh = function()
    if not frame:IsShown() or not currentItem then return end
    local itemID = currentItem

    local name, _, quality, _, _, _, _, _, _, texture, vendor = GetItemInfo(itemID)
    if not texture and GetItemInfoInstant then texture = select(5, GetItemInfoInstant(itemID)) end
    icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    nameText:SetText((color and color.hex or "|cffffffff") .. (name or ("Item #" .. itemID)) .. "|r")
    local now = ns.PriceOf(itemID)
    local auction = ns.AuctionPrice and ns.AuctionPrice(itemID)
    currentText:SetText("Now: " .. Money(now) .. "  |cff999999("
        .. (auction and SourceLabel() or "vendor price") .. ")|r")

    -- Range buttons: the selected one is grayed out.
    local range = Range()
    for i, r in ipairs(RANGES) do rangeButtons[i]:SetEnabled(r.key ~= range) end

    -- Points in range
    local all = PricePoints(itemID)
    local points = {}
    local from = range > 0 and (DayKey(time()) - (range - 1) * DAY) or 0
    for _, p in ipairs(all) do
        if p.t >= from then points[#points + 1] = p end
    end

    for _, l in ipairs(lines) do l:Hide() end
    for _, d in ipairs(dots) do d:Hide() end
    wipe(plotted)
    graph.hovered = nil

    local low, high, sum
    for _, p in ipairs(points) do
        low = (not low or p.price < low.price) and p or low
        high = (not high or p.price > high.price) and p or high
        sum = (sum or 0) + p.price
    end

    if #points == 0 then
        graphEmpty:SetText(#all == 0
            and "No price history yet.\nGatherMaxing saves a price every day you play while "
                .. "Auctionator or TSM has one."
            or "No prices in this range. Try All.")
        for i = 0, 2 do yLabels[i]:SetText("") end
        xLeft:SetText(""); xRight:SetText("")
    else
        graphEmpty:SetText(#points == 1 and "Only one day so far. The line grows as days are saved." or "")
        -- Scale with a little room above and below.
        local pmin, pmax = low.price, high.price
        local pad = (pmax - pmin) * 0.1
        if pad == 0 then pad = math.max(pmax * 0.1, 1) end
        pmin, pmax = math.max(pmin - pad, 0), pmax + pad
        local tmin, tmax = points[1].t, points[#points].t
        if range > 0 then tmin = math.min(tmin, from) end
        tmax = math.max(tmax, DayKey(time()))
        for i, p in ipairs(points) do
            local x = tmax > tmin and (p.t - tmin) / (tmax - tmin) * GRAPH_W or GRAPH_W / 2
            local y = (p.price - pmin) / (pmax - pmin) * GRAPH_H
            plotted[i] = { x = x, y = y, point = p }
            local d = GetDot(i)
            d:ClearAllPoints()
            d:SetPoint("CENTER", graph, "BOTTOMLEFT", x, y)
            d:Show()
            if i > 1 and graph.CreateLine then
                local l = GetLine(i - 1)
                l:SetStartPoint("BOTTOMLEFT", graph, plotted[i - 1].x, plotted[i - 1].y)
                l:SetEndPoint("BOTTOMLEFT", graph, x, y)
                l:Show()
            end
        end
        yLabels[0]:SetText(Money(pmin))
        yLabels[1]:SetText(Money((pmin + pmax) / 2))
        yLabels[2]:SetText(Money(pmax))
        xLeft:SetText(date("%b %d", tmin))
        xRight:SetText(date("%b %d", tmax))
    end

    -- Stats
    local rows = {}
    local function add(label, value) rows[#rows + 1] = { label, value } end
    local first = points[1]
    add("Change", first and Percent(first.price, now) or "|cff999999-|r")
    add("Average", sum and Money(sum / #points) or "-")
    add("Lowest", low and (Money(low.price) .. " |cff999999" .. date("%b %d", low.t) .. "|r") or "-")
    add("Highest", high and (Money(high.price) .. " |cff999999" .. date("%b %d", high.t) .. "|r") or "-")
    -- Last 7 days vs the 7 before, when there's enough history.
    local today = DayKey(time())
    local weekAgo
    for _, p in ipairs(all) do
        if p.t <= today - 7 * DAY then weekAgo = p end
    end
    add("This week", weekAgo and Percent(weekAgo.price, now) or "|cff999999-|r")
    add("Vendor", vendor and vendor > 0 and Money(vendor) or "-")
    local gathered, gatheredValue = 0, 0
    if ns.db and ns.db.loot then
        for _, loot in pairs(ns.db.loot) do
            local r = loot[itemID]
            if r then gathered, gatheredValue = gathered + r.count, gatheredValue + r.value end
        end
    end
    add("Gathered", gathered > 0 and (gathered .. "  |cff999999(" .. Money(gatheredValue) .. ")|r") or "none yet")
    add("Days saved", #all > 0 and (#all .. "  |cff999999since " .. date("%b %d", all[1].t) .. "|r") or "0")
    if ns.HasTSM and ns.HasTSM() then
        add("TSM market", TSMValue("DBMarket", itemID) and Money(TSMValue("DBMarket", itemID)) or "-")
        add("TSM historical", TSMValue("DBHistorical", itemID) and Money(TSMValue("DBHistorical", itemID)) or "-")
        add("Region avg", TSMValue("DBRegionMarketAvg", itemID) and Money(TSMValue("DBRegionMarketAvg", itemID)) or "-")
        add("Region sale", TSMValue("DBRegionSaleAvg", itemID) and Money(TSMValue("DBRegionSaleAvg", itemID)) or "-")
    end
    for _, s in ipairs(stats) do s.label:SetText(""); s.value:SetText("") end
    for i, r in ipairs(rows) do
        local s = StatLine(i)
        s.label:SetText(r[1])
        s.value:SetText(r[2])
    end
end
ns.RefreshPriceHistory = Refresh

-- Item names and icons can arrive from the server after the window opens.
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function() Refresh() end)
frame:SetScript("OnHide", function()
    if GameTooltip:GetOwner() == graph then GameTooltip:Hide() end
end)

-- Opens the window for an item, next to the main window when it's open.
function ns.ShowPriceHistory(itemID)
    if not itemID then return end
    currentItem = itemID
    if not frame:IsShown() then
        local anchor
        local book = ns.skillBookFrame
        local hist = _G.GatherMaxingHistory
        if book and book:IsShown() then anchor = book
        elseif hist and hist:IsShown() then anchor = hist end
        frame:ClearAllPoints()
        if anchor then
            frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
        else
            frame:SetPoint("CENTER")
        end
        frame:Show()
    end
    Refresh()
end
