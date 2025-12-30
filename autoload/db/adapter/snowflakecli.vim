" snowflakecli.vim - Snowflake CLI adapter for vim-dadbod
" Maintainer:   Adam
" Version:      1.0
" Description:  Modern Snowflake CLI (snow sql) adapter supporting
"               external browser, OAuth, key pair, and password authentication

" Canonicalize URL to standard format
function! db#adapter#snowflakecli#canonicalize(url) abort
  " Normalize scheme variations (snowflakecli:// or snowflakecli:)
  let url = substitute(a:url, '^snowflakecli:/\@!', 'snowflakecli:///', '')

  " Absorb standard parameters into URL structure
  " Maps: account→host, user→user, password→password, database→database
  return db#url#absorb_params(url, {
        \ 'user': 'user',
        \ 'password': 'password',
        \ 'account': 'host',
        \ 'database': 'database'})
endfunction

" Build command for interactive SQL shell
function! db#adapter#snowflakecli#interactive(url) abort
  let url = db#url#parse(a:url)
  let cmd = ['snow', 'sql']

  " Named connection shortcut - uses config from ~/.snowflake/config.toml
  if has_key(url.params, 'connection')
    return cmd + ['--connection', url.params.connection]
  endif

  " Build connection with temporary connection flag
  let cmd += ['--temporary-connection']

  " Account (required) - format: organization-account
  if has_key(url, 'host') && !empty(url.host)
    let cmd += ['--account', url.host]
  endif

  " User
  if has_key(url, 'user') && !empty(url.user)
    let cmd += ['--user', url.user]
  endif

  " Password (not used with externalbrowser auth)
  if has_key(url, 'password') && !empty(url.password)
    let cmd += ['--password', url.password]
  endif

  " Database
  if get(url, 'path', '') !~# '^/\=$'
    let db = substitute(url.path, '^/', '', '')
    if !empty(db)
      let cmd += ['--database', db]
    endif
  endif

  " Authenticator method (externalbrowser, oauth, snowflake_jwt, etc.)
  if has_key(url.params, 'authenticator')
    let cmd += ['--authenticator', url.params.authenticator]
  endif

  " OAuth token
  if has_key(url.params, 'token')
    let cmd += ['--token', url.params.token]
  endif

  " Additional connection parameters
  for param in ['warehouse', 'role', 'schema', 'private_key_path']
    if has_key(url.params, param)
      let cmd += ['--' . param, url.params[param]]
    endif
  endfor

  return cmd
endfunction

" Build command for non-interactive query execution
function! db#adapter#snowflakecli#filter(url) abort
  " Base command from interactive
  let cmd = db#adapter#snowflakecli#interactive(a:url)

  " Add CSV output format for simple parsing
  " Note: snow CLI doesn't support TSV format (unlike legacy snowsql)
  let cmd += ['--format', 'CSV']

  return cmd
endfunction

" Build command for executing SQL from a file
function! db#adapter#snowflakecli#input(url, in) abort
  return db#adapter#snowflakecli#filter(a:url) + ['--filename', a:in]
endfunction

" Get list of tables for dadbod-ui integration
" This function is CRITICAL for dadbod-ui to show tables
function! db#adapter#snowflakecli#tables(url) abort
  let cmd = db#adapter#snowflakecli#filter(a:url)

  " Try SHOW TERSE TABLES first (Snowflake-specific, efficient)
  let out = db#systemlist(cmd + ['--query', 'SHOW TERSE TABLES'])

  " Check if command succeeded
  if v:shell_error != 0
    " Fallback to information_schema query
    let query = "SELECT table_name FROM information_schema.tables WHERE table_schema = CURRENT_SCHEMA() ORDER BY table_name"
    let out = db#systemlist(cmd + ['--query', query])

    " If still fails, return empty list
    if v:shell_error != 0
      return []
    endif

    " Parse simple CSV output (single column, skip header)
    return filter(out[1:], 'v:val !~# "^\\s*$"')
  endif

  " Parse SHOW TERSE TABLES output
  " Format: created_on,name,kind,database_name,schema_name
  " We want the table name (2nd column)
  let tables = []
  for line in out
    " Skip header line
    if line =~# '^created_on\|^"created_on'
      continue
    endif

    " Skip empty lines
    if line =~# '^\s*$'
      continue
    endif

    " Simple CSV parsing - split on comma and remove quotes
    " This works for table names which don't contain commas
    let fields = split(line, ',')
    if len(fields) >= 2
      " Extract table name (2nd field), remove quotes
      let table_name = substitute(fields[1], '^"\|"$', '', 'g')
      call add(tables, table_name)
    endif
  endfor

  return tables
endfunction

" Get list of databases for tab-completion
function! db#adapter#snowflakecli#complete_database(url) abort
  let pre = matchstr(a:url, '[^:]\+://.\{-\}/')
  let cmd = db#adapter#snowflakecli#filter(pre)

  " Execute SHOW TERSE DATABASES
  let out = db#systemlist(cmd + ['--query', 'SHOW TERSE DATABASES'])

  " Check if command succeeded
  if v:shell_error != 0
    return []
  endif

  " Parse database names from output (2nd column)
  let databases = []
  for line in out
    " Skip header
    if line =~# '^created_on\|^"created_on'
      continue
    endif

    " Skip empty lines
    if line =~# '^\s*$'
      continue
    endif

    " Simple CSV parsing - split on comma and remove quotes
    let fields = split(line, ',')
    if len(fields) >= 2
      let db_name = substitute(fields[1], '^"\|"$', '', 'g')
      call add(databases, db_name)
    endif
  endfor

  return databases
endfunction

" Fallback for opaque URL completion
function! db#adapter#snowflakecli#complete_opaque(url) abort
  return db#adapter#snowflakecli#complete_database(a:url)
endfunction
