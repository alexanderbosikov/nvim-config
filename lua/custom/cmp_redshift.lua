-- cmp-источник: ключевые слова, операторы и функции Redshift.
--
-- Статический список по AWS Redshift Database Developer Guide (SQL reference:
-- SQL commands / SQL functions reference). SQL LSP нет, поэтому без этого
-- источника ключевые слова подсказывал только buffer — и только уже набранные.
--
-- Работает в .sql и в sql-ячейках ноутбука (markdown-буфер, sql — инъекция
-- treesitter; определяем тем же sql_region, что и nb_catalog).
-- У функций в detail — сигнатура, она видна в меню и в документации пункта.
local M = {}

local KEYWORDS = [[
  select from where group by order having limit offset qualify distinct all top
  with recursive as on using join inner left right full outer cross natural
  union intersect except minus insert into values update set delete truncate
  merge matched then create table view materialized temp temporary if exists not
  drop alter add column rename to cascade restrict primary key foreign references
  unique default null is and or in between like ilike similar escape case when
  else end cast convert asc desc nulls first last over partition rows range
  unbounded preceding following current row window filter within grouping sets
  rollup cube pivot unpivot lateral true false interval at time zone
  distkey sortkey diststyle even auto compound interleaved encode backup
  explain analyze vacuum grant revoke usage schema external stored location
  unload copy iam_role format parquet csv delimiter header gzip manifest
  begin commit rollback transaction procedure function returns language plpgsql
  call return declare loop for raise notice exception
]]

-- Операторы, которые имеет смысл предлагать словом/конструкцией.
local OPERATORS = {
  { "is distinct from", "a is distinct from b — сравнение с учётом null" },
  { "is not distinct from", "a is not distinct from b — null = null" },
  { "similar to", "строка similar to regex-шаблон SQL" },
  { "not similar to", "отрицание similar to" },
  { "ilike", "like без учёта регистра" },
  { "not ilike", "отрицание ilike" },
  { "is null", "проверка на null" },
  { "is not null", "проверка на не-null" },
  { "at time zone", "ts at time zone 'UTC'" },
  { "union all", "объединение без удаления дублей" },
  { "group by all", "группировка по всем неагрегатным колонкам" },
  { "order by", "сортировка" },
  { "partition by", "секционирование окна" },
  { "rows between unbounded preceding and current row", "рамка окна (обязательна для агрегатных оконных с order by)" },
}

