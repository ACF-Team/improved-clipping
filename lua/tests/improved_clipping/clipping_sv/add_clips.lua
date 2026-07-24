local E = 23.725 -- Half extent of models/hunter/blocks/cube1x1x1.mdl's physmesh

local function PhysBounds(Ent)
	local Min = Vector(math.huge, math.huge, math.huge)
	local Max = Vector(-math.huge, -math.huge, -math.huge)

	for _, Convex in ipairs(Ent:GetPhysicsObject():GetMeshConvexes()) do
		for _, Vertex in ipairs(Convex) do
			local Pos = Vertex.pos

			Min.x = math.min(Min.x, Pos.x)
			Min.y = math.min(Min.y, Pos.y)
			Min.z = math.min(Min.z, Pos.z)
			Max.x = math.max(Max.x, Pos.x)
			Max.y = math.max(Max.y, Pos.y)
			Max.z = math.max(Max.z, Pos.z)
		end
	end

	return Min, Max
end

-- GLuaTest only puts expect() in the case function's environment, so helpers up here
-- report booleans and the cases do the asserting
local function Near(Actual, Expected, Tolerance)
	return math.abs(Actual - Expected) <= (Tolerance or 0.1)
end

return {
	groupName = "ImprovedClipping.AddClips",

	beforeEach = function(State)
		State.Cube = ents.Create("prop_physics")

		local Cube = State.Cube
		Cube:SetModel("models/hunter/blocks/cube1x1x1.mdl")
		Cube:SetPos(Vector(0, 0, 0))
		Cube:Spawn()

		State.Mass = Cube:GetPhysicsObject():GetMass()
	end,

	afterEach = function(State)
		SafeRemoveEntity(State.Cube)
		GetConVar("improved_clipping_max_clips"):SetInt(8)
	end,

	cases = {
		{
			name = "Returns the new clip's ID and stores it",
			func = function(State)
				local IDs = ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 })

				expect(#IDs).to.equal(1)
				expect(IDs[1]).to.equal(1)

				local Clips = ImprovedClipping.GetClips(State.Cube)
				expect(#Clips).to.equal(1)
				expect(Clips[1].Distance).to.equal(0)
				expect(Clips[1].Normal).to.equal(Vector(1, 0, 0))
			end
		},

		{
			name = "Rebuilds the physics mesh to the kept half",
			func = function(State)
				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 })

				local Min, Max = PhysBounds(State.Cube)
				expect(Near(Min.x, 0)).to.beTrue()
				expect(Near(Max.x, E)).to.beTrue()
				expect(Near(Min.y, -E)).to.beTrue()
				expect(Near(Max.y, E)).to.beTrue()
			end
		},

		{
			name = "Applies several clips in one rebuild",
			func = function(State)
				local IDs = ImprovedClipping.AddClips(State.Cube,
					{ Vector(1, 0, 0), Vector(0, 1, 0) },
					{ 0, 0 })

				expect(#IDs).to.equal(2)
				expect(IDs[2]).to.equal(2)

				local Min = PhysBounds(State.Cube)
				expect(Near(Min.x, 0)).to.beTrue()
				expect(Near(Min.y, 0)).to.beTrue()
			end
		},

		{
			name = "Keeps counting IDs up across calls",
			func = function(State)
				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 })
				local IDs = ImprovedClipping.AddClips(State.Cube, { Vector(0, 1, 0) }, { 0 })

				expect(IDs[1]).to.equal(2)
			end
		},

		{
			name = "Refuses to clip the entire mesh away",
			func = function(State)
				local IDs = ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 100 })

				expect(#IDs).to.equal(0)
				expect(#ImprovedClipping.GetClips(State.Cube)).to.equal(0)

				local Min, Max = PhysBounds(State.Cube)
				expect(Near(Min.x, -E)).to.beTrue()
				expect(Near(Max.x, E)).to.beTrue()
			end
		},

		{
			name = "Leaves earlier clips alone when a later one fails",
			func = function(State)
				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 })
				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 100 })

				expect(#ImprovedClipping.GetClips(State.Cube)).to.equal(1)

				local Min = PhysBounds(State.Cube)
				expect(Near(Min.x, 0)).to.beTrue()
			end
		},

		{
			name = "Tracks the entity as clipped",
			func = function(State)
				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 })

				expect(ImprovedClipping.ClippedEntities[State.Cube]).to.beTrue()
			end
		},

		{
			name = "Stops adding clips at the convar limit",
			func = function(State)
				GetConVar("improved_clipping_max_clips"):SetInt(2)

				local IDs = ImprovedClipping.AddClips(State.Cube,
					{ Vector(1, 0, 0), Vector(0, 1, 0), Vector(0, 0, 1) },
					{ 0, 0, 0 })

				expect(#IDs).to.equal(2)
				expect(ImprovedClipping.ClipsLeft(State.Cube)).to.equal(0)
			end
		},

		{
			name = "Adds nothing once the limit is reached",
			func = function(State)
				GetConVar("improved_clipping_max_clips"):SetInt(1)

				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 })
				local IDs = ImprovedClipping.AddClips(State.Cube, { Vector(0, 1, 0) }, { 0 })

				expect(#IDs).to.equal(0)
				expect(#ImprovedClipping.GetClips(State.Cube)).to.equal(1)
			end
		},

		{
			name = "Keeps the mass by default",
			func = function(State)
				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 })

				expect(Near(State.Cube:GetPhysicsObject():GetMass(), State.Mass, 0.5)).to.beTrue()
			end
		},

		{
			name = "Scales the mass with the remaining volume when asked",
			func = function(State)
				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 }, { false })

				local Mass = State.Cube:GetPhysicsObject():GetMass()
				expect(Mass < State.Mass).to.beTrue()
				expect(Near(Mass, State.Mass * 0.5, State.Mass * 0.1)).to.beTrue()
			end
		},

		{
			name = "Defaults Seal to false and stores it when set",
			func = function(State)
				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 })
				expect(ImprovedClipping.GetClips(State.Cube)[1].Seal).to.beFalse()

				ImprovedClipping.AddClips(State.Cube, { Vector(0, 1, 0) }, { 0 }, nil, { true })
				expect(ImprovedClipping.GetClips(State.Cube)[2].Seal).to.beTrue()
			end
		},

		{
			name = "Does nothing for an invalid entity",
			func = function()
				local IDs = ImprovedClipping.AddClips(NULL, { Vector(1, 0, 0) }, { 0 })

				expect(#IDs).to.equal(0)
			end
		},

		{
			name = "Runs the ClipsChanged hook",
			func = function(State)
				local Called = stub()
				hook.Add("ImprovedClipping_ClipsChanged", "improved_clipping_test", Called)

				ImprovedClipping.AddClips(State.Cube, { Vector(1, 0, 0) }, { 0 })

				expect(Called).was.called()
			end,

			cleanup = function()
				hook.Remove("ImprovedClipping_ClipsChanged", "improved_clipping_test")
			end
		},
	}
}
