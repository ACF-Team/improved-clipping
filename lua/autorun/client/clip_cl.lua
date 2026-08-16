ImprovedClipping = ImprovedClipping or {}

----------------------------------------
-- Rendering
--
-- The model is drawn whole, but hardware clip planes cut it on the GPU: every stored clip
-- is pushed as a render clip plane before the model draws, so the geometry on each plane's
-- far side is discarded by the rasterizer. 
--
-- Clips with sealing are not natively handled by Improved Clipping. It's up to the entity to handle that.
--
-- If any clip has Inside = true, the model is drawn a second time with backface culling reversed,
-- so the interior of the cut is drawn into the hole. This is purely visual and doesn't affect physics.
local function RenderOverride(self)
	local State = self.ImprovedClipping
	if not State then return end

	local Was = render.EnableClipping(true)
	local Angles = self:GetAngles()
	local Planes = 0
	local Inside = false

	for i, Clip in ipairs(State.Clips) do
		local Normal = Vector(Clip.Normal)
		Normal:Rotate(Angles)

		local Point = self:LocalToWorld(Clip.Normal * Clip.Distance)
		render.PushCustomClipPlane(Normal, Normal:Dot(Point))

		Planes = i
		if Clip.Inside then Inside = true end
	end

	self:DrawModel()

	if Inside then
		render.CullMode(MATERIAL_CULLMODE_CW)
		self:DrawModel()
		render.CullMode(MATERIAL_CULLMODE_CCW)
	end

	for _ = 1, Planes do
		render.PopCustomClipPlane()
	end

	render.EnableClipping(Was)
end

-- Called by SetClips whenever the entity's clips change in any way. The server starts the
-- sync by networking the clips; this completes it by installing or removing the render
-- override. The override reads the live clip list, so changed clips need nothing rebuilt.
function ImprovedClipping.Sync(Ent)
	-- External-mesh entities draw their own clipped mesh; no render override
	if Ent.ImprovedClippingExternalMesh then return end

	if Ent.ImprovedClipping then
		if Ent.RenderOverride ~= RenderOverride then
			Ent.RenderOverridePreClipping = Ent.RenderOverride
			Ent.RenderOverride = RenderOverride
		end
	elseif Ent.RenderOverride == RenderOverride then
		Ent.RenderOverride = Ent.RenderOverridePreClipping
		Ent.RenderOverridePreClipping = nil
	end
end

----------------------------------------
-- Receiving clips

-- Cached per entity index so clips survive clientside entity recreation
local Cache = {}

-- Index -> attempts. Clips that erase an entity's collision are refused every time, so retries
-- are capped.
local Pending = {}
local MAX_ATTEMPTS = 50

local function ApplyClips(Index)
	local Ent = Entity(Index)
	if not IsValid(Ent) then return false end
	-- Wait for the spawn effect to end before clipping the entity
	if Ent.SpawnEffect then return false end

	return ImprovedClipping.SetClips(Ent, Cache[Index])
end

timer.Create("improved_clipping_pending", 0.1, 0, function()
	for Index, Attempts in pairs(Pending) do
		if ApplyClips(Index) then
			Pending[Index] = nil
		elseif Attempts >= MAX_ATTEMPTS then
			Pending[Index] = nil

			ErrorNoHalt(string.format(
				"Improved Clipping: gave up clipping entity %d after %d attempts. Drawing it unclipped.\n",
				Index, MAX_ATTEMPTS
			))
		else
			Pending[Index] = Attempts + 1
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
			Seal = net.ReadBool(),
			Inside = net.ReadBool(),
		}
	end

	Cache[Index] = Clips
	Pending[Index] = 1
end)

net.Receive("improved_clipping_notify", function()
	local NotifyType = net.ReadUInt(3)
	local Text = net.ReadString()

	notification.AddLegacy("Impr. Clip: " .. Text, NotifyType, 3)
end)

hook.Add("NetworkEntityCreated", "improved_clipping", function(Ent)
	local Index = Ent:EntIndex()
	if Cache[Index] then
		Pending[Index] = 1
	end
end)

----------------------------------------
-- Clientside physics sync
--
-- If the entity had a client side physics object (re) built, we need to sync it.
hook.Add("PhysgunPickup", "improved_clipping_physics", function(_, Ent)
	if not Ent.ImprovedClippingClientPhys then return end

	hook.Add("Think", "improved_clipping_physics", function()
		if not IsValid(Ent) then
			hook.Remove("Think", "improved_clipping_physics")
			return
		end

		local PhysObj = Ent:GetPhysicsObject()
		if IsValid(PhysObj) then
			PhysObj:SetPos(Ent:GetPos())
			PhysObj:SetAngles(Ent:GetAngles())
		end
	end)

	return false
end)

hook.Add("PhysgunDrop", "improved_clipping_physics", function(_, Ent)
	if not Ent.ImprovedClippingClientPhys then return end

	hook.Remove("Think", "improved_clipping_physics")
end)
