if isServer() then return end


--- Gathers all thumpable objects from the given worldobjects list that are player-built
--- @param worldobjects IsoObject[]
--- @return IsoThumpable[]
local function gatherThumpables(worldobjects)
    local list = {}
    local seen = {} -- hash set
    for _, o in ipairs(worldobjects) do
        local md = o:getModData()
        if not seen[o] then
            seen[o] = true
            if md[GBD_Shared.playerBuiltFlag] then
                for k,_ in pairs(md) do
                    -- we only care about thumpables that have an associated perk
                    if luautils.stringStarts(k, GBD_Shared.prefixPerk) then
                        table.insert(list, o)
                        break
                    end
                end
            end
        end
    end
    return list
end

--- Strips prefix from scrap material keys
--- @param fullType string | nil
local function formatScrapMaterialFullType(fullType)
    local itemName = nil
    local tmpItem = InventoryItemFactory.CreateItem(fullType)
    if tmpItem then
        itemName = tmpItem:getDisplayName() or itemName
    end
    return itemName
end

local function isBlowTorch(it)
    if it:getFullType() == "Base.BlowTorch" then return true end
    if it:hasTag("BlowTorch") then return true end
    return false
end

--- Checks if an item is valid for dismanteling (not broken, has enough fuel if blowtorch)
--- @param item InventoryItem
--- @return boolean
local function isValidItemForDismanteling(item)
    if item:isBroken() then return false end
    if isBlowTorch(item) then
        ---@cast item DrainableComboItem
        local current = item:getUsedDelta()
        return type(current) == "number" and current >= GBD_Shared.blowtorchDrain
    end
    return true
end

--- Recursively collect items from an inventory or container (works for player inventory and nested containers)
--- @param player IsoPlayer
--- @param tag string
--- @param type string
--- @param filterCallback function
--- @return InventoryItem>
local function getFirstItemsRecursiveByTagOrType(player, tag, type, filterCallback)
    local foundItem = {}

    local function _collectItemsRecursive(container, _tag, _type, _filterCallback, out)
        if not container then return end
        local _items = nil
        _items = container:getItems()
        if not _items then return end

        -- we keep track of last type that failed the check to skip if it has the same name
        -- makes iteration faster for example when player has 100 nails in their inventory
        local lastFalseCheckedType = ""

        for i = 0, _items:size() - 1 do
            local item = _items:get(i)
            local fullType = item:getFullType()
            local isLastFalseChecked = fullType == lastFalseCheckedType 
            if not isLastFalseChecked then
                if item:hasTag(tag) or fullType == type then
                    if filterCallback == nil or filterCallback(item) then
                        table.insert(out, item)
                        return
                    else
                        lastFalseCheckedType = fullType
                    end
                end
            end
            if item:IsInventoryContainer() and item:isEquipped() then
                -- recurse only into inventory containers that are equipped
                _collectItemsRecursive(item, _tag, _type, _filterCallback, out)
            end
        end
    end

    _collectItemsRecursive(player:getInventory(), tag, type, filterCallback, foundItem)
    return foundItem[1]
end


-- Perk -> required tools mapping
local REQUIRED_BY_PERK = {
    [Perks.Woodwork] = {
        { tag = "Saw", fullType = "Base.Saw", label = "saw" },
        { tag = "Hammer", fullType = "Base.Hammer", label = "hammer" }
    },
    [Perks.MetalWelding] = {
        { tag = "BlowTorch", fullType = "Base.BlowTorch", label = "blowtorch" },
        { tag = "WeldingMask", fullType = "Base.WeldingMask", label = "welding mask" },
    },
    [Perks.Electricity] = {
        { fullType = "Base.Screwdriver", tag = "Screwdriver", label = "screwdriver"},
    },
    [Perks.Mechanics] = {
        { fullType = "Base.Wrench", tag = "Wrench", label = "wrench" }
    },
}

--- Computes missing required tools for dismanteling the given thumpable
--- @param thump IsoThumpable
--- @param player IsoPlayer
--- @return table
local function computeMissingToolsFor(thump, player)
    local missingTools = {}
    local perks = GBD_Shared.getPerksFromXp(thump)
    for _, perk in ipairs(perks) do
        local req = REQUIRED_BY_PERK[perk]
        for _, spec in ipairs(req) do
            local foundItem = getFirstItemsRecursiveByTagOrType(player, spec.tag, spec.fullType, isValidItemForDismanteling)
            if not foundItem then
                local label = spec.label or "tool"
                if spec.fullType then
                    local tmpItem = InventoryItemFactory.CreateItem(spec.fullType)
                    if tmpItem then
                        label = tmpItem:getDisplayName() or label
                    end
                end
                table.insert(missingTools, label)
            end
        end
    end
    return missingTools
end

