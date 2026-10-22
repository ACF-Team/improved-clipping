
local sb = Ponder.API.NewStoryboard("improved_clipping", "tutorials", "single-hitplane")
sb:WithMenuName("Single hitplane")
sb:WithPlaybackName("Single hitplane")
sb:WithModelIcon("models/props_junk/wood_crate001a.mdl")
sb:WithDescription("Use any surface as the plane, offset it, and use modifiers.")
sb:SetPrimaryLanguage("en")
sb:WithIndexOrder(5) -- Ponder lists the highest first

local Model, BoxPos, Half, ToolPos = "models/hunter/blocks/cube1x1x1.mdl", Vector(0, 0, 40), 23.725, Vector(90, -90, 90)

---------------------------------------------
-- Clipping off another prop
---------------------------------------------
local c = sb:Chapter("Clipping off another prop")
c:AddInstruction("MoveCameraLookAt", {Target = BoxPos, Distance = 1400, Angle = 55, Height = 500, Length = 0.6})
c:AddInstruction("PlaceModel", {Name = "prop", Model = Model, Position = BoxPos, Length = 0})
c:AddInstruction("ColorModel", {Target = "prop", Color = Color(230, 170, 60), Length = 0})
c:AddInstruction("ShowToolgun", {Tool = "improved_clipping", Position = ToolPos, Length = 0.375})
c:AddInstruction("Caption", {Text = "Improved Clipping cuts a prop along a plane, changing both what it looks like and its physics.", FadeInOutTime = 0.225, TextLength = 2.775})
c:AddDelay(3)

-- A wedge whose slanted face defines the plane. The model's slope faces up and toward +Y, and its middle is the hit.
local RampModel = "models/hunter/triangles/1x05x05.mdl"
local RampNormal = Vector(0, 0.447, 0.894)
local RampPos = Vector(0, 60, BoxPos.z - Half + 11.862)
local RampHit = RampPos
local RampDist = RampNormal:Dot(RampHit - BoxPos)

c:AddInstruction("PlaceModel", {Name = "ramp", Model = RampModel, Position = RampPos, Length = 0.375})
c:AddInstruction("ColorModel", {Target = "ramp", Color = Color(120, 160, 220), Length = 0})
c:AddInstruction("Caption", {Text = "The plane doesn't have to come from the prop you cut. Left click any prop to take a plane from its surface.", FadeInOutTime = 0.225, TextLength = 4.425})
c:AddDelay(1.125)
c:AddInstruction("MoveToolgunTo", {Position = ToolPos, Length = 0.45})
c:AddDelay(0.525)
c:AddDelay(c:AddInstruction("KeyPress", {Name = "key", Key = "Left Click"}).PressedAt)
c:AddInstruction("ClickToolgun", {Position = RampHit, Length = 0.375})
c:AddDelay(0.375)
c:AddInstruction("DebugCross", {Name = "hit", Position = RampHit, Size = 20, IgnoreZ = true, Color = Color(0, 255, 0)})
c:AddInstruction("ClipOverlay", {Normal = RampNormal, Distance = RampDist})
c:AddDelay(2.625)
c:AddInstruction("Caption", {Text = "Now right click the prop you want to cut. The part on the red side is removed.", FadeInOutTime = 0.225, TextLength = 5.175})
c:AddDelay(2.25)
c:AddInstruction("MoveToolgunTo", {Position = ToolPos, Length = 0.45})
c:AddDelay(0.525)
c:AddDelay(c:AddInstruction("KeyPress", {Name = "key", Key = "Right Click"}).PressedAt)
c:AddInstruction("ClickToolgun", {Position = BoxPos, Length = 0.375})
c:AddDelay(0.375)
c:AddInstruction("EndClipOverlay", {})
c:AddInstruction("ClipModel", {Target = "prop", Clips = {{Normal = RampNormal, Distance = RampDist}}})
c:AddInstruction("RemoveDebugOverlay", {Name = "hit"})
c:AddDelay(2.25)
c:AddInstruction("ClipModel", {Target = "prop"})
c:AddInstruction("RemoveModel", {Name = "ramp", Length = 0.375})
c:AddDelay(0.45)

