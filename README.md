# Improved Clipping

Clipping tool with both visual and physical support.

Additional support for special entities such as primitives.

TODO:
- `ImprovedClipping.ClipsLeft(Ent)` [sh]
    - Returns clips remaining, depending on realm called on.
- `ImprovedClipping.AddClips(Ent, Normals, Distances, KeepMasses)` [sh]
    - Adds clips, modifies mesh and batch updates physics object once. Returns IDs.
- `ImprovedClipping.RemoveClips(Ent, IDs)` [sh]
    - Removes clips, modifies mesh and batch updates physics object once
- `ImprovedClipping.Reset(Ent)` [sh]
    - Resets physics mesh and properties

Inspired by prior clipping addons such as:
- https://github.com/ndbeals/Clip_Tool
- https://github.com/Sevii77/proper_clipping