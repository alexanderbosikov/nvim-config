-- Claude Code в сплите (CLI уже стоит: /opt/homebrew/bin/claude).
-- Префикс <leader>c: тоггл cwd оттуда убран (custom/remap.lua), <leader>ca
-- остаётся за LSP code action (plugins/lsp.lua) — поэтому «принять правку» на cy.
return {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    event = "VeryLazy", -- иначе :ClaudeCode* появятся только после первого маппинга
    opts = {
        terminal = {
            snacks_win_opts = {
                keys = {
                    -- в terminal-режиме <leader> недоступен: пробел уедет в промпт
                    -- Claude. Прячем окно на <C-q>, не выходя в normal-режим.
                    -- <C-\><C-n> по-прежнему выводит в normal (скролл, копирование).
                    claude_hide = {
                        "<C-q>",
                        function(self)
                            self:hide()
                        end,
                        mode = "t",
                        desc = "Claude: спрятать окно",
                    },
                },
            },
        },
    },
    keys = {
        -- одна клавиша на всё: снаружи открывает/фокусирует, изнутри прячет
        -- (в terminal-режиме тот же <C-q> обрабатывает claude_hide, см. opts)
        { "<C-q>", "<cmd>ClaudeCodeFocus<cr>", desc = "Claude: показать/спрятать" },
        { "<leader>cc", "<cmd>ClaudeCode<cr>", desc = "Claude: открыть/закрыть" },
        { "<leader>cf", "<cmd>ClaudeCodeFocus<cr>", desc = "Claude: фокус в окно" },
        { "<leader>cr", "<cmd>ClaudeCode --resume<cr>", desc = "Claude: выбрать сессию" },
        { "<leader>cC", "<cmd>ClaudeCode --continue<cr>", desc = "Claude: продолжить последнюю" },
        { "<leader>cb", "<cmd>ClaudeCodeAdd %<cr>", desc = "Claude: добавить текущий файл" },
        { "<leader>cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Claude: отправить выделение" },
        { "<leader>cy", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Claude: принять правку" },
        { "<leader>cd", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Claude: отклонить правку" },
        { "<leader>cm", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Claude: выбрать модель" },
    },
}
