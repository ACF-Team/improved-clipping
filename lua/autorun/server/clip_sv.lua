ImprovedClipping = ImprovedClipping or {}

util.AddNetworkString("improved_clipping")

-- Sends the entity's full clip list; a count of 0 tells the client to reset
local function SendClips(Ent, Target)
	local State = Ent.ImprovedClipping
	local Clips = State and State.Clips or {}

	net.Start("improved_clipping")
	net.WriteUInt(Ent:EntIndex(), 14)
	net.WriteUInt(#Clips, 4)

	for _, Clip in ipairs(Clips) do
		net.WriteUInt(Clip.ID, 32)
		net.WriteFloat(Clip.Normal.x)
		net.WriteFloat(Clip.Normal.y)
		net.WriteFloat(Clip.Normal.z)
		net.WriteFloat(Clip.Distance)
		net.WriteBool(Clip.Seal)
	end

	net.Send(Target or player.GetHumans())
end

-- Tells clients to drop cached clips for a removed entity's index
function ImprovedClipping.SyncRemoval(Index)
	net.Start("improved_clipping")
	net.WriteUInt(Index, 14)
	net.WriteUInt(0, 4)
	net.Broadcast()
end

-- Stores the clips for the duplicator and networks them, batched per entity
function ImprovedClipping.Sync(Ent)
	timer.Create("improved_clipping_net_" .. Ent:EntIndex(), 0.1, 1, function()
		if not IsValid(Ent) then return end

		local State = Ent.ImprovedClipping

		if State then
			local Normals, Distances, KeepMasses, Seals = {}, {}, {}, {}
			for i, Clip in ipairs(State.Clips) do
				Normals[i] = Clip.Normal
				Distances[i] = Clip.Distance
				KeepMasses[i] = Clip.KeepMass
				Seals[i] = Clip.Seal
			end

			local PhysObj = Ent:GetPhysicsObject()

			duplicator.StoreEntityModifier(Ent, "improved_clipping", {
				Normals = Normals,
				Distances = Distances,
				KeepMasses = KeepMasses,
				Seals = Seals,
				OriginalMass = State.Mass,
				Mass = IsValid(PhysObj) and PhysObj:GetMass() or nil,
			})
		end

		SendClips(Ent)
	end)
end

duplicator.RegisterEntityModifier("improved_clipping", function(Player, Ent, Data)
	if not IsValid(Ent) then return end

	if not hook.Run("CanTool", Player, { Entity = Ent }, "improved_clipping") then
		Player:ChatPrint(tostring(Ent) .. " will be spawned without clips (not allowed to clip).")
		duplicator.ClearEntityModifier(Ent, "improved_clipping")

		return
	end

	-- Wait a tick so the entity's physics object is fully set up before clipping
	timer.Simple(0, function()
		if not IsValid(Ent) then return end

		ImprovedClipping.AddClips(Ent, Data.Normals, Data.Distances, Data.KeepMasses, Data.Seals)

		local State = Ent.ImprovedClipping
		if State and Data.OriginalMass then
			State.Mass = Data.OriginalMass
		end

		local PhysObj = Ent:GetPhysicsObject()
		if IsValid(PhysObj) and Data.Mass then
			PhysObj:SetMass(Data.Mass)
		end
	end)
end)

-- Send all existing clips once the player is fully connected (first unforced SetupMove)
hook.Add("PlayerInitialSpawn", "improved_clipping", function(Player)
	local Hook = "improved_clipping_" .. Player:EntIndex()

	hook.Add("SetupMove", Hook, function(Player2, _, Cmd)
		if not IsValid(Player) then
			hook.Remove("SetupMove", Hook)
			return
		end

		if Player ~= Player2 then return end
		if Cmd:IsForced() then return end

		hook.Remove("SetupMove", Hook)

		for Ent in pairs(ImprovedClipping.ClippedEntities) do
			if IsValid(Ent) then
				SendClips(Ent, Player)
			end
		end
	end)
end)
