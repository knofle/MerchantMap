local _, MM = ...

MM.services = {}

-- Adds the Classic vendors and their stock (VendorData.lua), and the data shipped in VerifiedData.lua.
-- Vendors you've visited keep your prices and position, and get any Classic items you haven't seen.
-- Seeds are rebuilt every login and stripped on logout, so saved data only holds what you have seen.

-- Zone maps by name, for resolving Classic area IDs to uiMapIDs
local function ZoneMapsByName()
    local root = C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID() or 947
    local info = C_Map.GetMapInfo(root)
    while info and info.parentMapID and info.parentMapID ~= 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    local byName = {}
    for _, child in ipairs(info and C_Map.GetMapChildrenInfo(info.mapID, Enum.UIMapType.Zone, true) or {}) do
        byName[child.name] = byName[child.name] or child.mapID
    end
    return byName
end

-- Service NPC icons, by the first part of their category path after "Services/"
local SERVICE_ICONS = {
    ["Trainers/Classes"] = "Interface\\Minimap\\Tracking\\Class",
    ["Trainers/Professions"] = "Interface\\Minimap\\Tracking\\Profession",
    ["Trainers/Pet"] = "Interface\\Minimap\\Tracking\\StableMaster",
    ["Trainers/Riding"] = "Interface\\Minimap\\Tracking\\StableMaster",
    ["Trainers"] = "Interface\\Minimap\\Tracking\\Class",
    ["Flight Masters"] = "Interface\\Minimap\\Tracking\\FlightMaster",
    ["Innkeepers"] = "Interface\\Minimap\\Tracking\\Innkeeper",
    ["Bankers"] = "Interface\\Minimap\\Tracking\\Banker",
    ["Auctioneers"] = "Interface\\Minimap\\Tracking\\Auctioneer",
    ["Stable Masters"] = "Interface\\Minimap\\Tracking\\StableMaster",
    ["Battlemasters"] = "Interface\\Minimap\\Tracking\\BattleMaster",
    ["Guild Masters"] = "Interface\\Minimap\\Tracking\\Banker",
    ["Repair"] = "Interface\\Minimap\\Tracking\\Repair",
    ["Transmogrifiers"] = "Interface\\Minimap\\Tracking\\Transmogrifier",
    ["Mailboxes"] = "Interface\\Minimap\\Tracking\\Mailbox",
}

local function ServiceIcon(path)
    local rest = path:gsub("^Services/", "")
    local two = rest:match("^[^/]+/[^/]+")
    return SERVICE_ICONS[two] or SERVICE_ICONS[rest:match("^[^/]+")]
end

function MM:ServiceIcon(path)
    return ServiceIcon(path)
end

-- Zone lookups and faction, set at login
local byName, areaMaps, faction

-- Classic area ID -> uiMapID, looked up once per area
local function AreaMap(areaID)
    local mapID = areaMaps[areaID]
    if mapID == nil then
        local area = C_Map.GetAreaInfo(areaID)
        mapID = area and byName[area] or false
        areaMaps[areaID] = mapID
    end
    return mapID or nil
end

-- Confirmed NPC positions, from talking to them: yours (db.verifiedServices) or shipped, whichever is newer.
-- Keyed "s" .. npcID for service NPCs and by Classic NPC ID for vendors whose shop you couldn't open.
-- New service NPCs that aren't in the Classic data also carry their paths and faction.
local function ConfirmedSpot(key)
    local seen, shipped = MM.db.verifiedServices[key], MM.shippedServices[key]
    if shipped and (not seen or seen.t < shipped[5]) then
        seen = {
            name = shipped[1], mapID = shipped[2], x = shipped[3], y = shipped[4], t = shipped[5],
            paths = shipped[6], faction = shipped[7], title = shipped[8],
        }
    end
    return seen
end

