vim.g.mapleader = " "

-- Изолированный python для провайдера nvim (pynvim). Заводился под molten, тот убран,
-- но провайдер может понадобиться любому remote-плагину, а venv уже есть — оставляем.
-- Держим отдельно от venv'ов проектов, чтобы зависимости не пересекались.
-- Ядро ноутбуков берётся не отсюда: jupyter.nvim запускает сайдкар своим интерпретатором
-- (vim.g.jupyter_python), см. lua/plugins/jupyter.lua.
vim.g.python3_host_prog = vim.fn.expand("~/.venvs/neovim/bin/python")

require("custom.lazy")
require("custom")
