local _, VA = ...

VA.services = {}

-- Adds Classic vendors and their stock for vendors not visited yet, flagged unverified.
-- Also adds the verified data shipped in VerifiedData.lua.
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
}

local function ServiceIcon(path)
    local rest = path:gsub("^Services/", "")
    local two = rest:match("^[^/]+/[^/]+")
    return SERVICE_ICONS[two] or SERVICE_ICONS[rest:match("^[^/]+")]
end

function VA:ServiceIcon(path)
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
    local seen, shipped = VA.db.verifiedServices[key], VA.shippedServices[key]
    if shipped and (not seen or seen.t < shipped[5]) then
        seen = {
            name = shipped[1], mapID = shipped[2], x = shipped[3], y = shipped[4], t = shipped[5],
            paths = shipped[6], faction = shipped[7], title = shipped[8],
        }
    end
    return seen
end

-- Service NPCs (trainers, flight masters, innkeepers...) live only in memory: VA.services["s" .. npcID].
-- They start unverified with their Classic location; verified ones (yours or shipped) use the verified position.
function VA:RefreshServices()
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
                npc.mapID, npc.x, npc.y, npc.unverified = AreaMap(v[4]), v[5] / 100, v[6] / 100, true
            end
            if npc.mapID then self.services[key] = npc end
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
        if candidate.name == name and (not filter or filter(candidate)) and VA:ZoneOf(candidate.mapID) == zone then
            return k, candidate
        end
    end
end

local function IsClassicSeed(vendor) return vendor.unverified end

-- Talking to an NPC (or opening their trainer, flight map, bank...) confirms where they stand.
-- Service NPCs become verified; Classic vendors whose shop you can't open get their position updated,
-- while their stock stays unverified until you do.
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
    local zone = VA:ZoneOf(mapID)
    local x, y = pos:GetXY()
    local now = time()
    local changed = false

    local key, npc = FindNPC(VA.services, npcID and "s" .. npcID, name, zone)
    if npc then
        -- New NPCs keep what they offer, since the Classic data can't supply it
        local isNew = not VA.knownServices[tonumber(key:sub(2))]
        VA.db.verifiedServices[key] = {
            name = name, mapID = mapID, x = x, y = y, t = now,
            paths = isNew and npc.paths or nil, faction = isNew and npc.faction or nil, title = isNew and npc.title or nil,
        }
        changed = npc.unverified
        npc.name, npc.mapID, npc.x, npc.y, npc.unverified, npc.verifiedAt = name, mapID, x, y, nil, now
    elseif npcID and NewServicePath(unit, event, kind) then
        -- A service NPC the Classic data doesn't have
        local side = UnitFactionGroup(unit)
        VA.db.verifiedServices["s" .. npcID] = {
            name = name, mapID = mapID, x = x, y = y, t = now, paths = { NewServicePath(unit, event, kind) },
            title = UnitTitle(unit),
            faction = side == "Horde" and "H" or side == "Alliance" and "A" or "AH",
        }
        VA:RefreshServices()
        changed = true
    end

    key, npc = FindNPC(VA.db.vendors, npcID, name, zone, IsClassicSeed)
    if npc then
        VA.db.verifiedServices[key] = { name = name, mapID = mapID, x = x, y = y, t = now }
        changed = changed or not npc.located
        npc.mapID, npc.x, npc.y, npc.located = mapID, x, y, now
    end

    if changed then
        VA:OnDataChanged()
        VA:PointToNextUnverified()
    end
end

local verifyEvents = CreateFrame("Frame")
for _, event in ipairs({
    "GOSSIP_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED", "BANKFRAME_OPENED", "AUCTION_HOUSE_SHOW",
    "PET_STABLE_SHOW", "BATTLEFIELDS_SHOW", "GUILD_REGISTRAR_SHOW", "MERCHANT_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "TRANSMOGRIFY_OPEN",
}) do
    -- Not every client has every event
    pcall(verifyEvents.RegisterEvent, verifyEvents, event)
end
verifyEvents:SetScript("OnEvent", function(_, event, kind) ConfirmNPC("npc", event, kind) end)

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