-- Service NPCs (trainers, flight masters, innkeepers...) live only in memory: MM.services["s" .. npcID].
-- They use their Classic location until confirmed (by you or shipped), then the confirmed position.
function MM:RefreshServices()
    self.services = {}
    for npcID, v in pairs(self.knownServices) do
        local key = "s" .. npcID
        local seen = ConfirmedSpot(key)
        if v[3]:find(faction, 1, true) then
            local npc = {
                name = v[1], title = v[2], paths = v[7], icon = ServiceIcon(v[7][1]), service = true,
            }
            if seen then
                npc.name, npc.mapID, npc.x, npc.y, npc.verifiedAt = seen.name, seen.mapID, seen.x, seen.y, seen.t
            else
                npc.mapID, npc.x, npc.y = AreaMap(v[4]), v[5] / 100, v[6] / 100
            end
            if npc.mapID then self.services[key] = npc end
        end
    end

    -- Mailboxes: objects, so they can't be targeted or confirmed by talking to them.
    -- Keyed by where they stand, which stays the same when the data is rebuilt.
    local mailPaths = { "Services/Mailboxes" }
    for _, box in ipairs(self.knownMailboxes or {}) do
        local mapID = box[1]:find(faction, 1, true) and AreaMap(box[2])
        if mapID then
            self.services["m" .. box[2] .. ":" .. box[3] .. ":" .. box[4]] = {
                name = "Mailbox", paths = mailPaths, icon = ServiceIcon(mailPaths[1]), service = true, object = true,
                mapID = mapID, x = box[3] / 100, y = box[4] / 100, verifiedAt = 0,
            }
        end
    end

    -- New NPCs found in Forever
    local new = {}
    for key in pairs(self.db.verifiedServices) do new[key] = true end
    for key in pairs(self.shippedServices) do new[key] = true end
    for key in pairs(new) do
        local seen = not self.services[key] and ConfirmedSpot(key)
        if seen and seen.paths and (seen.faction or "AH"):find(faction, 1, true) then
            self.services[key] = {
                name = seen.name, title = seen.title, paths = seen.paths, icon = ServiceIcon(seen.paths[1]), service = true,
                mapID = seen.mapID, x = seen.x, y = seen.y, verifiedAt = seen.t, faction = seen.faction,
            }
        end
    end
end

-- What an NPC that isn't in the Classic data offers, from the window they opened
local NEW_SERVICE_EVENTS = {
    BATTLEFIELDS_SHOW = "Services/Battlemasters",
    TAXIMAP_OPENED = "Services/Flight Masters",
    BANKFRAME_OPENED = "Services/Bankers",
    AUCTION_HOUSE_SHOW = "Services/Auctioneers",
    PET_STABLE_SHOW = "Services/Stable Masters",
    GUILD_REGISTRAR_SHOW = "Services/Guild Masters",
    TRANSMOGRIFY_OPEN = "Services/Transmogrifiers",
}
local NEW_SERVICE_TYPES = {
    BattleMaster = "Services/Battlemasters", TaxiNode = "Services/Flight Masters", Banker = "Services/Bankers",
    Auctioneer = "Services/Auctioneers", StableMaster = "Services/Stable Masters", Binder = "Services/Innkeepers",
    Transmogrifier = "Services/Transmogrifiers",
}

-- Or from their title, like <Darkspear Islands Battlemaster> or <Hunter Trainer>
local TITLE_PATHS = {
    { "battlemaster", "Services/Battlemasters" },
    { "flight master", "Services/Flight Masters" }, { "gryphon master", "Services/Flight Masters" },
    { "wind rider master", "Services/Flight Masters" }, { "hippogryph master", "Services/Flight Masters" },
    { "bat handler", "Services/Flight Masters" },
    { "innkeeper", "Services/Innkeepers" }, { "banker", "Services/Bankers" },
    { "auctioneer", "Services/Auctioneers" }, { "stable master", "Services/Stable Masters" },
    { "guild master", "Services/Guild Masters" }, { "weapon master", "Services/Trainers/Weapon Masters" },
    { "pet trainer", "Services/Trainers/Pet" }, { "riding", "Services/Trainers/Riding" },
    { "transmogrifier", "Services/Transmogrifiers" },
}
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local PROFESSIONS = {
    "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing",
    "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring",
}

