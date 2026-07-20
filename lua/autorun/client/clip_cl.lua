ImprovedClipping = ImprovedClipping or {}

----------------------------------------
-- Rendering
--
-- Instead of pushing render clip planes every frame, the clipped render mesh is baked
-- once into an IMesh and drawn by an invisible clientside proxy entity in the real
-- entity's place.

-- Meshes are indexed with 16 bit indices. No prop should come near this.
local MAX_MESH_VERTICES = 65535

-- Clipped entity -> the clientside entity that draws its mesh
local Proxies = {}

local function DestroyMesh(Proxy)
	-- nil when never built, false for a model we couldn't build one from
	if Proxy.ClipMesh then
		Proxy.ClipMesh.Mesh:Destroy()
	end

	Proxy.ClipMesh = nil
end

-- Model -> { Material, [i] = { Triangles, Density } }, or false for a model with no meshes
local ModelCache = {}

local function GetModelData(Model)
	local Data = ModelCache[Model]
	if Data ~= nil then return Data end

	local Meshes = util.GetModelMeshes(Model)

	if Meshes then
		Data = { Material = Material(Meshes[1].material) }

		for i, Submesh in ipairs(Meshes) do
			Data[i] = {
				Triangles = Submesh.triangles,
				Density = ImprovedClipping.TexelDensity(Submesh.triangles),
			}
		end
	else
		Data = false
	end

	ModelCache[Model] = Data

	return Data
end

-- Cuts the model's render mesh along every clip plane and bakes it into an IMesh.
-- GetRenderMesh takes one mesh and one material, so the submeshes are merged and the
-- model's first material covers the lot.
--
-- Returns false if there's nothing we can build, which the caller caches so we don't
-- retry util.GetModelMeshes every frame.
local function BuildMesh(Ent)
	local Model = GetModelData(Ent:GetModel())
	if not Model then return false end

	local Clips = Ent.ImprovedClipping.Clips
	local Triangles = {}

	for _, Submesh in ipairs(Model) do
		local Vertices = Submesh.Triangles

		for _, Clip in ipairs(Clips) do
			Vertices = ImprovedClipping.ClipTriangles(Vertices, Clip.Normal, Clip.Distance, true, Clip.Seal ~= false, Submesh.Density)
			if not Vertices[1] then break end
		end

		for _, Vertex in ipairs(Vertices) do
			Triangles[#Triangles + 1] = Vertex
		end
	end

	if #Triangles > MAX_MESH_VERTICES then
		ErrorNoHalt(string.format(
			"Improved Clipping: %s clips to %d vertices, over the %d a mesh can hold. Drawing it unclipped.\n",
			Ent:GetModel(), #Triangles, MAX_MESH_VERTICES
		))

		return false
	end

	local IMesh = Mesh()

	-- Clipped away to nothing; an unbuilt mesh is still a valid one to hand over
	if Triangles[1] then
		IMesh:BuildFromTriangles(Triangles)
	end

	return { Mesh = IMesh, Material = Model.Material }
end

-- Only DrawModel reads GetRenderMesh, and the engine never calls it for a prop, so the
-- mesh lives on a scripted clientside proxy entity where it does get read
local function GetRenderMesh(self)
	local Ent = self.ClipParent
	if not IsValid(Ent) or not Ent.ImprovedClipping then return end

	local RenderMesh = self.ClipMesh
	if RenderMesh == nil then
		RenderMesh = BuildMesh(Ent)
		self.ClipMesh = RenderMesh
	end

	-- Nothing to hand over; the proxy draws the model unclipped
	if RenderMesh == false then return end

	return RenderMesh
end

-- The clipped entity draws nothing, the proxy stands in for it. Preferred over
-- SetNoDraw, which the tool's preview toggles for its own reasons.
local function RenderOverride() end

-- The proxy only looks like the entity if it's told everything the entity knows
local function SyncProxy(Ent, Proxy)
	local Color = Ent:GetColor()
	local Opaque = Color.a == 255

	Proxy:SetColor(Color)
	Proxy:SetMaterial(Ent:GetMaterial())
	Proxy:SetRenderMode(Opaque and RENDERMODE_NORMAL or RENDERMODE_TRANSCOLOR)

	-- Translucency is drawn in a later pass than opaque geometry
	Proxy.RenderGroup = Opaque and RENDERGROUP_OPAQUE or RENDERGROUP_BOTH
end

local function RemoveProxy(Ent)
	local Proxy = Proxies[Ent]
	if not Proxy then return end

	Proxies[Ent] = nil

	if IsValid(Proxy) then
		DestroyMesh(Proxy)
		Proxy:Remove()
	end
end

local function CreateProxy(Ent)
	local Proxy = ents.CreateClientside("base_anim")
	Proxy:SetModel(Ent:GetModel())
	Proxy:SetPos(Ent:GetPos())
	Proxy:SetAngles(Ent:GetAngles())
	Proxy:Spawn()
	Proxy:Activate()
	Proxy:SetParent(Ent)

	Proxy.ClipParent = Ent
	Proxy.GetRenderMesh = GetRenderMesh

	SyncProxy(Ent, Proxy)

	Proxies[Ent] = Proxy
end

-- Nothing tells us when an entity is coloured or painted, so keep the proxy in step
hook.Add("Think", "improved_clipping_visual", function()
	for Ent, Proxy in pairs(Proxies) do
		if not IsValid(Ent) or not IsValid(Proxy) then
			RemoveProxy(Ent)
		else
			SyncProxy(Ent, Proxy)
		end
	end
end)

-- The clientside proxy drawing Ent's clipped mesh, or nil
function ImprovedClipping.GetProxy(Ent)
	return Proxies[Ent]
end

-- Called by SetClips whenever the entity's clips change in any way. The server
-- starts the sync by networking the clips; this completes it by updating visuals.
function ImprovedClipping.Sync(Ent)
	-- External-mesh entities draw their own clipped mesh; no proxy or render override
	if Ent.ImprovedClippingExternalMesh then return end

	if Ent.ImprovedClipping then
		if Ent.RenderOverride ~= RenderOverride then
			Ent.RenderOverridePreClipping = Ent.RenderOverride
			Ent.RenderOverride = RenderOverride
		end

		local Proxy = Proxies[Ent]
		if IsValid(Proxy) then
			-- Rebuilt against the new clips on the next draw
			DestroyMesh(Proxy)
		else
			CreateProxy(Ent)
		end
	else
		RemoveProxy(Ent)

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
			KeepMass = true,
		}
	end

	Cache[Index] = Clips
	Pending[Index] = 1
end)

hook.Add("NetworkEntityCreated", "improved_clipping", function(Ent)
	local Index = Ent:EntIndex()
	if Cache[Index] then
		Pending[Index] = 1
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
