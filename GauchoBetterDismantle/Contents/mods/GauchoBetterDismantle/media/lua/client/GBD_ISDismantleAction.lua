-- File: media/lua/client/GBD_ISDismantleAction.lua

require "TimedActions/ISBaseTimedAction"

GBD_ISDismantleAction = ISBaseTimedAction:derive("ISBaseTimedAction")

-- Helpers for tool type detection

--- @param item InventoryItem
--- @return boolean
local function isBlowTorch(item)
    if not item then return false end
    if item:hasTag("BlowTorch") then
        return true
    end
    local fullType = item:getFullType()
    if fullType == "Base.BlowTorch" then
        return true
    end
    return false
end

--- @param item InventoryItem
--- @return boolean
local function isHammer(item)
    if not item then return false end
    if item:hasTag("Hammer") then
        return true
    end
    return false
end

--- @param item InventoryItem
--- @return boolean
local function isSaw(item)
    if not item then return false end
    if item:hasTag("Saw") then
        return true
    end
    return false
end

--- @param item InventoryItem
--- @return boolean
local function isScrewdriver(item)
    if not item then return false end
    if item:hasTag("Screwdriver") then
        return true
    end
    return false
end

--- Configures the action sound based on the selected tool
function GBD_ISDismantleAction:setActionSound()
    -- Try to use the tool's configured sounds
    self.soundId = nil
    if self.selectedTool and self.toolIsBlowTorch then
        self.soundId = self.character:playSound("BlowTorch")
    elseif self.selectedTool and self.toolIsHammer then
        self.soundId = self.character:playSound("Hammering")
    elseif self.selectedTool and self.toolIsSaw then
        self.soundId = self.character:playSound("Sawing")
    else -- default to hammer sound
        self.soundId = self.character:playSound("Hammering")
    end
end

--- Sends a dismantle request to the server for the given thumpable
--- @param thump IsoThumpable
local function sendDismantleCommand(thump)
    local spr = thump:getSprite(); if not spr then return end
    sendClientCommand(getPlayer(), GBD_Shared.Channel, GBD_Shared.dismantleCommand, {x = thump:getX(), y = thump:getY(), z = thump:getZ(), sprite = spr:getName()})
end


--------------------------
-- Timed action methods --
--------------------------
function GBD_ISDismantleAction:isValid()
    -- Minimal validation: just ensure references exist.
    local valid = self.character ~= nil and self.object ~= nil and self.square ~= nil

    -- check if blowtorch has fuel (if applicable)
    if valid and self.selectedTool and isBlowTorch(self.selectedTool) and self.selectedTool.IsDrainable and self.selectedTool:IsDrainable() then
        local current = self.selectedTool:getUsedDelta()
        if current < 0.1 then
            valid = false
        end
    end

    return valid
end

function GBD_ISDismantleAction:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function GBD_ISDismantleAction:update()
    self.character:faceThisObject(self.object)

    if self.soundId and not self.character:getEmitter():isPlaying(self.soundId) then
        self:setActionSound()
    end

    self.character:setMetabolicTarget(Metabolics.UsingTools)
end

function GBD_ISDismantleAction:start()
    local hc = getCore():getBadHighlitedColor()
    self.object:setHighlightColor(hc)
    self.object:setHighlighted(true, false)

    local isFloor = self.object.isFloor and self.object:isFloor()

    if self.selectedTool and self.toolIsBlowTorch then
        self:setActionAnim(isFloor and "BlowTorchFloor" or "BlowTorch")
        self:setOverrideHandModels(self.selectedTool, nil)
    elseif self.selectedTool and self.toolIsSaw then
        self:setActionAnim("SawLog")
        self:setOverrideHandModels(self.selectedTool, nil)
    elseif self.selectedTool and self.toolIsScrewdriver then
        self:setActionAnim("disassemble")
        self:setOverrideHandModels("Screwdriver", nil)
    else  -- default to hammer animation
        self:setActionAnim(isFloor and "BuildLow" or "Build")
        self:setOverrideHandModels(self.selectedTool, nil)
    end

    self:setActionSound()
end

function GBD_ISDismantleAction:stop()
    self.object:setHighlighted(false)
    if self.soundId and self.soundId ~= 0 then
        self.character:stopOrTriggerSound(self.soundId)
    end
    ISBaseTimedAction.stop(self)
end

function GBD_ISDismantleAction:perform()
    self.object:setHighlighted(false)
    if self.soundId and self.soundId ~= 0 then
        self.character:stopOrTriggerSound(self.soundId)
    end

    -- consume blowtorch fuel: GBD_Shared.blowtorchDrain per dismantle, client-side (vanilla-style)
    if self.selectedTool and isBlowTorch(self.selectedTool) and self.selectedTool.IsDrainable and self.selectedTool:IsDrainable() then
        local ok, current = self.selectedTool:getUsedDelta()
        if ok and type(current) == "number" then
            local delta = GBD_Shared.blowtorchDrain
            local newDelta = math.min(1, current + delta)
            pcall(function() self.selectedTool:setUsedDelta(newDelta) end)
        end
    end

    -- send remove the thumpable command
    local sq = self.square or (self.object and self.object:getSquare())
    if sq and self.object then
        -- transmit first for MP, then remove local
        sendDismantleCommand(self.object)

    end

    ISBaseTimedAction.perform(self)
end



function GBD_ISDismantleAction:new(character, thumpable, equippedTool, time)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    local tool = character:getPrimaryHandItem()

    o.character = character
    o.object = thumpable
    o.square = thumpable and thumpable:getSquare() or nil
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = time or 200
    o.soundId = nil
    o.selectedTool = equippedTool or tool

    o.toolIsBlowTorch = isBlowTorch(o.selectedTool)
    o.toolIsSaw = isSaw(o.selectedTool)
    o.toolIsHammer = isHammer(o.selectedTool)
    o.toolIsScrewdriver = isScrewdriver(o.selectedTool)

    return o
end
