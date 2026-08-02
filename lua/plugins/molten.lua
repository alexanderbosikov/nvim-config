-- Molten: выполнение ячеек в Jupyter-ядре с выводом прямо в буфер.
-- Текст/таблицы polars — виртуальным текстом под ячейкой; картинки
-- (matplotlib/seaborn) — инлайн через image.nvim (см. plugins/image.lua).
-- Зависимости провайдера (pynvim/jupyter_client/nbformat) — в ~/.venvs/neovim,
-- путь к нему задан через vim.g.python3_host_prog в init.lua.

-- Границы кода текущей ячейки в percent-формате ("# %%" ... "# %%").
local function percent_cell_range()
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local total = vim.api.nvim_buf_line_count(0)
    local function is_marker(l)
        return vim.fn.getline(l):match("^#%s*%%%%") ~= nil
    end
    -- начало ячейки: ближайший маркер сверху (или строка 1)
    local start_l = cur
    while start_l > 1 and not is_marker(start_l) do
        start_l = start_l - 1
    end
    local body_start = is_marker(start_l) and start_l + 1 or start_l
    -- конец ячейки: перед следующим маркером (или EOF)
    local end_l = cur + 1
    while end_l <= total and not is_marker(end_l) do
        end_l = end_l + 1
    end
    return body_start, end_l - 1
end

