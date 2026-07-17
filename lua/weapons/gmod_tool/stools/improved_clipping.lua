TOOL.Category = "Construction"
TOOL.Name = "#tool.improved_clipping.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.Information = {
	{ name = "left0", stage = 0 },
	{ name = "right0", stage = 0 },
	{ name = "reload0", stage = 0 },
}

if CLIENT then
	language.Add("tool.improved_clipping.name", "Improved Clipping")
	language.Add("tool.improved_clipping.desc", "Applies visual/physical clips to props, changing their visuals/geometry")

	language.Add("tool.improved_clipping.left0", "Define clipping plane(s)")
	language.Add("tool.improved_clipping.right0", "Add clip to selected entity")
	language.Add("tool.improved_clipping.reload0", "Clear all clips on selected entity")

	local OverlayColor = Color(0, 255, 0)
	local OverlayMaterial = Material("models/debug/debugwhite")

	-- Returns the entity under the crosshair if the improved clipping tool is the active tool.
	local function GetOverlayTarget()
		local Player = LocalPlayer()
		local Weapon = Player:GetActiveWeapon()
		if not IsValid(Weapon) or Weapon:GetClass() ~= "gmod_tool" then return end

		local Tool = Player:GetTool()
		if not Tool or Tool ~= Player:GetTool("improved_clipping") then return end

		local Entity = Player:GetEyeTrace().Entity
		if not IsValid(Entity) or Entity:IsWorld() then return end

		return Entity
	end

	-- Draws overlay over this entity
	local HiddenEntity

	hook.Add("PostDrawTranslucentRenderables", "ImprovedClipping_Overlay", function(bDrawingDepth, bDrawingSkybox)
		if bDrawingDepth or bDrawingSkybox then return end

		local Entity = GetOverlayTarget()

		if IsValid(HiddenEntity) and HiddenEntity ~= Entity then
			HiddenEntity:SetNoDraw(false)
			HiddenEntity = nil
		end

		if not Entity then return end

		Entity:SetNoDraw(true)
		HiddenEntity = Entity

		render.MaterialOverride(OverlayMaterial)
		render.SetColorModulation(OverlayColor.r / 255, OverlayColor.g / 255, OverlayColor.b / 255)

		Entity:DrawModel()

		render.MaterialOverride(nil)
	end)
elseif SERVER then

end

function TOOL:LeftClick(Trace)
	if CLIENT then return true end
end

function TOOL:RightClick(Trace)
	if CLIENT then return true end
end

function TOOL:Reload(Trace)
	if CLIENT then return true end
end

function TOOL:Think()
	if CLIENT then return true end
end