-- Profession trainers titled by rank, like <Journeyman Enchanter> or <Expert Tailor>
local RANKS = { apprentice = true, journeyman = true, expert = true, artisan = true, master = true, ["grand master"] = true }
local CRAFTERS = {
    alchemist = "Alchemy", blacksmith = "Blacksmithing", armorsmith = "Blacksmithing", weaponsmith = "Blacksmithing",
    enchanter = "Enchanting", engineer = "Engineering", cook = "Cooking", chef = "Cooking",
    fisherman = "Fishing", herbalist = "Herbalism", leatherworker = "Leatherworking", miner = "Mining",
    skinner = "Skinning", tailor = "Tailoring", physician = "First Aid",
}

local function RankedTrainer(lower)
    local rank, crafter = lower:match("^(grand master) (%a+)$")
    if not rank then rank, crafter = lower:match("^(%a+) (%a+)$") end
    local profession = rank and RANKS[rank] and CRAFTERS[crafter]
    return profession and "Services/Trainers/Professions/" .. profession
end

local function UnitTitle(unit)
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit(unit)
    local line = data and data.lines and data.lines[2]
    local text = line and line.leftText
    if not text or (issecretvalue and issecretvalue(text)) or text:find("^Level") then return end
    return text
end

local function TitlePath(unit)
    local title = UnitTitle(unit)
    if not title then return end
    local lower = strlower(title)
    local ranked = RankedTrainer(lower)
    if ranked then return ranked end
    for _, rule in ipairs(TITLE_PATHS) do
        if lower:find(rule[1], 1, true) then return rule[2] end
    end
    if lower:find("trainer", 1, true) then
        for _, class in ipairs(CLASSES) do
            if lower:find(strlower(class), 1, true) then return "Services/Trainers/Classes/" .. class end
        end
        for _, profession in ipairs(PROFESSIONS) do
            if lower:find(strlower(profession), 1, true) then return "Services/Trainers/Professions/" .. profession end
        end
        return "Services/Trainers/Other"
    end
end

local function NewServicePath(unit, event, kind)
    if NEW_SERVICE_EVENTS[event] then return NEW_SERVICE_EVENTS[event] end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and Enum.PlayerInteractionType then
        for name, path in pairs(NEW_SERVICE_TYPES) do
            if Enum.PlayerInteractionType[name] == kind then return path end
        end
    end
    return TitlePath(unit)
end

-- Finds the NPC by key, or by name in the same zone when Forever's ID differs from Classic's
local function FindNPC(list, key, name, zone, filter)
    local npc = key and list[key]
    if npc and (not filter or filter(npc)) then return key, npc end
    for k, candidate in pairs(list) do
        if candidate.name == name and (not filter or filter(candidate)) and MM:ZoneOf(candidate.mapID) == zone then
            return k, candidate
        end
    end
end

local function IsClassicSeed(vendor) return vendor.classic end

-- Talking to an NPC (or opening their trainer, flight map, bank...) confirms where they stand.
-- Service NPCs and Classic vendors whose shop you can't open get their position updated.
local function ConfirmNPC(unit, event, kind)
    local name = UnitName(unit)
    if not name or (issecretvalue and issecretvalue(name)) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end

    local npcID
    local guid = UnitGUID(unit)
    if guid and not (issecretvalue and issecretvalue(guid)) then
        npcID = tonumber((select(6, strsplit("-", guid))))
    end
    local zone = MM:ZoneOf(mapID)
    local x, y = pos:GetXY()
    local now = time()
    local changed = false

    local key, npc = FindNPC(MM.services, npcID and "s" .. npcID, name, zone)
    if npc then
        -- New NPCs keep what they offer, since the Classic data can't supply it
        local isNew = not MM.knownServices[tonumber(key:sub(2))]
        MM.db.verifiedServices[key] = {
            name = name, mapID = mapID, x = x, y = y, t = now,
            paths = isNew and npc.paths or nil, faction = isNew and npc.faction or nil, title = isNew and npc.title or nil,
        }
        changed = true
        npc.name, npc.mapID, npc.x, npc.y, npc.verifiedAt = name, mapID, x, y, now
    elseif npcID and NewServicePath(unit, event, kind) then
        -- A service NPC the Classic data doesn't have
        local side = UnitFactionGroup(unit)
        MM.db.verifiedServices["s" .. npcID] = {
            name = name, mapID = mapID, x = x, y = y, t = now, paths = { NewServicePath(unit, event, kind) },
            title = UnitTitle(unit),
            faction = side == "Horde" and "H" or side == "Alliance" and "A" or "AH",
        }
        MM:RefreshServices()
        changed = true
    end

    key, npc = FindNPC(MM.db.vendors, npcID, name, zone, IsClassicSeed)
    if npc then
        MM.db.verifiedServices[key] = { name = name, mapID = mapID, x = x, y = y, t = now }
        changed = changed or not npc.located
        npc.mapID, npc.x, npc.y, npc.located = mapID, x, y, now
    end

    if changed then
        MM:OnDataChanged()
        MM:PointToNextUnvisited()
    end
