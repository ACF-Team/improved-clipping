-- Draws the clipping tool's client-side overlays: physics convexes, existing clip planes, and the
-- pending plane preview. Takes GetClippingTarget as an explicit dependency since locals from the
-- main stool file (where the matching tool state lives) aren't visible across include() boundaries.
return function(GetClippingTarget)
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

	hook.Add("PostDrawTranslucentRenderables", "ImprovedClipping_Overlay", function(bDrawingDepth, bDrawingSkybox)
		if bDrawingDepth or bDrawingSkybox then return end

		local Player = LocalPlayer()
		local Trace = Player:GetEyeTrace()
		local Entity = GetClippingTarget(Player, Trace)

		-- Draw the clip proxy if it exists, so existing clips show; else the model
		local Proxy = IsValid(Entity) and ImprovedClipping.GetProxy(Entity)
		local Target = IsValid(Proxy) and Proxy or Entity

		if IsValid(HiddenEntity) and HiddenEntity ~= Target then
			HiddenEntity:SetNoDraw(false)
			HiddenEntity = nil
		end

		if not Entity then return end

		local Shift = Player:KeyDown(IN_SPEED)

		local Tool = Player:GetTool("improved_clipping")
		local Normal = Tool and Tool.Normal
		local Pos = Tool and Tool.Pos
		if not Shift and (not Normal or not Pos) then return end

		Target:SetNoDraw(true)
		HiddenEntity = Target

		-- Shift: show convexes and clip planes instead of the plane preview
		if Shift then
			DrawConvexes(Entity)
			DrawClipPlanes(Entity)

			return
		end

		local Invert = Player:KeyDown(IN_WALK) and -1 or 1
		local Offset = Tool:GetClientNumber("offset") * Invert
		local Distance = Normal:Dot(Pos) * Invert

		DrawPossibleClipPlane(Target, Normal * Invert, Distance, Offset)
	end)
end
