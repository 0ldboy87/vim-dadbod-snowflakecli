" after/plugin/dadbod_snowflakecli_schemas.vim
" Extends vim-dadbod-ui to add Snowflake schema support

" Config: set to 0 to disable column tree nodes in DBUI
if !exists('g:dadbod_snowflakecli_show_columns')
  let g:dadbod_snowflakecli_show_columns = 1
endif

" Single-query approach: information_schema.tables already contains views
" (table_type = 'VIEW'), no UNION needed.
let s:snowflake_schemas_query = join([
  \ "SELECT schema_name",
  \ "FROM information_schema.schemata",
  \ "WHERE catalog_name = current_database()",
  \ "ORDER BY schema_name"
  \ ], ' ')

let s:snowflake_schemas_tables_query = join([
  \ "SELECT table_schema, table_name",
  \ "FROM information_schema.tables",
  \ "WHERE table_catalog = current_database()",
  \ "AND table_type IN ('BASE TABLE', 'VIEW')",
  \ "ORDER BY table_schema, table_name"
  \ ], ' ')

let s:snowflake_columns_query = join([
  \ "SELECT table_schema, table_name, column_name, data_type",
  \ "FROM information_schema.columns",
  \ "WHERE table_catalog = current_database()",
  \ "ORDER BY table_schema, table_name, ordinal_position"
  \ ], ' ')

" Session cache: key = conn_url + "|" + query, value = raw result lines.
" Cleared with :DBUISnowflakeClearCache.
let s:schema_cache = {}

" Column cache: key = conn_url, value = {schema: {table: [{'name':..,'type':..},..]}}
" Populated lazily on first table expand, not during prewarm.
let s:column_cache = {}

" Track in-flight column jobs to prevent duplicates.
let s:column_jobs = {}

" Jobs in flight: key = cache_key, value = job_id.
" Prevents duplicate parallel jobs for the same query.
let s:schema_jobs = {}

" ─── Async helpers ──────────────────────────────────────────────────────────

function! s:start_async_job(cache_key, cmd, query) abort
  if has_key(s:schema_jobs, a:cache_key)
    return
  endif
  let output = []
  let job_id = jobstart(a:cmd + [a:query], {
        \ 'stdout_buffered': 1,
        \ 'on_stdout': {j, data, e -> extend(output, data)},
        \ 'on_exit': {j, code, e -> s:on_job_done(a:cache_key, output, code)},
        \ })
  if job_id > 0
    let s:schema_jobs[a:cache_key] = job_id
  endif
endfunction

" Called when a background snow sql job finishes.
" Stores the result and triggers a re-populate of any expanded snowflakecli DB.
function! s:on_job_done(cache_key, output, exit_code) abort
  call remove(s:schema_jobs, a:cache_key)
  if a:exit_code != 0
    return
  endif
  let s:schema_cache[a:cache_key] = map(a:output, {_, v -> substitute(v, "\r$", "", "")})
  call s:repopulate_expanded_dbs()
endfunction

" ─── CSV field parser (handles quoted commas) ──────────────────────────────

" Split a CSV line into fields, respecting double-quoted values.
" e.g. 'PUBLIC,MY_TABLE,ID,"NUMBER(38,0)"' → ['PUBLIC','MY_TABLE','ID','NUMBER(38,0)']
function! s:split_csv_line(line) abort
  let fields = []
  let current = ''
  let in_quotes = 0
  for ch in split(a:line, '\zs')
    if ch ==# '"'
      let in_quotes = !in_quotes
    elseif ch ==# ',' && !in_quotes
      call add(fields, trim(current))
      let current = ''
    else
      let current .= ch
    endif
  endfor
  call add(fields, trim(current))
  return fields
endfunction

" ─── Column async helpers ──────────────────────────────────────────────────

