ImprovedClipping = ImprovedClipping or {}

util.AddNetworkString("improved_clipping")
util.AddNetworkString("improved_clipping_notify")

-- Shows a notification.AddLegacy popup on the given player's client
local function SendNotify(Player, Text, NotifyType)
	if not IsValid(Player) then return end

	net.Start("improved_clipping_notify")
	net.WriteUInt(NotifyType, 3)
	net.WriteString(Text)
	net.Send(Player)
end

-- NOTIFY_GENERIC/NOTIFY_ERROR are client-only globals; this runs serverside, so use their values directly
function ImprovedClipping.Notify(Player, Text) SendNotify(Player, Text, 0) end
function ImprovedClipping.Warn(Player, Text) SendNotify(Player, Text, 1) end

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
		net.WriteBool(Clip.Inside)
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

-- Saves the clips in the old addons' formats too so dupes from here load on their servers, both of them because Proper Clipping compares the two and errors when either is missing
local function StoreCompatModifiers(Ent, State)
	-- Measured from the center the entity had before we clipped it, which is the one the loading addon sees on a freshly spawned prop
	local Center = State.OriginalOBBCenter
	local Proper, Legacy = {}, {}

	for i, Clip in ipairs(State.Clips) do
		-- Measured from the origin with the normal already negated, our convention exactly, and every clip of ours is physical
		Proper[i] = { Vector(Clip.Normal), Clip.Distance, Clip.Inside, true }

		-- The older tools store an angle and an OBB center offset, measured off the rebuilt normal so their comparison stays exact
		local Ang = Clip.Normal:Angle()

		Legacy[i] = {
			n = Ang,
			d = Clip.Distance - Ang:Forward():Dot(Center),
			inside = Clip.Inside,
			new = true,
		}
	end

	-- StoreEntityModifier merges into what is already there, so a shorter list would keep the old tail
	duplicator.ClearEntityModifier(Ent, "proper_clipping")
	duplicator.ClearEntityModifier(Ent, "clips")

	duplicator.StoreEntityModifier(Ent, "proper_clipping", Proper)
	duplicator.StoreEntityModifier(Ent, "clips", Legacy)
end

-- Stores the clips for the duplicator and networks them, batched per entity
function ImprovedClipping.Sync(Ent)
	timer.Create("improved_clipping_net_" .. Ent:EntIndex(), 0.1, 1, function()
		if not IsValid(Ent) then return end

		local State = Ent.ImprovedClipping

		if State then
			local Normals, Distances, Seals, Insides = {}, {}, {}, {}
			for i, Clip in ipairs(State.Clips) do
				Normals[i] = Clip.Normal
				Distances[i] = Clip.Distance
				Seals[i] = Clip.Seal
				Insides[i] = Clip.Inside
			end

			-- Cleared first for the same reason as in StoreCompatModifiers above
			duplicator.ClearEntityModifier(Ent, "improved_clipping")

			duplicator.StoreEntityModifier(Ent, "improved_clipping", {
				Normals = Normals,
				Distances = Distances,
				Seals = Seals,
				Insides = Insides,
			})

			StoreCompatModifiers(Ent, State)
		end

		SendClips(Ent)
	end)
end

duplicator.RegisterEntityModifier("improved_clipping", function(Player, Ent, Data)
	if not IsValid(Ent) then return end

	if not hook.Run("CanTool", Player, { Entity = Ent }, "improved_clipping") then
		Player:ChatPrint(tostring(Ent) .. " will be spawned without clips (not allowed to clip).")
		duplicator.ClearEntityModifier(Ent, "improved_clipping")
		duplicator.ClearEntityModifier(Ent, "proper_clipping")
		duplicator.ClearEntityModifier(Ent, "clips")

		return
	end

	if not IsValid(Ent) then return end

	ImprovedClipping.AddClips(Ent, Data.Normals, Data.Distances, Data.Seals, Data.Insides)
end)

-- After pasting, AdvDupe2 replaces the physics of parented, unconstrained entities
-- with a shadow of the original model (PhysicsInitShadow in sv_clipboard.lua), wiping
-- the clipped vcollide the modifier above built. Once the paste is done, rebuild those
-- entities so the clipped physics takes over from the shadow.
hook.Add("AdvDupe_FinishPasting", "improved_clipping", function(Data)
	if not istable(Data) or not istable(Data[1]) or not istable(Data[1].CreatedEntities) then return end

	local Ents = {}
	for _, Ent in pairs(Data[1].CreatedEntities) do
		Ents[#Ents + 1] = Ent
	end

	timer.Simple(0, function()
		for _, Ent in ipairs(Ents) do
			if IsValid(Ent) and Ent.ImprovedClipping and not Ent.ImprovedClippingExternalMesh and IsValid(Ent:GetParent()) then
				local PhysObj = Ent:GetPhysicsObject()
				local Mass = IsValid(PhysObj) and PhysObj:GetMass() or nil

				ImprovedClipping.RebuildPhysics(Ent)

				PhysObj = Ent:GetPhysicsObject()
				if IsValid(PhysObj) and Mass then
					PhysObj:SetMass(Mass)
				end
			end
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
