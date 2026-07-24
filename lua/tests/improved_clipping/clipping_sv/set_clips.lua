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

local function Clip(ID, Normal, Distance, KeepMass, Seal)
	return {
		ID = ID,
		Normal = Normal,
		Distance = Distance,
		KeepMass = KeepMass ~= false,
		Seal = Seal == true,
	}
end

return {
	groupName = "ImprovedClipping.SetClips",

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
			name = "Replaces the clip list wholesale",
			func = function(State)
				local Cube = State.Cube

				expect(ImprovedClipping.SetClips(Cube, { Clip(1, Vector(1, 0, 0), 0) })).to.beTrue()
				expect(ImprovedClipping.SetClips(Cube, { Clip(1, Vector(0, 1, 0), 0) })).to.beTrue()

				local Clips = ImprovedClipping.GetClips(Cube)
				expect(#Clips).to.equal(1)
				expect(Clips[1].Normal).to.equal(Vector(0, 1, 0))
			end
		},

		{
			name = "Rebuilds from the original mesh, not the already clipped one",
			func = function(State)
				local Cube = State.Cube

				-- Keeps +X, then replaces that with a clip keeping -X. Rebuilding off the
				-- clipped mesh instead of the original would leave nothing to keep.
				ImprovedClipping.SetClips(Cube, { Clip(1, Vector(1, 0, 0), 0) })
				expect(ImprovedClipping.SetClips(Cube, { Clip(1, Vector(-1, 0, 0), 0) })).to.beTrue()

				local Min, Max = PhysBounds(Cube)
				expect(Near(Min.x, -E)).to.beTrue()
				expect(Near(Max.x, 0)).to.beTrue()
			end
		},

		{
			name = "Reverts the clip list when the rebuild fails",
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.SetClips(Cube, { Clip(1, Vector(1, 0, 0), 0) })

				local Fail = ImprovedClipping.SetClips(Cube, {
					Clip(1, Vector(1, 0, 0), 0),
					Clip(2, Vector(-1, 0, 0), 100),
				})

				expect(Fail).to.beFalse()

				local Clips = ImprovedClipping.GetClips(Cube)
				expect(#Clips).to.equal(1)
				expect(Clips[1].ID).to.equal(1)

				local Min = PhysBounds(Cube)
				expect(Near(Min.x, 0)).to.beTrue()
			end
		},

		{
			name = "Continues IDs from the highest one set",
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.SetClips(Cube, { Clip(7, Vector(1, 0, 0), 0) })

				local IDs = ImprovedClipping.AddClips(Cube, { Vector(0, 1, 0) }, { 0 })
				expect(IDs[1]).to.equal(8)
			end
		},

		{
			name = "GetClips hands back a copy",
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.SetClips(Cube, { Clip(1, Vector(1, 0, 0), 0) })

				local Clips = ImprovedClipping.GetClips(Cube)
				Clips[1].Distance = 999
				Clips[1].Normal.x = 999
				Clips[2] = Clip(2, Vector(0, 1, 0), 0)

				local Fresh = ImprovedClipping.GetClips(Cube)
				expect(#Fresh).to.equal(1)
				expect(Fresh[1].Distance).to.equal(0)
				expect(Fresh[1].Normal).to.equal(Vector(1, 0, 0))
			end
		},

		{
			name = "ClipsLeft counts down from the convar",
			func = function(State)
				local Cube = State.Cube
				local Max = GetConVar("improved_clipping_max_clips"):GetInt()

				expect(ImprovedClipping.ClipsLeft(Cube)).to.equal(Max)

				ImprovedClipping.SetClips(Cube, { Clip(1, Vector(1, 0, 0), 0) })
				expect(ImprovedClipping.ClipsLeft(Cube)).to.equal(Max - 1)
			end
		},

		{
			name = "Does nothing for an invalid entity",
			func = function()
				expect(ImprovedClipping.SetClips(NULL, { Clip(1, Vector(1, 0, 0), 0) })).to.beFalse()
			end
		},
	}
}
