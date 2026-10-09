local _, MM = ...

MM.ALL, MM.UNCAT = "__all", "__uncat"

local DEFAULTS = {
    "Consumables/Food & Drink",
    "Consumables/Ammo",
    "Professions/Tailoring/Recipes",
    "Professions/Tailoring/Materials",
    "Professions/Leatherworking/Recipes",
    "Professions/Leatherworking/Materials",
}

-- Top-level categories the addon makes (the defaults above and AutoCategories.lua's)
local ADDON_ROOTS = {
    ["Consumables"] = true, ["Class Supplies"] = true, ["Gear"] = true, ["Leveling"] = true, ["Mounts"] = true,
    ["Pets"] = true, ["Professions"] = true, ["PvP"] = true, ["Quest Items"] = true, ["Reputation"] = true,
}

local function IsUnder(path, root)
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

function MM:ParentPath(path)
    return path:match("^(.*)/[^/]+$")
end

function MM:IsCategory(path)
    return path ~= self.ALL and path ~= self.UNCAT
end

-- " Professions//Tailoring " -> "Professions/Tailoring"
function MM:NormalizePath(text)
    local parts = {}
    for part in text:gmatch("[^/]+") do
        part = strtrim(part)
        if part ~= "" then parts[#parts + 1] = part end
    end
    return #parts > 0 and table.concat(parts, "/") or nil
end

-- Moves every path under old to new, or deletes them when new is nil
local function Remap(set, old, new)
    local moved = {}
    for path in pairs(set) do
        if IsUnder(path, old) then moved[#moved + 1] = path end
    end
    for _, path in ipairs(moved) do
        set[path] = nil
        if new then set[new .. path:sub(#old + 1)] = true end
    end
end

function MM:InitCategories()
    local db = self.db
    db.itemCats = db.itemCats or {}
    db.collapsed = db.collapsed or {}
    db.autoDone = db.autoDone or {}

    -- 1.3: categories no longer sit under a "Base" root
    if db.categories and not db.baseRemoved then
        local function Strip(set)
            local out = {}
            for path in pairs(set) do
                if path ~= "Base" then out[(path:gsub("^Base/", ""))] = true end
            end
            return out
        end
        db.categories = Strip(db.categories)
        db.collapsed = Strip(db.collapsed)
        for itemID, set in pairs(db.itemCats) do
            local stripped = Strip(set)
            db.itemCats[itemID] = next(stripped) and stripped or nil
        end
    end
    db.baseRemoved = true

    if not db.categories then
        db.categories = {}
        for _, path in ipairs(DEFAULTS) do self:AddCategory(path) end
    end

    -- Mana food and drink is filed under "Drink" now
    local MANA, DRINK = "Consumables/Food & Drink/Mana", "Consumables/Food & Drink/Drink"
    if db.categories[MANA] then
        Remap(db.categories, MANA, DRINK)
        Remap(db.collapsed, MANA, DRINK)
        for _, set in pairs(db.itemCats) do Remap(set, MANA, DRINK) end
    end

    -- Categories you made, which unlike the addon's can be renamed and deleted.
    -- Before this was tracked, anything outside the addon's own top-level categories counts as yours.
    if not db.userCategories then
        db.userCategories = {}
        for path in pairs(db.categories) do
            if not ADDON_ROOTS[path:match("^[^/]+")] then db.userCategories[path] = true end
        end
    end
end

-- A category made with the New button, along with any parents it needed
function MM:AddUserCategory(text)
    local path = self:NormalizePath(text)
    if not path then return end
    local prefix
    for part in path:gmatch("[^/]+") do
        prefix = prefix and (prefix .. "/" .. part) or part
        if not self.db.categories[prefix] then self.db.userCategories[prefix] = true end
    end
    return self:AddCategory(path)
end

-- Yours, and so is everything under it
function MM:IsUserCategory(path)
    local user = self.db.userCategories
    if not user[path] then return false end
    for other in pairs(self.db.categories) do
        if IsUnder(other, path) and not user[other] then return false end
    end
    return true
end

function MM:AddCategory(text)
    local path = self:NormalizePath(text)
    if not path then return end
    local db = self.db
    local prefix, parent
    for part in path:gmatch("[^/]+") do
        parent, prefix = prefix, prefix and (prefix .. "/" .. part) or part
        if not db.categories[prefix] then
            -- New categories start folded, and so does a parent getting its first child
            if parent and not self:HasChildren(parent) then db.collapsed[parent] = true end
            db.categories[prefix] = true
            if prefix ~= path then db.collapsed[prefix] = true end
        end
    end
    return path
end

function MM:HasChildren(path)
    local prefix = path .. "/"
    for other in pairs(self.db.categories) do
        if other:sub(1, #prefix) == prefix then return true end
    end
    return false
end

function MM:RenameCategory(old, text)
    local new = self:NormalizePath(text)
    if not new or new == old or IsUnder(new, old) then return end
    local db = self.db
    Remap(db.categories, old, new)
    Remap(db.collapsed, old, new)
    Remap(db.userCategories, old, new)
    for _, set in pairs(db.itemCats) do Remap(set, old, new) end
    -- New parents it's moved under are yours too
    self:AddUserCategory(new)
    return new
end

function MM:DeleteCategory(path)
    local db = self.db
    Remap(db.categories, path)
    Remap(db.collapsed, path)
    Remap(db.userCategories, path)
    for itemID, set in pairs(db.itemCats) do
        Remap(set, path)
        if not next(set) then db.itemCats[itemID] = nil end
    end
end

function MM:AssignItem(itemID, path)
    local set = self.db.itemCats[itemID] or {}
    self.db.itemCats[itemID] = set
    set[path] = true
end

-- Removes the item from root and all of its subcategories
function MM:UnassignItem(itemID, root)
    local set = self.db.itemCats[itemID]
    if not set then return end
    Remap(set, root)
    if not next(set) then self.db.itemCats[itemID] = nil end
end

-- Holidays/<holiday> for the holidays turned on that an item belongs to (set by Seed.lua)
local HOLIDAYS = "Holidays"

function MM:IsHolidayPath(path)
    return path == HOLIDAYS or path:sub(1, #HOLIDAYS + 1) == HOLIDAYS .. "/"
end

function MM:HolidayPaths()
    local paths = {}
    for _, holidays in pairs(self.itemHolidays or {}) do
        for holiday in pairs(holidays) do
            paths[HOLIDAYS] = true
            paths[HOLIDAYS .. "/" .. holiday] = true
        end
    end
    return paths
end

function MM:ItemHolidayPaths(itemID)
    return self.itemHolidays and self.itemHolidays[itemID]
end

function MM:ItemInCategory(itemID, root)
    local set = self.db.itemCats[itemID]
    local holidays = self:ItemHolidayPaths(itemID)
    if root == self.ALL then return true end
    if root == self.UNCAT then return not set and not holidays end
    if self:IsHolidayPath(root) then
        return holidays ~= nil and (root == HOLIDAYS or holidays[root:sub(#HOLIDAYS + 2)] == true)
    end
    if not set then return false end
    for path in pairs(set) do
        if IsUnder(path, root) then return true end
    end
    return false
end