-- Your own vendors set aside while newer shipped data is shown; put back on logout
local setAside = {}

-- Verified vendors shipped with the addon (VerifiedData.lua). Shown when newer than your own visit,
-- without touching your saved data.
local function SeedShipped(db)
    for key, v in pairs(VA.shippedVendors) do
        local name, mapID, x, y, seen, stock, seedID = unpack(v)
        local mine = db.vendors[key]
        local classic = VA.knownVendors[key] or (seedID and VA.knownVendors[seedID])
        local sameFaction = not classic or classic[3]:find(faction, 1, true)
        if sameFaction and not (mine and (mine.lastSeen or 0) >= seen) then
            if mine then
                local offers = {}
                for itemID in pairs(mine.items) do
                    local item = db.items[itemID]
                    if item and item.vendors[key] then
                        offers[itemID] = item.vendors[key]
                        item.vendors[key] = nil
                    end
                end
                setAside[key] = { vendor = mine, offers = offers }
            end
            local vendor = { name = name, mapID = mapID, x = x, y = y, lastSeen = seen, seedID = seedID, items = {}, shipped = true }
            db.vendors[key] = vendor
            for itemID, offer in pairs(stock) do
                local item = db.items[itemID]
                if not item then
                    item = {
                        name = C_Item.GetItemNameByID(itemID) or VA.shippedItemNames[itemID],
                        icon = C_Item.GetItemIconByID(itemID),
                        vendors = {},
                    }
                    db.items[itemID] = item
                end
                item.vendors[key] = { price = offer[1], cost = offer[2], limited = offer[3], pvp = offer[4], shipped = true }
                vendor.items[itemID] = true
                VA:QueueAutoCategorize(itemID)
            end
        end
    end
end

local function Seed()
    local db = VA.db
    byName, areaMaps = ZoneMapsByName(), {}
    faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    SeedShipped(db)

    -- Visited vendors whose in-game ID differed from the Classic one
    local adopted = {}
    for _, vendor in pairs(db.vendors) do
        if vendor.seedID then adopted[vendor.seedID] = true end
    end

    VA:RefreshServices()
    for npcID, v in pairs(VA.knownVendors) do
        if not db.vendors[npcID] and not adopted[npcID] and v[3]:find(faction, 1, true) then
            local mapID = AreaMap(v[4])
            local vendor = { name = v[1], title = v[2], items = {}, unverified = true }
            if mapID then vendor.mapID, vendor.x, vendor.y = mapID, v[5] / 100, v[6] / 100 end
            -- Position confirmed by talking to them, even if their shop wouldn't open
            local spot = ConfirmedSpot(npcID)
            if spot then vendor.mapID, vendor.x, vendor.y, vendor.located = spot.mapID, spot.x, spot.y, spot.t end
            db.vendors[npcID] = vendor

            for _, itemID in ipairs(v[7]) do
                local item = db.items[itemID]
                if not item then
                    item = {
                        name = C_Item.GetItemNameByID(itemID) or VA.knownItemNames[itemID],
                        icon = C_Item.GetItemIconByID(itemID),
                        vendors = {},
                    }
                    db.items[itemID] = item
                end
                item.vendors[npcID] = { unverified = true }
                vendor.items[itemID] = true
                VA:QueueAutoCategorize(itemID)
            end
        end
    end
end

local function Strip()
    local db = VA.db
    for key, vendor in pairs(db.vendors) do
        if vendor.unverified or vendor.shipped then db.vendors[key] = nil end
    end
    for _, item in pairs(db.items) do
        for key, offer in pairs(item.vendors) do
            if offer.unverified or offer.shipped then item.vendors[key] = nil end
        end
    end
    -- Your own vendors come back, unless you visited them again this session
    for key, saved in pairs(setAside) do
        if not db.vendors[key] then
            db.vendors[key] = saved.vendor
            for itemID, offer in pairs(saved.offers) do
                local item = db.items[itemID]
                if item then item.vendors[key] = offer end
            end
        end
    end
    for itemID, item in pairs(db.items) do
        if not next(item.vendors) then db.items[itemID] = nil end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then Seed() else Strip() end
end)