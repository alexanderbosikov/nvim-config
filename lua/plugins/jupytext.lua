-- Открывает .ipynb как обычный текстовый буфер (percent-формат "# %%"),
-- при :w конвертит обратно в json. Требует CLI `jupytext` в PATH
-- (установлен как uv tool → ~/.local/bin/jupytext).
return {
    "GCBallesteros/jupytext.nvim",
    lazy = false, -- должен перехватить открытие .ipynb ещё до чтения буфера
    config = function()
        -- ФИКС нового файла: jupytext.nvim вешает BufReadCmd и на несуществующем
        -- .ipynb зовёт jupytext CLI → ошибка и пустой буфер. Наш автокоманд
        -- зарегистрирован РАНЬШЕ (порядок определения), поэтому успевает
        -- записать на диск минимальный валидный ноутбук до чтения плагином.
        local seed = table.concat({
            '{',
            ' "cells": [',
            '  {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": []}',
            ' ],',
            ' "metadata": {',
            '  "kernelspec": {"display_name": "Python (jupyter-utils)", "language": "python", "name": "jupyter-utils"},',
            '  "language_info": {"name": "python"}',
            ' },',
            ' "nbformat": 4,',
            ' "nbformat_minor": 4',
            '}',
        }, "\n")
        vim.api.nvim_create_autocmd("BufReadCmd", {
            pattern = "*.ipynb",
            group = vim.api.nvim_create_augroup("JupytextSeedNew", { clear = true }),
            callback = function(ev)
                if vim.fn.filereadable(ev.match) == 0 then
                    vim.fn.writefile(vim.split(seed, "\n"), ev.match)
                    return
                end
                -- jupytext.nvim падает на ноутбуках без metadata.kernelspec
                -- (частый случай: ipynb, собранный jupytext CLI из голого .py,
                -- пишется с notebook_metadata_filter=-all). Дописываем kernelspec
                -- в файл до того, как его прочитает плагин.
                local ok, nb = pcall(vim.json.decode, table.concat(vim.fn.readfile(ev.match), "\n"))
                if not ok or type(nb) ~= "table" then
                    return -- битый json — пусть плагин сам отругается
                end
                if type(nb.metadata) ~= "table" then
                    nb.metadata = vim.empty_dict()
                end
                if nb.metadata.kernelspec == nil then
                    nb.metadata.kernelspec = {
                        display_name = "Python (jupyter-utils)",
                        language = "python",
                        name = "jupyter-utils",
                    }
                    vim.fn.writefile({ vim.json.encode(nb) }, ev.match)
                end
            end,
        })

        require("jupytext").setup({
            -- "markdown" → буфер = markdown: md-ячейки рендерит render-markdown,
            -- код-ячейки — fenced ```python-блоки (подсветка — treesitter-инъекции,
            -- красивые блоки — тоже render-markdown). Магики (%%sql) в фенсах
            -- сохраняются как есть.
            style = "markdown",
            -- НЕ "auto": auto берёт расширение языка (py), а формата py:markdown
            -- у jupytext нет — упадёт при конвертации
            output_extension = "md",
            force_ft = "markdown", -- иначе ft будет python (из metadata.language)
        })

        -- ФИКС скролла под выводом molten: вывод последней ячейки — это
        -- virt_lines под последней реальной строкой, курсору туда не попасть.
        -- Гарантируем пустую строку в конце буфера — j доводит до неё, и вывод
        -- рендерится над курсором. modified не выставляем: строка «служебная».
        -- Только python-представление: в markdown у последней ячейки и так есть
        -- закрывающий ```-фенс под кодом, а лишняя пустая строка при сохранении
        -- превращается в пустую markdown-ячейку в ipynb.
        vim.api.nvim_create_autocmd("FileType", {
            pattern = "python",
            group = vim.api.nvim_create_augroup("JupytextTrailingLine", { clear = true }),
            callback = function(ev)
                if not vim.api.nvim_buf_get_name(ev.buf):match("%.ipynb$") then
                    return
                end
                local n = vim.api.nvim_buf_line_count(ev.buf)
                local last = vim.api.nvim_buf_get_lines(ev.buf, n - 1, n, false)[1]
                if last ~= "" then
                    vim.api.nvim_buf_set_lines(ev.buf, n, n, false, { "" })
                    vim.bo[ev.buf].modified = false
                end
            end,
        })
    end,
}
