-- Builds VendorData.lua (the Classic vendors and service NPCs) from QuestieDB's Forever database.
-- QuestieDB keeps its data in the metadata lines of QuestieDB_Forever.toc, with its corrections already applied.
--
-- Usage (from the addon folder):
--   lua Tools/BuildVendorData.lua VendorData.lua "<WoW>/Interface/AddOns/QuestieDB/QuestieDB_Forever.toc"

local outPath, tocPath = arg[1], arg[2]
if not (outPath and tocPath) then
    print("Usage: lua BuildVendorData.lua <VendorData.lua> <QuestieDB_Forever.toc>")
    os.exit(1)
end

-- NPC fields and flags, as QuestieDB numbers them
local NAME, ZONE, FRIENDLY, TITLE, FLAGS, SPAWNS = 1, 9, 13, 14, 15, 7
local ITEM_NAME, ITEM_VENDORS = 1, 14
local VENDOR, TRAINER, INNKEEPER, REPAIR = 4, 16, 128, 16384

-- Service flags and their categories, in the order they're listed
local SERVICE_FLAGS = {
    { 8, "Services/Flight Masters" }, { 128, "Services/Innkeepers" }, { 256, "Services/Bankers" },
    { 4096, "Services/Auctioneers" }, { 8192, "Services/Stable Masters" }, { 2048, "Services/Battlemasters" },
    { 512, "Services/Guild Masters" }, { 1024, "Services/Guild Masters" }, { 16384, "Services/Repair" },
}

-- Trainer categories from words in their title, first match wins
local TRAINER_WORDS = {
    { "weapon master", "Weapon Masters" }, { "pet trainer", "Pet" },
    { "riding", "Riding" }, { "pilot", "Riding" },
    { "warrior", "Classes/Warrior" }, { "paladin", "Classes/Paladin" }, { "hunter", "Classes/Hunter" },
    { "rogue", "Classes/Rogue" }, { "priest", "Classes/Priest" }, { "shaman", "Classes/Shaman" },
    { "mage", "Classes/Mage" }, { "portal", "Classes/Mage" }, { "warlock", "Classes/Warlock" },
    { "druid", "Classes/Druid" },
    { "alchemy", "Professions/Alchemy" }, { "alchemist", "Professions/Alchemy" },
    { "blacksmithing", "Professions/Blacksmithing" }, { "blacksmith", "Professions/Blacksmithing" },
    { "armorsmith", "Professions/Blacksmithing" }, { "weaponsmith", "Professions/Blacksmithing" },
    { "armor crafter", "Professions/Blacksmithing" }, { "weapon crafter", "Professions/Blacksmithing" },
    { "cooking", "Professions/Cooking" }, { "cook", "Professions/Cooking" }, { "chef", "Professions/Cooking" },
    { "butcher", "Professions/Cooking" },
    { "enchanting", "Professions/Enchanting" }, { "enchanter", "Professions/Enchanting" },
    { "engineering", "Professions/Engineering" }, { "engineer", "Professions/Engineering" },
    { "first aid", "Professions/First Aid" }, { "physician", "Professions/First Aid" },
    { "surgeon", "Professions/First Aid" },
    { "fishing", "Professions/Fishing" }, { "fisherman", "Professions/Fishing" },
    { "herbalism", "Professions/Herbalism" }, { "herbalist", "Professions/Herbalism" },
    { "leatherworking", "Professions/Leatherworking" }, { "leatherworker", "Professions/Leatherworking" },
    { "leathercrafter", "Professions/Leatherworking" },
    { "mining", "Professions/Mining" }, { "miner", "Professions/Mining" },
    { "skinning", "Professions/Skinning" }, { "skinner", "Professions/Skinning" },
    { "tailoring", "Professions/Tailoring" }, { "tailor", "Professions/Tailoring" },
}

