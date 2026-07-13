
vim.keymap.set("n", "<leader>e", vim.cmd.Ex)

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

vim.keymap.set("x", "<leader>p", "\"_dP")

vim.keymap.set("n", "<leader>y", "\"+y")
vim.keymap.set("v", "<leader>y", "\"+y")
vim.keymap.set("n", "<leader>Y", "\"+Y")

vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

-- id of the most recently launched query, for <leader>dk (cancel).
local last_call_id = nil

-- same as require("dbee").execute(), minus the trailing dbee.open() call,
-- so running a query doesn't yank focus into the result+history layout.
-- watch the statusline and open it yourself with <leader>do when it's done.
local function dbee_execute_silent(query)
  local api = require("dbee").api
  local conn = api.core.get_current_connection()
  if not conn then
    vim.notify("dbee: no connection selected (<leader>dc to pick one)", vim.log.levels.ERROR)
    return
  end
  local call = api.core.connection_execute(conn.id, query)
  last_call_id = call and call.id
  api.ui.result_set_call(call)
end

vim.keymap.set("n", "<leader>dr", function()
  local query = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  -- tag the query with the file path (relative to nvim's cwd) so the dbee
  -- history shows the path instead of the SQL. The marker is a plain SQL
  -- comment (harmless for execution); dbee_call_log_patch renders it as the
  -- bare path with no "--" and no trailing SQL.
  local relpath = vim.fn.expand("%:.")
  if relpath ~= "" then
    query = "-- @dbee-file: " .. relpath .. "\n" .. query
  end
  dbee_execute_silent(query)
end, { desc = "DBee: run current file" })

vim.keymap.set("v", "<leader>dr", function()
  vim.cmd('noautocmd normal! "vy')
  dbee_execute_silent(vim.fn.getreg("v"))
end, { desc = "DBee: run selection" })

vim.keymap.set("n", "<leader>dk", function()
  if not last_call_id then
    vim.notify("dbee: no query to cancel", vim.log.levels.WARN)
    return
  end
  -- no-op if the call already finished
  require("dbee").api.core.call_cancel(last_call_id)
end, { desc = "DBee: cancel last query" })

vim.keymap.set("n", "<leader>dy", function()
  -- copy the whole result to the OS clipboard as CSV. Uses the store API with
  -- an explicit "+" register: the yaC mapping loses v:register, so it would
  -- otherwise land in the unnamed register and never reach pbcopy.
  local ok = pcall(function()
    require("dbee").store("csv", "yank", { extra_arg = "+" })
  end)
  if ok then
    vim.notify("dbee: result copied to clipboard (CSV)")
  else
    vim.notify("dbee: no result to copy (run a query first)", vim.log.levels.WARN)
  end
end, { desc = "DBee: copy all result rows to clipboard (CSV)" })

vim.keymap.set("n", "<leader>dc", function()
  vim.cmd("topleft 40vsplit")
  local win = vim.api.nvim_get_current_win()
  require("dbee.api.ui").drawer_show(win)
end, { desc = "DBee: show connections drawer" })

vim.keymap.set("n", "<leader>do", function()
  require("dbee").toggle()
end, { desc = "DBee: toggle result+history layout" })
vim.keymap.set("i", "jk", "<Esc>")

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
