; extends

; commentstring для sql-ячеек: gc комментирует их как SQL ("-- ").
; Метадата bo.commentstring читается встроенным comment (см. vim/_comment.lua)
; раньше, чем поиск по инъектированным языкам, поэтому без этого gc внутри
; sql-фенса вставлял бы markdown-комментарий <!-- -->.
;
; Раньше сопоставлялось с `%%sql` в теле: ячейки с магикой приводились к
; ```python-фенсу автокомандой. Теперь они остаются такими, какими их делает
; jupytext, — ```sql с magic_args в info-строке, — и цепляться надо за язык фенса.
(fenced_code_block
  (info_string (language) @_lang)
  (code_fence_content) @none
  (#eq? @_lang "sql")
  (#set! bo.commentstring "-- %s"))
