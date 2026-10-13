vim.opt.guicursor = ""

vim.opt.nu = true
vim.opt.relativenumber = true

-- netrw выставляет свои настройки буфера через setlocal, а `number` — опция ОКОННАЯ:
-- открыл файл из :Ex в том же окне, и номера строк пропали, хотя глобально они включены.
-- Ловится это `:verbose setlocal number?` — покажет netrw.vim. Поэтому в его же настройках
-- номера оставляем включёнными; остальное — дефолт netrw.
vim.g.netrw_bufsettings = "noma nomod nu rnu nobl nowrap ro"

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

vim.opt.colorcolumn = "80"

-- .inx (расширения Inkscape) — это XML
vim.filetype.add({
	extension = {
		inx = "xml",
	},
})
