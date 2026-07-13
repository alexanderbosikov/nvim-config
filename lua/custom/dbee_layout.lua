-- Minimal dbee layout: shows only the result and call log (history) windows.
-- The connections drawer is opened separately via <leader>dc (see remap.lua),
-- since you only need it when switching/connecting, not on every query run.
local tools = require("dbee.layouts.tools")
local api_ui = require("dbee.api.ui")

local ResultLayout = {}

function ResultLayout:new(opts)
  opts = opts or {}
  local o = {
    egg = nil,
    windows = {},
    is_opened = false,
    call_log_width = opts.call_log_width or 40,
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

function ResultLayout:is_open()
  return self.is_opened
end

function ResultLayout:open()
  self.egg = tools.save()
  self.windows = {}

  tools.make_only(0)
  local result_win = vim.api.nvim_get_current_win()
  self.windows["result"] = result_win
  api_ui.result_show(result_win)

  -- history on the left, result stays on the right
  vim.cmd("topleft " .. self.call_log_width .. "vsplit")
  local log_win = vim.api.nvim_get_current_win()
  self.windows["call_log"] = log_win
  api_ui.call_log_show(log_win)

  vim.api.nvim_set_current_win(result_win)
  self.is_opened = true
end

function ResultLayout:reset()
  vim.api.nvim_win_set_width(self.windows["call_log"], self.call_log_width)
end

function ResultLayout:close()
  for _, win in pairs(self.windows) do
    pcall(vim.api.nvim_win_close, win, false)
  end
  tools.restore(self.egg)
  self.egg = nil
  self.is_opened = false
end

return ResultLayout
