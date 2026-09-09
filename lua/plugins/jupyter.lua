-- jupyter.nvim: свой плагин для ячеек .ipynb (~/projects/jupyter.nvim).
-- Ядро живёт в отдельном процессе-сайдкаре, вывод приезжает в обычный scratch-буфер,
-- поэтому копируется и ищется нативно. Устройство — в ARCHITECTURE.md плагина.
--
-- Мапы на префиксе <leader>n (notebook). Он достался от времён, когда плагин стоял
-- параллельно molten и делил с ним буфер; molten убран, <leader>j свободен, но привычка
-- уже наработана — переезд стоит дороже, чем экономия одной клавиши.
--
-- Окно вывода — справа на половину экрана; в нём же первые строки таблицы.
-- Полная таблица постранично: <leader>nt в отдельной вкладке (H/L страницы,
-- [[ / ]] края, R обновить, q закрыть), сортировка по колонке под курсором на s/S/c.
--
-- Под каждой выполнявшейся ячейкой рисуется статус: время, размер таблицы, имя
-- исключения, «⟲» для прогона из истории, «⚠» если код правили после прогона.
-- История прогонов лежит в .jupyter-out/ и переживает перезагрузку; [r / ]r листают её.
--
-- При первом запуске ячейки к её маркеру дописывается id (jncell="a3f9") — по нему
-- находится история, в том числе снаружи nvim. Отменяется обычным undo.
--
-- Известные шероховатости плагина — в его README, раздел «Известные проблемы».

return {
    {
        name = "jupyter.nvim",
        dir = vim.fn.expand("~/projects/jupyter.nvim"),
        ft = { "python", "markdown" }, -- .ipynb приходит как python (jupytext)
        main = "jupyter",
        init = function()
            -- сайдкару нужен python с jupyter_client и polars; в neovim-venv их нет
            vim.g.jupyter_python = vim.fn.expand("~/work/jupyter-utils/.venv/bin/python")
        end,
        opts = {
            kernel_name = "jupyter-utils", -- ~/Library/Jupyter/kernels/jupyter-utils
            -- Выход из редактора ядро не гасит: тяжёлые фреймы после долгого запроса к
            -- Redshift стоят дороже перезапуска nvim. Вернуться к живому ядру —
            -- :JupyterAttach, плагин сам предложит это при открытии ноутбука.
            -- Забытые ядра видно в :checkhealth jupyter, снимаются :JupyterOrphans!
            keep_kernel_on_exit = true,
            -- в терминале рендерить itables нечем: ядро должно знать это с рождения
            env = { NB_UTILS_ITABLES = "0" },
            -- дробный size = доля экрана; в высокое окно справа влезает много строк
            output = {
                position = "right",
                size = 0.5,
                preview_rows = 50,
                open_on_attach = true, -- окно вывода сразу при открытии ноутбука
            },
            -- keys заменяет дефолты целиком, а не дополняет их
            keys = {
                run_cell = "<leader>nc",
                run_all = "<leader>nA",
                run_below = "<leader>nB",
                insert_above = "<leader>na",
                insert_below = "<leader>nb",
                -- <C-j>/<C-k> свободны в конфиге и мнемоничны; ]n/[n оставлены как
                -- идиоматичный вариант. <C-d>/<C-u> не заняты намеренно: это твоя же
                -- прокрутка с центрированием, а ячейки бывают в 10+ строк.
                next_cell = { "<C-j>", "]n" },
                prev_cell = { "<C-k>", "[n" },
                toggle_output = "<leader>no",
                show_toc = "<leader>nT", -- оглавление: заголовки и ячейки со статусом
                open_table = "<leader>nt",
                edit_cell_args = "<leader>ng", -- параметры %%sql: спросит, подставив нынешние
                -- листание истории прогонов ячейки: ]r / [r свободны
                prev_run = "[r",
                next_run = "]r",
                interrupt = "<leader>ni",
                restart = "<leader>nR",
            },
        },
    },
}
