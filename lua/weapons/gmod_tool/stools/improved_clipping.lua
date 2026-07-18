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
	["max_visual_client"] = "8",
	["physical_clip"]     = "1",
	["keep_mass"]         = "1",
	["seal_holes"]        = "1",
	["add_undo"]          = "1",
	["mode"]              = "0",
	["offset"]            = "0",
}

for Name, Default in pairs(ConVarDefaults) do TOOL.ClientConVar[Name] = Default end

if CLIENT then
	language.Add("tool.improved_clipping.name", "Improved Clipping")
	language.Add("tool.improved_clipping.desc", "Applies visual/physical clips to props, changing their visuals/geometry")

	language.Add("tool.improved_clipping.left0", "Define clipping planes. Last 2 planes used.")
	language.Add("tool.improved_clipping.left1", "Define clipping plane")

	language.Add("tool.improved_clipping.right0", "Add clip to selected entity")
	language.Add("tool.improved_clipping.reload0", "Clear all clips on selected entity")

	function TOOL.BuildCPanel(Panel)
		Panel:NumSlider("Max Visual Clips", "improved_clipping_max_visual_client", 1, 8, 0)

		Panel:CheckBox("Physical clip", "improved_clipping_physical_clip")
		Panel:CheckBox("Keep mass when physics clipping", "improved_clipping_keep_mass")
		Panel:CheckBox("Seal holes", "improved_clipping_seal_holes")
		Panel:CheckBox("Add clips to undo list", "improved_clipping_add_undo")

		local Mode = Panel:ComboBox("Mode", "improved_clipping_mode")
		Mode:AddChoice("2-Hitplanes Intersection", 0)
		Mode:AddChoice("1-Hitplane", 1)

		Panel:NumSlider("Offset", "improved_clipping_offset", -10, 10, 2)

		local ResetButton = Panel:Button("Reset Values")
		function ResetButton:DoClick()
			for Name, Default in pairs(ConVarDefaults) do
				RunConsoleCommand("improved_clipping_" .. Name, Default)
			end
		end
	end

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
	self:SetOperation(self:GetClientNumber("mode", 0))

	if CLIENT then return true end
end