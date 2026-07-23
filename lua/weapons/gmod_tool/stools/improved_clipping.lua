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

AddCSLuaFile("modules/visualizations.lua")
AddCSLuaFile("modules/profiler.lua")

local function WritePlane(Normal, Pos)
	net.WriteFloat(Normal.x)
	net.WriteFloat(Normal.y)
	net.WriteFloat(Normal.z)
	net.WriteFloat(Pos.x)
	net.WriteFloat(Pos.y)
	net.WriteFloat(Pos.z)
end

local function ReadPlane()
	local Normal = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
	local Pos = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
	return Normal, Pos
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

-- Shared by both realms to compute the clip plane
local function ComputeClipPlane(Tool, Trace)
	local op = Tool:GetOperation()

	if op == 0 then
		local Plane1 = { Origin = Trace.HitPos, Normal = Trace.HitNormal }
		local Plane2 = Tool.LastPlane or Plane1
		Tool.LastPlane = Plane1

		local LineNormal = Plane1.Normal:Cross(Plane2.Normal)
		local LineLengthSqr = LineNormal:LengthSqr()

		if LineLengthSqr > 1e-10 then -- Planes are not parallel
			local Normal = LineNormal:Cross(Plane1.Normal + Plane2.Normal):GetNormalized()
			local Pos = Plane1.Origin + LineNormal:Cross(Plane2.Normal) * Plane2.Normal:Dot(Plane2.Origin - Plane1.Origin) / LineLengthSqr
			return Normal, Pos
		end

		return Trace.HitNormal, Trace.HitPos
	elseif op == 1 then
		return Trace.HitNormal, Trace.HitPos
	end
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

	local BuildPanel_Profiler = include("modules/profiler.lua")

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

		Panel:AddPanel(BuildPanel_Profiler())
	end

	include("modules/visualizations.lua")(GetClippingTarget)

	net.Receive("improved_clipping_plane_sp", function()
		local Tool = LocalPlayer():GetTool("improved_clipping")
		if not Tool then return end

		Tool.Normal, Tool.Pos = ReadPlane()
	end)
end

if SERVER then
	util.AddNetworkString("improved_clipping_plane_sp")

	net.Receive("improved_clipping_plane_sp", function(_, Ply)
		if not IsValid(Ply) then return end

		local Tool = Ply:GetTool("improved_clipping")
		if not Tool then return end

		Tool.Normal, Tool.Pos = ReadPlane()
	end)
end

function TOOL:LeftClick(Trace)
	local Entity = GetClippingTarget(self:GetOwner(), Trace)
	if not Entity then return false end

	-- Prediction runs this more than once per click, which would advance LastPlane each time
	if CLIENT and not IsFirstTimePredicted() then return true end

	-- Server has nothing to compute here in multiplayer; it waits for the client's net message instead.
	if SERVER and not game.SinglePlayer() then return true end

	local Normal, Pos = ComputeClipPlane(self, Trace)
	if not Normal or not Pos then return true end

	self.Normal = Normal
	self.Pos = Pos

	if SERVER and game.SinglePlayer() then
		net.Start("improved_clipping_plane_sp")
		WritePlane(Normal, Pos)
		net.Send(self:GetOwner())
	elseif CLIENT then
		net.Start("improved_clipping_plane_sp")
		WritePlane(Normal, Pos)
		net.SendToServer()
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