-- Holiday vendors, by words in their name or title, and the ones without any
local HOLIDAY_WORDS = {
    { "smokywood pastures", "Feast of Winter Veil" }, { "darkmoon faire", "Darkmoon Faire" },
    { "hallow's end", "Hallow's End" }, { "lunar festival", "Lunar Festival" },
    { "love is in the air", "Love is in the Air" }, { "noblegarden", "Noblegarden" },
    { "children's week", "Children's Week" }, { "midsummer", "Midsummer Fire Festival" },
    { "harvest festival", "Harvest Festival" }, { "brewfest", "Brewfest" },
}
local HOLIDAY_NPCS = { [14860] = "Darkmoon Faire" } -- Flik
-- The Darkmoon Faire alternates between these, with a toggle for each
local DARKMOON_ZONES = { [12] = "Elwynn Forest", [215] = "Mulgore" }
-- Holiday items sold by everyday vendors. Vendors selling only holiday items count as holiday vendors.
local HOLIDAY_ITEMS = {
    [21815] = "Love is in the Air", [21829] = "Love is in the Air", [21833] = "Love is in the Air",
    [23160] = "Children's Week", [23161] = "Children's Week",
}

local function HasFlag(flags, flag)
    return flags and math.floor(flags / flag) % 2 == 1
end

------------------------------------------------------------------------------------------------
-- Reading the TOC: "## X-Npc-66-S: <base64>", with long values split as "~N~" over "-1" to "-N"

local raw, version = {}, "?"
local file = assert(io.open(tocPath, "r"))
for line in file:lines() do
    local key, value = line:match("^## (X%-[^:]+): ([^\r]*)")
    if key then
        raw[key] = value
    else
        version = line:match("^## Version: ([^\r]*)") or version
    end
end
file:close()

local B64 = {}
local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
for i = 1, 64 do B64[letters:byte(i)] = i - 1 end

-- Base64 to a list of bytes
local function Bytes(text)
    local bytes, n, bits, count = {}, 0, 0, 0
    for i = 1, #text do
        local v = B64[text:byte(i)]
        if v then
            bits, count = bits * 64 + v, count + 6
            if count >= 8 then
                count = count - 8
                local p = 2 ^ count
                n = n + 1
                bytes[n] = math.floor(bits / p)
                bits = bits % p
            end
        end
    end
    return bytes
end

-- Values are CBOR: maps, arrays, integers, strings and floats
local function Float(b, pos, size, expBits)
    local value = 0
    for i = pos, pos + size - 1 do value = value * 256 + b[i] end
    local mantBits = size * 8 - 1 - expBits
    local sign = value >= 2 ^ (size * 8 - 1) and -1 or 1
    value = value % 2 ^ (size * 8 - 1)
    local exp, mant = math.floor(value / 2 ^ mantBits), value % 2 ^ mantBits
    local bias = 2 ^ (expBits - 1) - 1
    if exp == 0 then return sign * mant * 2 ^ (1 - bias - mantBits) end
    return sign * (1 + mant / 2 ^ mantBits) * 2 ^ (exp - bias)
end

local Read
function Read(b, pos)
    local head = b[pos]
    local major, info = math.floor(head / 32), head % 32
    pos = pos + 1
    if major == 7 then
        if info == 25 then return Float(b, pos, 2, 5), pos + 2 end
        if info == 26 then return Float(b, pos, 4, 8), pos + 4 end
        if info == 27 then return Float(b, pos, 8, 11), pos + 8 end
        if info == 20 then return false, pos end
        if info == 21 then return true, pos end
        return nil, pos
    end
    local n = info
    if info >= 24 then
        local size = ({ 1, 2, 4, 8 })[info - 23]
        n = 0
        for i = pos, pos + size - 1 do n = n * 256 + b[i] end
        pos = pos + size
    end
    if major == 0 then return n, pos end
    if major == 1 then return -1 - n, pos end
    if major == 2 or major == 3 then
        local chars = {}
        for i = 1, n do chars[i] = string.char(b[pos + i - 1]) end
        return table.concat(chars), pos + n
    end
    local t = {}
    if major == 4 then
        for i = 1, n do t[i], pos = Read(b, pos) end
    else
        for _ = 1, n do
            local k
            k, pos = Read(b, pos)
            t[k], pos = Read(b, pos)
        end
    end
    return t, pos