end

local confirmEvents = CreateFrame("Frame")
for _, event in ipairs({
    "GOSSIP_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED", "BANKFRAME_OPENED", "AUCTION_HOUSE_SHOW",
    "PET_STABLE_SHOW", "BATTLEFIELDS_SHOW", "GUILD_REGISTRAR_SHOW", "MERCHANT_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "TRANSMOGRIFY_OPEN",
}) do
    -- Not every client has every event
    pcall(confirmEvents.RegisterEvent, confirmEvents, event)
end
confirmEvents:SetScript("OnEvent", function(_, event, kind) ConfirmNPC("npc", event, kind) end)

-- Some NPCs won't talk to you at all (stable masters to non-hunters), so targeting one
-- within about 10 yards confirms them too. Walking up to a target from afar counts.
local watch
local function Near(unit)
    local ok, near = pcall(CheckInteractDistance, unit, 3)
    return ok and near
end

local targetEvents = CreateFrame("Frame")
targetEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
targetEvents:SetScript("OnEvent", function()
    if watch then watch:Cancel() end
    watch = nil
    local guid = UnitGUID("target")
    if not guid or (issecretvalue and issecretvalue(guid)) or UnitIsPlayer("target")
        or UnitCanAttack("player", "target") or InCombatLockdown() then
        return
    end
    if Near("target") then return ConfirmNPC("target") end
    local tries = 0
    watch = C_Timer.NewTicker(0.5, function()
        tries = tries + 1
        local now = not InCombatLockdown() and UnitGUID("target")
        if tries > 60 or not now or (issecretvalue and issecretvalue(now)) or now ~= guid then
            watch:Cancel()
            watch = nil
        elseif Near("target") then
            watch:Cancel()
            watch = nil
            ConfirmNPC("target")
        end
    end)
end)

-- Holidays are only shown when turned on in the options
local function HolidayOff(holiday)
    return holiday ~= nil and not MM.db.holidays[holiday]
end

-- Holiday vendors are keyed by where they stand, npcID .. "@" .. areaID, since some show up
-- in several places (the Darkmoon Faire alternates between Elwynn Forest and Mulgore)
local function SpotKey(npcID, spot) return npcID .. "@" .. spot[2] end

local function KeyHoliday(key)
    if not key then return end
    local npcID, area = tostring(key):match("^(%d+)@(%d+)$")
    local spots = MM.holidaySpots[tonumber(npcID or key)]
    for _, spot in ipairs(spots or {}) do
        if not area or spot[2] == tonumber(area) then return spot[1] end
    end
end

-- Key for a vendor you're at: the holiday spot in your zone, or just the NPC ID
function MM:VendorSpotKey(npcID, mapID)
    local spots = type(npcID) == "number" and self.holidaySpots[npcID]
    if not spots then return npcID end
    local zone = self:ZoneOf(mapID)
    for _, spot in ipairs(spots) do
        if AreaMap(spot[2]) == zone then return SpotKey(npcID, spot) end
    end
    return SpotKey(npcID, spots[1])
end

-- Your own vendors and items taken out for the session (newer shipped data, holidays turned off);
-- put back on logout
local setAside, hiddenItems = {}, {}

local function SetAside(db, key)
    local vendor, offers = db.vendors[key], {}
    for itemID in pairs(vendor.items) do
        local item = db.items[itemID]
        if item and item.vendors[key] then
            offers[itemID] = item.vendors[key]
            item.vendors[key] = nil
        end
    end
    setAside[key] = { vendor = vendor, offers = offers }
    db.vendors[key] = nil
end

