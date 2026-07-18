ImprovedClipping = ImprovedClipping or {}
ImprovedClipping.ClippedEntities = ImprovedClipping.ClippedEntities or {}

local MaxClips = CreateConVar("improved_clipping_max_clips", "8", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Max clips a entity can have", 0, 8)

-- Clips are stored in entity-local space on Ent.ImprovedClipping:
--   Clips = { { ID, Normal, Distance, KeepMass }, ... } -- geometry on the Normal side is kept
--   OriginalConvexes, Mass, Volume                      -- captured before the first clip

----------------------------------------
-- Plane clipping math

local function IsAbovePlane(Point, Normal, Distance)
	return Normal:Dot(Point) > Distance
end

local function IntersectLinePlane(A, B, Normal, Distance)
	local Direction = B - A
	local Dot = Normal:Dot(Direction)

	if math.abs(Dot) < 1e-6 then return end

	return A + Direction * ((Distance - Normal:Dot(A)) / Dot)
end

local function PushTriangle(Result, A, B, C)
	local i = #Result + 1
	Result[i] = A
	Result[i + 1] = B
	Result[i + 2] = C
end

-- Clips a triangle soup (flat vertex array, 3 per triangle) against a plane,
-- keeping the geometry on the side the normal points toward.
local function ClipTriangles(Vertices, Normal, Distance)
	local Result = {}

	for i = 1, #Vertices - 2, 3 do
		local V1, V2, V3 = Vertices[i], Vertices[i + 1], Vertices[i + 2]
		local A1 = IsAbovePlane(V1, Normal, Distance)
		local A2 = IsAbovePlane(V2, Normal, Distance)
		local A3 = IsAbovePlane(V3, Normal, Distance)
		local AboveCount = (A1 and 1 or 0) + (A2 and 1 or 0) + (A3 and 1 or 0)

		if AboveCount == 3 then
			PushTriangle(Result, V1, V2, V3)
		elseif AboveCount == 2 then
			-- Clips to a quad, split into two triangles. VC is the vertex below the plane.
			local VA, VB, VC
			if not A1 then VA, VB, VC = V2, V3, V1
			elseif not A2 then VA, VB, VC = V3, V1, V2
			else VA, VB, VC = V1, V2, V3 end

			local PCA = IntersectLinePlane(VC, VA, Normal, Distance)
			local PCB = IntersectLinePlane(VC, VB, Normal, Distance)

			if PCA and PCB then
				PushTriangle(Result, VA, VB, PCB)
				PushTriangle(Result, VA, PCB, PCA)
			end
		elseif AboveCount == 1 then
			-- Clips to a smaller triangle. VA is the vertex above the plane.
			local VA, VB, VC
			if A1 then VA, VB, VC = V1, V2, V3
			elseif A2 then VA, VB, VC = V2, V3, V1
			else VA, VB, VC = V3, V1, V2 end

			local PAB = IntersectLinePlane(VA, VB, Normal, Distance)
			local PAC = IntersectLinePlane(VA, VC, Normal, Distance)

			if PAB and PAC then
				PushTriangle(Result, VA, PAB, PAC)
			end
		end
	end

	return Result
end

----------------------------------------
-- Physics rebuilding

local function GetConvexes(PhysObj)
	local Convexes = {}

	for i, Convex in ipairs(PhysObj:GetMeshConvexes()) do
		local Vertices = {}
		for j, Vertex in ipairs(Convex) do
			Vertices[j] = Vertex.pos
		end

		Convexes[i] = Vertices
	end

	return Convexes
end

local ConstraintTimers = {}

-- Rebuilding destroys constraints; recreate them a tick later, deduplicated across entities
local function QueueConstraints(Constraints)
	for _, Data in ipairs(Constraints) do
		local Type = duplicator.ConstraintType[Data.Type]

		if Type then
			local Args, Key = {}, ""
			for i, Arg in ipairs(Type.Args) do
				Args[i] = Data[Arg]
				Key = Key .. tostring(Data[Arg]) .. "\0"
			end

			if not ConstraintTimers[Key] then
				ConstraintTimers[Key] = true

				timer.Simple(0, function()
					ConstraintTimers[Key] = nil
					Type.Func(unpack(Args))
				end)
			end
		end
	end
end

local function CapturePhysData(Ent, PhysObj)
	local Data = {
		Damping = { PhysObj:GetDamping() },
		Material = PhysObj:GetMaterial(),
		Contents = PhysObj:GetContents(),
		Motion = PhysObj:IsMotionEnabled(),
	}

	if SERVER then
		Data.Constraints = constraint.GetTable(Ent)
		constraint.RemoveAll(Ent)
	end

	return Data
end

local function ApplyPhysData(PhysObj, Data)
	PhysObj:SetDamping(unpack(Data.Damping))
	PhysObj:SetMaterial(Data.Material)
	PhysObj:SetContents(Data.Contents)

	if SERVER then
		PhysObj:EnableMotion(Data.Motion)
		if Data.Motion then PhysObj:Wake() end

		QueueConstraints(Data.Constraints)
	else
		PhysObj:EnableMotion(false)
		PhysObj:Sleep()
	end
end

-- Rebuilds the physics object once from the original mesh with every stored clip applied
local function RebuildPhysics(Ent)
	local PhysObj = Ent:GetPhysicsObject()

	if CLIENT and not IsValid(PhysObj) then
		Ent:PhysicsInit(SOLID_VPHYSICS)
		PhysObj = Ent:GetPhysicsObject()
	end

	if not IsValid(PhysObj) then return false end

	local State = Ent.ImprovedClipping
	local Convexes = State.OriginalConvexes
	local KeepMass = true

	for _, Clip in ipairs(State.Clips) do
		if not Clip.KeepMass then KeepMass = false end

		local Clipped = {}
		for _, Vertices in ipairs(Convexes) do
			local Result = ClipTriangles(Vertices, Clip.Normal, Clip.Distance)
			if Result[1] then
				Clipped[#Clipped + 1] = Result
			end
		end

		Convexes = Clipped
	end

	-- Refuse to clip the entire mesh away
	if not Convexes[1] then return false end

	local Data = CapturePhysData(Ent, PhysObj)

	-- Can crash without this
	-- https://github.com/Facepunch/garrysmod/blob/master/garrysmod/lua/entities/sent_ball.lua#L75
	Ent.ConstraintSystem = nil

	if not Ent:PhysicsInitMultiConvex(Convexes) then
		if SERVER then QueueConstraints(Data.Constraints) end
		return false
	end

	Ent:SetMoveType(MOVETYPE_VPHYSICS)
	Ent:SetSolid(SOLID_VPHYSICS)
	Ent:EnableCustomCollisions(true)

	PhysObj = Ent:GetPhysicsObject()
	if not IsValid(PhysObj) then return false end

	ApplyPhysData(PhysObj, Data)

	if SERVER then
		local Mass = State.Mass
		if not KeepMass and State.Volume > 0 then
			Mass = math.max(1, Mass * (PhysObj:GetVolume() or State.Volume) / State.Volume)
		end

		PhysObj:SetMass(Mass)
	end

	return true
end

----------------------------------------
-- Public API

-- Returns how many more clips the entity can have in the current realm
function ImprovedClipping.ClipsLeft(Ent)
	local State = IsValid(Ent) and Ent.ImprovedClipping
	return math.max(0, MaxClips:GetInt() - (State and #State.Clips or 0))
end

-- Returns a copy of the entity's clips: { { ID, Normal, Distance, KeepMass }, ... }
function ImprovedClipping.GetClips(Ent)
	local Clips = {}
	local State = IsValid(Ent) and Ent.ImprovedClipping
	if not State then return Clips end

	for i, Clip in ipairs(State.Clips) do
		Clips[i] = {
			ID = Clip.ID,
			Normal = Vector(Clip.Normal),
			Distance = Clip.Distance,
			KeepMass = Clip.KeepMass,
		}
	end

	return Clips
end

-- Replaces the entity's entire clip list and rebuilds the physics object once.
-- An empty list fully resets the entity.
function ImprovedClipping.SetClips(Ent, Clips)
	if not IsValid(Ent) then return false end

	local State = Ent.ImprovedClipping

	if not Clips[1] then
		if not State then return true end

		State.Clips = {}
		RebuildPhysics(Ent)

		Ent.ImprovedClipping = nil
		ImprovedClipping.ClippedEntities[Ent] = nil
		Ent:RemoveCallOnRemove("improved_clipping")

		if SERVER then
			duplicator.ClearEntityModifier(Ent, "improved_clipping")
			ImprovedClipping.Sync(Ent)
		else
			Ent.RenderOverride = State.RenderOverride
		end

		return true
	end

	if not State then
		local PhysObj = Ent:GetPhysicsObject()

		if CLIENT and not IsValid(PhysObj) then
			Ent:PhysicsInit(SOLID_VPHYSICS)
			PhysObj = Ent:GetPhysicsObject()
		end

		if not IsValid(PhysObj) then return false end

		State = {
			Clips = {},
			NextID = 1,
			OriginalConvexes = GetConvexes(PhysObj),
			Mass = PhysObj:GetMass(),
			Volume = PhysObj:GetVolume() or 0,
		}

		Ent.ImprovedClipping = State
		ImprovedClipping.ClippedEntities[Ent] = true

		if CLIENT then
			State.RenderOverride = Ent.RenderOverride
			Ent.RenderOverride = ImprovedClipping.RenderOverride
		end

		Ent:CallOnRemove("improved_clipping", function(Removed)
			ImprovedClipping.ClippedEntities[Removed] = nil
			if SERVER then ImprovedClipping.SyncRemoval(Removed:EntIndex()) end
		end)
	end

	local Old = State.Clips
	State.Clips = Clips

	if not RebuildPhysics(Ent) then
		State.Clips = Old
		return false
	end

	local NextID = 1
	for _, Clip in ipairs(Clips) do
		NextID = math.max(NextID, Clip.ID + 1)
	end
	State.NextID = NextID

	if SERVER then ImprovedClipping.Sync(Ent) end

	return true
end

-- Adds clips (entity-local planes), rebuilding the physics object once. Returns the added IDs.
function ImprovedClipping.AddClips(Ent, Normals, Distances, KeepMasses)
	local IDs = {}
	if not IsValid(Ent) then return IDs end

	local Count = math.min(#Normals, ImprovedClipping.ClipsLeft(Ent))
	if Count < 1 then return IDs end

	local State = Ent.ImprovedClipping
	local NextID = State and State.NextID or 1

	local Clips = {}
	if State then
		for i, Clip in ipairs(State.Clips) do
			Clips[i] = Clip
		end
	end

	for i = 1, Count do
		local Clip = {
			ID = NextID,
			Normal = Normals[i],
			Distance = Distances[i],
			KeepMass = not KeepMasses or KeepMasses[i] ~= false,
		}

		NextID = NextID + 1
		Clips[#Clips + 1] = Clip
		IDs[#IDs + 1] = Clip.ID
	end

	if not ImprovedClipping.SetClips(Ent, Clips) then return {} end

	return IDs
end

-- Removes clips by ID, rebuilding the physics object once
function ImprovedClipping.RemoveClips(Ent, IDs)
	if not IsValid(Ent) then return false end

	local State = Ent.ImprovedClipping
	if not State then return false end

	local Remove = {}
	for _, ID in ipairs(IDs) do
		Remove[ID] = true
	end

	local Clips = {}
	for _, Clip in ipairs(State.Clips) do
		if not Remove[Clip.ID] then
			Clips[#Clips + 1] = Clip
		end
	end

	if #Clips == #State.Clips then return false end

	return ImprovedClipping.SetClips(Ent, Clips)
end

-- Removes all clips, resetting the physics mesh and properties
function ImprovedClipping.Reset(Ent)
	return ImprovedClipping.SetClips(Ent, {})
end