" Parse 4-column CSV (table_schema, table_name, column_name, data_type) into
" nested dict: {schema: {table: [{'name': col, 'type': dtype}, ...]}}
function! s:parse_columns_csv(results) abort
  let cols = {}
  for line in a:results[1:]
    if empty(trim(line))
      continue
    endif
    let fields = s:split_csv_line(line)
    if len(fields) < 4
      continue
    endif
    let [schema, table, col_name, dtype] = [fields[0], fields[1], fields[2], fields[3]]
    if !has_key(cols, schema)
      let cols[schema] = {}
    endif
    if !has_key(cols[schema], table)
      let cols[schema][table] = []
    endif
    call add(cols[schema][table], {'name': col_name, 'type': dtype})
  endfor
  return cols
endfunction

" Start an async job to fetch all columns for a connection.
function! s:start_column_job(conn_url) abort
  if has_key(s:column_jobs, a:conn_url) || has_key(s:column_cache, a:conn_url)
    return
  endif
  let scheme = db_ui#schemas#get('snowflakecli')
  if empty(scheme)
    return
  endif
  let cmd = db#adapter#dispatch(a:conn_url, get(scheme, 'callable', 'interactive'))
        \ + get(scheme, 'args', [])
  let output = []
  let job_id = jobstart(cmd + [s:snowflake_columns_query], {
        \ 'stdout_buffered': 1,
        \ 'on_stdout': {j, data, e -> extend(output, data)},
        \ 'on_exit': {j, code, e -> s:on_column_job_done(a:conn_url, output, code)},
        \ })
  if job_id > 0
    let s:column_jobs[a:conn_url] = job_id
  endif
endfunction

function! s:on_column_job_done(conn_url, output, exit_code) abort
  silent! call remove(s:column_jobs, a:conn_url)
  if a:exit_code != 0
    return
  endif
  let cleaned = map(a:output, {_, v -> substitute(v, "\r$", "", "")})
  let s:column_cache[a:conn_url] = s:parse_columns_csv(cleaned)
  call s:repopulate_expanded_dbs()
endfunction

" Get columns for a specific schema.table from the cache.
" Returns list of {'name':..,'type':..} or empty list.
function! s:get_cached_columns(conn_url, schema, table) abort
  if !has_key(s:column_cache, a:conn_url)
    return []
  endif
  return get(get(s:column_cache[a:conn_url], a:schema, {}), a:table, [])
endfunction

" Re-populates every expanded snowflakecli DB via the drawer.
" render({'db_key_name': key}) re-calls populate() → populate_schemas(),
" which now returns from cache immediately.
function! s:repopulate_expanded_dbs() abort
  let drawer = db_ui#drawer#get()
  if empty(drawer) || !has_key(drawer, 'dbui') || empty(drawer.dbui)
    return
  endif
  for [key, db] in items(drawer.dbui.dbs)
    if get(db, 'expanded', 0) && get(db, 'scheme', '') ==# 'snowflakecli'
      silent! call drawer.render({'db_key_name': key})
    endif
  endfor
endfunction

" ─── Pre-warming ────────────────────────────────────────────────────────────

" Kick off async schema jobs for a single snowflakecli connection URL.
function! s:prewarm_connection(conn_url) abort
  if a:conn_url !~# '^snowflakecli'
    return
  endif
  let scheme = db_ui#schemas#get('snowflakecli')
  if empty(scheme)
    return
  endif
  let cmd = db#adapter#dispatch(a:conn_url, get(scheme, 'callable', 'interactive'))
        \ + get(scheme, 'args', [])
  for query in [scheme.schemes_query, scheme.schemes_tables_query]
    let cache_key = a:conn_url . '|' . query
    if !has_key(s:schema_cache, cache_key)
      call s:start_async_job(cache_key, cmd, query)
    endif
  endfor
endfunction