---------------------------------------------
-- Plane offset
---------------------------------------------
c = sb:Chapter("Plane offset")
c:AddInstruction("Caption", {Text = "Single Hitplane: left click a surface to take a plane from it, then right click to apply.", FadeInOutTime = 0.225, TextLength = 2.925})
c:AddDelay(0.75)
c:AddInstruction("MoveToolgunTo", {Position = ToolPos, Length = 0.45})
c:AddDelay(0.525)
c:AddDelay(c:AddInstruction("KeyPress", {Name = "key", Key = "Left Click"}).PressedAt)
c:AddInstruction("ClickToolgun", {Position = BoxPos + Vector(0, 0, Half), Length = 0.375})
c:AddDelay(0.375)
c:AddInstruction("DebugCross", {Name = "hit", Position = BoxPos + Vector(0, 0, Half), Size = 20, IgnoreZ = true, Color = Color(0, 255, 0)})
c:AddInstruction("ClipOverlay", {Normal = Vector(0, 0, 1), Distance = Half - 0.1}) -- Just inside the surface, since a plane exactly on it z-fights its own cap
c:AddDelay(1.5)
c:AddInstruction("Caption", {Text = "The plane sits on the surface you hit. Use the Plane Offset slider to move it along its normal, here -15.", FadeInOutTime = 0.225, TextLength = 2.775})
c:AddInstruction("PlaceToolMenu", {Name = "menu", Tool = "improved_clipping"})
c:AddDelay(0.75)
c:AddDelay(c:AddInstruction("SetToolOption", {Name = "menu", ConVar = "improved_clipping_offset", Value = -15}).Length)
c:AddInstruction("ClipOverlay", {Normal = Vector(0, 0, 1), Distance = Half - 15})
c:AddDelay(2.25)
c:AddInstruction("RemovePanel", {Name = "menu", Length = 0.3})
c:AddInstruction("Caption", {Text = "Right click to apply the clip.", FadeInOutTime = 0.225, TextLength = 3.15})
c:AddDelay(0.6)
c:AddInstruction("MoveToolgunTo", {Position = ToolPos, Length = 0.45})
c:AddDelay(0.525)
c:AddDelay(c:AddInstruction("KeyPress", {Name = "key", Key = "Right Click"}).PressedAt)
c:AddInstruction("ClickToolgun", {Position = BoxPos, Length = 0.375})
c:AddDelay(0.375)
c:AddInstruction("EndClipOverlay", {})
c:AddInstruction("ClipModel", {Target = "prop", Clips = {{Normal = Vector(0, 0, 1), Distance = Half - 15}}})
c:AddInstruction("RemoveDebugOverlay", {Name = "hit"})
c:AddDelay(1.875)
c:AddDelay(0.3)

---------------------------------------------
-- Flip plane
---------------------------------------------
c = sb:Chapter("Flip plane")
local angNormal = Angle(40, 0, 0):Forward()
c:AddInstruction("ClipModel", {Target = "prop"})
c:AddInstruction("Caption", {Text = "Hold Alt while applying to cut the other side of the plane.", FadeInOutTime = 0.225, TextLength = 3.15})
c:AddDelay(1.125)
c:AddInstruction("ClipOverlay", {Normal = angNormal, Distance = 0})
c:AddDelay(2.25)
local alt = c:AddInstruction("KeyPress", {Name = "alt", Key = "Alt", Position = Vector(0.465, 0.27, 0)})
c:AddDelay(alt.PressedAt)
c:AddInstruction("ClipOverlay", {Normal = -angNormal, Distance = 0})
c:AddInstruction("Caption", {Text = "With Alt held, the kept and removed sides swap. Right click to apply.", FadeInOutTime = 0.225, TextLength = 5.175})
c:AddDelay(2.625)
c:AddInstruction("MoveToolgunTo", {Position = ToolPos, Length = 0.45})
c:AddDelay(0.525)
c:AddDelay(c:AddInstruction("KeyPress", {Name = "key", Key = "Right Click", Position = Vector(0.54, 0.27, 0)}).PressedAt)
c:AddInstruction("ClickToolgun", {Position = BoxPos, Length = 0.375})
c:AddDelay(0.375)
alt:ReleaseAt(c.Time)
c:AddInstruction("EndClipOverlay", {})
c:AddInstruction("ClipModel", {Target = "prop", Clips = {{Normal = -angNormal, Distance = 0}}})
c:AddDelay(1.875)

---------------------------------------------
-- Preview clip
---------------------------------------------
c = sb:Chapter("Preview clip")
c:AddInstruction("Caption", {Text = "Hold Shift to preview the physics convexes and the clip planes on the prop.", FadeInOutTime = 0.225, TextLength = 3.15})
c:AddDelay(c:AddInstruction("TransformModel", {Target = "prop", Rotation = Angle(0, 180, 0), Length = 1.5}).Length)
local shift = c:AddInstruction("KeyPress", {Name = "shift", Key = "Shift"})
c:AddDelay(shift.PressedAt)
c:AddInstruction("ClipOverlay", {Shift = true})
c:AddDelay(3.375)
shift:ReleaseAt(c.Time)
c:AddInstruction("EndClipOverlay", {})
c:AddDelay(0.3)

---------------------------------------------
-- Undo and reset clip
---------------------------------------------
c = sb:Chapter("Undo and reset clip")
c:AddInstruction("Caption", {Text = "Reload clears every clip on the prop. Undo (Z) removes the last one.", FadeInOutTime = 0.225, TextLength = 3.525})
c:AddInstruction("MoveToolgunTo", {Position = ToolPos, Length = 0.375})
c:AddDelay(c:AddInstruction("KeyPress", {Name = "reload", Key = "R"}).PressedAt)
c:AddInstruction("ClipModel", {Target = "prop"})
c:AddDelay(1.5)
c:AddDelay(c:AddInstruction("KeyPress", {Name = "undo", Key = "Z"}).PressedAt)
c:AddDelay(1.5)
c:AddInstruction("HideToolgun", {Length = 0.375})
c:AddDelay(0.375)
