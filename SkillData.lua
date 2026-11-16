-- Skill data shared by the node tooltips and the Skill Book.
--   ns.NODES[name]        = { prof, skill, item }   node name -> what it needs
--   ns.BOOK[prof]         = { { skill, name, item | icon, note, gather }, ... }
--                           gather = true for things you can gather (nodes,
--                           herbs, corpses), not ranks or smelting
--   ns.PlayerSkill(prof)  -> rank, max  (nil if not learned)
--   ns.SkillColor(skill, need) -> r, g, b  (recipe-style difficulty color)
--   ns.CorpseSkill(level) -> skill needed to skin a corpse of that level

local ADDON, ns = ...

-- Classic gathering nodes: skill needed and the main item they give.
-- `book = false` keeps look-alike variants out of the Skill Book.
local NODE_LIST = {
    mining = {
        { "Copper Vein", 1, 2770 },
        { "Tin Vein", 65, 2771 },
        { "Incendicite Mineral Vein", 65, 3340 },
        { "Silver Vein", 75, 2775 },
        { "Ooze Covered Silver Vein", 75, 2775, book = false },
        { "Lesser Bloodstone Deposit", 75, 4278 },
        { "Iron Deposit", 125, 2772 },
        { "Indurium Mineral Vein", 150, 5833 },
        { "Gold Vein", 155, 2776 },
        { "Ooze Covered Gold Vein", 155, 2776, book = false },
        { "Mithril Deposit", 175, 3858 },
        { "Ooze Covered Mithril Deposit", 175, 3858, book = false },
        { "Truesilver Deposit", 230, 7911 },
        { "Ooze Covered Truesilver Deposit", 230, 7911, book = false },
        { "Dark Iron Deposit", 230, 11370 },
        { "Small Thorium Vein", 245, 10620 },
        { "Ooze Covered Thorium Vein", 245, 10620, book = false },
        { "Rich Thorium Vein", 275, 10620 },
        { "Ooze Covered Rich Thorium Vein", 275, 10620, book = false },
        { "Hakkari Thorium Vein", 275, 10620, book = false },
        { "Small Obsidian Chunk", 305, 22202 },
        { "Large Obsidian Chunk", 305, 22202, book = false },
    },
    herbalism = {
        { "Peacebloom", 1, 2447 },
        { "Silverleaf", 1, 765 },
        { "Earthroot", 15, 2449 },
        { "Mageroyal", 50, 785 },
        { "Briarthorn", 70, 2450 },
        { "Stranglekelp", 85, 3820 },
        { "Bruiseweed", 100, 2453 },
        { "Wild Steelbloom", 115, 3355 },
        { "Grave Moss", 120, 3369 },
        { "Kingsblood", 125, 3356 },
        { "Liferoot", 150, 3357 },
        { "Fadeleaf", 160, 3818 },
        { "Goldthorn", 170, 3821 },
        { "Khadgar's Whisker", 185, 3358 },
        { "Wintersbite", 195, 3819 },
        { "Firebloom", 205, 4625 },
        { "Purple Lotus", 210, 8831 },
        { "Arthas' Tears", 220, 8836 },
        { "Sungrass", 230, 8838 },
        { "Blindweed", 235, 8839 },
        { "Ghost Mushroom", 245, 8845 },
        { "Gromsblood", 250, 8846 },
        { "Golden Sansam", 260, 13464 },
        { "Dreamfoil", 270, 13463 },
        { "Mountain Silversage", 280, 13465 },
        { "Plaguebloom", 285, 13466 },
        { "Icecap", 290, 13467 },
        { "Black Lotus", 300, 13468 },
    },
}

ns.NODES = {}
for prof, list in pairs(NODE_LIST) do
    for _, n in ipairs(list) do
        ns.NODES[n[1]] = { prof = prof, skill = n[2], item = n[3] }
    end
end

-- Classic skill needed to skin (or gather from) a corpse of this level.
function ns.CorpseSkill(level)
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end

---------------------------------------------------------------------------
-- Skill Book entries, per profession
---------------------------------------------------------------------------
local BOOK = {}
ns.BOOK = BOOK

-- Training ranks (same for every gathering profession).
local RANKS = {
    { 1,   "Apprentice", "Learn at any trainer. Max skill 75." },
    { 50,  "Journeyman", "Train at character level 10. Max skill 150." },
    { 125, "Expert",     "Train at character level 20. Max skill 225." },
    { 200, "Artisan",    "Train at character level 35. Max skill 300." },
}

