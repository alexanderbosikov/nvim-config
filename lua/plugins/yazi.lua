-- yazi как файловый менеджер вместо netrw (сам yazi — из brew).
-- netrw не отключаем: он остаётся под :Ex / :Explore, а open_for_directories
-- оставлен false, поэтому `nvim <каталог>` открывается как раньше.
---@type LazySpec
return {
    "mikavilpas/yazi.nvim",
    version = "*", -- последний стабильный тег
    event = "VeryLazy",
    dependencies = {
        { "nvim-lua/plenary.nvim", lazy = true },
    },
    keys = {
        { "<leader>e", "<cmd>Yazi<cr>", mode = { "n", "v" }, desc = "Yazi: текущий файл" },
        { "<leader>E", "<cmd>Yazi cwd<cr>", desc = "Yazi: рабочий каталог (cwd)" },
        { "<C-Up>", "<cmd>Yazi toggle<cr>", desc = "Yazi: вернуться в прошлую сессию" },
    },
    ---@type YaziConfig | {}
    opts = {
        open_for_directories = false,
        keymaps = {
            show_help = "<f1>",
        },
    },
}
