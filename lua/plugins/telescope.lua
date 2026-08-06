return {
    'nvim-telescope/telescope.nvim',

    tag = "v0.1.9",

    dependencies = {
        'nvim-lua/plenary.nvim',
        -- optional but recommended
        { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    },

    config = function()
	require('telescope').setup({})

	local builtin = require('telescope.builtin')
	vim.keymap.set('n', '<leader>ff', builtin.find_files, {})

	-- Поиск в конкретной рабочей директории, не меняя cwd: s = sandbox,
	-- d = dbt-dwh. Заглавная (<leader>Fs/<leader>Fd) — live_grep по содержимому.
	-- Пути берём из vim.g.work_dirs (custom/remap.lua).
	for suffix, key in pairs({ s = 'sandbox', d = 'dbt' }) do
		local dir = function() return vim.g.work_dirs[key] end
		vim.keymap.set('n', '<leader>f' .. suffix, function()
			builtin.find_files({ cwd = dir() })
		end, { desc = 'Find files in ' .. key })
		vim.keymap.set('n', '<leader>F' .. suffix, function()
			builtin.live_grep({ cwd = dir() })
		end, { desc = 'Live grep in ' .. key })
	end
	vim.keymap.set('n', 'C-p', builtin.git_files, {})	
	vim.keymap.set('n', '<leader>ps', function() 
		builtin.grep_string({ search = vim.fn.input("Grep > ") })
	end)
     end
}
