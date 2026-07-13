-- SQL linting via sqlfluff, so syntax errors (missing commas, unbalanced
-- brackets, unparsable sections) surface as inline diagnostics live.
--
-- Uses sqlfluff's JINJA templater (not dbt): it stubs ref/source/config/var via
-- apply_dbt_builtins without spinning up dbt, so a lint takes ~1s instead of
-- ~12s. That's fast enough to run on every edit (debounced), reading the buffer
-- via stdin so it reflects unsaved changes.
--
-- Trade-off: the jinja templater doesn't run the real dbt macros, so models that
-- lean on custom macros (adapter/this/execute, etc.) may show a templating error
-- instead of a clean syntax check. The authoritative dbt-templater check still
-- lives in the project .sqlfluff for CLI / CI.
return {
  "mfussenegger/nvim-lint",
  ft = "sql",
  config = function()
    local lint = require("lint")
    lint.linters_by_ft = { sql = { "sqlfluff" } }

    local dialect = "redshift"

    local sqlfluff = lint.linters.sqlfluff
    sqlfluff.stdin = true -- lint buffer content (live, reflects unsaved edits)

    -- show only errors (parse errors / PRS), not style warnings (LT*, etc.).
    -- wrap the built-in parser and drop anything below ERROR severity.
    local base_parser = sqlfluff.parser
    sqlfluff.parser = function(output, bufnr, linter_cwd)
      local diagnostics = base_parser(output, bufnr, linter_cwd)
      return vim.tbl_filter(function(d)
        return d.severity == vim.diagnostic.severity.ERROR
      end, diagnostics)
    end

    -- dbt project root (dir with dbt_project.yml), searched upward from the file
    local function project_root()
      local start = vim.api.nvim_buf_get_name(0)
      local found = vim.fs.find({ "dbt_project.yml" }, { upward = true, path = start })[1]
      return found and vim.fs.dirname(found) or nil
    end

    local function run_lint()
      -- skip if a lint is already in flight for this buffer
      local running = require("lint").get_running(0)
      if running and #running > 0 then
        return
      end

      local root = project_root()
      local cmd
      if root and vim.fn.executable(root .. "/venv/bin/sqlfluff") == 1 then
        cmd = root .. "/venv/bin/sqlfluff" -- project venv (also fine for jinja)
      elseif vim.fn.executable("sqlfluff") == 1 then
        cmd = "sqlfluff"
      else
        return -- no sqlfluff available -> skip silently
      end

      sqlfluff.cmd = cmd
      -- jinja templater + explicit dialect, read SQL from stdin ("-")
      sqlfluff.args =
        { "lint", "--format=json", "--templater=jinja", "--dialect=" .. dialect, "-" }
      -- cwd for config discovery: project root, else the file's own dir
      local cwd = root or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
      require("lint").try_lint("sqlfluff", { cwd = cwd })
    end

    -- debounce so bursts of edits coalesce into a single lint ~600ms after you
    -- stop typing
    local timer
    local function schedule_lint()
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
      timer = vim.uv.new_timer()
      timer:start(600, 0, vim.schedule_wrap(function()
        if timer then
          timer:stop()
          timer:close()
          timer = nil
        end
        run_lint()
      end))
    end

    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
      pattern = "*.sql",
      callback = run_lint,
    })
    vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "TextChangedI" }, {
      pattern = "*.sql",
      callback = schedule_lint,
    })
  end,
}
