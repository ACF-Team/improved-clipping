# Improved Clipping

Clipping tool with both visual and physical support.

Additional support for special entities such as primitives.

API:
- `ImprovedClipping.ClipsLeft(Ent)` [sh]
    - Returns clips remaining, depending on realm called on.
- `ImprovedClipping.AddClips(Ent, Normals, Distances, KeepMasses)` [sh]
    - Adds clips, modifies mesh and batch updates physics object once. Returns IDs.
    - Normals/Distances are entity-local planes; geometry on the normal's side is kept.
- `ImprovedClipping.RemoveClips(Ent, IDs)` [sh]
    - Removes clips, modifies mesh and batch updates physics object once
- `ImprovedClipping.GetClips(Ent)` [sh]
    - Returns a copy of the entity's clips: `{ { ID, Normal, Distance, KeepMass }, ... }`
- `ImprovedClipping.SetClips(Ent, Clips)` [sh]
    - Replaces the entire clip list and rebuilds physics once. Empty list fully resets.
- `ImprovedClipping.Reset(Ent)` [sh]
    - Resets physics mesh and properties

Inspired by prior clipping addons such as:
- https://github.com/ndbeals/Clip_Tool
- https://github.com/Sevii77/proper_clipping