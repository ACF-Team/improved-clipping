
local sb = Ponder.API.NewStoryboard("improved_clipping", "tutorials", "restrictions-sealing")
sb:WithMenuName("Restrictions and sealing")
sb:WithPlaybackName("Clipping restrictions and sealing")
sb:WithModelIcon("models/props_junk/wood_crate001a.mdl")
sb:WithDescription("Clip limits, show inside and seal holes.")
sb:SetPrimaryLanguage("en")
sb:WithIndexOrder(1) -- Ponder lists the highest first

local Model, BoxPos, Half, ToolPos = "models/hunter/blocks/cube1x1x1.mdl", Vector(0, 0, 40), 23.725, Vector(90, -90, 90)

---------------------------------------------
-- Clip limit
---------------------------------------------
local c = sb:Chapter("Clip limit")
c:AddInstruction("MoveCameraLookAt", {Target = BoxPos, Distance = 1400, Angle = 55, Height = 500, Length = 0.6})
c:AddInstruction("PlaceModel", {Name = "prop", Model = Model, Position = BoxPos, Length = 0})
c:AddInstruction("ColorModel", {Target = "prop", Color = Color(230, 170, 60), Length = 0})
c:AddInstruction("ShowToolgun", {Tool = "improved_clipping", Position = ToolPos, Length = 0.375})
c:AddInstruction("Caption", {Text = "A prop can only hold a limited number of clips. Each time you right click, one is used.", FadeInOutTime = 0.225, TextLength = 2.025})
c:AddDelay(2.25)

-- Each clip takes a different corner off the box
local clips = {}
for index, cut in ipairs({{Vector(1, 1, 1), 30}, {Vector(-1, 1, 1), 30}, {Vector(1, -1, 1), 30}, {Vector(-1, -1, 1), 30}, {Vector(1, 1, -1), 30}, {Vector(-1, -1, -1), 30}}) do
	clips[index] = {Normal = cut[1]:GetNormalized(), Distance = cut[2]}

	c:AddInstruction("Caption", {Text = "Clips used: " .. index .. " / 6", FadeInOutTime = 0.225, TextLength = 0.975, Position = Vector(0.5, 0.78, 0)})
	c:AddInstruction("ClipModel", {Target = "prop", Clips = {unpack(clips)}})
	c:AddDelay(1.2)
end

c:AddInstruction("Caption", {Text = "The limit is the server convar improved_clipping_max_clips. Here it is set to 6. It defaults to 8 and can go up to 12.", FadeInOutTime = 0.225, TextLength = 3.525})
c:AddDelay(3.75)
c:AddInstruction("Caption", {Text = "Once a prop has no clips left, further clips are refused until you remove some with Undo or Reload.", FadeInOutTime = 0.225, TextLength = 3.525})
c:AddDelay(3.75)
c:AddInstruction("ClipModel", {Target = "prop"})
c:AddDelay(1.2)

-- Let the whole prop settle back, then fade it out before the next chapter's props come in
c:AddInstruction("RemoveModel", {Name = "prop", Length = 0.45})
c:AddDelay(0.75)

---------------------------------------------
-- Show inside
---------------------------------------------
c = sb:Chapter("Show inside")

local clip = {Normal = Vector(0.5, 0, 1):GetNormalized(), Distance = 8}

c:AddInstruction("PlaceModel", {Name = "prop", Model = Model, Position = BoxPos, Length = 0.45})
c:AddInstruction("ColorModel", {Target = "prop", Color = Color(230, 170, 60), Length = 0})
c:AddInstruction("ClipModel", {Target = "prop", Clips = {clip}})
c:AddDelay(0.75)
c:AddInstruction("Caption", {Text = "A clip only removes geometry. Unsealed, the cut leaves the prop hollow.", FadeInOutTime = 0.225, TextLength = 2.775})
c:AddDelay(3)

c:AddInstruction("Caption", {Text = "Show inside draws the prop's interior within the clip. It is visual only, and does not work on deferred entities like primitives.", FadeInOutTime = 0.225, TextLength = 4.275})
c:AddInstruction("PlaceToolMenu", {Name = "menu", Tool = "improved_clipping"})
c:AddDelay(1.2)
c:AddDelay(c:AddInstruction("SetToolOption", {Name = "menu", ConVar = "improved_clipping_show_inside", Value = true}).Length)
c:AddDelay(0.45)
c:AddInstruction("ClipModel", {Target = "prop", Clips = {clip}, Inside = true})
c:AddDelay(2.85)
c:AddInstruction("RemovePanel", {Name = "menu", Length = 0.3})

c:AddInstruction("RemoveModel", {Name = "prop", Length = 0.45})
c:AddDelay(0.75)

---------------------------------------------
-- Seal holes
---------------------------------------------
c = sb:Chapter("Seal holes")

-- Sealing needs a deferred entity like a primitive, so this chapter only shows the prop when Primitive is installed
c:AddInstruction("PlaceClippedPrimitive", {Position = BoxPos, Color = Color(230, 170, 60), Clips = {clip}, Seal = false})
c:AddDelay(0.75)
c:AddInstruction("Caption", {Text = "On a deferred entity like a primitive, the cut can be capped. Without it, the prop is hollow.", FadeInOutTime = 0.225, TextLength = 3.275})
c:AddDelay(3.5)

c:AddInstruction("Caption", {Text = "Seal holes caps the cut surface. It only changes how the prop looks, never its physics.", FadeInOutTime = 0.225, TextLength = 3.525})
c:AddInstruction("PlaceToolMenu", {Name = "menu", Tool = "improved_clipping"})
c:AddDelay(1.2)
c:AddDelay(c:AddInstruction("SetToolOption", {Name = "menu", ConVar = "improved_clipping_seal_holes", Value = true}).Length)
c:AddDelay(0.45)
c:AddInstruction("PlaceClippedPrimitive", {Position = BoxPos, Color = Color(230, 170, 60), Clips = {clip}, Seal = true})
c:AddDelay(2.1)
c:AddInstruction("RemovePanel", {Name = "menu", Length = 0.3})

c:AddInstruction("RemoveMesh", {Name = "primitive", Length = 0.225})
c:AddInstruction("HideToolgun", {Length = 0.375})
c:AddDelay(0.45)
