return {
	"neovim/nvim-lspconfig",
	dependencies = {
		"williamboman/mason.nvim",
		"williamboman/mason-lspconfig.nvim",
		"b0o/SchemaStore.nvim",
		"hrsh7th/nvim-cmp",
		"hrsh7th/cmp-nvim-lsp",
		"hrsh7th/cmp-buffer",
		"hrsh7th/cmp-path",
		"L3MON4D3/LuaSnip",
		"saadparwaiz1/cmp_luasnip",
	},
	config = function()
		local capabilities = require("cmp_nvim_lsp").default_capabilities()

		require("mason").setup()

		-- mason-lspconfig v2 серверы включает сам (automatic_enable) и `handlers` больше
		-- не читает: настройки серверов — через vim.lsp.config, иначе они молча не применяются
		vim.lsp.config("*", { capabilities = capabilities })
		vim.lsp.config("pyright", {
			-- uv не активирует venv: сами подсовываем python окружения,
			-- иначе pyright берёт системный python без зависимостей
			-- (polars/nb_utils и т.п. — пустой автокомплит).
			-- Каскад: .venv проекта, иначе venv jupyter-utils — ноутбуки
			-- в любых папках бегут на ядре jupyter-utils с nb_utils.
			before_init = function(_, config)
				local candidates = {
					config.root_dir and (config.root_dir .. "/.venv/bin/python"),
					vim.fn.expand("~/work/jupyter-utils/.venv/bin/python"),
				}
				for _, python in ipairs(vim.tbl_filter(function(c) return c end, candidates)) do
					if vim.fn.executable(python) == 1 then
						config.settings = config.settings or {}
						config.settings.python = config.settings.python or {}
						config.settings.python.pythonPath = python
						break
					end
				end
			end,
		})
		vim.lsp.config("lua_ls", {
			settings = { Lua = { diagnostics = { globals = { "vim" } } } },
		})
		vim.lsp.config("jsonls", {
			settings = {
				json = {
					schemas = require("schemastore").json.schemas(),
					validate = { enable = true },
				},
			},
		})
		vim.lsp.config("yamlls", {
			settings = {
				yaml = {
					schemaStore = { enable = false, url = "" },
					schemas = require("schemastore").yaml.schemas(),
				},
			},
		})

		require("mason-lspconfig").setup({
			ensure_installed = { "lua_ls", "pyright", "ruff", "jsonls", "yamlls" },
		})

		-- автодополнение
		local cmp = require("cmp")
		local luasnip = require("luasnip")

		-- dbt/jinja snippets for sql files (ref, source, config, if, for, set)
		require("custom.dbt_snippets")

		-- таблицы и колонки из кэша каталога nb_utils для sql-ячеек ноутбуков:
		-- cmp-dbee там не работает (смотрит на filetype буфера, а он markdown)
		cmp.register_source("nb_catalog", require("custom.cmp_catalog").source.new())
		-- ключевые слова, операторы и функции Redshift (статический список)
		cmp.register_source("redshift", require("custom.cmp_redshift").source.new())

		cmp.setup({
			snippet = {
				expand = function(args)
					luasnip.lsp_expand(args.body)
				end,
			},
			-- первый пункт меню выделен сразу (без noselect), поэтому первое <C-n> ведёт на второй
			completion = { completeopt = "menu,menuone" },
			mapping = cmp.mapping.preset.insert({
				["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
				["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
				["<C-y>"] = cmp.mapping.confirm({ select = true }),
				["<C-Space>"] = cmp.mapping.complete(),
				-- Tab / Shift-Tab jump between snippet placeholders; when not in a
				-- snippet they fall back to a normal tab.
				["<Tab>"] = cmp.mapping(function(fallback)
					if luasnip.expand_or_locally_jumpable() then
						luasnip.expand_or_jump()
					else
						fallback()
					end
				end, { "i", "s" }),
				["<S-Tab>"] = cmp.mapping(function(fallback)
					if luasnip.locally_jumpable(-1) then
						luasnip.jump(-1)
					else
						fallback()
					end
				end, { "i", "s" }),
			}),
			sources = {
				{ name = "nvim_lsp" },
				{ name = "nb_catalog" }, -- имена таблиц/колонок из кэша nb_utils (sql внутри ноутбука)
				{ name = "luasnip" },
				{ name = "cmp-dbee" }, -- table/column completion from the active dbee connection (sql)
				{ name = "redshift" }, -- keywords/functions Redshift (sql и sql-ячейки ноутбука)
				{ name = "buffer" },
				{ name = "path" },
			},
		})

		-- keymaps при подключении LSP
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(args)
				local opts = { buffer = args.buf }
				vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
				vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
				vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
				vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
				vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
				vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
				vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
			end,
		})

		vim.diagnostic.config({
			float = { border = "rounded", source = true },
		})
	end,
}
