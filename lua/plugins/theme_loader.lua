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

-- Поправки поверх любой темы, переживают горячую смену (omarchy):
--   - неиспользуемое имя (`DiagnosticUnnecessary`) тема красит почти в цвет фона, и
--     `import polars as pl` читается как дыра. Оставляем цвет синтаксиса, только пунктир;
--   - в части тем (tokyonight) имя модуля того же цвета, что `import`, и строка импорта
--     сливается в одно пятно. Тогда имя модуля — обычным цветом переменной.
local function tweak_theme()
  vim.api.nvim_set_hl(0, "DiagnosticUnnecessary", { underdotted = true })
  local function fg(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false }).fg
  end
  if fg("@module") ~= nil and fg("@module") == fg("@keyword.import") then
    vim.api.nvim_set_hl(0, "@module", { link = "@variable" })
  end
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ThemeTweaks", { clear = true }),
  callback = tweak_theme,
})

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
