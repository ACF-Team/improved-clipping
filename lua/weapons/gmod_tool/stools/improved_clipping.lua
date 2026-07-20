-- https://wiki.facepunch.com/gmod/Structures/TOOL
-- https://wiki.facepunch.com/gmod/Tool_Information_Display
TOOL.Category = "Construction"
TOOL.Name = "#tool.improved_clipping.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.Information = {
	{ name = "left0", stage = 0, op = 0 },
	{ name = "left1", stage = 0, op = 1 },
	{ name = "right0", stage = 0 },
	{ name = "reload0", stage = 0 },
	{ name = "alt", stage = 0 },
	{ name = "shift", stage = 0 },
}

local ConVarDefaults = {
	["keep_mass"]         = "1",
	["seal_holes"]        = "0",
	["add_undo"]          = "1",
	["mode"]              = "0",
	["offset"]            = "0",
}

for Name, Default in pairs(ConVarDefaults) do TOOL.ClientConVar[Name] = Default end

-- The clip plane comes off a trace, and each realm traces separately against its own collision
-- mesh, so the client sends the plane it previewed and the server clips with that.
if SERVER then
	util.AddNetworkString("improved_clipping_plane")

	net.Receive("improved_clipping_plane", function(_, Player)
		local Tool = IsValid(Player) and Player:GetTool("improved_clipping")
		if not Tool then return end

		-- Floats, since net.WriteVector rounds off enough to skew an oblique plane
		local Normal = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
		local Pos = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())

		-- x ~= x is only true for nan
		if Normal:IsZero() or Normal.x ~= Normal.x or Pos.x ~= Pos.x then return end

		Tool.Normal = Normal:GetNormalized()
		Tool.Pos = Pos
	end)
end

-- Returns the entity hit by Trace if Player has the improved clipping tool equipped and active.
local function GetClippingTarget(Player, Trace)
	if not IsValid(Player) then return end

	local Weapon = Player:GetActiveWeapon()
	if not IsValid(Weapon) or Weapon:GetClass() ~= "gmod_tool" then return end

	local Tool = Player:GetTool()
	if not Tool or Tool ~= Player:GetTool("improved_clipping") then return end

	local Entity = Trace and Trace.Entity
	if not IsValid(Entity) or Entity:IsWorld() then return end

	return Entity
end

if CLIENT then
	language.Add("tool.improved_clipping.name", "Improved Clipping")
	language.Add("tool.improved_clipping.desc", "Applies physical clips to props, changing their visuals/geometry")

	language.Add("tool.improved_clipping.left0", "Define clipping planes. Last 2 planes used.")
	language.Add("tool.improved_clipping.left1", "Define clipping plane")

	language.Add("tool.improved_clipping.right0", "Add clip to selected entity")
	language.Add("tool.improved_clipping.reload0", "Clear all clips on selected entity")
	language.Add("tool.improved_clipping.alt", "Hold Alt to invert the clipping plane (cut the other side)")
	language.Add("tool.improved_clipping.shift", "Hold Shift to preview clipped physics convexes and existing clip planes")

	function TOOL.BuildCPanel(Panel)
		local KeepMass = Panel:CheckBox("Keep mass when physics clipping", "improved_clipping_keep_mass")
		KeepMass:SetTooltip("Preserve the entity's original mass after its physics mesh is clipped")

		local SealHoles = Panel:CheckBox("Seal holes (expensive?)", "improved_clipping_seal_holes")
		SealHoles:SetTooltip("Cap the cut surface of new clips so the clipped entity doesn't appear hollow")
		SealHoles:SetTextColor(Color(200, 0, 0))

		local AddUndo = Panel:CheckBox("Add clips to undo list", "improved_clipping_add_undo")
		AddUndo:SetTooltip("Allow clips made with this tool to be reverted with the undo command (Z)")

		local Mode = Panel:ComboBox("Plane Mode", "improved_clipping_mode")
		Mode:SetTooltip("How the clipping plane is determined from your hits")
		Mode:AddChoice("Dual Hitplane Intersection", 0)
		Mode:AddChoice("Single Hitplane", 1)

		local Offset = Panel:NumSlider("Plane Offset", "improved_clipping_offset", -10, 10, 2)
		Offset:SetTooltip("Shifts the clipping plane along its normal by this many units")

		local ResetButton = Panel:Button("Reset Values")
		ResetButton:SetTooltip("Reset all of the above options to their default values")
		function ResetButton:DoClick()
			for Name, Default in pairs(ConVarDefaults) do
				RunConsoleCommand("improved_clipping_" .. Name, Default)
			end
		end
	end

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

