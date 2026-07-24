-- Ground truth: PhysObj:GetMeshConvexes()[1] of models/hunter/blocks/cube1x1x1.mdl,
-- read off a live cube. 12 triangles, corners at +-23.725 on every axis.
local E = 23.725

local Signs = {
	{ 1, -1, -1 }, { -1, -1, 1 }, { 1, -1, 1 },
	{ -1, -1, -1 }, { -1, -1, 1 }, { 1, -1, -1 },
	{ 1, 1, 1 }, { 1, 1, -1 }, { 1, -1, 1 },
	{ 1, 1, -1 }, { 1, -1, -1 }, { 1, -1, 1 },
	{ 1, 1, -1 }, { -1, -1, -1 }, { 1, -1, -1 },
	{ -1, 1, -1 }, { -1, -1, -1 }, { 1, 1, -1 },
	{ -1, 1, -1 }, { -1, -1, 1 }, { -1, -1, -1 },
	{ -1, 1, 1 }, { -1, -1, 1 }, { -1, 1, -1 },
	{ -1, 1, 1 }, { -1, 1, -1 }, { 1, 1, 1 },
	{ -1, 1, -1 }, { 1, 1, -1 }, { 1, 1, 1 },
	{ -1, 1, 1 }, { 1, 1, 1 }, { -1, -1, 1 },
	{ 1, 1, 1 }, { 1, -1, 1 }, { -1, -1, 1 },
}

local function CubeVertices()
	local Vertices = {}

	for i, Sign in ipairs(Signs) do
		Vertices[i] = Vector(Sign[1] * E, Sign[2] * E, Sign[3] * E)
	end

	return Vertices
end

-- Axis-aligned bounds of a flat vertex array of either Vectors or mesh structs
local function Bounds(Vertices)
	local Min = Vector(math.huge, math.huge, math.huge)
	local Max = Vector(-math.huge, -math.huge, -math.huge)

	for _, Vertex in ipairs(Vertices) do
		local Pos = Vertex.pos or Vertex

		Min.x = math.min(Min.x, Pos.x)
		Min.y = math.min(Min.y, Pos.y)
		Min.z = math.min(Min.z, Pos.z)
		Max.x = math.max(Max.x, Pos.x)
		Max.y = math.max(Max.y, Pos.y)
		Max.z = math.max(Max.z, Pos.z)
	end

	return Min, Max
end

-- GLuaTest only puts expect() in the case function's environment, so helpers up here
-- report booleans and the cases do the asserting
local function Near(Actual, Expected, Tolerance)
	return math.abs(Actual - Expected) <= (Tolerance or 0.01)
end

