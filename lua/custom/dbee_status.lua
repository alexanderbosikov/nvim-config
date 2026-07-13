-- Tracks the state of the last dbee query (call_state_changed event) so it
-- can be shown in the statusline. See :h dbee.ref.types.call for call_state.
local M = {
  state = nil,
  duration_us = nil,
  running_since = nil, -- os.time() when the current query started running
}

local labels = {
  executing = { text = "running", hl = "DiagnosticWarn" },
  retrieving = { text = "running", hl = "DiagnosticWarn" },
  archived = { text = "done", hl = "DiagnosticOk" },
  executing_failed = { text = "error", hl = "DiagnosticError" },
  retrieving_failed = { text = "error", hl = "DiagnosticError" },
  archive_failed = { text = "error", hl = "DiagnosticError" },
  canceled = { text = "canceled", hl = "DiagnosticWarn" },
}

local running_states = { executing = true, retrieving = true }

-- terminal states worth a desktop notification (skip the in-progress ones)
local notify_on = {
  archived = "Query finished",
  executing_failed = "Query failed",
  retrieving_failed = "Query failed",
  archive_failed = "Query failed",
  canceled = "Query canceled",
}

local function escape_applescript(s)
  return (tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", " "))
end

local function mac_notify(title, message)
  if vim.fn.has("mac") == 0 or vim.fn.executable("osascript") == 0 then
    return
  end
  local script = string.format(
    'display notification "%s" with title "%s"',
    escape_applescript(message),
    escape_applescript(title)
  )
  vim.system({ "osascript", "-e", script }, { text = true })
end

function M.register()
  require("dbee").api.core.register_event_listener("call_state_changed", function(data)
    M.state = data.call.state
    M.duration_us = data.call.time_taken_us

    -- track when the query started running so the statusline can show a live
    -- elapsed counter; keep the start across executing -> retrieving, clear it
    -- once the query reaches a terminal state.
    if running_states[M.state] then
      M.running_since = M.running_since or os.time()
    else
      M.running_since = nil
    end

    local title = notify_on[M.state]
    if title then
      local message
      if M.state == "archived" then
        message = string.format("done in %.2fs", (M.duration_us or 0) / 1e6)
      elseif M.state == "canceled" then
        message = "canceled"
      else
        message = data.call.error or "error"
      end
      mac_notify(title, message)
    end
  end)
end

---@return string
function M.text()
  local info = labels[M.state]
  if not info then
    return ""
  end

  local text = "DB " .. info.text
  if running_states[M.state] and M.running_since then
    -- live elapsed time; ticks via lualine's periodic statusline refresh
    text = text .. string.format(" %ds", os.time() - M.running_since)
  elseif M.state == "archived" and M.duration_us then
    text = text .. string.format(" (%.2fs)", M.duration_us / 1e6)
  end
  return text
end

---@return string
function M.color()
  local info = labels[M.state]
  return info and info.hl or ""
end

return M
