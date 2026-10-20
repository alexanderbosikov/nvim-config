-- jupyter.nvim: свой плагин для ячеек .ipynb (локальный клон: ~/projects/jupyter.nvim на
-- рабочем Маке, ~/Projects/jupyter-nvim на домашнем Linux).
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
--
-- Экспорт в HTML/PDF — не плагин, а ~/.local/bin/nb-export: <leader>ne / <leader>nE.
-- Ноутбук прогоняется заново в отдельном ядре (выводы плагина лежат в .jupyter-out, не
-- в .ipynb), так что тяжёлый ноутбук с Redshift экспортируется долго.

-- Первый существующий путь из списка: пути на машинах разные, конфиг один
local function first_existing(paths)
    for _, p in ipairs(paths) do
        local full = vim.fn.expand(p)
        if vim.uv.fs_stat(full) then
            return full
        end
    end
    return vim.fn.expand(paths[1])
end

local function export(pdf)
    local path = vim.api.nvim_buf_get_name(0)
    if not path:match("%.ipynb$") then
        vim.notify("nb-export: буфер не .ipynb", vim.log.levels.WARN)
        return
    end
    vim.cmd("silent update")
    vim.notify("nb-export: " .. vim.fn.fnamemodify(path, ":t") .. (pdf and " → pdf…" or " → html…"))
    local cmd = { vim.fn.expand("~/.local/bin/nb-export"), "--open" }
    if pdf then
        table.insert(cmd, "--pdf")
    end
    table.insert(cmd, path)
    vim.system(cmd, { text = true }, function(r)
        vim.schedule(function()
            if r.code == 0 then
                vim.notify("nb-export: " .. vim.trim(r.stdout))
            else
                local lines = vim.split(vim.trim(r.stderr), "\n")
                local tail = table.concat(vim.list_slice(lines, math.max(1, #lines - 9)), "\n")
                vim.notify("nb-export упал:\n" .. tail, vim.log.levels.ERROR)
            end
        end)
    end)
end

return {
    {
        name = "jupyter.nvim",
        dir = first_existing({ "~/projects/jupyter.nvim", "~/Projects/jupyter-nvim" }),
        ft = { "python", "markdown" }, -- .ipynb приходит как python (jupytext)
        main = "jupyter",
        keys = {
            { "<leader>ne", function() export(false) end, ft = { "python", "markdown" }, desc = "Notebook → HTML" },
            { "<leader>nE", function() export(true) end, ft = { "python", "markdown" }, desc = "Notebook → PDF" },
        },
        init = function()
            -- сайдкару нужен python с jupyter_client и polars; в neovim-venv их нет
            vim.g.jupyter_python = first_existing({
                "~/work/jupyter-utils/.venv/bin/python",
                "~/Projects/jupyter-utils/.venv/bin/python",
            })
            -- первая ячейка нового (несуществующего или пустого) .ipynb
            vim.g.jupyter_new_notebook = {
                "```python",
                "import polars as pl",
                "import nb_utils",
                "from nb_utils import run_query",
                "",
                "%connect rs",
                "```",
            }
        end,
        opts = {
            kernel_name = "jupyter-utils", -- ~/Library/Jupyter/kernels (Мак) или ~/.local/share/jupyter/kernels (Linux)
            -- Выход из редактора ядро не гасит: тяжёлые фреймы после долгого запроса к
            -- Redshift стоят дороже перезапуска nvim. Вернуться к живому ядру —
            -- :JupyterAttach, плагин сам предложит это при открытии ноутбука.
            -- Забытые ядра видно в :checkhealth jupyter, снимаются :JupyterOrphans!
            keep_kernel_on_exit = true,
            -- в терминале рендерить itables нечем: ядро должно знать это с рождения
            env = { NB_UTILS_ITABLES = "0" },
            -- дробный size = доля экрана; в высокое окно справа влезает много строк
            -- статус на строке закрывающего фенса, поверх черты render-markdown
            -- (border = "thin"): прилегает к телу и сам служит нижней границей ячейки.
            -- При border = "hide" строка фенса скрыта — тогда нужен дефолтный "below".
            status = { position = "fence" },
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
                -- закрепить вывод ячейки в окне над основным; повтор на той же ячейке
                -- или q в закреплённом окне — снять
                pin_output = "<leader>np",
                show_toc = "<leader>nT", -- оглавление: заголовки и ячейки со статусом
                open_table = "<leader>nt",
                -- картинки ячейки во всю вкладку; <Tab>/<S-Tab> листают, как в таблице.
                -- f как «figure», а не I: <leader>ni рядом — прерывание ядра
                open_image = "<leader>nf",
                edit_cell_args = "<leader>ng", -- параметры %%sql: спросит, подставив нынешние
                -- перестройка ячеек; m и y — как в командном режиме Jupyter
                split_cell = "<leader>ns",
                merge_cell = "<leader>nM",
                move_cell_up = "<leader>nK",
                move_cell_down = "<leader>nJ",
                cell_to_markdown = "<leader>nm",
                cell_to_code = "<leader>ny",
                -- python ↔ sql: правит слово в фенсе, %%sql плагин соберёт сам
                cell_lang = "<leader>nl",
                -- начало и конец своей ячейки; пара к ]n / [n по соседним
                cell_start = "[N",
                cell_end = "]N",
                -- листание истории прогонов ячейки: ]r / [r свободны
                prev_run = "[r",
                next_run = "]r",
                interrupt = "<leader>ni",
                restart = "<leader>nR",
                -- спросить агента про ячейку под курсором; из visual — про выделение.
                -- Промпт набирается в плавающем окне, уезжает в панель tmux с claude,
                -- метка на ячейке встаёт сразу по нажатию.
                ask = "<leader>nq",
                ask_notebook = "<leader>nQ", -- то же про весь ноутбук (:JupyterAsk!)
            },
        },
    },
}
