local E = 23.725

-- ImprovedClipping.Sync batches the duplicator modifier behind a 0.1s timer, so the dupe
-- tests have to wait it out before copying
local SyncDelay = 0.2

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

local function SpawnCube(Pos)
	local Cube = ents.Create("prop_physics")
	Cube:SetModel("models/hunter/blocks/cube1x1x1.mdl")
	Cube:SetPos(Pos or Vector(0, 0, 0))
	Cube:Spawn()

	return Cube
end

-- Copies the entity through the duplicator and returns the pasted copy
local function Paste(Ent, State, Player)
	-- duplicator.Copy hands back { Entities, Constraints, Mins, Maxs }, not the entity list
	local Data = duplicator.Copy(Ent)
	local Pasted = duplicator.Paste(Player, Data.Entities, Data.Constraints)
	local Copy

	for _, New in pairs(Pasted) do
		State.Spawned[#State.Spawned + 1] = New
		Copy = Copy or New
	end

	return Copy
end

return {
	groupName = "ImprovedClipping duplication",

	beforeEach = function(State)
		State.Spawned = {}

		State.Cube = SpawnCube()
		State.Spawned[1] = State.Cube
		State.Mass = State.Cube:GetPhysicsObject():GetMass()

		-- The duplicator modifier gates on CanTool; keep it out of the gamemode's hands
		hook.Add("CanTool", "improved_clipping_test", function() return true end)
	end,

	afterEach = function(State)
		hook.Remove("CanTool", "improved_clipping_test")

		for _, Ent in ipairs(State.Spawned) do
			SafeRemoveEntity(Ent)
		end
	end,

	cases = {
		{
			name = "Stores the clips on the entity's duplicator modifier",
			async = true,
			timeout = 5,
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0), Vector(0, 1, 0) }, { 0, 10 }, { true, false }, { false, true })

				timer.Simple(SyncDelay, function()
					local Data = Cube.EntityMods and Cube.EntityMods.improved_clipping
					expect(Data).to.exist()

					expect(#Data.Normals).to.equal(2)
					expect(Data.Normals[1]).to.equal(Vector(1, 0, 0))
					expect(Data.Distances[2]).to.equal(10)
					expect(Data.KeepMasses[1]).to.beTrue()
					expect(Data.KeepMasses[2]).to.beFalse()
					expect(Data.Seals[2]).to.beTrue()
					expect(Data.OriginalMass).to.equal(State.Mass)
					expect(Data.Mass).to.equal(Cube:GetPhysicsObject():GetMass())

					done()
				end)
			end
		},

		{
			name = "A pasted copy comes back with the same clips",
			async = true,
			timeout = 5,
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })

				timer.Simple(SyncDelay, function()
					local Copy = Paste(Cube, State)
					expect(IsValid(Copy)).to.beTrue()

					local Clips = ImprovedClipping.GetClips(Copy)
					expect(#Clips).to.equal(1)
					expect(Clips[1].Normal).to.equal(Vector(1, 0, 0))
					expect(Clips[1].Distance).to.equal(0)

					done()
				end)
			end
		},

		{
			name = "A pasted copy comes back with the clipped physics mesh",
			async = true,
			timeout = 5,
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })

				timer.Simple(SyncDelay, function()
					local Copy = Paste(Cube, State)

					local Min, Max = PhysBounds(Copy)
					expect(Near(Min.x, 0)).to.beTrue()
					expect(Near(Max.x, E)).to.beTrue()
					expect(Near(Min.y, -E)).to.beTrue()

					done()
				end)
			end
		},

		{
			name = "A pasted copy keeps the clipped mass and can be reset to the original",
			async = true,
			timeout = 5,
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 }, { false })

				local Clipped = Cube:GetPhysicsObject():GetMass()

				timer.Simple(SyncDelay, function()
					local Copy = Paste(Cube, State)
					expect(Near(Copy:GetPhysicsObject():GetMass(), Clipped, 0.5)).to.beTrue()

					-- Reset has to give back the mass the cube had before it was ever clipped
					expect(ImprovedClipping.Reset(Copy)).to.beTrue()
					expect(Near(Copy:GetPhysicsObject():GetMass(), State.Mass, 0.5)).to.beTrue()

					local Min, Max = PhysBounds(Copy)
					expect(Near(Min.x, -E)).to.beTrue()
					expect(Near(Max.x, E)).to.beTrue()

					done()
				end)
			end
		},

		{
			name = "A copy of a reset entity comes back unclipped",
			async = true,
			timeout = 5,
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })
				ImprovedClipping.Reset(Cube)

				timer.Simple(SyncDelay, function()
					local Copy = Paste(Cube, State)

					expect(Copy.ImprovedClipping).to.beNil()
					expect(#ImprovedClipping.GetClips(Copy)).to.equal(0)

					local Min, Max = PhysBounds(Copy)
					expect(Near(Min.x, -E)).to.beTrue()
					expect(Near(Max.x, E)).to.beTrue()

					done()
				end)
			end
		},

		{
			name = "Pasting without tool permission spawns the copy unclipped",
			async = true,
			timeout = 5,
			func = function(State)
				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })

				timer.Simple(SyncDelay, function()
					hook.Add("CanTool", "improved_clipping_test", function() return false end)

					-- The modifier chats at the pasting player when it refuses
					local Player = { ChatPrint = stub() }
					local Copy = Paste(Cube, State, Player)

					expect(Player.ChatPrint).was.called()
					expect(#ImprovedClipping.GetClips(Copy)).to.equal(0)

					local Min, Max = PhysBounds(Copy)
					expect(Near(Min.x, -E)).to.beTrue()
					expect(Near(Max.x, E)).to.beTrue()

					done()
				end)
			end
		},

		{
			name = "AdvDupe_FinishPasting rebuilds parented entities whose physics were replaced",
			async = true,
			timeout = 5,
			func = function(State)
				local Parent = SpawnCube(Vector(0, 0, 200))
				State.Spawned[#State.Spawned + 1] = Parent

				local Cube = State.Cube
				ImprovedClipping.AddClips(Cube, { Vector(1, 0, 0) }, { 0 })
				Cube:SetParent(Parent)

				-- What AdvDupe2 does to parented, unconstrained entities after a paste:
				-- the clipped vcollide is replaced by a shadow of the original model
				Cube:PhysicsInitShadow(false, false)
				Cube:GetPhysicsObject():SetMass(State.Mass)

				local Min = PhysBounds(Cube)
				expect(Near(Min.x, -E)).to.beTrue() -- The clip is gone from the mesh

				hook.Run("AdvDupe_FinishPasting", { { CreatedEntities = { Cube } } })

				timer.Simple(0.1, function()
					local NewMin, NewMax = PhysBounds(Cube)
					expect(Near(NewMin.x, 0)).to.beTrue()
					expect(Near(NewMax.x, E)).to.beTrue()

					expect(Near(Cube:GetPhysicsObject():GetMass(), State.Mass, 0.5)).to.beTrue()
					expect(Cube:GetParent()).to.equal(Parent)

					done()
				end)
			end
		},
	}
}