for _, p in ipairs(ns.PROFESSIONS) do
    local list = {}
    for _, r in ipairs(RANKS) do
        list[#list + 1] = { skill = r[1], name = r[2], icon = p.icon, note = r[3], rank = true }
    end
    for _, n in ipairs(NODE_LIST[p.key] or {}) do
        if n.book ~= false then
            list[#list + 1] = { skill = n[2], name = n[1], item = n[3], node = true, gather = true }
        end
    end
    BOOK[p.key] = list
end

-- Smelting comes with Mining.
local SMELTING = {
    { 1,   "Smelt Copper",    2840 },
    { 65,  "Smelt Tin",       3576 },
    { 65,  "Smelt Bronze",    2841 },
    { 75,  "Smelt Silver",    2842 },
    { 125, "Smelt Iron",      3575 },
    { 155, "Smelt Gold",      3577 },
    { 165, "Smelt Steel",     3859 },
    { 175, "Smelt Mithril",   3860 },
    { 230, "Smelt Truesilver", 6037 },
    { 230, "Smelt Dark Iron", 11371, "Only at the Black Forge in Blackrock Depths." },
    { 250, "Smelt Thorium",   12359 },
}
for _, s in ipairs(SMELTING) do
    table.insert(BOOK.mining, { skill = s[1], name = s[2], item = s[3], note = s[4] })
end

-- Skinning: which corpse levels you can skin, and the leather they mostly give.
local SKINNING = {
    { 10, 2318 }, { 15, 2318 }, { 20, 2319 }, { 25, 2319 }, { 30, 4234 },
    { 35, 4234 }, { 40, 4304 }, { 45, 4304 }, { 50, 8170 }, { 55, 8170 }, { 60, 8170 },
}
local LEATHER = { [2318] = "Light Leather", [2319] = "Medium Leather", [4234] = "Heavy Leather",
                  [4304] = "Thick Leather", [8170] = "Rugged Leather" }
for _, s in ipairs(SKINNING) do
    table.insert(BOOK.skinning, {
        skill = ns.CorpseSkill(s[1]),
        name = "Corpses up to level " .. s[1],
        item = s[2],
        note = "Mostly " .. LEATHER[s[2]] .. ".",
        gather = true,
    })
end

-- Lowest skill first; ranks before nodes at the same skill.
for _, list in pairs(BOOK) do
    table.sort(list, function(a, b)
        if a.skill ~= b.skill then return a.skill < b.skill end
        if (a.rank or false) ~= (b.rank or false) then return a.rank == true end
        return a.name < b.name
    end)
end

---------------------------------------------------------------------------
-- Player skill and difficulty colors
---------------------------------------------------------------------------

-- Skill line IDs, so the lookup works in any client language.
local SKILL_LINE = { mining = 186, herbalism = 182, skinning = 393, fishing = 356 }

-- Newer profession API: GetProfessions() gives up to 5 indexes
-- (two main professions, archaeology, fishing, cooking).
local function FromProfessions(prof)
    if not GetProfessions or not GetProfessionInfo then return nil end
    local want = SKILL_LINE[prof]
    for _, index in pairs({ GetProfessions() }) do
        local name, _, rank, max, _, _, skillLine = GetProfessionInfo(index)
        if skillLine == want or name == ns.PROF_BY_KEY[prof].label then return rank, max end
    end
end

-- Classic skill list (Character > Skills).
local function FromSkillLines(prof)
    if not GetNumSkillLines or not GetSkillLineInfo then return nil end
    local want = ns.PROF_BY_KEY[prof].label
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
        if not isHeader and name == want then return rank, max end
    end
end

-- This character's skill and max skill in a profession, or nil if not learned.
function ns.PlayerSkill(prof)
    local ok, rank, max = pcall(FromProfessions, prof)
    if ok and rank then return rank, max end
    ok, rank, max = pcall(FromSkillLines, prof)
    if ok and rank then return rank, max end
end

-- Lists what each skill API reports, for /gmax tipdebug.
function ns.DebugSkills()
    local say = function(...) print("|cffe0a030GatherMaxing skills|r:", ...) end
    say("GetProfessions", GetProfessions and "yes" or "missing",
        "| GetSkillLineInfo", GetSkillLineInfo and "yes" or "missing")
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            local name, _, rank, max, _, _, skillLine = GetProfessionInfo(index)
            say("profession", tostring(name), tostring(rank) .. "/" .. tostring(max), "line", tostring(skillLine))
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
            if not isHeader then say("skill line", tostring(name), tostring(rank) .. "/" .. tostring(max)) end
        end
    end
    for _, p in ipairs(ns.PROFESSIONS) do say(p.label, "->", tostring(ns.PlayerSkill(p.key))) end
end

-- Recipe-style difficulty color for gathering.
function ns.SkillColor(skill, need)
    if not skill or skill < need then return 1, 0.25, 0.25 end -- red: can't
    local over = skill - need
    if over < 25 then return 1, 0.5, 0.25 end                  -- orange
    if over < 50 then return 1, 1, 0 end                        -- yellow
    if over < 100 then return 0.25, 0.75, 0.25 end              -- green
    return 0.5, 0.5, 0.5                                        -- gray
end
