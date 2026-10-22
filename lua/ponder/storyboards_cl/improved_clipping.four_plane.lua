
local sb = Ponder.API.NewStoryboard("improved_clipping", "tutorials", "four-plane")
sb:WithMenuName("4 plane intersection")
sb:WithPlaybackName("4 plane intersection")
sb:WithModelIcon("models/props_junk/wood_crate001a.mdl")
sb:WithDescription("Miter two overlapping plates of different thickness by clicking their front and back faces.")
sb:SetPrimaryLanguage("en")
sb:WithIndexOrder(3) -- Ponder lists the highest first

-- Two plates of different thickness overlapping at a corner. Their front faces meet at x = y = 0, facing the starting camera.
local HalfLen, HalfHeight, Z = 47.7, 23.975, 40
local Model1, Thick1 = "models/hunter/blocks/cube1x2x05.mdl", 24.225
local Model2, Thick2 = "models/hunter/blocks/cube1x2x025.mdl", 12.3625
local Angles1, Pos1 = Angle(90, 0, 0), Vector(-Thick1 / 2, -HalfLen, Z) -- Runs along Y, faces X
local Angles2, Pos2 = Angle(90, 90, 0), Vector(-HalfLen, -Thick2 / 2, Z) -- Runs along X, faces Y
local Corner = Vector(-Thick1 / 2, -Thick2 / 2, Z)
local FrontToolPos, BackToolPos = Corner + Vector(90, -90, 50), Corner + Vector(-90, 90, 50)

local Hits = {
	Vector(0, -60, Z), -- Front of plate 1
	Vector(-60, 0, Z), -- Front of plate 2
	Vector(-Thick1, -60, Z), -- Back of plate 1
	Vector(-60, -Thick2, Z), -- Back of plate 2
}
local LabelOffsets = {Vector(10, 0, 16), Vector(0, 10, 16), Vector(-10, 0, 16), Vector(0, -10, 16)}

-- The plane the tool computes from those hits: through the front faces' crossing line and the back faces' one
local PlaneNormal, PlanePoint = Vector(Thick2, -Thick1, 0):GetNormalized(), Vector(0, 0, Z)

-- The plane in a plate's own space, as ClipModel and ClipOverlay take it
local function LocalPlane(Normal, Angles, Pos)
	return {Normal = WorldToLocal(Normal, angle_zero, vector_origin, Angles), Distance = Normal:Dot(PlanePoint - Pos)}
end

local Clip2 = LocalPlane(PlaneNormal, Angles2, Pos2)
local Clip1 = LocalPlane(-PlaneNormal, Angles1, Pos1) -- Alt flips the plane for the other plate

local LineBottom, LineTop = Vector(0, 0, Z - HalfHeight - 20), Vector(0, 0, Z + HalfHeight + 20)
local Back = Vector(-Thick1, -Thick2, 0)
local DualDiagonal = Vector(-1, -1, 0) * (Thick1 + 16)

local function Click(c, Index)
	c:AddInstruction("MoveToolgunTo", {Position = Index <= 2 and FrontToolPos or BackToolPos, Length = 0.45})
	c:AddDelay(0.525)
	c:AddDelay(c:AddInstruction("KeyPress", {Name = "key", Key = "Left Click"}).PressedAt)
	c:AddInstruction("ClickToolgun", {Position = Hits[Index], Length = 0.375})
	c:AddDelay(0.375)
	c:AddInstruction("DebugCross", {Name = "hit" .. Index, Position = Hits[Index], Size = 20, IgnoreZ = true, Color = Color(0, 255, 0)})
	c:AddInstruction("DebugText", {Name = "label" .. Index, Position = Hits[Index] + LabelOffsets[Index], Text = tostring(Index), Font = "DermaLarge", Color = Color(0, 255, 0)})
	c:AddDelay(0.3)
end

---------------------------------------------
-- Front faces
---------------------------------------------
local c = sb:Chapter("Front faces")
c:AddInstruction("MoveCameraLookAt", {Target = Corner, Distance = 1400, Angle = 55, Height = 500, Length = 0.6})
c:AddInstruction("PlaceModel", {Name = "plate1", Model = Model1, Position = Pos1, Angles = Angles1, Length = 0})
c:AddInstruction("ColorModel", {Target = "plate1", Color = Color(230, 170, 60), Length = 0})
c:AddInstruction("PlaceModel", {Name = "plate2", Model = Model2, Position = Pos2, Angles = Angles2, Length = 0})
c:AddInstruction("ColorModel", {Target = "plate2", Color = Color(120, 160, 220), Length = 0})
c:AddInstruction("ShowToolgun", {Tool = "improved_clipping", Position = FrontToolPos, Length = 0.375})
c:AddInstruction("Caption", {Text = "4 Plane Intersection: cut two overlapping plates of different thickness so they meet cleanly, by clicking four faces in order.", FadeInOutTime = 0.225, TextLength = 2.775})
c:AddDelay(0.75)
c:AddInstruction("PlaceToolMenu", {Name = "menu", Tool = "improved_clipping"})
c:AddDelay(0.9)
c:AddDelay(c:AddInstruction("SetToolOption", {Name = "menu", ConVar = "improved_clipping_mode", Value = 3}).Length)
c:AddDelay(1.5)
c:AddInstruction("RemovePanel", {Name = "menu", Length = 0.3})
c:AddDelay(0.3)
c:AddInstruction("Caption", {Text = "First left click the front face of plate 1, then the front face of plate 2.", FadeInOutTime = 0.225, TextLength = 3.3})
c:AddDelay(0.6)
Click(c, 1)
Click(c, 2)
c:AddInstruction("DebugLine", {Name = "line1", Start = LineBottom, End = LineTop, IgnoreZ = true, Color = Color(255, 255, 0)})
c:AddInstruction("Caption", {Text = "Those two faces cross along this line.", FadeInOutTime = 0.225, TextLength = 1.95})
c:AddDelay(2.4)