local function HideHolidays(db)
    for key, vendor in pairs(db.vendors) do
        if HolidayOff(KeyHoliday(key) or KeyHoliday(vendor.seedID)) then SetAside(db, key) end
    end
    -- Holiday items, and items only those vendors sell
    for itemID, item in pairs(db.items) do
        if HolidayOff(MM.holidayItems[itemID]) or not next(item.vendors) then
            hiddenItems[itemID] = item
            db.items[itemID] = nil
        end
    end
end

-- Vendors shipped with the addon (VerifiedData.lua). Shown when newer than your own visit,
-- without touching your saved data.
local function SeedShipped(db)
    for key, v in pairs(MM.shippedVendors) do
        local name, mapID, x, y, seen, stock, seedID, notSeen = unpack(v)
        local mine = db.vendors[key]
        local base = tonumber(tostring(seedID or key):match("^(%d+)@"))
        local classic = MM.knownVendors[base or seedID or key]
        local sameFaction = not classic or classic[3]:find(faction, 1, true)
        local holidayOff = HolidayOff(KeyHoliday(key) or KeyHoliday(seedID))
        if sameFaction and not holidayOff and not (mine and (mine.lastSeen or 0) >= seen) then
            if mine then SetAside(db, key) end
            local vendor = { name = name, mapID = mapID, x = x, y = y, lastSeen = seen, seedID = seedID, items = {}, shipped = true }
            -- Classic items nobody saw in this shop
            for _, itemID in ipairs(notSeen or {}) do
                vendor.notSeen = vendor.notSeen or {}
                vendor.notSeen[itemID] = true
            end
            db.vendors[key] = vendor
            for itemID, offer in pairs(stock) do
                if not HolidayOff(MM.holidayItems[itemID]) then
                    local item = db.items[itemID]
                    if not item then
                        item = {
                            name = C_Item.GetItemNameByID(itemID) or MM.shippedItemNames[itemID],
                            icon = C_Item.GetItemIconByID(itemID),
                            vendors = {},
                        }
                        db.items[itemID] = item
                    end
                    item.vendors[key] = { price = offer[1], cost = offer[2], limited = offer[3], pvp = offer[4], shipped = true }
                    vendor.items[itemID] = true
                    MM:QueueAutoCategorize(itemID)
                end
            end
            -- Your items the shipped data doesn't have stay listed
            for itemID, offer in pairs(setAside[key] and setAside[key].offers or {}) do
                if not vendor.items[itemID] and db.items[itemID] then
                    db.items[itemID].vendors[key] = offer
                    vendor.items[itemID] = true
                end
            end
        end
    end
end

-- Removes everything seeded, so saved data only holds what you have seen
local function Strip()
    local db = MM.db
    for key, vendor in pairs(db.vendors) do
        if vendor.classic or vendor.shipped then db.vendors[key] = nil end
    end
    for _, item in pairs(db.items) do
        for key, offer in pairs(item.vendors) do
            if offer.classic or offer.shipped then item.vendors[key] = nil end
        end
    end
    -- What was set aside comes back, unless you saw it again this session
    for itemID, item in pairs(hiddenItems) do
        local current = db.items[itemID]
        if current then
            for key, offer in pairs(item.vendors) do current.vendors[key] = current.vendors[key] or offer end
        else
            db.items[itemID] = item
        end
    end
    for key, saved in pairs(setAside) do
        if not db.vendors[key] then
            db.vendors[key] = saved.vendor
            for itemID, offer in pairs(saved.offers) do
                local item = db.items[itemID]
                if item then item.vendors[key] = offer end
            end
        end
    end
    wipe(setAside)
    wipe(hiddenItems)
    -- Your vendors lose the Classic items added to them
    for key, vendor in pairs(db.vendors) do
        for itemID in pairs(vendor.items) do
            local item = db.items[itemID]
            if not (item and item.vendors[key]) then vendor.items[itemID] = nil end
        end
    end
    for itemID, item in pairs(db.items) do
        if not next(item.vendors) then db.items[itemID] = nil end
    end
end

