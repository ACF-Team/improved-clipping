-- Instructions for the Improved Clipping storyboards. They drive the addon's own functions on Ponder's models,
-- so the storyboards show the same clipping, rendering and physics as the tool does.

-- Clips the named model like the tool does. Clips are {Normal, Distance} in the model's space and remove the normal's side.
-- The addon's own clips keep the normal's side, so they are flipped on the way in.
local ClipModel = Ponder.API.NewInstruction("ClipModel")
ClipModel.Target = ""
ClipModel.Clips  = {} -- Replaces the model's clips. Empty clears them
ClipModel.Inside = false -- Also draw the interior within each cut
ClipModel.Length = 0

function ClipModel:First(playback)
    local model = playback.Environment:GetNamedModel(self.Target)
    if not IsValid(model) then return Ponder.Print("ClipModel: no model " .. self.Target) end

    local clips = {}
    for index, clip in ipairs(self.Clips) do
        clips[index] = {ID = index, Normal = -clip.Normal, Distance = -clip.Distance, Seal = false, Inside = self.Inside}
    end

    ImprovedClipping.SetClips(model, clips)
end

-- The tool's own overlay on the named model: the plane preview, or with Shift the physics and applied clips.
-- The plane preview takes the plane's normal and distance in the model's space, like ClipModel.
local DrawOverlay = include("weapons/gmod_tool/stools/modules/visualizations.lua")()

local ClipOverlay = Ponder.API.NewInstruction("ClipOverlay")
ClipOverlay.Target   = "prop"
ClipOverlay.Shift    = false
ClipOverlay.Normal   = vector_up
ClipOverlay.Distance = 0
ClipOverlay.Length   = 0

function ClipOverlay:First(playback)
    local env = playback.Environment
    local model = env:GetNamedModel(self.Target)
    if not IsValid(model) then return Ponder.Print("ClipOverlay: no model " .. self.Target) end

    -- The overlay draws the model itself, so Ponder's own draw is faded out until it ends
    model.PONDER_AlphaOverride = 0
    env.ClipOverlay = {Model = model, Shift = self.Shift, Normal = self.Normal, Position = model:LocalToWorld(self.Normal * self.Distance)}
end

local EndClipOverlay = Ponder.API.NewInstruction("EndClipOverlay")
EndClipOverlay.Length = 0

function EndClipOverlay:First(playback)
    local overlay = playback.Environment.ClipOverlay
    if not overlay then return end

    if IsValid(overlay.Model) then overlay.Model.PONDER_AlphaOverride = 1 end
    playback.Environment.ClipOverlay = nil
end

local OverlayRenderer = Ponder.API.NewRenderer("ClipOverlayRenderer")

function OverlayRenderer:Render3D(env)
    local overlay = env.ClipOverlay
    if overlay and IsValid(overlay.Model) then
        DrawOverlay(overlay.Model, overlay.Model, overlay.Shift, overlay.Normal, overlay.Position, 0)
    end
end

-- A cube built by Primitive, which can seal its cuts. Only does anything when Primitive is installed.
local PlaceClippedPrimitive = Ponder.API.NewInstruction("PlaceClippedPrimitive")
PlaceClippedPrimitive.Name     = "primitive"
PlaceClippedPrimitive.Position = vector_origin
PlaceClippedPrimitive.Size     = Vector(47.45, 47.45, 47.45)
PlaceClippedPrimitive.Color    = color_white
PlaceClippedPrimitive.Clips    = {} -- Like ClipModel
PlaceClippedPrimitive.Seal     = true
PlaceClippedPrimitive.Length   = 0

function PlaceClippedPrimitive:First(playback)
    if not Primitive then return Ponder.Print("PlaceClippedPrimitive needs Primitive installed") end

    local clips = {}
    for index, clip in ipairs(self.Clips) do
        clips[index] = {Normal = -clip.Normal, Distance = -clip.Distance, Seal = self.Seal}
    end

    local _, result = Primitive.construct.get("cube", {PrimSIZE = self.Size}, false, false, clips)
    local env = playback.Environment

    env:RemoveNamedObjectByName("Mesh", self.Name)
    env:NewNamedObject("Mesh", self.Name, {
        Triangles = result.tris, Material = Material("hunter/myplastic"), Position = self.Position, Angles = angle_zero,
        Scale = Vector(1, 1, 1), Color = self.Color, Alpha = 1,
    })
end
