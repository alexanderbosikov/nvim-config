; extends

; commentstring для %%sql-ячеек: gc комментирует их как SQL ("-- ").
; Метадата bo.commentstring читается встроенным comment (см. vim/_comment.lua)
; раньше, чем поиск по инъектированным языкам — надёжнее, чем полагаться на
; порядок обхода langtree (python и sql в фенсе оказываются на одном уровне).
(fenced_code_block
  (code_fence_content) @none
  (#lua-match? @none "^%%%%sql")
  (#set! bo.commentstring "-- %s"))
