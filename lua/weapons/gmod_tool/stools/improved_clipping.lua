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
}

local ConVarDefaults = {
	["keep_mass"]         = "1",
	["seal_holes"]        = "1",
	["add_undo"]          = "1",
	["mode"]              = "0",
	["offset"]            = "0",
}

for Name, Default in pairs(ConVarDefaults) do TOOL.ClientConVar[Name] = Default end

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

	function TOOL.BuildCPanel(Panel)
		local KeepMass = Panel:CheckBox("Keep mass when physics clipping", "improved_clipping_keep_mass")
		KeepMass:SetTooltip("Preserve the entity's original mass after its physics mesh is clipped")

		local SealHoles = Panel:CheckBox("Seal holes", "improved_clipping_seal_holes")
		SealHoles:SetTooltip("Cap the cut surface so the clipped entity doesn't appear hollow")

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

	local OverlayMaterial = Material("models/debug/debugwhite")

	-- Hides the real entity while we draw its clipped preview in its place
	local HiddenEntity

	hook.Add("PostDrawTranslucentRenderables", "ImprovedClipping_Overlay", function(bDrawingDepth, bDrawingSkybox)
		if bDrawingDepth or bDrawingSkybox then return end

		local Player = LocalPlayer()
		local Trace = Player:GetEyeTrace()
		local Entity = GetClippingTarget(Player, Trace)

		if IsValid(HiddenEntity) and HiddenEntity ~= Entity then
			HiddenEntity:SetNoDraw(false)
			HiddenEntity = nil
		end

		if not Entity then return end

		local Tool = Player:GetTool("improved_clipping")
		local Normal = Tool and Tool.Normal
		local Pos = Tool and Tool.Pos
		if not Normal or not Pos then return end

		Entity:SetNoDraw(true)
		HiddenEntity = Entity

		local Invert = Player:KeyDown(IN_WALK) and -1 or 1
		local Offset = Tool:GetClientNumber("offset") * Invert
		local Distance = Normal:Dot(Pos) * Invert

		local WasClippingEnabled = render.EnableClipping(true)
		render.MaterialOverride(OverlayMaterial)

		render.PushCustomClipPlane(Normal * Invert, Distance - Offset)
		render.SetColorModulation(1, 0, 0)
		Entity:DrawModel()
		render.PopCustomClipPlane()

		render.PushCustomClipPlane(-Normal * Invert, -Distance + Offset)
		render.SetColorModulation(0, 1, 0)
		Entity:DrawModel()
		render.PopCustomClipPlane()

		render.MaterialOverride(nil)
		render.EnableClipping(WasClippingEnabled)
	end)
end

-- Runs in both realms so the pending clip plane is available immediately client-side for the preview.
function TOOL:LeftClick(Trace)
	local Entity = GetClippingTarget(self:GetOwner(), Trace)
	if not Entity then return false end

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

	return true
end

function TOOL:RightClick(Trace)
	if CLIENT then return true end

	local Entity = GetClippingTarget(self:GetOwner(), Trace)
	if not Entity then return false end

	if not self.Normal or not self.Pos then return false end

	local Owner = self:GetOwner()
	local Invert = Owner:KeyDown(IN_WALK) and -1 or 1
	local Normal = self.Normal * Invert
	local Offset = self:GetClientNumber("offset") * Invert
	local Distance = self.Normal:Dot(Entity:GetPos() - self.Pos) * Invert - Offset

	-- local KeepMass = self:GetClientNumber("keep_mass", 1) ~= 0
	-- local IDs = ImprovedClipping.AddClips(Entity, { Normal }, { Distance }, { KeepMass })

	-- if next(IDs) and self:GetClientNumber("add_undo", 1) ~= 0 then
	-- 	undo.Create("Improved Clipping")
	-- 	undo.AddFunction(function(_, UndoEntity, UndoIDs)
	-- 		if IsValid(UndoEntity) then ImprovedClipping.RemoveClips(UndoEntity, UndoIDs) end
	-- 	end, Entity, IDs)
	-- 	undo.SetPlayer(Owner)
	-- 	undo.Finish()
	-- end

	return true
end

function TOOL:Reload(Trace)
	if CLIENT then return true end

	local Entity = GetClippingTarget(self:GetOwner(), Trace)
	if not Entity then return false end

	-- ImprovedClipping.Reset(Entity)

	return true
end

function TOOL:Think()
	self:SetOperation(self:GetClientNumber("mode", 0))

	if CLIENT then return true end
end