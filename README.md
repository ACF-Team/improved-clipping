# Improved Clipping

Clipping tool with both visual and physical support.

Visuals are baked clipped render meshes (with sealed cut faces) drawn in the
entity's place, rather than per-frame render clip planes.

Additional support for special entities such as primitives.

TODO:
- Decide between `Improved` and `Mesh` for naming

API:
- `ImprovedClipping.ClipsLeft(Ent)` [sh]
    - Returns clips remaining, depending on realm called on.
- `ImprovedClipping.AddClips(Ent, Normals, Distances, KeepMasses, Seals)` [sh]
    - Adds clips, modifies mesh and batch updates physics object once. Returns IDs.
    - Normals/Distances are entity-local planes; geometry on the normal's side is kept.
    - KeepMasses/Seals are optional and default true; Seal caps the cut face.
- `ImprovedClipping.RemoveClips(Ent, IDs)` [sh]
    - Removes clips, modifies mesh and batch updates physics object once
- `ImprovedClipping.GetClips(Ent)` [sh]
    - Returns a copy of the entity's clips: `{ { ID, Normal, Distance, KeepMass, Seal }, ... }`
- `ImprovedClipping.SetClips(Ent, Clips)` [sh]
    - Replaces the entire clip list and rebuilds physics once. Empty list fully resets.
    - Returns false and reverts if the rebuild fails.
- `ImprovedClipping.Reset(Ent)` [sh]
    - Resets physics mesh and properties

Special entities:
- `Ent.ImprovedClippingExternalMesh` [sh]
    - Set truthy on entities that own their own mesh, such as primitives. Clips are still
      stored, networked and duplicated, but the physics object and render proxy are left
      alone, and `SetClips` always succeeds since there is no rebuild to fail.
    - Entities that reinitialize their physics object on rebuild should set this, otherwise
      the rebuild wipes the clips.
- `ImprovedClipping_ClipsChanged(Ent)` [hook, sh]
    - Fires whenever an entity's clips change. Rebuild the clipped mesh from here, reading
      the planes with `GetClips`.

Inspired by prior clipping addons such as:
- https://github.com/ndbeals/Clip_Tool
- https://github.com/Sevii77/proper_clipping