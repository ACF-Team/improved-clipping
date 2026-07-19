ImprovedClipping = ImprovedClipping or {}
ImprovedClipping.ClippedEntities = ImprovedClipping.ClippedEntities or {}

local MaxClips = CreateConVar("improved_clipping_max_clips", "8", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Max clips a entity can have", 0, 8)

-- Clips are stored in entity-local space on Ent.ImprovedClipping:
--   Clips = { { ID, Normal, Distance, KeepMass, Seal }, ... } -- geometry on the Normal side is kept
--   OriginalConvexes, Mass, Volume                      -- captured before the first clip

----------------------------------------
-- Plane clipping math

local function IsAbovePlane(Point, Normal, Distance)
	return Normal:Dot(Point) > Distance
end

-- Where the segment crosses the plane, and the fraction along A -> B it does so at
local function IntersectLinePlane(A, B, Normal, Distance)
	local Direction = B - A
	local Dot = Normal:Dot(Direction)

	if math.abs(Dot) < 1e-6 then return end

	local Fraction = math.Clamp((Distance - Normal:Dot(A)) / Dot, 0, 1)

	return A + Direction * Fraction, Fraction
end

-- Builds the vertex sitting Fraction of the way from V1 to V2, interpolating render attributes
local function LerpVertex(V1, V2, Pos, Fraction)
	local Normal = LerpVector(Fraction, V1.normal, V2.normal)
	Normal:Normalize()

	local Vertex = {
		pos = Pos,
		normal = Normal,
		u = Lerp(Fraction, V1.u, V2.u),
		v = Lerp(Fraction, V1.v, V2.v),
	}

	local UD1, UD2 = V1.userdata, V2.userdata
	if UD1 and UD2 then
		Vertex.userdata = {
			Lerp(Fraction, UD1[1], UD2[1]),
			Lerp(Fraction, UD1[2], UD2[2]),
			Lerp(Fraction, UD1[3], UD2[3]),
			UD1[4],
		}
	end

	return Vertex
end

local function PushTriangle(Result, A, B, C)
	local i = #Result + 1
	Result[i] = A
	Result[i + 1] = B
	Result[i + 2] = C
end

-- Orthonormal basis of the plane, Right x Up == Normal
local function PlaneBasis(Normal)
	local Right = (math.abs(Normal.z) < 0.9 and Vector(0, 0, 1) or Vector(1, 0, 0)):Cross(Normal)
	Right:Normalize()

	return Right, Normal:Cross(Right)
end

-- Texels per unit of the source mesh, so cap geometry matches the skin's texture scale
local function TexelDensity(Vertices)
	local UVArea, WorldArea = 0, 0

	for i = 1, #Vertices - 2, 3 do
		local V1, V2, V3 = Vertices[i], Vertices[i + 1], Vertices[i + 2]

		WorldArea = WorldArea + (V2.pos - V1.pos):Cross(V3.pos - V1.pos):Length()
		UVArea = UVArea + math.abs((V2.u - V1.u) * (V3.v - V1.v) - (V2.v - V1.v) * (V3.u - V1.u))
	end

	if WorldArea < 1e-6 or UVArea < 1e-6 then return 1 / 64 end

	return math.sqrt(UVArea / WorldArea)
end

-- Caps the hole the clip opened up by fanning the cut points around their centroid
local function CapHole(Result, Cut, Normal, Source)
	if #Cut < 3 then return end

	local CapNormal = -Normal
	local Right, Up = PlaneBasis(CapNormal)

	local Centroid = Vector(0, 0, 0)
	for _, Pos in ipairs(Cut) do
		Centroid = Centroid + Pos
	end
	Centroid = Centroid * (1 / #Cut)

	-- Descending, because Source winds front faces clockwise about the normal. Points
	-- come back twice and pair into slivers too thin to see.
	local Points = {}
	for i, Pos in ipairs(Cut) do
		local Offset = Pos - Centroid
		Points[i] = { Pos = Pos, Angle = math.atan2(Up:Dot(Offset), Right:Dot(Offset)) }
	end

	table.sort(Points, function(A, B) return A.Angle > B.Angle end)

	local Density = TexelDensity(Source)
	local Tangent = { Right.x, Right.y, Right.z, 1 }

	local function CapVertex(Pos)
		return {
			pos = Pos,
			normal = CapNormal,
			u = Right:Dot(Pos) * Density,
			v = Up:Dot(Pos) * Density,
			userdata = Tangent,
		}
	end

	local Hub = CapVertex(Centroid)

	for i = 1, #Points do
		local A = CapVertex(Points[i].Pos)
		local B = CapVertex(Points[i == #Points and 1 or i + 1].Pos)

		PushTriangle(Result, Hub, A, B)
	end
end

-- Clips a triangle soup (flat vertex array, 3 per triangle) against a plane,
-- keeping the geometry on the side the normal points toward.
--
-- Textured means the vertices are util.GetModelMeshes structs ({ pos, normal, u, v,
-- userdata }) instead of bare Vectors, and cut vertices interpolate those attributes.
-- Cap then seals the hole along the plane. Physics passes neither.
local function ClipTriangles(Vertices, Normal, Distance, Textured, Cap)
	local Result = {}
	local Cut = (Textured and Cap) and {} or nil

	for i = 1, #Vertices - 2, 3 do
		local V1, V2, V3 = Vertices[i], Vertices[i + 1], Vertices[i + 2]
		local P1, P2, P3
		if Textured then
			P1, P2, P3 = V1.pos, V2.pos, V3.pos
		else
			P1, P2, P3 = V1, V2, V3
		end

		local A1 = IsAbovePlane(P1, Normal, Distance)
		local A2 = IsAbovePlane(P2, Normal, Distance)
		local A3 = IsAbovePlane(P3, Normal, Distance)
		local AboveCount = (A1 and 1 or 0) + (A2 and 1 or 0) + (A3 and 1 or 0)

		if AboveCount == 3 then
			PushTriangle(Result, V1, V2, V3)
		elseif AboveCount == 2 then
			-- Clips to a quad, split into two triangles. VC is the vertex below the plane.
			local VA, VB, VC, PA, PB, PC
			if not A1 then VA, VB, VC, PA, PB, PC = V2, V3, V1, P2, P3, P1
			elseif not A2 then VA, VB, VC, PA, PB, PC = V3, V1, V2, P3, P1, P2
			else VA, VB, VC, PA, PB, PC = V1, V2, V3, P1, P2, P3 end

			local PosCA, FracCA = IntersectLinePlane(PC, PA, Normal, Distance)
			local PosCB, FracCB = IntersectLinePlane(PC, PB, Normal, Distance)

			if PosCA and PosCB then
				local PCA = Textured and LerpVertex(VC, VA, PosCA, FracCA) or PosCA
				local PCB = Textured and LerpVertex(VC, VB, PosCB, FracCB) or PosCB

				PushTriangle(Result, VA, VB, PCB)
				PushTriangle(Result, VA, PCB, PCA)

				if Cut then
					Cut[#Cut + 1] = PosCA
					Cut[#Cut + 1] = PosCB
				end
			end
		elseif AboveCount == 1 then
			-- Clips to a smaller triangle. VA is the vertex above the plane.
			local VA, VB, VC, PA, PB, PC
			if A1 then VA, VB, VC, PA, PB, PC = V1, V2, V3, P1, P2, P3
			elseif A2 then VA, VB, VC, PA, PB, PC = V2, V3, V1, P2, P3, P1
			else VA, VB, VC, PA, PB, PC = V3, V1, V2, P3, P1, P2 end

			local PosAB, FracAB = IntersectLinePlane(PA, PB, Normal, Distance)
			local PosAC, FracAC = IntersectLinePlane(PA, PC, Normal, Distance)

			if PosAB and PosAC then
				local PAB = Textured and LerpVertex(VA, VB, PosAB, FracAB) or PosAB
				local PAC = Textured and LerpVertex(VA, VC, PosAC, FracAC) or PosAC

				PushTriangle(Result, VA, PAB, PAC)

				if Cut then
					Cut[#Cut + 1] = PosAC
					Cut[#Cut + 1] = PosAB
				end
			end
		end
	end

	if Cut then
		CapHole(Result, Cut, Normal, Vertices)
	end

	return Result
end

ImprovedClipping.ClipTriangles = ClipTriangles

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

-- Converts a world-space plane (a direction and a point on the plane) into the
-- entity-local Normal/Distance pair Clips are stored as
function ImprovedClipping.WorldToLocalPlane(Ent, WorldNormal, WorldPoint)
	local Normal = Ent:WorldToLocal(Ent:GetPos() + WorldNormal)
	local Distance = Normal:Dot(Ent:WorldToLocal(WorldPoint))

	return Normal, Distance
end

----------------------------------------
-- Public API

-- Returns how many more clips the entity can have in the current realm
function ImprovedClipping.ClipsLeft(Ent)
	local State = IsValid(Ent) and Ent.ImprovedClipping
	return math.max(0, MaxClips:GetInt() - (State and #State.Clips or 0))
end

-- Returns a copy of the entity's clips: { { ID, Normal, Distance, KeepMass, Seal }, ... }
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
			Seal = Clip.Seal,
		}
	end

	return Clips
end

-- Replaces the entity's entire clip list, rebuilding the physics object once. An empty list
-- fully resets the entity. Entities owning their own mesh skip the rebuild, so nothing can fail
-- for them and this always succeeds; for everyone else a failed rebuild reverts and returns false.
function ImprovedClipping.SetClips(Ent, Clips)
	if not IsValid(Ent) then return false end

	local State = Ent.ImprovedClipping
	local External = Ent.ImprovedClippingExternalMesh

	if not Clips[1] then
		if not State then return true end

		State.Clips = {}
		if not External then RebuildPhysics(Ent) end

		Ent.ImprovedClipping = nil
		ImprovedClipping.ClippedEntities[Ent] = nil
		Ent:RemoveCallOnRemove("improved_clipping")

		if SERVER then duplicator.ClearEntityModifier(Ent, "improved_clipping") end
		ImprovedClipping.Sync(Ent)
		hook.Run("ImprovedClipping_ClipsChanged", Ent)

		return true
	end

	if not State then
		if External then
			-- Only RebuildPhysics reads the mesh, mass and volume, and it never runs for these
			State = {
				Clips = {},
				NextID = 1,
				OriginalConvexes = {},
				Mass = 0,
				Volume = 0,
			}
		else
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
		end

		Ent.ImprovedClipping = State
		ImprovedClipping.ClippedEntities[Ent] = true

		Ent:CallOnRemove("improved_clipping", function(Removed)
			ImprovedClipping.ClippedEntities[Removed] = nil
			if SERVER then ImprovedClipping.SyncRemoval(Removed:EntIndex()) end
		end)
	end

	local Old = State.Clips
	State.Clips = Clips

	if not External and not RebuildPhysics(Ent) then
		State.Clips = Old
		return false
	end

	local NextID = 1
	for _, Clip in ipairs(Clips) do
		NextID = math.max(NextID, Clip.ID + 1)
	end
	State.NextID = NextID

	ImprovedClipping.Sync(Ent)
	hook.Run("ImprovedClipping_ClipsChanged", Ent)

	return true
end

-- Adds clips (entity-local planes), rebuilding the physics object once. Returns the added IDs.
function ImprovedClipping.AddClips(Ent, Normals, Distances, KeepMasses, Seals)
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
			Seal = not Seals or Seals[i] ~= false,
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
