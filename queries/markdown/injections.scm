; ВНИМАНИЕ: файл СПЕЦИАЛЬНО без "; extends" — это полная замена рантайм-запроса,
; и лежит он СПЕЦИАЛЬНО в queries/, а не в after/queries/: базовым запросом
; treesitter берёт первый файл без "; extends" в порядке rtp, а $VIMRUNTIME идёт
; раньше after/ — там копия просто игнорировалась бы (см. vim.treesitter.query
; .get_files). queries/ в конфиге идёт раньше рантайма, поэтому базовым
; становится этот файл; after/queries/markdown/highlights.scm с "; extends"
; по-прежнему дописывается сверху.
;
; Зачем замена: после нормализации (custom/ipynb_magics.lua) sql-ячейка выглядит
; как ```python-фенс с `%%sql` первой строкой. Стандартный паттерн берёт язык из
; info-строки и инъектирует в такой фенс python; otter собирает python-чанки
; именно по инъекциям и отдаёт тело SQL pyright/ruff — на каждой sql-ячейке
; красные подчёркивания. Ниже копия $VIMRUNTIME/queries/markdown/injections.scm
; (nvim 0.12) с двумя правками: (1) фенсы, тело которых начинается с %%sql,
; исключены из общей инъекции; (2) для них инъектируется sql — со сдвигом на
; строку магики. При обновлении nvim имеет смысл сверить копию с рантайм-файлом.

(fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content
  (#not-lua-match? @injection.content "^%%%%sql"))

; Ячейки с магикой %%sql: содержимое фенса после строки магики парсить как SQL —
; даёт SQL-подсветку и sql-commentstring для gc (см. highlights.scm).
(fenced_code_block
  (code_fence_content) @injection.content
  (#lua-match? @injection.content "^%%%%sql")
  (#offset! @injection.content 1 0 0 0)
  (#set! injection.language "sql"))

((html_block) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined)
  (#set! injection.include-children))

((minus_metadata) @injection.content
  (#set! injection.language "yaml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

((plus_metadata) @injection.content
  (#set! injection.language "toml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

([
  (inline)
  (pipe_table_cell)
] @injection.content
  (#set! injection.language "markdown_inline"))
