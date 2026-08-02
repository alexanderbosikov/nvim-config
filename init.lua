vim.g.mapleader = " "

-- Изолированный python для провайдера nvim (molten: pynvim/jupyter_client/nbformat).
-- Держим отдельно от venv'ов проектов, чтобы зависимости не пересекались.
-- Задаём ДО lazy.setup: иначе :UpdateRemotePlugins при установке molten
-- побежит на системном python3, где нет pynvim.
vim.g.python3_host_prog = vim.fn.expand("~/.venvs/neovim/bin/python")

require("custom.lazy")
require("custom")
