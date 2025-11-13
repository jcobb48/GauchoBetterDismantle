if not isServer() then return end

local Channel = GBD_Shared.Channel

--- Tags an object as player-built
--- @param obj IsoThumpable
--- @return void
local function tagPlayerBuiltObject(obj)
    print("received construction: ", obj)
    if not obj then return end
    local md = obj:getModData()

    if not md then return end

    md[GBD_Shared.playerBuiltFlag] = true

    for k,v in pairs(md) do
        if luautils.stringStarts(k, "need:") then
            local nk = GBD_Shared.prefixMaterials .. string.sub(k, 6)
            if md[nk] == nil then md[nk] = v end
        elseif luautils.stringStarts(k, "xp:") then
            local nk = GBD_Shared.prefixPerk .. string.sub(k, 4)
            if md[nk] == nil then md[nk] = v end
        end
    end
    obj:transmitModData()
end


Events.OnObjectAdded.Add(tagPlayerBuiltObject)


--- Resolves a server-side IsoThumpable object based on position and sprite name
--- @param x number
--- @param y number
--- @param z number
--- @param spriteName string
--- @return IsoThumpable | nil
local function resolveServerObject(x, y, z, spriteName)
    local sq = getCell():getGridSquare(x, y, z)
    if not sq then return nil end
    local objects = sq:getObjects()
    for i=0,objects:size()-1 do
        local o = objects:get(i)
        if instanceof(o, "IsoThumpable") then
            local spr = o:getSprite()
            if spr and spr:getName() == spriteName then return o end
        end
    end
    return nil
end


--- Drops items of given fullType at square
--- @param square IsoGridSquare
--- @param fullType string
--- @param count number
--- @return void
local function dropItemsAt(square, fullType, count)
    for i=1,count do square:AddWorldInventoryItem(fullType, 0, 0, 0) end
end


--- Drops scrap materials from a dismantled object
--- @param player IsoPlayer
--- @param object IsoThumpable
local function dropScraps(player, object)
    if not object then return end
    local sq = object:getSquare()
    if not sq then return end
    local scrapMaterials = GBD_Shared:getScrapMaterials(object)
    local scrapSkillChance = GBD_Shared:computeSkillScrapChance(player, object)
    local drops = 0
    local MAX_DROPS = 10

    for _,e in ipairs(scrapMaterials) do
        local fullType = e.key
        local qty = tonumber(e.value) or 0

        for i=1,qty do
            if drops >= MAX_DROPS then break end
            local finalChance = scrapSkillChance + ZombRandFloat(0.0, GBD_Shared.getRandomMax())
            if finalChance > 1.0 then finalChance = 1.0 end
            if finalChance < 0.0 then finalChance = 0.0 end
            if ZombRandFloat(0.0,1.0) < finalChance then
                dropItemsAt(sq, fullType, 1)
                drops = drops + 1
            end
        end
        if drops >= MAX_DROPS then break end
    end
end


--- Event handler for OnClientCommand
--- @param module string
--- @param command string
--- @param player IsoPlayer
--- @param args table
local function onClientCommand(module, command, player, args)
    if module ~= Channel or command ~= GBD_Shared.dismantleCommand then return end

    local object = resolveServerObject(args.x, args.y, args.z, args.sprite)
    if not object then return end

    local sq = object:getSquare()
    if not sq then return end

    if not GBD_Shared.isPlayerBuilt(object) then return end

    -- Drop scraps according to perks and object config
    dropScraps(player, object)

    -- Small XP reward: +2 for each relevant xp key present
    local perks = GBD_Shared.getPerksFromXp(object)
    for _,perk in ipairs(perks) do
        player:getXp():AddXP(perk, 2)
    end

    -- Remove object
    sq:transmitRemoveItemFromSquare(object)
end

Events.OnClientCommand.Add(onClientCommand)





