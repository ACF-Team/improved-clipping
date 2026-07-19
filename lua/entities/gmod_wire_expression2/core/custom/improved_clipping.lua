E2Lib.RegisterExtension("improved_clipping", false, "Used to add physical clips to props and other clippable entities", "This still abides by CanTool, so if the player can't use the tool normally they also won't be able to use the E2 functions")

----------------------------------------
-- Check funcs

local function checktool(ent, self)
	return IsValid(ent) and hook.Run("CanTool", self.player, { Entity = ent }, "improved_clipping") and true or false
end

local function vec(v)
	return Vector(v[1], v[2], v[3])
end

----------------------------------------
-- Adding

local function addclip(self, ent, origin, normal, keepmass, seal)
	if not checktool(ent, self) then return 0 end

	local LocalNormal, Distance = ImprovedClipping.WorldToLocalPlane(ent, vec(normal), vec(origin))
	local IDs = ImprovedClipping.AddClips(ent, { LocalNormal }, { Distance }, { keepmass }, { seal })

	return IDs[1] or 0
end

__e2setcost(500)
e2function number entity:addMeshClip(vector origin, vector normal, number keepMass, number seal)
	return addclip(self, this, origin, normal, keepMass ~= 0, seal ~= 0)
end

e2function number entity:addMeshClip(vector origin, vector normal, number keepMass)
	return addclip(self, this, origin, normal, keepMass ~= 0, true)
end

e2function number entity:addMeshClip(vector origin, vector normal)
	return addclip(self, this, origin, normal, true, true)
end

----------------------------------------
-- Removing

e2function number entity:removeMeshClips()
	local ent = this

	if not checktool(ent, self) then return 0 end

	return ImprovedClipping.Reset(ent) and 1 or 0
end

e2function number entity:removeMeshClip()
	local ent = this

	if not checktool(ent, self) then return 0 end

	return ImprovedClipping.Reset(ent) and 1 or 0
end

e2function number entity:removeMeshClip(number id)
	local ent = this

	if not checktool(ent, self) then return 0 end

	return ImprovedClipping.RemoveClips(ent, { id }) and 1 or 0
end

e2function number entity:removeMeshClipByID(number id)
	local ent = this

	if not checktool(ent, self) then return 0 end

	return ImprovedClipping.RemoveClips(ent, { id }) and 1 or 0
end

----------------------------------------
-- Other

__e2setcost(20)
e2function number entity:meshClipsLeft()
	return ImprovedClipping.ClipsLeft(this)
end

e2function number entity:isMeshClipped()
	return (IsValid(this) and this.ImprovedClipping) and 1 or 0
end

__e2setcost(50)
e2function table entity:getMeshClips()
	local res = E2Lib.newE2Table()
	if not IsValid(this) then return res end

	local Clips = ImprovedClipping.GetClips(this)

	for key, Clip in ipairs(Clips) do
		res.n[key] = {
			s = {
				id = Clip.ID,
				normal = Clip.Normal,
				distance = Clip.Distance,
				keepMass = Clip.KeepMass and 1 or 0,
				seal = Clip.Seal and 1 or 0,
			},
			stypes = {
				id = "n",
				normal = "v",
				distance = "n",
				keepMass = "n",
				seal = "n",
			},
			size = 5,
			n = {},
			ntypes = {},
		}
		res.ntypes[key] = "t"
	end

	res.size = #Clips
	return res
end