end

local function Value(key)
    local text = raw[key]
    if not text then return end
    local parts = tonumber(text:match("^~(%d+)~$"))
    if parts then
        local chunks = {}
        for i = 1, parts do chunks[i] = raw[key .. "-" .. i] end
        text = table.concat(chunks)
    end
    return (Read(Bytes(text), 1))
end

------------------------------------------------------------------------------------------------
-- Picking out vendors and service NPCs

-- QuestieDB's Forever data also carries Season of Discovery NPCs and items, which aren't in Forever.
-- They all use IDs from this range: older ones are Classic, newer ones were added for Forever.
local function SeasonOfDiscovery(id)
    return id >= 200000 and id < 240000
end

local npcs, sold = {}, {}
for key in pairs(raw) do
    local npcID = tonumber(key:match("^X%-Npc%-(%d+)%-S$"))
    if npcID and not SeasonOfDiscovery(npcID) then npcs[npcID] = Value(key) end
    local itemID = tonumber(key:match("^X%-Item%-(%d+)%-" .. ITEM_VENDORS .. "$"))
    if itemID and not SeasonOfDiscovery(itemID) then
        for _, npcID in ipairs(Value(key) or {}) do
            sold[npcID] = sold[npcID] or {}
            table.insert(sold[npcID], itemID)
        end
    end
end

-- First spawn, in the NPC's own zone when it has one there
local function Spawn(npcID, npc)
    local spawns = Value("X-Npc-" .. npcID .. "-" .. SPAWNS)
    if type(spawns) ~= "table" then return end
    local zones = {}
    for zone in pairs(spawns) do table.insert(zones, zone) end
    table.sort(zones)
    if spawns[npc[ZONE]] then table.insert(zones, 1, npc[ZONE]) end
    for _, zone in ipairs(zones) do
        for _, point in ipairs(spawns[zone]) do
            if point[1] and point[1] >= 0 and point[2] >= 0 then return zone, point[1], point[2] end
        end
    end
end

local function TrainerPath(title)
    local lower = (title or ""):lower()
    for _, rule in ipairs(TRAINER_WORDS) do
        if lower:find("%f[%a]" .. rule[1] .. "%f[%A]") then return "Services/Trainers/" .. rule[2] end
    end
    return "Services/Trainers/Other"
end

local function ServicePaths(flags)
    local paths, seen = {}, {}
    for _, rule in ipairs(SERVICE_FLAGS) do
        if HasFlag(flags, rule[1]) and not seen[rule[2]] then
            seen[rule[2]] = true
            table.insert(paths, rule[2])
        end
    end
    return paths
end

-- Vendors are flagged as such, or sell something and aren't flagged as anything that rules it out
local function IsVendor(npcID, flags)
    if HasFlag(flags, VENDOR) then return true end
    return sold[npcID] and (not flags or HasFlag(flags, INNKEEPER) or HasFlag(flags, REPAIR))
end

