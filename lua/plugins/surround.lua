return {
  "echasnovski/mini.surround",
  version = false,
  event = "VeryLazy",
  config = function()
    require("mini.surround").setup({
      custom_surroundings = {
        -- dbt ref(): wrap a word/selection in {{ ref('...') }}
        --   saiwr  on a word  ->  {{ ref('word') }}
        --   sar    on a visual selection
        r = {
          output = { left = "{{ ref('", right = "') }}" },
        },
        -- dbt jinja expression: wrap in {{ ... }}
        --   saiwj  ->  {{ word }}
        j = {
          output = { left = "{{ ", right = " }}" },
        },
      },
      -- default mappings: sa add, sd delete, sr replace, sf/sF find, sh highlight
    })
  end,
}
