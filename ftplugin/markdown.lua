-- По умолчанию длинные строки переносятся (по словам, с сохранением отступа).
-- Широкие таблицы с переносом читать невозможно: строка таблицы уезжает в
-- несколько виртуальных, колонки перестают совпадать по вертикали. Для них —
-- <leader>uw (выключить перенос и ходить вбок скроллом) или <leader>mt.
--
-- При nowrap render-markdown гасил бы рендер, когда окно проскроллено вбок
-- (leftcol ~= 0, core/ui.lua) — это обходит патч в plugins/render-markdown.lua.
vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.breakindent = true

-- Запас по горизонтали вокруг курсора: соседняя колонка видна до того, как
-- упрёшься в край. Шаг самого скролла (sidescroll) не трогаем — в nvim он и так
-- 1, по колонке, а не по полэкрана, как в vim; к тому же опция глобальная,
-- оконного варианта у неё нет.
vim.opt_local.sidescrolloff = 4

-- Тоггл переноса — для широких таблиц. Маппинг буферный: за пределами markdown
-- <leader>uw не занят.
vim.keymap.set("n", "<leader>uw", function()
  vim.opt_local.wrap = not vim.wo.wrap
  vim.notify("wrap: " .. (vim.wo.wrap and "on" or "off"))
end, { buffer = true, desc = "Markdown: перенос строк вкл/выкл" })

-- Широкая таблица → длинные ячейки переносятся на строки-продолжения
-- (~/work/tools/mdtable). В normal берётся абзац под курсором — таблица
-- от пустой строки до пустой строки; в visual — выделение. Таблицы, которые
-- и так влезают в ширину, скрипт не трогает.
local mdtable = "python3 " .. vim.fn.expand("~/work/tools/mdtable/mdtable.py")
vim.keymap.set("n", "<leader>mt", function()
  local view = vim.fn.winsaveview()
  vim.cmd("silent normal! vip\27")
  vim.cmd("silent '<,'>!" .. mdtable)
  vim.fn.winrestview(view)
end, { buffer = true, desc = "Markdown: переформатировать таблицу под курсором" })
vim.keymap.set("x", "<leader>mt", ":<C-u>silent '<,'>!" .. mdtable .. "<CR>",
  { buffer = true, desc = "Markdown: переформатировать выделенную таблицу" })