-- Runs in both realms so the pending clip plane is available immediately client-side for the preview.
function TOOL:LeftClick(Trace)
	local Entity = GetClippingTarget(self:GetOwner(), Trace)
	if not Entity then return false end

	-- The server takes its plane off the net message instead of tracing for its own
	if SERVER then return true end

	-- Prediction runs this more than once per click, which would advance LastPlane each time
	if not IsFirstTimePredicted() then return true end

	local op = self:GetOperation()
	if op == 0 then
		local Plane1 = { Origin = Trace.HitPos, Normal = Trace.HitNormal }
		local Plane2 = self.LastPlane or Plane1
		self.LastPlane = Plane1

		local LineNormal = Plane1.Normal:Cross(Plane2.Normal)
		local LineLengthSqr = LineNormal:LengthSqr()

		if LineLengthSqr > 1e-10 then -- Planes are not parallel
			self.Normal = LineNormal:Cross(Plane1.Normal + Plane2.Normal):GetNormalized()
			self.Pos = Plane1.Origin + LineNormal:Cross(Plane2.Normal) * Plane2.Normal:Dot(Plane2.Origin - Plane1.Origin) / LineLengthSqr
		else
			self.Normal = Trace.HitNormal
			self.Pos = Trace.HitPos
		end
	elseif op == 1 then
		self.Normal = Trace.HitNormal
		self.Pos = Trace.HitPos
	end

	if not self.Normal or not self.Pos then return true end

	net.Start("improved_clipping_plane")
	net.WriteFloat(self.Normal.x)
	net.WriteFloat(self.Normal.y)
	net.WriteFloat(self.Normal.z)
	net.WriteFloat(self.Pos.x)
	net.WriteFloat(self.Pos.y)
	net.WriteFloat(self.Pos.z)
	net.SendToServer()

	return true
end

function TOOL:RightClick(Trace)
	if CLIENT then return true end

	local Entity = GetClippingTarget(self:GetOwner(), Trace)
	if not Entity then return false end

	if not self.Normal or not self.Pos then return false end

	local Owner = self:GetOwner()
	local Invert = Owner:KeyDown(IN_WALK) and -1 or 1

	-- The preview plane in entity-local space, normal facing the kept (green) half
	local WorldNormal = self.Normal * -Invert
	local WorldPoint = self.Pos - self.Normal * self:GetClientNumber("offset")
	local Normal, Distance = ImprovedClipping.WorldToLocalPlane(Entity, WorldNormal, WorldPoint)

	local KeepMass = self:GetClientNumber("keep_mass", 1) ~= 0
	local Seal = self:GetClientNumber("seal_holes", 0) ~= 0
	local IDs = ImprovedClipping.AddClips(Entity, { Normal }, { Distance }, { KeepMass }, { Seal })

	if next(IDs) and self:GetClientNumber("add_undo", 1) ~= 0 then
		undo.Create("Improved Clipping")
		undo.AddFunction(function(_, UndoEntity, UndoIDs)
			if IsValid(UndoEntity) then ImprovedClipping.RemoveClips(UndoEntity, UndoIDs) end
		end, Entity, IDs)
		undo.SetPlayer(Owner)
		undo.Finish()
	end

	return true
end

function TOOL:Reload(Trace)
	if CLIENT then return true end

	local Entity = GetClippingTarget(self:GetOwner(), Trace)
	if not Entity then return false end

	ImprovedClipping.Reset(Entity)

	return true
end

function TOOL:Think()
	self:SetOperation(self:GetClientNumber("mode", 0))

	if CLIENT then return true end
end