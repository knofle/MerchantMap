local _, MM = ...

-- Search matching for the window: query parsing, levels, "usable", gear words, categories and service NPCs.
-- S.tokens holds the current search's words, for MatchReason.

local S = {}
MM.Search = S
local lowerNames, lowerPaths = {}, {}

local function LowerName(itemID)
    local name = lowerNames[itemID]
    if not name then
        name = strlower(MM.db.items[itemID].name or "")
        lowerNames[itemID] = name
    end
    return name
end

-- Search shorthands; two-letter ones only match their expansion
local ALIASES = {
    alch = "alchemy", bs = "blacksmithing", cook = "cooking", ench = "enchanting", engi = "engineering",
    fish = "fishing", lw = "leatherworking", herb = "herbalism", mine = "mining", skin = "skinning",
    mats = "materials",
}

local function Tokens(query)
    local tokens = {}
    for word in query:gmatch("%S+") do
        tokens[#tokens + 1] = { word = word, alias = ALIASES[word] }
    end
    return tokens
end

local function TokenIn(text, t)
    return (t.alias and text:find(t.alias, 1, true))
        or ((not t.alias or #t.word > 2) and text:find(t.word, 1, true))
end

local function LowerPath(path)
    local lower = lowerPaths[path]
    if not lower then
        lower = strlower(path)
        lowerPaths[path] = lower
    end
    return lower
end

-- A level range like "1-15", "over 30", "under 30" (or a single level like "45") in the search keeps items whose
-- required level, or profession skill for recipes, is inside it; items with no requirement are left out
-- Returns the words left to match, the level range, and whether "usable" was asked for
local function ParseQuery(query)
    local low, high, usable
    local rest = query:gsub("(%d+)%s*%-%s*(%d+)", function(a, b)
        low, high = tonumber(a), tonumber(b)
        return " "
    end)
    if low and high and low > high then low, high = high, low end

    -- "over 30" and "under 30" (both including 30), alone or together with each other
    rest = rest:gsub("over%s+(%d+)", function(n)
        low, high = tonumber(n), high or math.huge
        return " "
    end)
    rest = rest:gsub("under%s+(%d+)", function(n)
        low, high = low or 1, tonumber(n)
        return " "
    end)

    -- A number on its own is an exact level: "45" is the same as "45-45"
    local words = {}
    for word in rest:gmatch("%S+") do
        local level = not low and word:match("^%d+$") and tonumber(word)
        if level then
            low, high = level, level
        elseif word == "usable" then
            usable = true
        else
            words[#words + 1] = word
        end
    end
    return table.concat(words, " "), low, high, usable
end

-- Required levels come from the item cache; uncached items are requested and fill in later.
-- For recipes the "level" is the profession skill they need, read from the tooltip.
local levels, pendingLevels = {}, {}
local RECIPE_CLASS = 9

local function RecipeSkill(itemID)
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
    for _, line in ipairs(data and data.lines or {}) do
        local skill = line.leftText and line.leftText:match("^Requires .- %((%d+)%)$")
        if skill then return tonumber(skill) end
    end
    return 0
end

local function RequiredLevel(itemID)
    local level = levels[itemID]
    if level == nil then
        if not C_Item.IsItemDataCachedByID(itemID) then
            pendingLevels[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
            return
        end
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
        if classID == RECIPE_CLASS then
            level = RecipeSkill(itemID)
        else
            level = select(5, C_Item.GetItemInfo(itemID)) or 0
        end
        levels[itemID] = level
    end
    return level
end

-- "usable": no red text in the item's tooltip (level, armor type, class, reputation, skill, already known).
-- Uncached items are requested and fill in later, like levels. Cleared when any of that can change.
local usableCache = {}

local function IsRed(color)
    return color and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
end

local function Usable(itemID)
    local known = usableCache[itemID]
    if known ~= nil then return known end
    if not C_Item.IsItemDataCachedByID(itemID) then
        pendingLevels[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
        return false
    end
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
    if not (data and data.lines) then return false end
    known = true
    for _, line in ipairs(data.lines) do
        if (line.leftText and IsRed(line.leftColor)) or (line.rightText and IsRed(line.rightColor)) then
            known = false
            break
        end
    end
    usableCache[itemID] = known
    return known
end

local usableEvents = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "UPDATE_FACTION", "LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED" }) do
    pcall(usableEvents.RegisterEvent, usableEvents, event)
end
usableEvents:SetScript("OnEvent", function() wipe(usableCache) end)

local function LevelOK(itemID, low, high)
    local level = RequiredLevel(itemID)
    if not level then return false end
    return level >= low and level <= high
end

-- Item type, subtype and slot words, so "staff", "mail legs" or "2h sword" find gear
local SLOT_WORDS = {
    INVTYPE_HEAD = "head helm", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder",
    INVTYPE_CLOAK = "back cloak", INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest robe",
    INVTYPE_BODY = "shirt", INVTYPE_TABARD = "tabard", INVTYPE_WRIST = "wrist bracers",
    INVTYPE_HAND = "hands gloves", INVTYPE_WAIST = "waist belt", INVTYPE_LEGS = "legs pants",
    INVTYPE_FEET = "feet boots", INVTYPE_FINGER = "finger ring", INVTYPE_TRINKET = "trinket",
    INVTYPE_WEAPON = "one-hand 1h", INVTYPE_2HWEAPON = "two-hand 2h",
    INVTYPE_WEAPONMAINHAND = "main hand 1h", INVTYPE_WEAPONOFFHAND = "off hand 1h",
    INVTYPE_SHIELD = "shield off hand", INVTYPE_HOLDABLE = "off hand held",
    INVTYPE_RANGED = "ranged", INVTYPE_RANGEDRIGHT = "ranged", INVTYPE_THROWN = "thrown ranged",
}
-- Singular forms that aren't already part of the plural subtype name
local SUBTYPE_WORDS = { staves = "staff" }

-- The item type, subtype and slot as shown in game, with the words each one matches
local function GearParts(itemID)
    local _, itemType, subType, equipLoc = C_Item.GetItemInfoInstant(itemID)
    local sub = strlower(subType or "")
    return {
        { itemType, strlower(itemType or "") },
        { subType ~= itemType and subType, sub .. " " .. (SUBTYPE_WORDS[sub] or "") },
        { _G[equipLoc or ""], SLOT_WORDS[equipLoc] or "" },
    }
end

local gearWords = {}
local function GearWords(itemID)
    local words = gearWords[itemID]
    if not words then
        local _, itemType, subType, equipLoc = C_Item.GetItemInfoInstant(itemID)
        local sub = strlower(subType or "")
        words = strlower(itemType or "") .. " " .. sub .. " " .. (SUBTYPE_WORDS[sub] or "")
            .. " " .. (SLOT_WORDS[equipLoc] or "")
        gearWords[itemID] = words
    end
    return words
end

local EMPTY = {}

-- Every word in the item's name, gear words or this category path
local function PathMatches(name, gear, path, tokens)
    local lower = LowerPath(path)
    for _, t in ipairs(tokens) do
        if not (TokenIn(name, t) or TokenIn(gear, t) or TokenIn(lower, t)) then return false end
    end
    return true
end

-- Every word must match the item's name or gear words, or those plus one of its category paths
local function Matches(itemID, tokens)
    local name, gear = LowerName(itemID), GearWords(itemID)
    local missing = false
    for _, t in ipairs(tokens) do
        if not (TokenIn(name, t) or TokenIn(gear, t)) then
            missing = true
            break
        end
    end
    if not missing then return true end

    for path in pairs(MM.db.itemCats[itemID] or EMPTY) do
        if PathMatches(name, gear, path, tokens) then return true end
    end
    for holiday in pairs(MM:ItemHolidayPaths(itemID) or EMPTY) do
        if PathMatches(name, gear, "Holidays/" .. holiday, tokens) then return true end
    end
    return false
end

-- Why an item is in the search results when its name alone doesn't explain it, for its tooltip.
-- The type or category is shown with the searched letters in white and the rest grey.
local MatchReason
S.tokens = EMPTY

do
local function MarkWord(lower, word, marked)
    local s, e = lower:find(word, 1, true)
    if s then
        for i = s, e do marked[i] = true end
    end
end

local function Highlight(text)
    local lower, marked = strlower(text), {}
    for _, t in ipairs(S.tokens) do
        if t.alias then MarkWord(lower, t.alias, marked) end
        if not t.alias or #t.word > 2 then MarkWord(lower, t.word, marked) end
    end
    local out, i = {}, 1
    while i <= #text do
        local on, j = marked[i] or false, i
        while j < #text and (marked[j + 1] or false) == on do j = j + 1 end
        out[#out + 1] = (on and "|cffffffff" or "|cff8a8a8a") .. text:sub(i, j) .. "|r"
        i = j + 1
    end
    return table.concat(out)
end

function MatchReason(itemID)
    local name, gear = LowerName(itemID), GearWords(itemID)
    local inName, inGear = true, true
    for _, t in ipairs(S.tokens) do
        if not TokenIn(name, t) then
            inName = false
            if not TokenIn(gear, t) then inGear = false end
        end
    end
    if inName then return end
    if inGear then
        local names = {}
        for _, part in ipairs(GearParts(itemID)) do
            for _, t in ipairs(S.tokens) do
                if part[1] and not TokenIn(name, t) and TokenIn(part[2], t) then
                    names[#names + 1] = part[1]
                    break
                end
            end
        end
        return "|cff8a8a8aItem type:|r " .. Highlight(table.concat(names, ", "))
    end
    for path in pairs(MM.db.itemCats[itemID] or EMPTY) do
        if PathMatches(name, gear, path, S.tokens) then return "|cff8a8a8aCategory:|r " .. Highlight(path) end
    end
    for holiday in pairs(MM:ItemHolidayPaths(itemID) or EMPTY) do
        local path = "Holidays/" .. holiday
        if PathMatches(name, gear, path, S.tokens) then return "|cff8a8a8aCategory:|r " .. Highlight(path) end
    end
end
end

local SERVICE_WORDS = {
    ["Services/Flight Masters"] = "flight path fp gryphon wind rider",
    ["Services/Innkeepers"] = "inn hearthstone",
    ["Services/Bankers"] = "bank",
    ["Services/Auctioneers"] = "auction ah",
    ["Services/Battlemasters"] = "battleground bg pvp",
    ["Services/Guild Masters"] = "guild tabard charter",
    ["Services/Stable Masters"] = "stable pet",
    ["Services/Transmogrifiers"] = "transmog tmog xmog",
    ["Services/Mailboxes"] = "mail post",
}

local function ServiceText(npc)
    if not npc.search then
        local parts = { npc.name, npc.title or "" }
        for _, path in ipairs(npc.paths) do
            parts[#parts + 1] = path
            parts[#parts + 1] = SERVICE_WORDS[path] or ""
        end
        npc.search = strlower(table.concat(parts, " "))
    end
    return npc.search
end

local function ServiceMatches(npc, tokens)
    local text = ServiceText(npc)
    for _, t in ipairs(tokens) do
        if not TokenIn(text, t) then return false end
    end
    return true
end

S.LowerName, S.ParseQuery, S.Tokens, S.LevelOK, S.Usable = LowerName, ParseQuery, Tokens, LevelOK, Usable
S.Matches, S.MatchReason, S.ServiceMatches = Matches, MatchReason, ServiceMatches
-- Items whose level or tooltip is still loading
S.pending = pendingLevels

function S.ResetNames()
    wipe(lowerNames)
end
