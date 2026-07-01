local function omarchy_colorscheme()
  local f = vim.fn.expand("~/.config/omarchy/current/theme/neovim.lua")
  if vim.fn.filereadable(f) == 0 then return nil end
  local content = table.concat(vim.fn.readfile(f), "\n")
  return content:match('colorscheme%s*=%s*["\']([^"\']+)["\']')
end

local function apply_theme()
  local cs = omarchy_colorscheme()
  if cs then pcall(vim.cmd.colorscheme, cs) end
end

local watcher = vim.uv.new_fs_event()
if watcher then
  watcher:start(
    vim.fn.expand("~/.config/omarchy/current/theme"),
    {},
    vim.schedule_wrap(apply_theme)
  )
end

return {
  {
    "folke/lazy.nvim",
    lazy = false,
    init = apply_theme,
  },
}
