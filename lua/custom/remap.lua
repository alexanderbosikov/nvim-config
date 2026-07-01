vim.keymap.set("n", "<leader>e", vim.cmd.Ex)

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

vim.keymap.set("x", "<leader>p", "\"_dP")

vim.keymap.set("n", "<leader>y", "\"+y")
vim.keymap.set("v", "<leader>y", "\"+y")
vim.keymap.set("n", "<leader>Y", "\"+Y")

vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

vim.keymap.set("n", "<leader>dr", function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  require("dbee").execute(table.concat(lines, "\n"))
end, { desc = "DBee: run current file" })

vim.keymap.set("v", "<leader>dr", function()
  vim.cmd('noautocmd normal! "vy')
  require("dbee").execute(vim.fn.getreg("v"))
end, { desc = "DBee: run selection" })
vim.keymap.set("i", "jk", "<Esc>")
vim.keymap.set('i', 'ол', '<Esc>')

for _, mode in ipairs({ "n", "i", "v" }) do
    vim.keymap.set(mode, "<Up>", "<Nop>")
    vim.keymap.set(mode, "<Down>", "<Nop>")
    vim.keymap.set(mode, "<Left>", "<Nop>")
    vim.keymap.set(mode, "<Right>", "<Nop>")
end

vim.keymap.set("n", "Q", "<Nop>")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