---------------------------------------------
-- Back faces
---------------------------------------------
c = sb:Chapter("Back faces")
c:AddInstruction("MoveCameraLookAt", {Target = Corner, Distance = 1400, Angle = 145, Height = 500, Length = 0.6})
c:AddDelay(0.6)
c:AddInstruction("MoveCameraLookAt", {Target = Corner, Distance = 1400, Angle = 235, Height = 500, Length = 0.6})
c:AddInstruction("MoveToolgunTo", {Position = BackToolPos, Length = 0.6})
c:AddDelay(0.6)
c:AddInstruction("Caption", {Text = "Then the back faces, in the same plate order: plate 1, then plate 2.", FadeInOutTime = 0.225, TextLength = 3.3})
c:AddDelay(0.6)
Click(c, 3)
Click(c, 4)
c:AddInstruction("DebugLine", {Name = "line2", Start = LineBottom + Back, End = LineTop + Back, IgnoreZ = true, Color = Color(255, 255, 0)})
c:AddInstruction("Caption", {Text = "The back faces cross along a second line.", FadeInOutTime = 0.225, TextLength = 1.95})
c:AddDelay(2.4)

-- Dual Hitplane's plane halves the corner's angle, so it runs diagonally out from the first line
local DualCorners = {LineTop, LineTop + DualDiagonal, LineBottom + DualDiagonal, LineBottom}
for i = 1, 4 do
	c:AddInstruction("DebugLine", {Name = "dual" .. i, Start = DualCorners[i], End = DualCorners[i % 4 + 1], IgnoreZ = true, Color = Color(255, 0, 0)})
end
c:AddInstruction("Caption", {Text = "Dual Hitplane would cut halfway between the front faces (red). The plates differ in thickness, so that misses the second line.", FadeInOutTime = 0.225, TextLength = 4.125})
c:AddDelay(4.575)
for i = 1, 4 do c:AddInstruction("RemoveDebugOverlay", {Name = "dual" .. i}) end
c:AddInstruction("Caption", {Text = "4 Plane Intersection's plane passes through both lines instead.", FadeInOutTime = 0.225, TextLength = 2.775})
c:AddInstruction("ClipOverlay", {Target = "plate2", Normal = Clip2.Normal, Distance = Clip2.Distance})
c:AddDelay(3)

---------------------------------------------
-- Applying the clips
---------------------------------------------
c = sb:Chapter("Applying the clips")
c:AddInstruction("Caption", {Text = "Right click one plate to cut it.", FadeInOutTime = 0.225, TextLength = 2.025})
c:AddDelay(0.6)
c:AddInstruction("MoveToolgunTo", {Position = BackToolPos, Length = 0.45})
c:AddDelay(0.525)
c:AddDelay(c:AddInstruction("KeyPress", {Name = "key", Key = "Right Click"}).PressedAt)
c:AddInstruction("ClickToolgun", {Position = Pos2, Length = 0.375})
c:AddDelay(0.375)
c:AddInstruction("EndClipOverlay", {})
c:AddInstruction("ClipModel", {Target = "plate2", Clips = {Clip2}})
c:AddDelay(1.5)

c:AddInstruction("Caption", {Text = "Hold Alt and right click the other plate to cut it on the opposite side.", FadeInOutTime = 0.225, TextLength = 3.3})
c:AddDelay(0.75)
c:AddInstruction("ClipOverlay", {Target = "plate1", Normal = Clip1.Normal, Distance = Clip1.Distance})
c:AddDelay(1.5)
local alt = c:AddInstruction("KeyPress", {Name = "alt", Key = "Alt", Position = Vector(0.465, 0.27, 0)})
c:AddDelay(alt.PressedAt)
c:AddInstruction("MoveToolgunTo", {Position = BackToolPos, Length = 0.45})
c:AddDelay(0.525)
c:AddDelay(c:AddInstruction("KeyPress", {Name = "key", Key = "Right Click", Position = Vector(0.54, 0.27, 0)}).PressedAt)
c:AddInstruction("ClickToolgun", {Position = Pos1, Length = 0.375})
c:AddDelay(0.375)
alt:ReleaseAt(c.Time)
c:AddInstruction("EndClipOverlay", {})
c:AddInstruction("ClipModel", {Target = "plate1", Clips = {Clip1}})
c:AddInstruction("ClearDebugOverlay", {})
c:AddDelay(0.75)

c:AddInstruction("MoveCameraLookAt", {Target = Corner, Distance = 1400, Angle = 145, Height = 500, Length = 0.6})
c:AddDelay(0.6)
c:AddInstruction("MoveCameraLookAt", {Target = Corner, Distance = 1400, Angle = 55, Height = 500, Length = 0.6})
c:AddDelay(0.6)
c:AddInstruction("Caption", {Text = "The plates now meet along the plane without overlapping.", FadeInOutTime = 0.225, TextLength = 2.775})
c:AddDelay(3)
c:AddInstruction("HideToolgun", {Length = 0.375})
c:AddDelay(0.375)

-- Nearly straight down, tilted just enough to keep the same screen orientation as the starting view
c:AddInstruction("MoveCameraLookAt", {Target = Corner, Distance = 150, Angle = 55, Height = 900, Length = 0.9})
c:AddDelay(0.9)
c:AddInstruction("Caption", {Text = "From above, the two plates join seamlessly along the cut.", FadeInOutTime = 0.225, TextLength = 3.15})
c:AddDelay(3.6)
