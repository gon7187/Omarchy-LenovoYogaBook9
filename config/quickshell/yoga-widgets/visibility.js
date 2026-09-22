.pragma library

function covers(clients, monitorId, workspaceId, specialWorkspaceId, box) {
  for (const client of clients) {
    if (!client || client.monitor !== monitorId || !client.mapped || client.hidden || client.visible === false) continue
    if (!client.pinned && (!client.workspace || (client.workspace.id !== workspaceId && client.workspace.id !== specialWorkspaceId))) continue
    if (!client.at || !client.size) continue
    const [x, y] = client.at
    const [width, height] = client.size
    if (width > 0 && height > 0 && x < box.x + box.width && box.x < x + width &&
        y < box.y + box.height && box.y < y + height) return true
  }
  return false
}
