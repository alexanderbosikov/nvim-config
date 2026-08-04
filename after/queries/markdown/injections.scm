; extends

; Ячейки с магикой %%sql (jupytext markdown-представление ноутбуков):
; содержимое фенса после строки магики парсить как SQL — даёт SQL-подсветку
; и sql-comментstring для gc (встроенный comment берёт язык из treesitter).
(fenced_code_block
  (code_fence_content) @injection.content
  (#lua-match? @injection.content "^%%%%sql")
  (#offset! @injection.content 1 0 0 0)
  (#set! injection.language "sql"))
