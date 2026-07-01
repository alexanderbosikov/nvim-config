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
	vim.keymap.set('n', 'C-p', builtin.git_files, {})	
	vim.keymap.set('n', '<leader>ps', function() 
		builtin.grep_string({ search = vim.fn.input("Grep > ") })
	end)
     end
}
