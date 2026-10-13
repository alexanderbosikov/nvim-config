return {
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		lazy = false,
		init = function()
			local parsers = {
				"lua",
				"vim",
				"vimdoc",
				"query",
				"python",
				"sql",
				"bash",
				"yaml",
				"toml",
				"xml",
				"json",
				"markdown",
				"markdown_inline",
				"gitignore",
				"diff",
				"jinja",
				"jinja_inline",
			}

			-- dbt: sql-файлы внутри проекта с dbt_project.yml парсятся jinja-парсером
			-- под отдельным именем языка "dbt" (queries/dbt/*), SQL инжектится в content.
			-- filetype остаётся sql — линтер, сниппеты, LSP не задеты.
			pcall(function()
				local path = vim.api.nvim_get_runtime_file("parser/jinja.so", false)[1]
				vim.treesitter.language.add("dbt", { path = path, symbol_name = "jinja" })
			end)

			local function ts_lang(buf)
				if vim.bo[buf].filetype ~= "sql" then
					return nil
				end
				if vim.b[buf].ts_dbt == nil then
					local name = vim.api.nvim_buf_get_name(buf)
					local found = name ~= ""
						and vim.fs.find("dbt_project.yml", { upward = true, path = vim.fs.dirname(name) })[1]
					vim.b[buf].ts_dbt = found and true or false
				end
				return vim.b[buf].ts_dbt and "dbt" or nil
			end

			local group = vim.api.nvim_create_augroup("ThePrimeagenTreesitter", { clear = true })
			vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
				group = group,
				callback = function(ev)
					if vim.bo.buftype ~= "" then
						return
					end

					pcall(vim.treesitter.start, ev.buf, ts_lang(ev.buf))
				end,
			})

			vim.api.nvim_create_autocmd("User", {
				group = group,
				pattern = "VeryLazy",
				once = true,
				callback = function()
					require("nvim-treesitter").install(parsers)
				end,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		lazy = false,
		config = function()
			require("nvim-treesitter-textobjects").setup({
				select = {
					enable = true,
					lookahead = true,
					keymaps = {
						["af"] = "@function.outer",
						["if"] = "@function.inner",
					},
				},
			})
		end,
	},
}
