-- Check MWSE Build --
if (mwse.buildDate == nil) or (mwse.buildDate < 20200111) then
    local function warning()
        tes3.messageBox(
            "[Enhanced Telekinesis ERROR] Your MWSE is out of date!"
            .. " You will need to update to a more recent version to use this mod."
        )
    end
    event.register("initialized", warning)
    event.register("loaded", warning)
    return
end
----------------------------

-- Declare Event Functions --
local onSimulate = nil
local onActivate = nil
----------------------------

-- Declare Data Structures --
local VisualController = {
  new = function(self, o)
    o = o or {}   -- create object if user does not provide one
    setmetatable(o, self)
    self.__index = self
    return o
  end,

  vfxName = nil,
  vfxPath = nil,
  vfx = nil,

  load = function(self)
    self.vfx = tes3.loadMesh(self.vfxPath)
  end,
  attach = function (self, ref)
    if (ref.sceneNode) then
      local node = self.vfx:clone()
      local boundingBox = ref.object.boundingBox
        if (boundingBox) then
          node.translation = (boundingBox.min + boundingBox.max) * 0.5
        end

      ref.sceneNode:attachChild(node, true)
      ref.sceneNode:update()
      ref.sceneNode:updateNodeEffects()
    end
  end,
  detach = function(self, ref)
    if (ref.sceneNode) then
      local node = ref.sceneNode:getObjectByName(self.vfxName)
      if (node ~= nil) then
          node.parent:detachChild(node)
      end
      ref.sceneNode:update()
      ref.sceneNode:updateNodeEffects()
    end
  end
}
-------------------------

-- Initialize Controllers --
local visualController = VisualController:new({ 
  vfxName = "OJ_ET_Telekinesis",
  vfxPath = "OJ\\ET\\telekinesis1.nif"
})

local target = nil
local targetOriginalPosition = nil
eventController = {
    active = false,
    register = function(self)
      self:unregister()

      self.active = true

      event.register("simulate", onSimulate)
      event.register("activate", onActivate, {priority = 1e+06})
    end,
    unregister = function(self)
      event.unregister("activate", onActivate, {priority = 1e+06})
      self.active = false
    end
}

timerController = {
    callback = function()
      -- If state is inactive, exit.
      if (tes3.isAffectedBy({reference = tes3.player, effect = tes3.effect.telekinesis}) == false) then
        timerController:cancel()
        return
      end
  

    end,
    active = false,
    timer = nil,
  
    start = function(self)
      self.active = true
      self.timer = timer.start({
        iterations = -1,
        duration = 0.5,
        callback = self.callback
      })

      eventController:register()
    end,
    cancel = function(self)
      self.active = false
      self.timer = self.timer:cancel()
      self.timer = nil

      eventController:unregister()
    end,
  }
----------------------------

-- Declare Event Functions --
local function getPlayerChestPosition()
  local eyePosition = tes3.getPlayerEyePosition()
  local heightDist = eyePosition:distance(tes3.player.position)
  local chestDist = heightDist * .3
  return eyePosition:interpolate(tes3.player.position, chestDist)
end

local interpolationDistance = 3
onSimulate = function()
  if (target) then
    local midpoint = getPlayerChestPosition()

    -- If target is not within reach,
    if (target.position:distance(midpoint) > 128) then
      -- Apply movement.
      target.position = target.position:interpolate(midpoint, interpolationDistance)  

      if (interpolationDistance < 100) then
        interpolationDistance = interpolationDistance * 1.03
      end
    else
      interpolationDistance = 3

      if (target.object.objectType == tes3.objectType.book) then
        local itemData = target.itemData
        tes3.addItem({
          reference = tes3.player,
          item = target.object,
          itemData = itemData,
          count = itemData and itemData.count or 1
        })
      
        target.itemData = nil
        target:disable()
        mwscript.setDelete({ reference = target, delete = true })
      else
        tes3.player:activate(target)
      end

      target = nil

      if (eventController.active == false) then
        event.unregister("simulate", onSimulate, {priority = 1e+06})
      end
    end 
  end
end

local types = {
  [tes3.objectType.alchemy] = true,
  [tes3.objectType.ammunition] = true,
  [tes3.objectType.apparatus] = true,
  [tes3.objectType.armor] = true,
  [tes3.objectType.book] = true,
  [tes3.objectType.clothing] = true,
  [tes3.objectType.ingredient] = true,
  [tes3.objectType.light] = true,
  [tes3.objectType.lockpick] = true,
  [tes3.objectType.miscItem] = true,
  [tes3.objectType.probe] = true,
  [tes3.objectType.repairItem] = true,
  [tes3.objectType.weapon] = true,
}
onActivate = function(e)
  if (types[e.target.object.objectType] == nil and target == nil) then
    return
  end

  if (target and target == e.target) then
    return
  end

  if (target and target ~= e.target) then
    return false
  end
  
  -- Block telekinesis on owned books.
  if ( e.target.object.objectType == tes3.objectType.book) then
    if (not tes3.hasOwnershipAccess({ target = e.target })) then
      return
    end
  end
  
  local midpoint = getPlayerChestPosition()
  if (e.target.position:distance(midpoint) > 128) then  
    target = e.target
    targetOriginalPosition = target.position
    visualController:attach(target)
 
    return false
  end 
end
----------------------------

-- Register Event Handlers --
local function onObjectInvalidated(e)
  if (target and e.object == target) then
    target = nil
    targetOriginalPosition = nil
  end
end
event.register("objectInvalidated", onObjectInvalidated) 

local function onCellChanged()
  if (target) then
    target.position = targetOriginalPosition
  end
end
event.register("cellChanged", onCellChanged)

local function onSpellResist(e)
    for _, effect in pairs(e.sourceInstance.source.effects) do
        if (effect.id == tes3.effect.telekinesis) then
            timerController:start()
            return
        end
    end
end
event.register("spellResist", onSpellResist)
----------------------------

-- Register Mod Initialization Event Handler --
local function onLoaded(e)
  -- Initialize any active effects. Will auto-stop timer if no effect is active.
  if (timerController.active == true) then
    timerController:cancel()
  end
  timerController.active = false

  visualController:load()

  print("[Enhanced Telekinesis: INFO] Initialized.")
end
event.register("loaded", onLoaded)
-------------------------

