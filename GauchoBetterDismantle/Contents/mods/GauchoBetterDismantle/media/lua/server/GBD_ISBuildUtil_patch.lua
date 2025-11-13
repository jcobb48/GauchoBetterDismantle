require "BuildingObjects/ISBuildUtil"

buildUtil._GBD_setInfo = buildUtil.setInfo

--- Overrides ISBuildUtil.setInfo to mark the built object as player-built
--- @param javaObject IsoThumpable
--- @param ISItem ISBuildingObject
--- @return void
function buildUtil.setInfo(javaObject, ISItem)
    -- Adds missing baseItem field to modData 
    ISItem.modData[GBD_Shared.prefixBaseItem] = ISItem.baseItem
    buildUtil._GBD_setInfo(javaObject, ISItem)
end