return {
	groupName = "ImprovedClipping.ClipTriangles",

	cases = {
		{
			name = "Ground truth: a live cube1x1x1 physmesh is one 12 triangle convex at +-23.725",
			func = function(State)
				State.Cube = ents.Create("prop_physics")

				local Cube = State.Cube
				Cube:SetModel("models/hunter/blocks/cube1x1x1.mdl")
				Cube:SetPos(Vector(0, 0, 0))
				Cube:Spawn()

				local Convexes = Cube:GetPhysicsObject():GetMeshConvexes()
				expect(#Convexes).to.equal(1)
				expect(#Convexes[1]).to.equal(36)

				local Min, Max = Bounds(Convexes[1])
				for _, Axis in ipairs({ "x", "y", "z" }) do
					expect(Near(Min[Axis], -E)).to.beTrue()
					expect(Near(Max[Axis], E)).to.beTrue()
				end
			end,

			cleanup = function(State)
				SafeRemoveEntity(State.Cube)
			end
		},

		{
			name = "Keeps the whole mesh when the plane misses it",
			func = function()
				local Result = ImprovedClipping.ClipTriangles(CubeVertices(), Vector(1, 0, 0), -100)

				expect(#Result).to.equal(36)
			end
		},

		{
			name = "Returns nothing when the plane cuts the whole mesh away",
			func = function()
				local Result = ImprovedClipping.ClipTriangles(CubeVertices(), Vector(1, 0, 0), 100)

				expect(#Result).to.equal(0)
			end
		},

		{
			name = "Keeps only the geometry on the normal's side",
			func = function()
				local Result = ImprovedClipping.ClipTriangles(CubeVertices(), Vector(1, 0, 0), 0)

				expect(#Result > 0).to.beTrue()
				expect(#Result % 3).to.equal(0)

				local Min, Max = Bounds(Result)
				expect(Near(Min.x, 0)).to.beTrue()
				expect(Near(Max.x, E)).to.beTrue()
				expect(Near(Min.y, -E)).to.beTrue()
				expect(Near(Max.y, E)).to.beTrue()
				expect(Near(Min.z, -E)).to.beTrue()
				expect(Near(Max.z, E)).to.beTrue()
			end
		},

		{
			name = "Flipping the normal keeps the opposite half",
			func = function()
				local Result = ImprovedClipping.ClipTriangles(CubeVertices(), Vector(-1, 0, 0), 0)

				local Min, Max = Bounds(Result)
				expect(Near(Min.x, -E)).to.beTrue()
				expect(Near(Max.x, 0)).to.beTrue()
			end
		},

		{
			name = "Cuts on an angled plane",
			func = function()
				local Normal = Vector(1, 1, 0)
				Normal:Normalize()

				local Result = ImprovedClipping.ClipTriangles(CubeVertices(), Normal, 0)
				expect(#Result > 0).to.beTrue()

				for _, Pos in ipairs(Result) do
					expect(Normal:Dot(Pos) >= -0.01).to.beTrue()
				end
			end
		},

		{
			name = "Leaves the cut open when not capping",
			func = function()
				-- An open half cube: 2 triangles per untouched face, 2 per cut face, none on the hole
				local Result = ImprovedClipping.ClipTriangles(CubeVertices(), Vector(1, 0, 0), 0)

				local OnPlane = 0
				for _, Pos in ipairs(Result) do
					if math.abs(Pos.x) < 0.01 then OnPlane = OnPlane + 1 end
				end

				-- Only the vertices the cut created sit on the plane, never a whole triangle
				for i = 1, #Result - 2, 3 do
					local Count = 0
					for j = i, i + 2 do
						if math.abs(Result[j].x) < 0.01 then Count = Count + 1 end
					end

					expect(Count < 3).to.beTrue()
				end

				expect(OnPlane > 0).to.beTrue()
			end
		},

		{
			name = "Caps the hole with triangles lying on the plane",
			func = function()
				local Meshes = util.GetModelMeshes("models/hunter/blocks/cube1x1x1.mdl")
				expect(Meshes).to.exist()

				local Vertices = Meshes[1].triangles
				local Result = ImprovedClipping.ClipTriangles(Vertices, Vector(1, 0, 0), 0, true, true)

				expect(#Result > 0).to.beTrue()
				expect(#Result % 3).to.equal(0)

				local Cap = 0
				for i = 1, #Result - 2, 3 do
					local OnPlane = 0
					for j = i, i + 2 do
						if math.abs(Result[j].pos.x) < 0.01 then OnPlane = OnPlane + 1 end
					end

					if OnPlane == 3 then Cap = Cap + 1 end
				end

				-- The square hole fans into two triangles
				expect(Cap).to.equal(2)
			end
		},

		{
			name = "Cap vertices face away from the clip normal and carry a tangent",
			func = function()
				local Vertices = util.GetModelMeshes("models/hunter/blocks/cube1x1x1.mdl")[1].triangles
				local Result = ImprovedClipping.ClipTriangles(Vertices, Vector(1, 0, 0), 0, true, true)

				for _, Vertex in ipairs(Result) do
					if math.abs(Vertex.pos.x) < 0.01 and math.abs(Vertex.normal.x) > 0.5 then
						expect(Near(Vertex.normal.x, -1)).to.beTrue()
						expect(Vertex.userdata).to.exist()
						expect(#Vertex.userdata).to.equal(4)
					end
				end
			end
		},

		{
			name = "Interpolates texture coordinates across the cut",
			func = function()
				local Vertices = util.GetModelMeshes("models/hunter/blocks/cube1x1x1.mdl")[1].triangles
				local Result = ImprovedClipping.ClipTriangles(Vertices, Vector(1, 0, 0), 0, true, false)

				for _, Vertex in ipairs(Result) do
					expect(Vertex.u).to.beA("number")
					expect(Vertex.v).to.beA("number")
					expect(Vertex.u == Vertex.u).to.beTrue() -- Not NaN
					expect(Vertex.v == Vertex.v).to.beTrue()
				end
			end
		},

		{
			name = "Measures the texel density of the source mesh",
			func = function()
				local Vertices = util.GetModelMeshes("models/hunter/blocks/cube1x1x1.mdl")[1].triangles
				local Density = ImprovedClipping.TexelDensity(Vertices)

				expect(Density > 0).to.beTrue()
			end
		},
	}
}
