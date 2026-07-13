-- dbt / Jinja snippets for SQL files, exposed through nvim-cmp (source "luasnip").
-- Type the trigger in insert mode, pick it from the completion menu (<C-y>),
-- then Tab/Shift-Tab to jump between the placeholders.
--
-- fmta uses <> for placeholders, so the literal {{ }} / {% %} need no escaping.
local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmta = require("luasnip.extras.fmt").fmta

ls.add_snippets("sql", {
  -- {{ ref('model') }}
  s("ref", fmta("{{ ref('<>') }}", i(1))),

  -- {{ source('schema', 'table') }}
  s("source", fmta("{{ source('<>', '<>') }}", { i(1), i(2) })),

  -- {{ var('name') }}
  s("var", fmta("{{ var('<>') }}", i(1))),

  -- Default incremental config block. The static parts are inserted as-is;
  -- the varying fields (<1> unique_key, <2> sort, <3> tags) are placeholders
  -- pre-filled with defaults — Tab through to edit, or leave them.
  s("config", fmta(
    [[
{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['<>'],
        sort=['<>'],
        dist='auto',
        tags=["<>"],
    )
}}]],
    {
      i(1, "event_date"),
      i(2, "event_date"),
      i(3, "redshift_metabase_daily"),
    }
  )),

  -- {% if cond %} ... {% endif %}
  s("if", fmta([[
{% if <> %}
    <>
{% endif %}
]], { i(1), i(2) })),

  -- {% for x in seq %} ... {% endfor %}
  s("for", fmta([[
{% for <> in <> %}
    <>
{% endfor %}
]], { i(1), i(2), i(3) })),

  -- {% set name = value %}
  s("set", fmta("{% set <> = <> %}", { i(1), i(2) })),
})
