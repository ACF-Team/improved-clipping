ImprovedClipping = ImprovedClipping or {}

----------------------------------------
-- Rendering

local render_EnableClipping = render.EnableClipping
local render_CullMode = render.CullMode
local render_PushCustomClipPlane = render.PushCustomClipPlane
local render_PopCustomClipPlane = render.PopCustomClipPlane

-- Tool client convar, registered when the tool loads, so it must be fetched lazily
local SealHoles
local function ShouldSealHoles()
	SealHoles = SealHoles or GetConVar("improved_clipping_seal_holes")
	return not SealHoles or SealHoles:GetBool()
end

-- RenderOverride installed on clipped entities by SetClips
function ImprovedClipping.RenderOverride(self)
	local State = self.ImprovedClipping
	if not State then return self:DrawModel() end

	local Clips = State.Clips
	local Previous = render_EnableClipping(true)
	local Pos = self:GetPos()
	local Ang = self:GetAngles()

	for _, Clip in ipairs(Clips) do
		local Normal = Vector(Clip.Normal)
		Normal:Rotate(Ang)

		render_PushCustomClipPlane(Normal, Normal:Dot(Pos) + Clip.Distance)
	end

	self:DrawModel()

	if ShouldSealHoles() then
		render_CullMode(MATERIAL_CULLMODE_CW)
		self:DrawModel()
		render_CullMode(MATERIAL_CULLMODE_CCW)
	end

	for _ = 1, #Clips do
		render_PopCustomClipPlane()
	end

	render_EnableClipping(Previous)
end

----------------------------------------
-- Receiving clips

-- Cached per entity index so clips survive clientside entity recreation
local Cache = {}
local Pending = {}

local function ApplyClips(Index)
	local Ent = Entity(Index)
	if not IsValid(Ent) then return false end
	-- Wait for the spawn effect to end before clipping the entity
	if Ent.SpawnEffect then return false end

	return ImprovedClipping.SetClips(Ent, Cache[Index])
end

timer.Create("improved_clipping_pending", 0.1, 0, function()
	for Index in pairs(Pending) do
		if ApplyClips(Index) then
			Pending[Index] = nil
		end
	end
end)

net.Receive("improved_clipping", function()
	local Index = net.ReadUInt(14)
	local Count = net.ReadUInt(4)

	if Count == 0 then
		Cache[Index] = nil
		Pending[Index] = nil

		local Ent = Entity(Index)
		if IsValid(Ent) then ImprovedClipping.Reset(Ent) end

		return
	end

	local Clips = {}
	for i = 1, Count do
		Clips[i] = {
			ID = net.ReadUInt(32),
			Normal = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat()),
			Distance = net.ReadFloat(),
			KeepMass = true,
		}
	end

	Cache[Index] = Clips
	Pending[Index] = true
end)

hook.Add("NetworkEntityCreated", "improved_clipping", function(Ent)
	local Index = Ent:EntIndex()
	if Cache[Index] then
		Pending[Index] = true
	end
end)

----------------------------------------
-- Clientside physics sync

-- Clipped clientside physics objects don't follow the entity; sync them during physgun use
hook.Add("PhysgunPickup", "improved_clipping_physics", function(_, Ent)
	if not Ent.ImprovedClipping then return end

	hook.Add("Think", "improved_clipping_physics", function()
		for Clipped in pairs(ImprovedClipping.ClippedEntities) do
			if IsValid(Clipped) then
				local PhysObj = Clipped:GetPhysicsObject()
				if IsValid(PhysObj) then
					PhysObj:SetPos(Clipped:GetPos())
					PhysObj:SetAngles(Clipped:GetAngles())
				end
			end
		end
	end)

	return false
end)

hook.Add("PhysgunDrop", "improved_clipping_physics", function(_, Ent)
	if not Ent.ImprovedClipping then return end

	hook.Remove("Think", "improved_clipping_physics")
end)