local vendors, services, itemNames = {}, {}, {}
for npcID, npc in pairs(npcs) do
    local flags, friendly = npc[FLAGS], npc[FRIENDLY]
    local paths = ServicePaths(flags)
    if HasFlag(flags, TRAINER) then table.insert(paths, 1, TrainerPath(npc[TITLE])) end
    local vendor = IsVendor(npcID, flags)
    if (vendor or #paths > 0) and (friendly == "A" or friendly == "H" or friendly == "AH") then
        local zone, x, y = Spawn(npcID, npc)
        if zone then
            local entry = { npc[NAME], npc[TITLE], friendly, zone, x, y }
            if vendor then
                local items = sold[npcID] or {}
                table.sort(items)
                for _, itemID in ipairs(items) do itemNames[itemID] = true end
                vendors[npcID] = { entry, items }
            end
            if #paths > 0 then services[npcID] = { entry, paths } end
        end
    end
end

local function Holiday(npcID, npc, items)
    if HOLIDAY_NPCS[npcID] then return HOLIDAY_NPCS[npcID] end
    local text = ((npc[NAME] or "") .. " " .. (npc[TITLE] or "")):lower()
    for _, rule in ipairs(HOLIDAY_WORDS) do
        if text:find(rule[1], 1, true) then return rule[2] end
    end
    local holiday = items and items[1] and HOLIDAY_ITEMS[items[1]]
    for _, itemID in ipairs(items or {}) do
        if HOLIDAY_ITEMS[itemID] ~= holiday then return end
    end
    return holiday
end

-- Holiday vendors in every zone they show up in, with the first spot in each
local holidaySpots = {}
for npcID in pairs(vendors) do
    local holiday = Holiday(npcID, npcs[npcID], vendors[npcID][2])
    if holiday then
        local spawns = Value("X-Npc-" .. npcID .. "-" .. SPAWNS)
        local spots = {}
        for zone, points in pairs(spawns) do
            local point = points[1]
            if point and point[1] >= 0 and point[2] >= 0 then
                local name = holiday
                if holiday == "Darkmoon Faire" and DARKMOON_ZONES[zone] then
                    name = holiday .. " (" .. DARKMOON_ZONES[zone] .. ")"
                end
                table.insert(spots, { name, zone, point[1], point[2] })
            end
        end
        table.sort(spots, function(a, b) return a[2] < b[2] end)
        holidaySpots[npcID] = spots
    end
end

-- Mailboxes, from QuestieDB's objects. The same box often shows up several times a step apart,
-- so spots closer than about a percent of the map count once.
local OBJ_NAME, OBJ_SPAWNS, OBJ_FACTION = 1, 4, 6
local MAILBOX_FACTIONS = { [12] = "A", [55] = "A", [80] = "A", [29] = "H", [68] = "H", [104] = "H" }
local mailboxes = {}
do
    local found = {}
    for key in pairs(raw) do
        local objectID = key:match("^X%-Object%-(%d+)%-S$")
        local object = objectID and Value(key)
        if type(object) == "table" and object[OBJ_NAME] == "Mailbox" then
            local spawns = Value("X-Object-" .. objectID .. "-" .. OBJ_SPAWNS)
            local friendly = MAILBOX_FACTIONS[object[OBJ_FACTION]] or "AH"
            for zone, points in pairs(type(spawns) == "table" and spawns or {}) do
                for _, point in ipairs(points) do
                    if point[1] >= 0 and point[2] >= 0 then
                        table.insert(found, { friendly, zone, point[1], point[2] })
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b)
        if a[2] ~= b[2] then return a[2] < b[2] end
        if a[3] ~= b[3] then return a[3] < b[3] end
        return a[4] < b[4]
    end)
    for _, box in ipairs(found) do
        local duplicate = false
        for _, kept in ipairs(mailboxes) do
            local dx, dy = kept[3] - box[3], kept[4] - box[4]
            if kept[2] == box[2] and dx * dx + dy * dy <= 1 then duplicate = true break end
        end
        if not duplicate then table.insert(mailboxes, box) end
    end
end

for itemID in pairs(itemNames) do
    local item = Value("X-Item-" .. itemID .. "-S")
    itemNames[itemID] = item and item[ITEM_NAME] or nil
end

------------------------------------------------------------------------------------------------
-- Writing VendorData.lua

