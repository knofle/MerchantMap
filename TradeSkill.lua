local _, MM = ...

-- Optional small button beside each reagent in the profession window, for reagents Merchant Map has
-- a vendor for. Clicking it searches the window for that reagent.

local C, W = MM.COLORS, MM.W
local ACCENT = C.accent
local buttons = {} -- reagent slot -> its button; Blizzard reuses slots from a pool
local form

local function OnClick(self)
    local item = MM.db.items[self.itemID]
    local name = item and item.name or C_Item.GetItemNameByID(self.itemID)
    if name then MM:Search(name) end
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Merchant Map", ACCENT[1], ACCENT[2], ACCENT[3])
    GameTooltip:AddLine("Find a vendor for this reagent", 1, 1, 1)
    GameTooltip:Show()
end

-- Dark bronze-edged square like the addon's buttons, with the game's own magnifier in sand
local function CreateButton(slot)
    local b = CreateFrame("Button", nil, slot)
    b:SetSize(16, 16)
    b:SetPoint("RIGHT", slot.Button, "LEFT", -3, 0)
    W.SkinButton(b)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    buttons[slot] = b
    return b
end

-- Basic reagents only: optional and finishing slots offer a choice rather than one item
local function Update()
    for _, b in pairs(buttons) do b:Hide() end
    if not (form and MM.db and MM.db.tradeSkillButtons) then return end
    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, slots in pairs(form.reagentSlots or {}) do
        for _, slot in ipairs(slots) do
            local schematic = slot.GetReagentSlotSchematic and slot:GetReagentSlotSchematic()
            local reagent = schematic and schematic.reagents and schematic.reagents[1]
            local itemID = reagent and reagent.itemID
            local isBasic = itemID and (not (basic and schematic.reagentType) or schematic.reagentType == basic)
            if isBasic and slot.Button and slot:IsShown() and MM.db.items[itemID] then
                local b = buttons[slot] or CreateButton(slot)
                b.itemID = itemID
                b:Show()
            end
        end
    end
end

function MM:RefreshTradeSkillButtons()
    Update()
end

local function Attach()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    form = page and page.SchematicForm
    if form and form.Init then hooksecurefunc(form, "Init", Update) end
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", Attach)
end
