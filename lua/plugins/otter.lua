-- LSP внутри код-ячеек ноутбуков (markdown-представление jupytext):
-- otter собирает python-код из ```python-фенсов в скрытый буфер и проксирует
-- к нему LSP-запросы (pyright/ruff уже настроены в lsp.lua). Автокомплит идёт
-- через обычный nvim_lsp-источник cmp, кеймапы — через LspAttach.
-- Код из всех ячеек склеивается в один буфер, поэтому переменные из верхних
-- ячеек видны в нижних — как в Jupyter.
return {
    "jmbuhr/otter.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
        require("otter").setup({
            buffers = {
                -- set_filetype убран: с otter 3.x filetype выставляется всегда
                write_to_disk = false, -- скрытые буферы живут только в памяти
            },
            handle_leading_whitespace = true,
        })

        -- авто-активация только в ноутбуках (markdown-буфер с именем *.ipynb);
        -- обычные .md не трогаем, чтобы не ловить диагностику на сниппетах в доках
        vim.api.nvim_create_autocmd("FileType", {
            pattern = "markdown",
            group = vim.api.nvim_create_augroup("OtterIpynb", { clear = true }),
            callback = function(ev)
                if not vim.api.nvim_buf_get_name(ev.buf):match("%.ipynb$") then
                    return
                end
                -- schedule: дождаться, пока буфер дочитается и treesitter разберёт фенсы
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(ev.buf) then
                        vim.api.nvim_buf_call(ev.buf, function()
                            require("otter").activate({ "python" })
                        end)
                    end
                end)
            end,
        })
    end,
}
