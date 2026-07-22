-- Builds the tool's "Profiler" panel: a per-owner breakdown of clipped props and clip counts
return function()
	local RefreshInterval = 5
	local TimerName = "ImprovedClipping_ProfilerRefresh"

	local pnl = vgui.Create("DForm")
	pnl:SetName("Profiler")
	pnl:DockPadding(0, 0, 0, 10)

	local tree = vgui.Create("DTree", pnl)
	tree:SetTall(256)
	tree:Dock(FILL)
	pnl:AddItem(tree)

	local function Refresh()
		tree:Clear()

		local struct = {}
		for Entity in pairs(ImprovedClipping.ClippedEntities) do
			if IsValid(Entity) then
				local Owner = CPPI and Entity:CPPIGetOwner()
				local Root = IsValid(Owner) and Owner:Nick() or "Unowned"

				if not struct[Root] then
					local sdata = {
						root = tree:AddNode(Root, "icon16/user.png"),
						num_ents = 0,
						num_clips = 0,
						num_sealed = 0,
					}

					sdata.node_ents = sdata.root:AddNode("", "icon16/bullet_black.png")
					sdata.node_clips = sdata.root:AddNode("", "icon16/bullet_black.png")
					sdata.node_avg = sdata.root:AddNode("", "icon16/bullet_black.png")
					sdata.node_sealed = sdata.root:AddNode("", "icon16/bullet_black.png")
					sdata.node_avg_sealed = sdata.root:AddNode("", "icon16/bullet_black.png")
					sdata.root:SetExpanded(true, true)

					struct[Root] = sdata
				end

				local sdata = struct[Root]

				sdata.num_ents = sdata.num_ents + 1

				for _, Clip in ipairs(ImprovedClipping.GetClips(Entity)) do
					sdata.num_clips = sdata.num_clips + 1
					if Clip.Seal then sdata.num_sealed = sdata.num_sealed + 1 end
				end

				sdata.node_ents:SetText(string.format("%d total props", sdata.num_ents))
				sdata.node_clips:SetText(string.format("%d total clips", sdata.num_clips))
				sdata.node_avg:SetText(string.format("%.2f avg clips per prop", sdata.num_clips / sdata.num_ents))
				sdata.node_sealed:SetText(string.format("%d total sealed clips", sdata.num_sealed))
				sdata.node_avg_sealed:SetText(string.format("%.2f avg sealed clips per prop", sdata.num_sealed / sdata.num_ents))
			end
		end
	end

	Refresh()
	timer.Create(TimerName, RefreshInterval, 0, Refresh)

	pnl.OnRemove = function()
		timer.Remove(TimerName)
	end

	return pnl
end