-- { имя, сигнатура, описание }
local FUNCTIONS = {
  -- агрегатные
  { "count", "count([distinct] expr | *)", "число строк / непустых значений" },
  { "sum", "sum([distinct] expr)", "сумма" },
  { "avg", "avg([distinct] expr)", "среднее; для int — целочисленное, кастуй в float" },
  { "min", "min(expr)", "минимум" },
  { "max", "max(expr)", "максимум" },
  { "listagg", "listagg([distinct] expr, 'delim') within group (order by ...)", "конкатенация строк группы" },
  { "approximate count", "approximate count(distinct expr)", "приближённый count distinct (HyperLogLog)" },
  { "approximate percentile_disc", "approximate percentile_disc(p) within group (order by expr)", "приближённый перцентиль" },
  { "percentile_cont", "percentile_cont(p) within group (order by expr)", "интерполированный перцентиль" },
  { "percentile_disc", "percentile_disc(p) within group (order by expr)", "дискретный перцентиль" },
  { "median", "median(expr)", "медиана (= percentile_cont(0.5))" },
  { "stddev", "stddev(expr)", "стандартное отклонение (выборочное)" },
  { "stddev_samp", "stddev_samp(expr)", "выборочное стандартное отклонение" },
  { "stddev_pop", "stddev_pop(expr)", "генеральное стандартное отклонение" },
  { "variance", "variance(expr)", "дисперсия (выборочная)" },
  { "var_samp", "var_samp(expr)", "выборочная дисперсия" },
  { "var_pop", "var_pop(expr)", "генеральная дисперсия" },
  { "bool_and", "bool_and(expr)", "true, если все true" },
  { "bool_or", "bool_or(expr)", "true, если хоть одно true" },
  { "bit_and", "bit_and(expr)", "побитовое and по группе" },
  { "bit_or", "bit_or(expr)", "побитовое or по группе" },
  { "any_value", "any_value(expr)", "любое значение из группы" },
  { "hll", "hll(expr)", "HyperLogLog-оценка числа уникальных" },
  { "hll_create_sketch", "hll_create_sketch(expr)", "HLL-скетч" },
  { "hll_cardinality", "hll_cardinality(sketch)", "кардинальность из скетча" },
  { "hll_combine", "hll_combine(sketch)", "объединение скетчей (агрегат)" },

  -- оконные
  { "row_number", "row_number() over (partition by ... order by ...)", "номер строки в окне" },
  { "rank", "rank() over (...)", "ранг с пропусками" },
  { "dense_rank", "dense_rank() over (...)", "ранг без пропусков" },
  { "percent_rank", "percent_rank() over (...)", "(rank - 1) / (n - 1)" },
  { "cume_dist", "cume_dist() over (...)", "кумулятивное распределение" },
  { "ntile", "ntile(n) over (...)", "номер корзины из n" },
  { "lag", "lag(expr [, offset [, default]]) [ignore nulls] over (...)", "значение из предыдущей строки" },
  { "lead", "lead(expr [, offset [, default]]) [ignore nulls] over (...)", "значение из следующей строки" },
  { "first_value", "first_value(expr) [ignore nulls] over (... rows between ...)", "первое значение рамки" },
  { "last_value", "last_value(expr) [ignore nulls] over (... rows between ...)", "последнее значение рамки" },
  { "nth_value", "nth_value(expr, n) over (... rows between ...)", "n-е значение рамки" },
  { "ratio_to_report", "ratio_to_report(expr) over (partition by ...)", "доля значения в сумме окна" },

  -- условные / null
  { "coalesce", "coalesce(a, b, ...)", "первое не-null" },
  { "nvl", "nvl(a, b, ...)", "синоним coalesce" },
  { "nvl2", "nvl2(expr, if_not_null, if_null)", "выбор по null-ности" },
  { "nullif", "nullif(a, b)", "null, если a = b" },
  { "decode", "decode(expr, search, result [, search, result]... [, default])", "case-сопоставление в стиле Oracle" },
  { "greatest", "greatest(a, b, ...)", "максимум из аргументов" },
  { "least", "least(a, b, ...)", "минимум из аргументов" },

  -- дата и время
  { "getdate", "getdate()", "текущий timestamp (начало транзакции, без tz)" },
  { "sysdate", "sysdate", "текущий timestamp (начало транзакции)" },
  { "current_date", "current_date", "текущая дата" },
  { "current_timestamp", "current_timestamp", "текущий timestamptz" },
  { "date_trunc", "date_trunc('part', ts)", "округление вниз до части: day, week, month, quarter, year, hour" },
  { "trunc", "trunc(ts)", "timestamp → date; trunc(num [, scale]) для чисел" },
  { "date_part", "date_part('part', ts)", "часть даты числом (float)" },
  { "extract", "extract(part from ts)", "часть даты" },
  { "datediff", "datediff(part, start, end)", "разница в границах part между датами" },
  { "date_diff", "date_diff('part', start, end)", "синоним datediff" },
  { "dateadd", "dateadd(part, n, ts)", "прибавить n единиц part" },
  { "date_add", "date_add('part', n, ts)", "синоним dateadd" },
  { "add_months", "add_months(date, n)", "прибавить месяцы (с учётом конца месяца)" },
  { "months_between", "months_between(d1, d2)", "число месяцев между датами (дробное)" },
  { "last_day", "last_day(date)", "последний день месяца" },
  { "next_day", "next_day(date, 'weekday')", "ближайший следующий день недели" },
  { "date_cmp", "date_cmp(d1, d2)", "-1 / 0 / 1" },
  { "convert_timezone", "convert_timezone(['src_tz',] 'dst_tz', ts)", "перевод между часовыми поясами" },
  { "to_date", "to_date(str, 'fmt')", "строка → date" },
  { "to_timestamp", "to_timestamp(str, 'fmt')", "строка → timestamptz" },
  { "to_char", "to_char(ts | num, 'fmt')", "форматирование в строку" },
  { "timestamp 'epoch'", "timestamp 'epoch' + n * interval '1 second'", "unix time → timestamp" },
  { "date", "date(ts)", "приведение к date" },

  -- строки
  { "len", "len(str)", "длина строки в символах" },
  { "length", "length(str)", "длина строки в символах" },
  { "char_length", "char_length(str)", "длина строки в символах" },
  { "octet_length", "octet_length(str)", "длина в байтах" },
  { "lower", "lower(str)", "в нижний регистр" },
  { "upper", "upper(str)", "в верхний регистр" },
  { "initcap", "initcap(str)", "Каждое Слово С Заглавной" },
  { "trim", "trim([both|leading|trailing] [chars from] str)", "обрезать символы" },
  { "btrim", "btrim(str [, chars])", "обрезать с обеих сторон" },
  { "ltrim", "ltrim(str [, chars])", "обрезать слева" },
  { "rtrim", "rtrim(str [, chars])", "обрезать справа" },
  { "left", "left(str, n)", "первые n символов" },
  { "right", "right(str, n)", "последние n символов" },
  { "substring", "substring(str from start [for len]) | substring(str, start, len)", "подстрока" },
  { "substr", "substr(str, start [, len])", "подстрока" },
  { "split_part", "split_part(str, 'delim', n)", "n-я часть по разделителю (с 1)" },
  { "position", "position(sub in str)", "позиция подстроки (0, если нет)" },
  { "strpos", "strpos(str, sub)", "позиция подстроки" },
  { "charindex", "charindex(sub, str)", "позиция подстроки" },
  { "replace", "replace(str, from, to)", "замена подстроки" },
  { "translate", "translate(str, from_chars, to_chars)", "посимвольная замена" },
  { "concat", "concat(a, b)", "конкатенация двух строк (или ||)" },
  { "lpad", "lpad(str, len [, fill])", "дополнить слева" },
  { "rpad", "rpad(str, len [, fill])", "дополнить справа" },
  { "repeat", "repeat(str, n)", "повторить строку" },
  { "reverse", "reverse(str)", "развернуть строку" },
  { "quote_ident", "quote_ident(str)", "обернуть идентификатор в кавычки" },
  { "quote_literal", "quote_literal(str)", "обернуть литерал в кавычки" },
  { "md5", "md5(str)", "md5-хеш" },
  { "sha2", "sha2(str, bits)", "sha2-хеш (bits: 0/224/256/384/512)" },
  { "func_sha1", "func_sha1(str)", "sha1-хеш" },
  { "fnv_hash", "fnv_hash(expr [, seed])", "64-битный FNV-хеш" },
  { "regexp_count", "regexp_count(str, pattern [, pos [, params]])", "число совпадений regex" },
  { "regexp_instr", "regexp_instr(str, pattern [, pos [, occ [, option [, params]]]])", "позиция совпадения regex" },
  { "regexp_replace", "regexp_replace(str, pattern [, repl [, pos [, params]]])", "замена по regex" },
  { "regexp_substr", "regexp_substr(str, pattern [, pos [, occ [, params]]])", "подстрока по regex; params 'e' — группа" },

  -- числа / математика
  { "abs", "abs(x)", "модуль" },
  { "round", "round(x [, scale])", "округление" },
  { "ceil", "ceil(x)", "вверх" },
  { "ceiling", "ceiling(x)", "вверх" },
  { "floor", "floor(x)", "вниз" },
  { "mod", "mod(a, b)", "остаток (или %)" },
  { "power", "power(x, y)", "степень" },
  { "sqrt", "sqrt(x)", "корень" },
  { "cbrt", "cbrt(x)", "кубический корень" },
  { "exp", "exp(x)", "e^x" },
  { "ln", "ln(x)", "натуральный логарифм" },
  { "log", "log(x)", "логарифм по основанию 10" },
  { "sign", "sign(x)", "-1 / 0 / 1" },
  { "random", "random()", "случайное [0, 1)" },
  { "pi", "pi()", "π" },
  { "width_bucket", "width_bucket(x, low, high, n)", "номер корзины гистограммы" },

  -- приведение типов
  { "cast", "cast(expr as type)", "приведение типа (или expr::type)" },
  { "convert", "convert(type, expr)", "приведение типа" },
  { "to_number", "to_number(str, 'fmt')", "строка → число" },

  -- json / super
  { "json_extract_path_text", "json_extract_path_text(json, 'k1' [, 'k2'...] [, null_if_invalid])", "значение по пути из json-строки" },
  { "json_extract_array_element_text", "json_extract_array_element_text(json_array, pos [, null_if_invalid])", "элемент json-массива" },
  { "json_array_length", "json_array_length(json_array [, null_if_invalid])", "длина json-массива" },
  { "is_valid_json", "is_valid_json(str)", "валидный ли json" },
  { "is_valid_json_array", "is_valid_json_array(str)", "валидный ли json-массив" },
  { "json_parse", "json_parse(str)", "строка → super" },
  { "json_serialize", "json_serialize(super)", "super → строка" },
  { "json_typeof", "json_typeof(super)", "тип значения super" },
  { "can_json_parse", "can_json_parse(str)", "парсится ли в super" },
  { "is_array", "is_array(super)", "super — массив?" },
  { "is_object", "is_object(super)", "super — объект?" },
  { "get_array_length", "get_array_length(super)", "длина массива super" },
  { "split_to_array", "split_to_array(str [, 'delim'])", "строка → массив super" },
  { "array", "array(a, b, ...)", "массив super" },
  { "array_concat", "array_concat(a1, a2)", "склейка массивов" },
  { "subarray", "subarray(arr, start, len)", "кусок массива" },
  { "array_flatten", "array_flatten(arr)", "развернуть вложенные массивы" },

  -- системные
  { "current_user", "current_user", "текущий пользователь" },
  { "current_schema", "current_schema()", "текущая схема" },
  { "current_database", "current_database()", "текущая база" },
  { "pg_last_query_id", "pg_last_query_id()", "id последнего запроса сессии" },
}

local items_cache

local function build_items()
  local kinds = require("cmp").lsp.CompletionItemKind
  local items = {}
  for word in KEYWORDS:gmatch("%S+") do
    items[#items + 1] = { label = word, kind = kinds.Keyword }
  end
  for _, op in ipairs(OPERATORS) do
    items[#items + 1] = {
      label = op[1],
      kind = kinds.Operator,
      documentation = op[2],
    }
  end
  for _, fn in ipairs(FUNCTIONS) do
    items[#items + 1] = {
      label = fn[1],
      kind = kinds.Function,
      detail = fn[2],
      documentation = fn[3],
    }
  end
  return items
end

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  local ft = vim.bo.filetype
  return ft == "sql" or ft == "markdown"
end

function source:get_debug_name()
  return "redshift"
end

function source:complete(params, callback)
  if vim.bo.filetype == "markdown" then
    local row = params.context.cursor.row - 1
    local col = params.context.cursor.col - 1
    if not require("custom.cmp_catalog")._sql_region(vim.api.nvim_get_current_buf(), row, col) then
      return callback({ items = {}, isIncomplete = false })
    end
  end
  items_cache = items_cache or build_items()
  callback({ items = items_cache, isIncomplete = false })
end

M.source = source

return M
