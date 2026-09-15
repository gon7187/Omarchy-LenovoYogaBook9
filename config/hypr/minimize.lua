-- Three-finger swipe down hides every window on the current workspace,
-- swipe up brings them back. Hyprland has no real minimize, so windows are
-- parked in a per-workspace special workspace (special:minimized-<id>).

local function stash_name(workspace)
  return "special:minimized-" .. workspace.id
end

local function minimize_all()
  local workspace = hl.get_active_workspace()
  if not workspace or workspace.id < 0 then return end

  for _, window in ipairs(hl.get_workspace_windows(workspace)) do
    hl.dispatch(hl.dsp.window.move({
      workspace = stash_name(workspace),
      window = "address:" .. window.address,
      follow = false,
    }))
  end
end

local function restore_all()
  local workspace = hl.get_active_workspace()
  if not workspace or workspace.id < 0 then return end

  local stash = hl.get_workspace(stash_name(workspace))
  if not stash then return end

  for _, window in ipairs(hl.get_workspace_windows(stash)) do
    hl.dispatch(hl.dsp.window.move({
      workspace = tostring(workspace.id),
      window = "address:" .. window.address,
      follow = false,
    }))
  end
end

hl.gesture({ fingers = 3, direction = "down", action = minimize_all })
hl.gesture({ fingers = 3, direction = "up", action = restore_all })

return { minimize_all = minimize_all, restore_all = restore_all }
