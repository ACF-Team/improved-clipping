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