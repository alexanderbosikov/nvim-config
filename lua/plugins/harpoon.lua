return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },

    config = function()
	local harpoon = require("harpoon")

	harpoon:setup()

	vim.keymap.set("n", "<leader>A", function()
		harpoon:list():prepend()
	end)
	vim.keymap.set("n", "<leader>a", function()
		harpoon:list():add()
	end)
	vim.keymap.set("n", "<C-e>", function()
		harpoon.ui:toggle_quick_menu(harpoon:list())
	end)

    -- Ctrl+h/j/k/l to jump to harpoon slots 1..4 — hold Ctrl, tap the letter.
    -- Ctrl is free here: Aerospace binds only alt-* globally, so unlike <M-…>
    -- these actually reach nvim. (ipairs index = slot number.)
    for idx, key in ipairs { "h", "j", "k", "l" } do
          vim.keymap.set("n", "<C-" .. key .. ">", function()
            harpoon:list():select(idx)
          end)
    end
    end,
}
