-- Patches dbee's call log (history) rendering so that queries tagged with a
-- "-- @dbee-file: <path>" marker on the first line display ONLY that path,
-- without the "--" prefix and without the trailing SQL. Queries without the
-- marker (e.g. visual selections) keep the default behaviour.
--
-- Must be required before require("dbee").setup() so the override is in place
-- when the CallLogUI instance is created.
local NuiLine = require("nui.line")
local NuiTree = require("nui.tree")
local CallLogUI = require("dbee.ui.call_log")

local MARKER = "^%-%- @dbee%-file:%s*([^\n]+)"

-- pad or truncate to a fixed width (mirrors the plugin's private make_length)
local function make_length(str, len)
  local orig = vim.fn.strchars(str)
  if orig > len then
    return str:sub(1, len - 1) .. "…"
  elseif orig < len then
    return str .. string.rep(" ", len - orig)
  end
  return str
end

-- initials of the call state, e.g. "executing_failed" -> "ef" (mirrors plugin)
local function call_state_initials(state)
  if not state then
    return "  "
  end
  local initials = ""
  for word in string.gmatch(state, "([^_]+)") do
    initials = initials .. word:sub(1, 1)
  end
  if #initials < 2 then
    initials = initials .. string.rep(" ", 2 - #initials)
  end
  return initials
end

-- what to show for a call: the tagged path, or the query text as before
local function display_text(query)
  local path = query:match(MARKER)
  if path then
    return path
  end
  return (string.gsub(query, "\n", " "))
end

function CallLogUI:create_tree(bufnr)
  return NuiTree {
    bufnr = bufnr,
    prepare_node = function(node)
      ---@type CallDetails
      local call = node.call
      local line = NuiLine()
      if not call then
        if node.text then
          line:append(node.text, "NonText")
        end
        return line
      end

      local candy = self.candies[call.state]
        or { icon = call_state_initials(call.state), icon_highlight = "", text_highlight = "" }

      local state_preview = candy.icon
      if not state_preview or state_preview == "" then
        state_preview = call_state_initials(call.state)
      end

      line:append(make_length(state_preview, 3), candy.icon_highlight)
      line:append(" ┃ ", "NonText")
      line:append(make_length(display_text(call.query), 40), candy.text_highlight)

      return line
    end,
    get_node_id = function(node)
      if node.id then
        return node.id
      end
      return tostring(math.random())
    end,
  }
end

return true
