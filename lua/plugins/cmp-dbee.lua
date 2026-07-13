-- Schema/table/column completion for SQL, sourced from the active dbee
-- connection. Exposes an nvim-cmp source named "cmp-dbee" (added to the cmp
-- sources list in lsp.lua). Needs an active dbee connection to return results.
return {
  "MattiasMTS/cmp-dbee",
  dependencies = { "kndndrj/nvim-dbee" },
  ft = "sql",
  config = function()
    require("cmp-dbee").setup()
  end,
}
