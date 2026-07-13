-- Fallback colorscheme used on machines without omarchy (e.g. work Mac).
local FALLBACK_COLORSCHEME = "tokyonight"

local omarchy_theme_dir = vim.fn.expand("~/.config/omarchy/current/theme")
local omarchy_neovim_file = omarchy_theme_dir .. "/neovim.lua"

local function has_omarchy()
  return vim.fn.filereadable(omarchy_neovim_file) == 1
end

local function omarchy_colorscheme()
  if not has_omarchy() then return nil end
  local content = table.concat(vim.fn.readfile(omarchy_neovim_file), "\n")
  return content:match('colorscheme%s*=%s*["\']([^"\']+)["\']')
end

local function apply_theme()
  local cs = omarchy_colorscheme() or FALLBACK_COLORSCHEME
  pcall(vim.cmd.colorscheme, cs)
end

-- only watch the omarchy theme dir when it actually exists; starting the
-- watcher on a missing directory errors on machines without omarchy.
if has_omarchy() then
  local watcher = vim.uv.new_fs_event()
  if watcher then
    watcher:start(omarchy_theme_dir, {}, vim.schedule_wrap(apply_theme))
  end
end

return {
  {
    "folke/lazy.nvim",
    lazy = false,
    init = apply_theme,
  },
}
