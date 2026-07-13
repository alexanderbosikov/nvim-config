-- Auto-retry a query once when it fails with a stale / "bad connection" error.
-- dbee sets no connection-pool idle timeout, so the first query after a long
-- idle period hits a dead pooled connection and fails; re-running it gets a
-- fresh connection (which is why the second attempt always works). This makes
-- that retry automatic and transparent.
local M = {}

-- ids of calls that were themselves spawned by a retry, so we never retry a
-- retry (prevents an infinite loop if the DB is genuinely down).
local retry_calls = {}

local function is_conn_error(err)
  if not err then
    return false
  end
  err = err:lower()
  return err:find("bad connection")
    or err:find("connection reset")
    or err:find("broken pipe")
    or err:find("connection refused")
    or err:find("eof")
    or false
end

function M.register()
  local api = require("dbee").api
  api.core.register_event_listener("call_state_changed", function(data)
    local call = data.call
    if call.state ~= "executing_failed" and call.state ~= "retrieving_failed" then
      return
    end
    if not is_conn_error(call.error) then
      return
    end
    if retry_calls[call.id] then
      return -- this failed call was already a retry -> give up, show the error
    end

    -- re-run the same query once on the current connection
    local ok, newcall = pcall(function()
      local conn = api.core.get_current_connection()
      if not conn then
        return nil
      end
      return api.core.connection_execute(conn.id, call.query)
    end)
    if ok and newcall then
      retry_calls[newcall.id] = true
      pcall(api.ui.result_set_call, newcall)
    end
  end)
end

return M
