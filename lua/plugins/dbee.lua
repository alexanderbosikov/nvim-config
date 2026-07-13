return {
  "kndndrj/nvim-dbee",
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  build = function()
    -- Install tries to automatically detect the install method.
    -- if it fails, try calling it with one of these parameters:
    --    "curl", "wget", "bitsadmin", "go"
    require("dbee").install("go")
  end,
  config = function()
    local redshift_user = os.getenv("REDSHIFT_USER")
    local redshift_password = os.getenv("REDSHIFT_PASSWORD")
    local redshift_host = os.getenv("REDSHIFT_HOST")
    local redshift_db = os.getenv("REDSHIFT_DB")

    -- must run before setup() so the history render override is in place
    require("custom.dbee_call_log_patch")

    require("dbee").setup({
      window_layout = require("custom.dbee_layout"):new(),
      sources = {
        require("dbee.sources").MemorySource:new({
          {
            name = "redshift",
            type = "redshift",
            url = string.format(
              "postgres://%s:%s@%s:5439/%s",
              redshift_user,
              redshift_password,
              redshift_host,
              redshift_db
            ),
          },
        }),
      },
    })

    require("custom.dbee_status").register()
    -- auto-retry once on stale "bad connection" (first query after idle)
    require("custom.dbee_reconnect").register()
  end,
}
