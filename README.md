# Improved Clipping

Clipping tool with both visual and physical support.

Instead of applying render clipping planes for visuals, we modify the visual mesh of the entity.

Additional support for special entities such as [primitives](https://steamcommunity.com/sharedfiles/filedetails/?id=2840295308) and [prop2mesh](https://steamcommunity.com/sharedfiles/filedetails/?id=2458909924) by delegating clips.

Please submit issues and feedback on the [github](https://github.com/ACF-Team/improved-clipping)

Inspired by prior clipping addons such as:
- [Visual Clip Tool](https://steamcommunity.com/sharedfiles/filedetails/?id=238138995)
- [Visual Clip Tool](https://steamcommunity.com/sharedfiles/filedetails/?id=106753151)
- [Proper Clipping](https://steamcommunity.com/sharedfiles/filedetails/?id=2256491552)

Server Convars:
- `improved_clipping_max_clips`
    - Max clips an entity can have. Default 8, Min 0, Max 8.

Client Convars:
- `improved_clipping_keep_mass`
    - Keep mass when physics clipping. Default 1.
- `improved_clipping_seal_holes`
    - Seal holes cut by clipping (expensive). Default 0.
- `improved_clipping_add_undo`
    - Add clips to the undo list. Default 1.
- `improved_clipping_mode`
    - Tool mode (dual hitplane / single hitplane). Default 0.
- `improved_clipping_offset`
    - Plane offset applied when clipping. Default 0.

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

Hooks/Attributes For Special entities:
- `Ent.ImprovedClippingExternalMesh` [sh]
    - Set truthy on entities that own their own mesh, such as primitives. Clips are still
      stored, networked and duplicated, but the physics object and render proxy are left
      alone, and `SetClips` always succeeds since there is no rebuild to fail.
    - Entities that reinitialize their physics object on rebuild should set this, otherwise
      the rebuild wipes the clips.
- `ImprovedClipping_ClipsChanged(Ent)` [sh]
    - Fires whenever an entity's clips change. Rebuild the clipped mesh from here, reading
      the planes with `GetClips`.