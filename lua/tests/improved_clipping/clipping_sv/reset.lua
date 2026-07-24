local E = 23.725

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

local function IsFullCube(Ent)
	local Min, Max = PhysBounds(Ent)

	for _, Axis in ipairs({ "x", "y", "z" }) do
		if not Near(Min[Axis], -E) or not Near(Max[Axis], E) then return false end
	end

	return true
end

return {
	groupName = "ImprovedClipping.RemoveClips and Reset",

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
	end,

	cases = {
		{
			name = "Removes a single clip by ID and rebuilds without it",
			func = function(State)
				local Cube = State.Cube
				local IDs = ImprovedClipping.AddClips(Cube,
					{ Vector(1, 0, 0), Vector(0, 1, 0) },
					{ 0, 0 })

				expect(ImprovedClipping.RemoveClips(Cube, { IDs[1] })).to.beTrue()

				local Clips = ImprovedClipping.GetClips(Cube)
				expect(#Clips).to.equal(1)
				expect(Clips[1].ID).to.equal(IDs[2])

				local Min = PhysBounds(Cube)
				expect(Near(Min.x, -E)).to.beTrue() -- The +X clip is gone
				expect(Near(Min.y, 0)).to.beTrue()  -- The +Y clip stayed
			end
		},

		{
			name = "Removing the last clip restores the original mesh",
			func = function(State)
				local Cube = State.Cube
				local IDs = ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })

				expect(ImprovedClipping.RemoveClips(Cube, IDs)).to.beTrue()

				expect(IsFullCube(Cube)).to.beTrue()
				expect(Cube.ImprovedClipping).to.beNil()
			end
		},

		{
			name = "Returns false for IDs that are not on the entity",
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })

				expect(ImprovedClipping.RemoveClips(Cube, { 99 })).to.beFalse()
				expect(#ImprovedClipping.GetClips(Cube)).to.equal(1)
			end
		},

		{
			name = "Returns false for an entity that was never clipped",
			func = function(State)
				expect(ImprovedClipping.RemoveClips(State.Cube, { 1 })).to.beFalse()
			end
		},

		{
			name = "Reset restores the original mesh and mass",
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0), Vector(0, 1, 0) }, { 0, 0 }, { false, false })

				expect(Cube:GetPhysicsObject():GetMass() < State.Mass).to.beTrue()
				expect(ImprovedClipping.Reset(Cube)).to.beTrue()

				expect(IsFullCube(Cube)).to.beTrue()
				expect(Near(Cube:GetPhysicsObject():GetMass(), State.Mass, 0.5)).to.beTrue()
			end
		},

		{
			name = "Reset clears the state, the tracking table and the duplicator modifier",
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })

				ImprovedClipping.Reset(Cube)

				expect(Cube.ImprovedClipping).to.beNil()
				expect(ImprovedClipping.ClippedEntities[Cube]).to.beNil()
				expect(Cube.EntityMods and Cube.EntityMods.improved_clipping or nil).to.beNil()
			end
		},

		{
			name = "Reset on an unclipped entity succeeds and changes nothing",
			func = function(State)
				expect(ImprovedClipping.Reset(State.Cube)).to.beTrue()

				expect(IsFullCube(State.Cube)).to.beTrue()
			end
		},

		{
			name = "Clipping again after a reset starts from the original mesh",
			func = function(State)
				local Cube = State.Cube

				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })
				ImprovedClipping.Reset(Cube)

				local IDs = ImprovedClipping.AddClips(Cube, { Vector(-1, 0, 0) }, { 0 })
				expect(#IDs).to.equal(1)
				expect(IDs[1]).to.equal(1) -- IDs start over with the state

				local Min, Max = PhysBounds(Cube)
				expect(Near(Min.x, -E)).to.beTrue()
				expect(Near(Max.x, 0)).to.beTrue()
			end
		},

		{
			name = "Removing the entity drops it from the tracking table",
			async = true,
			timeout = 5,
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })

				Cube:Remove()

				-- Remove() only marks the entity for deletion; the callback fires when the
				-- engine actually deletes it, a frame or more later
				timer.Simple(0.25, function()
					expect(ImprovedClipping.ClippedEntities[Cube]).to.beNil()

					done()
				end)
			end
		},

		{
			name = "Runs the ClipsChanged hook on reset",
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })

				local Called = stub()
				hook.Add("ImprovedClipping_ClipsChanged", "improved_clipping_test", Called)

				ImprovedClipping.Reset(Cube)

				expect(Called).was.called()
			end,

			cleanup = function()
				hook.Remove("ImprovedClipping_ClipsChanged", "improved_clipping_test")
			end
		},
	}
}
