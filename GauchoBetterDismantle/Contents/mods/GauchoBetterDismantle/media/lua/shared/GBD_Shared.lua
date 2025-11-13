
require "luautils"

GBD_Shared = GBD_Shared or {}

-- Network channel
GBD_Shared.Channel = "GBDDismantle"
GBD_Shared.dismantleCommand = "dismantleCommand"


--- constant values
GBD_Shared.prefixPerk = "gdb_perk:"
GBD_Shared.prefixMaterials = "gdb_material:"
GBD_Shared.prefixBaseItem = "gdb:base_item"
GBD_Shared.playerBuiltFlag = "gbd:player_built"
GBD_Shared.blowtorchDrain = 0.1


-- Random bonus range will be derived dynamically as 1.0 - MaxSkillChance (not below 0)
GBD_Shared.RANDOM_MAX = 0.25

-- Returns current BaseSkillChance, MaxSkillChance, and derived RandomMax
-- Always reads SandboxVars live to avoid requiring Lua reloads when values change.
function GBD_Shared.getScrapConfigValues()
    local sv = SandboxVars
    local modSV =  sv.GauchoBetterDismantle
    local base = modSV and type(modSV.BaseSkillChance) == "number" and modSV.BaseSkillChance or 0.15
    local maxc = modSV and type(modSV.MaxSkillChance) == "number" and modSV.MaxSkillChance or 0.75
    if base < 0 then base = 0 end
    if base > 1 then base = 1 end
    if maxc < 0 then maxc = 0 end
    if maxc > 1 then maxc = 1 end
    local randomMax = math.max(0.0, 1.0 - maxc)
    return base, maxc, randomMax
end

-- Convenience for callers that just need the random max bonus
function GBD_Shared.getRandomMax()
    local _, _, r = GBD_Shared.getScrapConfigValues()
    return r
end

--- @param thump IsoThumpable
--- @param prefix string
--- @return table<number, {key:string, value:number}>
--- Helper: iterate modData entries with a given prefix for a IsoThumpable, returns flat array of {key=fullTypeOrName, value=number}
function GBD_Shared.collectModData(thump, prefix)
    local md = thump:getModData()
    local out = {}
    if not md then return out end
    for k,v in pairs(md) do
        if luautils.stringStarts(k, prefix) then
            -- Always convert value to number; non-numeric values will be nil
            table.insert(out, { key = string.sub(k, #prefix + 1), value = tonumber(v) })
        end
    end
    return out
end

--- Gets scrappable of materials from a thumpable's modData
--- @param thump IsoThumpable
--- @return table<number, {key:string, value:number}>
function GBD_Shared:getScrapMaterials(thump)
    local materials = self.collectModData(thump, GBD_Shared.prefixMaterials)
    local baseItem = self.collectModData(thump, GBD_Shared.prefixBaseItem)
    for _,e in ipairs(baseItem) do table.insert(materials, e) end
    return materials
end


--- Computes base scrap chance
--- @param player IsoPlayer
--- @param thump IsoThumpable
--- @return number
function GBD_Shared:computeSkillScrapChance(player, thump)
    -- Base chance at perk level 0: 0.15
    -- Max chance at perk level 10: 0.75
    -- If multiple perks: compute each perk's chance independently then average.

    local BASE_MIN, BASE_MAX, _ = GBD_Shared.getScrapConfigValues()

    local craftSkills = self.getPerksFromXp(thump)
    local sumChance = 0.0
    local count = 0
    for _, perk in ipairs(craftSkills) do
        if perk then
            local lvl = 0
            if player then
                lvl = player:getPerkLevel(perk) or 0
            end
            if lvl < 0 then lvl = 0 end
            if lvl > 10 then lvl = 10 end
            -- Linear interpolation
            local chancePerk = BASE_MIN + (lvl / 10.0) * (BASE_MAX - BASE_MIN)
            sumChance = sumChance + chancePerk
            count = count + 1
        end
    end

    local averaged = BASE_MIN
    if count > 0 then
        averaged = sumChance / count
    end

    return averaged
end

--- Gets modData perks from a thumpable
---@param thump IsoThumpable
---@return Perk[]
function GBD_Shared.getPerksFromXp(thump)
    local results = {}
    local md = thump:getModData()
    for name,_ in pairs(md) do
        if luautils.stringStarts(name, GBD_Shared.prefixPerk) then
            local perkName = string.sub(name, #GBD_Shared.prefixPerk + 1)
            local perk = Perks[perkName]
            if perk then
                table.insert(results, perk)
            else
                print("[GBD_Shared] Unknown perk: " .. tostring(perkName))
            end
        end
    end
    return results
end

--- Checks if the given thumpable was player-built
--- @param thump IsoThumpable
--- @return boolean
function GBD_Shared.isPlayerBuilt(thump)
    local md = thump:getModData()
    if md then
        local playerBuilt = md[GBD_Shared.playerBuiltFlag]
        if playerBuilt then
            return true
        end
    end
    return false
end
