-- Draws the clipping tool's client-side overlays: physics convexes, existing clip planes, and the
-- pending plane preview. Returns the draw function; the caller resolves the clip target/tool state
-- and is responsible for hooking it up.
return function()
	local EdgeColor = Color(255, 255, 255, 255)

	local ConvexColors = {
		Color(0, 255, 0),
		Color(0, 0, 255),
		Color(255, 255, 0),
		Color(255, 0, 255),
		Color(0, 255, 255),
	}

	local function ConvexColor(Index)
		local Col = ConvexColors[(Index - 1) % #ConvexColors + 1]
		return Color(Col.r, Col.g, Col.b, 60)
	end

	-- The physics convex decomposition can differ from the render mesh, so draw it directly
	local function DrawConvexes(Entity)
		local PhysObj = Entity:GetPhysicsObject()
		if not IsValid(PhysObj) then return end

		local Convexes = PhysObj:GetMeshConvexes()
		if not Convexes then return end

		render.SetColorMaterial()

		for Index, Convex in ipairs(Convexes) do
			local Col = ConvexColor(Index)

			for i = 1, #Convex - 2, 3 do
				local A = PhysObj:LocalToWorld(Convex[i].pos)
				local B = PhysObj:LocalToWorld(Convex[i + 1].pos)
				local C = PhysObj:LocalToWorld(Convex[i + 2].pos)

				render.DrawQuad(A, B, C, C, Col)

				render.DrawLine(A, B, EdgeColor, true)
				render.DrawLine(B, C, EdgeColor, true)
				render.DrawLine(C, A, EdgeColor, true)
			end
		end
	end

	local ClipPlaneColor = Color(0, 200, 255, 60)

	-- Draws each already-applied clip as a translucent quad on its plane
	local function DrawClipPlanes(Entity)
		local Clips = ImprovedClipping.GetClips(Entity)
		if not Clips[1] then return end

		local Radius = Entity:BoundingRadius()
		local Size = Radius * 2

		for _, Clip in ipairs(Clips) do
			local LocalCenter = Clip.Normal * Clip.Distance
			local Center = Entity:LocalToWorld(LocalCenter)
			local Normal = -(Entity:LocalToWorld(LocalCenter + Clip.Normal) - Center):GetNormalized()

			render.DrawQuadEasy(Center, Normal, Size, Size, ClipPlaneColor)
			render.DrawQuadEasy(Center, -Normal, Size, Size, ClipPlaneColor)
		end
	end

	local OverlayMaterial = Material("models/debug/debugwhite")

	-- Draws Target split by the plane at Distance along Normal: kept side red, cut side green
	local function DrawPossibleClipPlane(Target, Normal, Distance, Offset)
		local WasClippingEnabled = render.EnableClipping(true)
		render.MaterialOverride(OverlayMaterial)

		render.PushCustomClipPlane(Normal, Distance - Offset)
		render.SetColorModulation(1, 0, 0)
		Target:DrawModel()
		render.PopCustomClipPlane()

		render.PushCustomClipPlane(-Normal, -Distance + Offset)
		render.SetColorModulation(0, 1, 0)
		Target:DrawModel()
		render.PopCustomClipPlane()

		render.MaterialOverride(nil)
		render.EnableClipping(WasClippingEnabled)
	end

	-- Hides the real entity while we draw its clipped preview in its place
	local HiddenEntity

	-- Draws the clip proxy/model preview and hides the real entity behind it, if a valid target is aimed at.
	-- Entity is the real clip target; Target is what to draw/hide in its place (Entity or its clip proxy).
	-- Normal/Offset are expected already inverted for the player's alt-invert state.
	local function DrawOverlay(Entity, Target, Shift, Normal, Pos, Offset)
		if IsValid(HiddenEntity) and HiddenEntity ~= Target then
			HiddenEntity:SetNoDraw(false)
			HiddenEntity = nil
		end

		if not Entity then return end
		if not Shift and (not Normal or not Pos) then return end

		Target:SetNoDraw(true)
		HiddenEntity = Target

		local PhysObj = Entity:GetPhysicsObject()
		if IsValid(PhysObj) then
			PhysObj:SetPos(Entity:GetPos())
			PhysObj:SetAngles(Entity:GetAngles())
		end

		if Shift then
			DrawConvexes(Entity)
			DrawClipPlanes(Entity)
		else
			local Distance = Normal:Dot(Pos)

			DrawPossibleClipPlane(Target, Normal, Distance, Offset)
		end
	end

	return DrawOverlay
end
