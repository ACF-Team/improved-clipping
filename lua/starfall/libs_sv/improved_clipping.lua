local checkluatype = SF.CheckLuaType
local checkpermission = SF.Permissions.check
local registerprivilege = SF.Permissions.registerPrivilege
local IsValid = FindMetaTable("Entity").IsValid

registerprivilege("entities.clip", "Clip", "Allows the user to add physical clips to entities", { entities = {} })

-- --------------------------------------
-- Instance

return function(instance)

local ents_methods, ent_meta, ewrap, eunwrap = instance.Types.Entity.Methods, instance.Types.Entity, instance.Types.Entity.Wrap, instance.Types.Entity.Unwrap
local vwrap, vunwrap = instance.Types.Vector.Wrap, instance.Types.Vector.Unwrap

local getent
instance:AddHook("initialize", function()
	getent = instance.Types.Entity.GetEntity
end)

-- --------------------------------------
-- Check funcs

local function checkclip(ent)
	checkpermission(instance, ent, "entities.clip")

	if not hook.Run("CanTool", instance.player, { Entity = ent }, "improved_clipping") then
		SF.Throw("Not allowed to clip this entity.", 3)
	end
end

-- --------------------------------------
-- Methods

--- Adds a physical clip to the entity, cutting away everything on the far side of the plane.
-- The entity's mass is always preserved.
-- @param origin A point on the clipping plane, in world space
-- @param normal The plane's normal, in world space; geometry on this side is kept
-- @param seal Optional bool (default true), whether to cap the cut surface
-- @return The new clip's ID, or 0 if it failed
function ents_methods:addClip(origin, normal, seal)
	local ent = getent(self)
	checkclip(ent)

	if seal == nil then seal = true else checkluatype(seal, TYPE_BOOL) end

	local LocalNormal, Distance = ImprovedClipping.WorldToLocalPlane(ent, vunwrap(normal), vunwrap(origin))
	local IDs = ImprovedClipping.AddClips(ent, { LocalNormal }, { Distance }, { seal })

	return IDs[1] or 0
end

--- Removes all clips from the entity
-- @return True if the entity had clips to remove
function ents_methods:removeClips()
	local ent = getent(self)
	checkclip(ent)

	return ImprovedClipping.Reset(ent)
end

--- Removes a clip from the entity given its ID
-- @param id The clip's ID, as returned by addClip
-- @return True if the clip was removed
function ents_methods:removeClip(id)
	local ent = getent(self)
	checkclip(ent)

	checkluatype(id, TYPE_NUMBER)

	return ImprovedClipping.RemoveClips(ent, { id })
end

--- Returns how many more clips can be added to the entity
-- @return Count number
function ents_methods:clipsLeft()
	local ent = getent(self)
	return ImprovedClipping.ClipsLeft(ent)
end

--- Returns whether the entity currently has any clips
-- @return True if the entity is clipped
function ents_methods:isClipped()
	local ent = getent(self)
	return IsValid(ent) and ent.ImprovedClipping ~= nil
end

--- Returns the entity's clips
-- @return Table array of clip data (id, normal, distance, seal)
function ents_methods:getClips()
	local ent = getent(self)
	if not IsValid(ent) then SF.Throw("Entity is not valid.", 2) end

	local rtn = {}
	for i, clip in ipairs(ImprovedClipping.GetClips(ent)) do
		rtn[i] = {
			id = clip.ID,
			normal = vwrap(clip.Normal),
			distance = clip.Distance,
			seal = clip.Seal,
		}
	end

	return rtn
end

end