-- Границы кода ячейки в markdown-представлении jupytext: fenced-блок
-- ```python ... ``` вокруг курсора. nil — курсор вне код-ячейки.
local function fence_cell_range()
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local total = vim.api.nvim_buf_line_count(0)
    -- ближайший фенс сверху: открывающий (с языком) — мы в код-ячейке,
    -- закрывающий (голый ```) — мы в markdown-тексте между ячейками
    local open_l
    for l = cur, 1, -1 do
        local fence = vim.fn.getline(l):match("^```(%S*)")
        if fence then
            if fence ~= "" then
                open_l = l -- открывающий фенс (в т.ч. курсор прямо на нём)
            end
            break
        end
    end
    if not open_l then
        return nil
    end
    for l = cur, total do
        if vim.fn.getline(l):match("^```%s*$") and l > open_l then
            return open_l + 1, l - 1
        end
    end
    return nil -- незакрытый фенс
end

-- Выполнить текущую ячейку: markdown-буфер — fenced-блок, иначе percent.
-- Molten не парсит ячейки сам — находим границы и гоним через EvaluateVisual.
local function eval_cell()
    local body_start, body_end
    if vim.bo.filetype == "markdown" then
        body_start, body_end = fence_cell_range()
        if not body_start then
            vim.notify("molten: курсор вне код-ячейки (```python-блока)", vim.log.levels.WARN)
            return
        end
    else
        body_start, body_end = percent_cell_range()
    end
    -- обрезаем хвостовые пустые строки: иначе вывод molten прикрепится ПОД
    -- финальную пустую строку буфера и до него нельзя будет доскроллить
    -- (пустую строку в конце держит автокоманда в jupytext.lua ровно для того,
    -- чтобы вывод последней ячейки рендерился НАД ней)
    while body_end > body_start and vim.fn.getline(body_end):match("^%s*$") do
        body_end = body_end - 1
    end
    if body_start > body_end then
        return
    end
    -- линейно выделяем тело ячейки и выходим (\27 = Esc) — так выставляются
    -- метки '< '>, которые читает MoltenEvaluateVisual
    vim.cmd(string.format("keepjumps normal! %dGV%dG\27", body_start, body_end))
    vim.cmd("MoltenEvaluateVisual")
end

-- Вставить новую код-ячейку выше/ниже текущей (конвенция Jupyter: a/b).
-- markdown: ```python-фенс с пустыми строками-разделителями; python: "# %%".
-- Курсор встаёт внутрь новой ячейки сразу в insert-режиме.
local function insert_cell(above)
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    if vim.bo.filetype == "markdown" then
        local s, e = fence_cell_range()
        local idx, lines, row_off
        if above then
            -- перед открывающим фенсом текущей ячейки (или перед строкой курсора)
            idx = s and (s - 2) or (cur - 1)
            lines = { "```python", "", "```", "" }
            row_off = 2
        else
            -- после закрывающего фенса (или после строки курсора)
            idx = e and (e + 1) or cur
            lines = { "", "```python", "", "```" }
            row_off = 3
        end
        vim.api.nvim_buf_set_lines(0, idx, idx, false, lines)
        vim.api.nvim_win_set_cursor(0, { idx + row_off, 0 })
    else
        local s, e = percent_cell_range()
        local idx, lines, row_off
        if above then
            -- перед "# %%"-маркером текущей ячейки (s - тело, маркер на s-1)
            idx = math.max(s - 2, 0)
            lines = { "# %%", "", "" }
            row_off = 2
        else
            idx = e
            lines = { "", "# %%", "" }
            row_off = 3
        end
        vim.api.nvim_buf_set_lines(0, idx, idx, false, lines)
        vim.api.nvim_win_set_cursor(0, { idx + row_off, 0 })
    end
    vim.cmd("startinsert")
end

return {
    "benlubas/molten-nvim",
    version = "^1.0.0", -- держимся 1.x
    build = ":UpdateRemotePlugins",
    ft = { "python", "markdown", "json" }, -- .ipynb приходит как python (jupytext)
    init = function()
        -- ядра molten стартуют из окружения nvim → выключаем itables в nb_utils:
        -- в терминале нет браузера, itables-HTML нечем рендерить, а так display
        -- датафреймов отдаёт обычный текстовый repr. Lab это не затрагивает.
        vim.env.NB_UTILS_ITABLES = "0"
        -- картинки — через image.nvim (kitty graphics protocol в ghostty);
        -- откат на чистый текст: поставить "none"
        vim.g.molten_image_provider = "image.nvim"
        -- вывод — виртуальным текстом прямо под ячейкой, фокус не воруется
        vim.g.molten_virt_text_output = true
        vim.g.molten_virt_lines_off_by_1 = false
        vim.g.molten_auto_open_output = false
        vim.g.molten_wrap_output = true
        vim.g.molten_output_win_max_height = 20
    end,
    config = function()
        -- вывод virt-text по умолчанию линкуется на Comment и сливается с
        -- комментами кода. Делаем: обычный fg + едва заметная фоновая подложка
        -- (подмес 8% fg темы в bg) — блок вывода визуально отделён от кода.
        -- Автокоманда — чтобы переживать смену темы (omarchy-theme-hotreload).
        local function blend(a, b, t)
            -- линейный подмес цвета b в a на долю t (цвета — 0xRRGGBB)
            local r = math.floor(math.floor(a / 65536) % 256 + (math.floor(b / 65536) % 256 - math.floor(a / 65536) % 256) * t + 0.5)
            local g = math.floor(math.floor(a / 256) % 256 + (math.floor(b / 256) % 256 - math.floor(a / 256) % 256) * t + 0.5)
            local bl = math.floor(a % 256 + (b % 256 - a % 256) * t + 0.5)
            return r * 65536 + g * 256 + bl
        end
        local function output_hl()
            local ok, normal = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
            if ok and normal.fg and normal.bg then
                vim.api.nvim_set_hl(0, "MoltenVirtualText", {
                    fg = normal.fg,
                    bg = blend(normal.bg, normal.fg, 0.08),
                })
            else
                -- тема без явных fg/bg (например, transparent) — хотя бы не Comment
                vim.api.nvim_set_hl(0, "MoltenVirtualText", { link = "Normal" })
            end
        end
        output_hl()
        vim.api.nvim_create_autocmd("ColorScheme", {
            group = vim.api.nvim_create_augroup("MoltenOutputHl", { clear = true }),
            callback = output_hl,
        })

        local map = function(lhs, rhs, desc, mode)
            vim.keymap.set(mode or "n", lhs, rhs, { silent = true, desc = desc })
        end
        map("<leader>ji", ":MoltenInit<CR>", "Molten: выбрать/инициализировать ядро")
        map("<leader>jl", ":MoltenEvaluateLine<CR>", "Molten: выполнить строку")
        map("<leader>je", ":MoltenEvaluateOperator<CR>", "Molten: выполнить (оператор+motion)")
        map("<leader>jr", ":<C-u>MoltenEvaluateVisual<CR>gv", "Molten: выполнить выделение", "v")
        map("<leader>jc", eval_cell, "Molten: выполнить ячейку")
        map("<leader>jC", ":MoltenReevaluateCell<CR>", "Molten: перезапустить ячейку")
        map("<leader>jo", ":MoltenShowOutput<CR>", "Molten: показать вывод")
        map("<leader>jh", ":MoltenHideOutput<CR>", "Molten: спрятать вывод")
        map("<leader>jO", ":noautocmd MoltenEnterOutput<CR>", "Molten: войти в окно вывода")
        map("<leader>jx", ":MoltenInterrupt<CR>", "Molten: прервать выполнение")
        map("<leader>jd", ":MoltenDelete<CR>", "Molten: удалить ячейку molten")
        map("<leader>jn", ":MoltenNext<CR>", "Molten: следующая ячейка")
        map("<leader>jp", ":MoltenPrev<CR>", "Molten: предыдущая ячейка")
        map("<leader>jt", function()
            require("custom.molten_table").open()
        end, "Molten: таблица в drawer (постранично)")
        map("<leader>ja", function()
            insert_cell(true)
        end, "Molten: новая ячейка выше (above)")
        map("<leader>jb", function()
            insert_cell(false)
        end, "Molten: новая ячейка ниже (below)")
    end,
}