--- Tries to find and equip the best matching tool for this thumpable based on REQUIRED_BY_PERK
--- @param player IsoPlayer
--- @param thump IsoThumpable
--- @return InventoryItem | nil | false
local function equipPreferredToolForThump(player, thump)
    if not player or not thump then return nil end
    local inv = player and player:getInventory()
    if not inv then return nil end

    -- Collect required specs from perks (union of all 'any' specs)
    local perks = GBD_Shared.getPerksFromXp(thump)
    local requiredSpecs = {}
    for _, perk in ipairs(perks) do
        local req = REQUIRED_BY_PERK[perk]
        for _, group in ipairs(req) do
            table.insert(requiredSpecs, group)
        end
    end

    -- if no required specs, nothing to equip and return null
    if #requiredSpecs == 0 then return nil end

    -- Priority function using a lookup table for tags and their priorities, lower is better
    local tagPriority = {
        ["blowtorch"] = 1,
        ["screwdriver"] = 2,
        ["hammer"] = 3,
        ["saw"] = 4,
        ["wrench"] = 5,
        ["welding mask"] = 100,
    }

    local function priority(spec)
        local prio = tagPriority[spec.label]
        if prio then return prio end
        return 999
    end

    -- Sort candidates by priority (best first)
    table.sort(requiredSpecs, function(a, b) return priority(a) < priority(b) end)

    -- Find candidate items in inventory that match any spec (include blowtorches initially)
    local requiredTools = {}


    for _, spec in ipairs(requiredSpecs) do
        local foundItem = nil
        foundItem = getFirstItemsRecursiveByTagOrType(player, spec.tag, spec.fullType, isValidItemForDismanteling)
        if foundItem then
            table.insert(requiredTools, foundItem)
        else
            -- if missing any required tool, return false which cancels the dismantle
            return false
        end
    end

    -- Equip the highest-priority required tool found
    local mainTool = requiredTools[1]
    if not mainTool:isEquipped() then
        ISInventoryPaneContextMenu.equipWeapon(mainTool, false, false, player:getPlayerNum())
    end

    -- If there is a wearable item equip it too
    for _, item in ipairs(requiredTools) do
        if instanceof(item, "Clothing") then
            if not item:isEquipped() then
                ISInventoryPaneContextMenu.wearItem(item, player:getPlayerNum())
            end
        end
    end
    return mainTool
end


local function onDismantle(thump)
    local player = getPlayer()
    if not player or not thump then return end
    local time = 200 -- simple fixed duration; could be perk-scaled later
    -- Try to equip a preferred tool for this object's required perks (best-effort)
    local equippedTool = equipPreferredToolForThump(player, thump)
    if equippedTool == false then
        return
    end
    local square = thump:getSquare()
    local adjacent = AdjacentFreeTileFinder.Find(square, player)
    if adjacent ~= nil then
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player, adjacent))
    end
    ISTimedActionQueue.add(GBD_ISDismantleAction:new(player, thump, equippedTool, time))
end


--- Adds a "Dismantle" option to the context menu for the given thumpable
--- @param context ISContextMenu
--- @param thump IsoThumpable
local function addDismantleOption(context, thump)
    if not GBD_Shared.isPlayerBuilt(thump) then return end

    local player = getPlayer()
    local missing = computeMissingToolsFor(thump, player)
    local hasAllTools = (#missing == 0)

    local optName = getText("ContextMenu_GauchoBetterDismantle_Dismantle")
    local opt = context:addOption(optName, thump, onDismantle)

    -- Existing tooltip for scrap preview
    local tt = ISToolTip:new(); tt:initialise(); tt:setVisible(false)
    local scrapMaterials = GBD_Shared:getScrapMaterials(thump)
    if #scrapMaterials > 0 then
        local lines = {}
        for _,e in ipairs(scrapMaterials) do
            local formattedItem = formatScrapMaterialFullType(e.key)
            local numberQty = tonumber(e.value) or 0
            if formattedItem and numberQty > 0 then
                table.insert(lines, string.format("%s x%d", formattedItem, numberQty))
            end
        end
        if #lines > 0 then
            local scrapSkillChance = GBD_Shared:computeSkillScrapChance(player, thump) * 100
            local randomMaxPct = (GBD_Shared.getRandomMax() or 0) * 100
            tt.description = string.format("%s: %.0f%% / %.0f%% <LINE> ", getText("ContextMenu_GauchoBetterDismantle_ScrapChance"), scrapSkillChance, math.min(100, scrapSkillChance + randomMaxPct))
            tt.description = tt.description .. getText("ContextMenu_GauchoBetterDismantle_Materials") .. ": " .. table.concat(lines, " ") .. " <LINE> "
            opt.toolTip = tt
        end
    end

    if not hasAllTools then
        opt.notAvailable = true
        tt.description = tt.description .. string.format("<RGB:1,0,0>%s", getText("ContextMenu_GauchoBetterDismantle_MissingRequired", table.concat(missing, ", "))) .. " <LINE> "
        opt.toolTip = tt
        return
    end
end


--- Event handler for OnPreFillWorldObjectContextMenu
--- @param player number
--- @param context ISContextMenu
--- @param worldobjects IsoObject[]
--- @param test boolean
local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if test then return end
    local list = gatherThumpables(worldobjects)
    for _,thump in ipairs(list) do addDismantleOption(context, thump) end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)