local function Number(n)
    return (string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", ""))
end

local function Text(s)
    return s and string.format("%q", s) or "nil"
end

local function Sorted(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

local function Line(npcID, entry, list)
    local name, title, friendly, zone, x, y = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
    return string.format("[%d]={%s,%s,%q,%d,%s,%s,{%s}},", npcID, Text(name), Text(title), friendly, zone,
        Number(x), Number(y), list)
end

local out = {
    "local _, MM = ...",
    "",
    "-- Classic NPC and item data, derived from Questie's database (https://github.com/Questie/Questie),",
    "-- which is licensed under the GNU General Public License v3.",
    "-- Modified for Merchant Map on " .. os.date("%Y-%m-%d") .. " from QuestieDB " .. version
        .. " (Forever): vendors and service NPCs extracted and converted to this format.",
    "-- Merchant Map's own recorded data (from visiting or talking to NPCs) takes over their position and adds prices",
    "-- and any items missing here.",
    "-- Vendors: [npcID] = { name, title, friendlyTo (\"A\", \"H\", \"AH\"), areaID, x, y, { itemIDs sold } }  (x/y in 0-100)",
    "MM.knownVendors = {",
}
local counts = { vendors = 0, services = 0, items = 0 }
for _, npcID in ipairs(Sorted(vendors)) do
    local v = vendors[npcID]
    table.insert(out, Line(npcID, v[1], table.concat(v[2], ",")))
    counts.vendors = counts.vendors + 1
end
table.insert(out, "}")
table.insert(out, "")
table.insert(out, "-- Names for the items above, used until the client has the item cached")
table.insert(out, "MM.knownItemNames = {")
for _, itemID in ipairs(Sorted(itemNames)) do
    table.insert(out, string.format("[%d]=%s,", itemID, Text(itemNames[itemID])))
    counts.items = counts.items + 1
end
table.insert(out, "}")
table.insert(out, "")
table.insert(out, "-- Service NPCs: trainers, flight masters, innkeepers, bankers, auctioneers, stable masters,")
table.insert(out, "-- battlemasters, guild masters and repairers.")
table.insert(out, "-- [npcID] = { name, title, friendlyTo, areaID, x, y, { category paths } }")
table.insert(out, "MM.knownServices = {")
for _, npcID in ipairs(Sorted(services)) do
    local s = services[npcID]
    local paths = {}
    for i, path in ipairs(s[2]) do paths[i] = string.format("%q", path) end
    table.insert(out, Line(npcID, s[1], table.concat(paths, ",")))
    counts.services = counts.services + 1
end
table.insert(out, "}")
table.insert(out, "")

table.insert(out, "-- Mailboxes: { friendlyTo, areaID, x, y }")
table.insert(out, "MM.knownMailboxes = {")
for _, box in ipairs(mailboxes) do
    table.insert(out, string.format("{%q,%d,%s,%s},", box[1], box[2], Number(box[3]), Number(box[4])))
end
table.insert(out, "}")
table.insert(out, "")
table.insert(out, "-- Holiday vendors and items, shown only for the holidays turned on in the options")
table.insert(out, "-- [npcID] = { { holiday, areaID, x, y }, ... }, one for each zone they show up in")
table.insert(out, "MM.holidaySpots = {")
for _, npcID in ipairs(Sorted(holidaySpots)) do
    local spots = {}
    for i, spot in ipairs(holidaySpots[npcID]) do
        spots[i] = string.format("{%q,%d,%s,%s}", spot[1], spot[2], Number(spot[3]), Number(spot[4]))
    end
    table.insert(out, string.format("[%d]={%s},", npcID, table.concat(spots, ",")))
end
table.insert(out, "}")
table.insert(out, "MM.holidayItems = {")
for _, itemID in ipairs(Sorted(HOLIDAY_ITEMS)) do
    table.insert(out, string.format("[%d]=%q,", itemID, HOLIDAY_ITEMS[itemID]))
end
table.insert(out, "}")
table.insert(out, "")

local f = assert(io.open(outPath, "w"))
f:write(table.concat(out, "\n"))
f:close()
print(string.format("Wrote %s from QuestieDB %s: %d vendors, %d items, %d service NPCs, %d mailboxes.",
    outPath, version, counts.vendors, counts.items, counts.services, #mailboxes))