" Read saved connections file and pre-warm every snowflakecli entry.
function! s:prewarm_all_saved() abort
  if empty(g:db_ui_save_location)
    return
  endif
  let conn_file = substitute(fnamemodify(g:db_ui_save_location, ':p'), '\/$', '', '')
        \ . '/connections.json'
  if !filereadable(conn_file)
    return
  endif
  for entry in json_decode(join(readfile(conn_file)))
    call s:prewarm_connection(db_ui#resolve(entry.url))
  endfor
endfunction

command! DBUISnowflakePrewarm    call s:prewarm_all_saved()
command! DBUISnowflakeClearCache let s:schema_cache = {} | let s:column_cache = {} | let s:column_jobs = {} | echom 'Snowflake schema + column cache cleared'

" Clear cache for the connection under cursor, then trigger the normal redraw.
function! s:invalidate_and_redraw() abort
  let drawer = db_ui#drawer#get()
  if empty(drawer) || !has_key(drawer, 'dbui') || empty(drawer.dbui)
    return
  endif
  let item = drawer.get_current_item()
  if empty(item) || !has_key(item, 'db_key_name')
    return
  endif
  let db = get(drawer.dbui.dbs, item.db_key_name, {})
  let conn = get(db, 'conn', '')
  if conn =~# '^snowflakecli'
    for key in keys(s:schema_cache)
      if key[:len(conn)-1] ==# conn
        call remove(s:schema_cache, key)
      endif
    endfor
    silent! call remove(s:column_cache, conn)
    silent! call remove(s:column_jobs, conn)
  endif
  call drawer.redraw()
endfunction

" ─── CSV parser ─────────────────────────────────────────────────────────────

function! s:parse_snowflake_csv(results, min_len) abort
  let rows = []
  for line in a:results[1:]  " skip header
    if empty(trim(line))
      continue
    endif
    let fields = s:split_csv_line(line)
    if a:min_len == 1
      " SELECT schema_name  → 1 field (index 0)
      " SHOW TERSE SCHEMAS  → 5 fields: created_on,name,kind,db,schema (index 1)
      if len(fields) >= 2
        call add(rows, fields[1])
      elseif len(fields) >= 1
        call add(rows, fields[0])
      endif
    elseif a:min_len == 2
      " SELECT table_schema, table_name → fields[0], fields[1]
      " SHOW TERSE TABLES               → 5 fields: index 4 (schema), 1 (name)
      if len(fields) >= 5
        call add(rows, [fields[4], fields[1]])
      elseif len(fields) >= 2
        call add(rows, [fields[0], fields[1]])
      endif
    else
      if len(fields) >= a:min_len
        call add(rows, fields)
      endif
    endif
  endfor
  return rows
endfunction

" ─── Registration ────────────────────────────────────────────────────────────

function! s:register_snowflake_schemas() abort
  if !exists('*db_ui#schemas#get') || !exists('*db_ui#schemas#query')
    return
  endif
  if exists('s:snowflake_registered')
    return
  endif
  let s:snowflake_registered = 1

  let s:snowflakecli = {
        \ 'schemes_query':        s:snowflake_schemas_query,
        \ 'schemes_tables_query': s:snowflake_schemas_tables_query,
        \ 'parse_results':        function('s:parse_snowflake_csv'),
        \ 'default_scheme':       'PUBLIC',
        \ 'quote':                1,
        \ 'callable':             'interactive',
        \ 'args':                 ['--format', 'CSV', '--query'],
        \ }

  " Patch db_ui#schemas#get to return our config for snowflakecli
  let s:orig_schemas_get = function('db_ui#schemas#get')
  function! db_ui#schemas#get(scheme) abort
    if a:scheme ==# 'snowflakecli'
      return s:snowflakecli
    endif
    return s:orig_schemas_get(a:scheme)
  endfunction

  " Patch db_ui#schemas#query with async cache for snowflakecli connections.
  "
  " Cache hit  → return stored lines immediately (no blocking)
  " Cache miss → start async job, return [] now; s:on_job_done will
  "              call render({db_key_name}) once results arrive so the
  "              drawer re-populates with real data
  let s:orig_schemas_query = function('db_ui#schemas#query')
  function! db_ui#schemas#query(db, scheme, query) abort
    let conn = type(a:db) == v:t_string ? a:db : a:db.conn
    if conn !~# '^snowflakecli'
      return s:orig_schemas_query(a:db, a:scheme, a:query)
    endif

    let cache_key = conn . '|' . a:query

    if has_key(s:schema_cache, cache_key)
      return s:schema_cache[cache_key]
    endif

    " Cache miss: fire async job and return empty for now
    let cmd = db#adapter#dispatch(conn, get(a:scheme, 'callable', 'interactive'))
          \ + get(a:scheme, 'args', [])
    call s:start_async_job(cache_key, cmd, a:query)
    return []
  endfunction
endfunction

" ─── Column tree in DBUI drawer ────────────────────────────────────────────

" Patch the drawer's render_tables to inject a Columns toggle folder with
" individual column leaf nodes for snowflakecli connections.
function! s:patch_drawer_render_tables() abort
  let drawer = db_ui#drawer#get()
  if empty(drawer) || exists('s:drawer_patched')
    return
  endif
  let s:drawer_patched = 1

  " Store the original render_tables as a Funcref.
  " We call it via call() for non-snowflakecli connections.
  let s:orig_render_tables = drawer.render_tables

  function! drawer.render_tables(tables, db, path, level, schema) abort
    if !g:dadbod_snowflakecli_show_columns || get(a:db, 'scheme', '') !=# 'snowflakecli'
      return call(s:orig_render_tables, [a:tables, a:db, a:path, a:level, a:schema], self)
    endif

    if !a:tables.expanded
      return
    endif

    if type(g:Db_ui_table_name_sorter) ==? type(function('tr'))
      let tables_list = call(g:Db_ui_table_name_sorter, [a:tables.list])
    else
      let tables_list = a:tables.list
    endif

    " Lazily trigger column fetch for this connection
    let conn = a:db.conn
    if !has_key(s:column_cache, conn) && !has_key(s:column_jobs, conn)
      call s:start_column_job(conn)
    endif

    for table in tables_list
      " Ensure columns sub-dict exists for toggle state
      if !has_key(a:tables.items[table], 'columns')
        let a:tables.items[table].columns = {'expanded': 0}
      endif

      call self.add(table, 'toggle', a:path.'->'.table, self.get_toggle_icon('table', a:tables.items[table]), a:db.key_name, a:level, { 'expanded': a:tables.items[table].expanded })

      if a:tables.items[table].expanded
        let col_item = a:tables.items[table].columns
        let col_path = a:path.'->'.table.'->columns'
        let columns = s:get_cached_columns(conn, a:schema, table)
        let col_count = len(columns)

        " Columns toggle folder
        let col_label = col_count > 0 ? 'Columns ('.col_count.')' : 'Columns'
        call self.add(col_label, 'toggle', col_path, self.get_toggle_icon('table', col_item), a:db.key_name, a:level + 1, { 'expanded': col_item.expanded })

        if col_item.expanded
          if empty(columns)
            call self.add('Loading...', 'noaction', 'column', '  ', a:db.key_name, a:level + 2)
          else
            for col in columns
              let col_display = col.name . '  ' . tolower(col.type)
              call self.add(col_display, 'noaction', 'column', '  ', a:db.key_name, a:level + 2)
            endfor
          endif
        endif

        " Remaining table helpers (skip the original 'Columns' helper)
        for [helper_name, helper] in items(a:db.table_helpers)
          if helper_name ==# 'Columns'
            continue
          endif
          call self.add(helper_name, 'open', 'table', g:db_ui_icons.tables, a:db.key_name, a:level + 1, {'table': table, 'content': helper, 'schema': a:schema })
        endfor
      endif
    endfor
  endfunction
endfunction

augroup SnowflakeCliSchemas
  autocmd!
  autocmd User DBUIOpened ++once call s:register_snowflake_schemas()
  autocmd User DBUIOpened        call s:prewarm_all_saved()
  autocmd User DBUIOpened        call s:patch_drawer_render_tables()
  autocmd FileType dbui nmap <buffer> R <Cmd>call <SID>invalidate_and_redraw()<CR>
augroup END

if exists('*db_ui#schemas#get')
  call s:register_snowflake_schemas()
endif
if exists('*db_ui#drawer#get')
  call s:patch_drawer_render_tables()
endif

" ─── Column completion for vim-dadbod-completion ────────────────────────────

" Parse CSV output from snow sql into [table_name, column_name] pairs.
" Skips the header row and strips quotes/whitespace.
function! s:parse_csv_columns(results) abort
  let rows = []
  for line in a:results[1:]
    if empty(trim(line))
      continue
    endif
    let fields = s:split_csv_line(line)
    if len(fields) >= 2
      call add(rows, [fields[0], fields[1]])
    endif
  endfor
  return rows
endfunction

function! s:parse_csv_count(result) abort
  for line in a:result[1:]
    let val = trim(substitute(line, '"', '', 'g'))
    if val =~# '^\d\+$'
      return str2nr(val)
    endif
  endfor
  return 0
endfunction

function! s:register_snowflake_completion() abort
  if !exists('*vim_dadbod_completion#schemas#get')
    return
  endif
  if exists('s:snowflake_completion_registered')
    return
  endif
  let s:snowflake_completion_registered = 1

  let s:reserved_words = vim_dadbod_completion#reserved_keywords#get_as_dict()
  let s:completion_quote_rules = {
        \ 'camelcase': {val -> val =~# '[A-Z]' && val =~# '[a-z]'},
        \ 'space': {val -> val =~# '\s'},
        \ 'reserved_word': {val -> has_key(s:reserved_words, toupper(val))}
        \ }

  function! s:snowflake_should_quote(val) abort
    if empty(trim(a:val))
      return 0
    endif
    for rule in ['camelcase', 'reserved_word', 'space']
      if s:completion_quote_rules[rule](a:val)
        return 1
      endif
    endfor
    return 0
  endfunction

  let s:snowflake_completion = {
        \ 'args': ['--format', 'CSV', '--query'],
        \ 'column_query': 'SELECT TABLE_NAME,COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS ORDER BY COLUMN_NAME ASC',
        \ 'count_column_query': 'SELECT COUNT(*) AS total FROM INFORMATION_SCHEMA.COLUMNS',
        \ 'table_column_query': {table -> 'SELECT TABLE_NAME,COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME=' . "'" . table . "' ORDER BY COLUMN_NAME ASC"},
        \ 'schemas_query': 'SELECT TABLE_SCHEMA,TABLE_NAME FROM INFORMATION_SCHEMA.COLUMNS GROUP BY TABLE_SCHEMA,TABLE_NAME',
        \ 'schemas_parser': function('s:parse_csv_columns'),
        \ 'quote': ['"', '"'],
        \ 'should_quote': function('s:snowflake_should_quote'),
        \ 'column_parser': function('s:parse_csv_columns'),
        \ 'count_parser': function('s:parse_csv_count'),
        \ }

  let s:orig_completion_get = function('vim_dadbod_completion#schemas#get')
  function! vim_dadbod_completion#schemas#get(scheme) abort
    if a:scheme ==# 'snowflakecli'
      return s:snowflake_completion
    endif
    return s:orig_completion_get(a:scheme)
  endfunction

  " If fetch() already ran for a snowflakecli buffer before this patch was
  " applied, the cache has an empty scheme and columns were never fetched.
  " Clear stale cache and re-trigger so the new schema config takes effect.
  if exists(':DBCompletionClearCache')
    silent! DBCompletionClearCache
  endif
endfunction

augroup SnowflakeCliCompletion
  autocmd!
  " vim-dadbod-completion is lazy-loaded on FileType sql. We try on the same
  " event AND on BufEnter so we catch it regardless of autocmd ordering.
  autocmd FileType sql,mysql,plsql call s:register_snowflake_completion()
  autocmd BufEnter *.sql call s:register_snowflake_completion()
augroup END

if exists('*vim_dadbod_completion#schemas#get')
  call s:register_snowflake_completion()
endif
