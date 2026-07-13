return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  config = function()
    -- one statusline for the whole editor (not one per window) —
    -- matters for split layouts like dbee_layout (result + history)
    vim.opt.laststatus = 3

    require("lualine").setup({
      options = {
        theme = "auto",
        globalstatus = true,
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { "filename" },
        lualine_x = {
          {
            function()
              return require("custom.dbee_status").text()
            end,
            -- lualine accepts a highlight-group name string here; don't pass
            -- a raw nvim_get_hl().fg integer — lualine wants "#rrggbb".
            color = function()
              return require("custom.dbee_status").color()
            end,
            cond = function()
              return require("custom.dbee_status").text() ~= ""
            end,
          },
          "filetype",
        },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    })
  end,
}