-- Classic items the vendor sells, without a price, for those not recorded already
local function AddClassicItems(db, key, vendor, itemIDs)
    local notSeen = vendor.notSeen or {}
    for _, itemID in ipairs(itemIDs) do
        if not HolidayOff(MM.holidayItems[itemID]) then
            local item = db.items[itemID]
            if not item then
                item = {
                    name = C_Item.GetItemNameByID(itemID) or MM.knownItemNames[itemID],
                    icon = C_Item.GetItemIconByID(itemID),
                    vendors = {},
                }
                db.items[itemID] = item
            end
            if not item.vendors[key] then
                item.vendors[key] = { classic = true, notSeen = notSeen[itemID] }
                vendor.items[itemID] = true
                MM:QueueAutoCategorize(itemID)
            end
        end
    end
end

-- A Classic vendor, or its items added to your record of them
local function SeedClassic(db, recorded, seedKey, v, areaID, x, y)
    local key = recorded[seedKey] or seedKey
    local vendor = db.vendors[key]
    if not vendor then
        vendor = { name = v[1], title = v[2], items = {}, classic = true }
        local mapID = AreaMap(areaID)
        if mapID then vendor.mapID, vendor.x, vendor.y = mapID, x / 100, y / 100 end
        -- Position confirmed by talking to them, even if their shop wouldn't open
        local spot = ConfirmedSpot(seedKey)
        if spot then vendor.mapID, vendor.x, vendor.y, vendor.located = spot.mapID, spot.x, spot.y, spot.t end
        db.vendors[key] = vendor
    end
    -- Your records don't store a title, so they use the Classic one
    vendor.title = v[2] or vendor.title
    AddClassicItems(db, key, vendor, v[7])
end

local function Seed()
    local db = MM.db
    byName, areaMaps = ZoneMapsByName(), {}
    faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    HideHolidays(db)
    SeedShipped(db)

    -- Recorded vendors (yours or shipped), by the Classic ID they stand for
    local recorded = {}
    for key, vendor in pairs(db.vendors) do recorded[vendor.seedID or key] = key end

    MM:RefreshServices()
    for npcID, v in pairs(MM.knownVendors) do
        if v[3]:find(faction, 1, true) then
            local spots = MM.holidaySpots[npcID]
            if spots then
                for _, spot in ipairs(spots) do
                    if not HolidayOff(spot[1]) then
                        SeedClassic(db, recorded, SpotKey(npcID, spot), v, spot[2], spot[3], spot[4])
                    end
                end
            else
                SeedClassic(db, recorded, npcID, v, v[4], v[5], v[6])
            end
        end
    end
    MM:RefreshItemHolidays()
end

-- Which shown holidays each item belongs to, for the Holidays category in the window
function MM:RefreshItemHolidays()
    local db, byItem = self.db, {}
    local function Add(itemID, holiday)
        byItem[itemID] = byItem[itemID] or {}
        byItem[itemID][holiday] = true
    end
    for key, vendor in pairs(db.vendors) do
        local holiday = KeyHoliday(key) or KeyHoliday(vendor.seedID)
        if holiday then
            for itemID in pairs(vendor.items) do
                local item = db.items[itemID]
                if item and item.vendors[key] then Add(itemID, holiday) end
            end
        end
    end
    for itemID, holiday in pairs(self.holidayItems) do
        if db.items[itemID] then Add(itemID, holiday) end
    end
    self.itemHolidays = byItem
end

-- Holidays in the data, in calendar order
MM.HOLIDAYS = {}
for _, holiday in ipairs({
    "Lunar Festival", "Love is in the Air", "Noblegarden", "Children's Week", "Midsummer Fire Festival",
    "Harvest Festival", "Brewfest", "Hallow's End", "Feast of Winter Veil",
    "Darkmoon Faire (Elwynn Forest)", "Darkmoon Faire (Mulgore)",
}) do
    local found = false
    for _, spots in pairs(MM.holidaySpots) do
        for _, spot in ipairs(spots) do found = found or spot[1] == holiday end
    end
    for _, h in pairs(MM.holidayItems) do found = found or h == holiday end
    if found then MM.HOLIDAYS[#MM.HOLIDAYS + 1] = holiday end
end

function MM:IsHolidayShown(holiday)
    return self.db.holidays[holiday] == true
end

-- Turning a holiday on or off seeds everything again
function MM:SetHolidayShown(holiday, on)
    self.db.holidays[holiday] = on or nil
    Strip()
    Seed()
    self:OnDataChanged()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then Seed() else Strip() end
end)
