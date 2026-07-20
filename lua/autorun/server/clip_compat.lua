ImprovedClipping = ImprovedClipping or {}

----------------------------------------
-- Loading clips from older clipping addons
--
-- One way only. A pasted dupe is converted and its legacy modifiers dropped, so it re-saves as
-- improved_clipping alone. Their per-clip physics flag is ignored and every clip becomes
-- physical; their inside flag is dropped and every clip comes in unsealed.

-- Proper Clipping owns these modifier names while it's installed
if ProperClipping then
	ErrorNoHalt("Improved Clipping: Proper Clipping is also installed, so it will keep loading old clips. Remove it to migrate them.\n")
	return
end

local LegacyModifiers = {
	"proper_clipping",          -- Proper Clipping
	"clips",                    -- https://steamcommunity.com/sharedfiles/filedetails/?id=106753151
	"clipping_all_prop_clips",  -- https://steamcommunity.com/sharedfiles/filedetails/?id=238138995
	"clipping_render_inside",   -- Companion to the above, read for its inside flag
}

local function Import(Player, Ent, Normals, Distances)
	-- Proper Clipping saves the same clips under two names, so the first format to load wins
	if Ent.ImprovedClippingImported then return end
	Ent.ImprovedClippingImported = true

	if hook.Run("CanTool", Player, { Entity = Ent }, "improved_clipping") then
		ImprovedClipping.AddClips(Ent, Normals, Distances)
	else
		Player:ChatPrint(tostring(Ent) .. " will be spawned without clips (not allowed to clip).")
	end

	-- Cleared even when refused, so the old format isn't left behind to retry
	for _, Name in ipairs(LegacyModifiers) do
		duplicator.ClearEntityModifier(Ent, Name)
	end
end

-- Convert returns Normal and Distance lists, a tick late so the physics object is set up
local function Register(Name, Convert)
	duplicator.RegisterEntityModifier(Name, function(Player, Ent, Data)
		if not IsValid(Ent) then return end

		timer.Simple(0, function()
			if not IsValid(Ent) then return end

			Import(Player, Ent, Convert(Ent, Data))
		end)
	end)
end

-- Measured from the origin with the normal already negated, which is our convention exactly
Register("proper_clipping", function(_, Data)
	local Normals, Distances = {}, {}

	for i, Clip in ipairs(Data) do
		Normals[i] = Clip[1]
		Distances[i] = Clip[2]
	end

	return Normals, Distances
end)

-- The older tools store an angle and an OBB center offset. OBBCenterOrg is left by prop resizers.
local function FromOBBCenter(Ent, Ang, Distance)
	local Normal = Ang:Forward()

	return Normal, Distance + Normal:Dot(Ent.OBBCenterOrg or Ent:OBBCenter())
end

Register("clips", function(Ent, Data)
	local Normals, Distances = {}, {}

	for i, Clip in ipairs(Data) do
		Normals[i], Distances[i] = FromOBBCenter(Ent, Clip.n, Clip.d)
	end

	return Normals, Distances
end)

Register("clipping_all_prop_clips", function(Ent, Data)
	local Normals, Distances = {}, {}

	for i, Clip in ipairs(Data) do
		Normals[i], Distances[i] = FromOBBCenter(Ent, Clip[1], Clip[2])
	end

	return Normals, Distances
end)
