" snowflakecli.vim - Snowflake CLI adapter for vim-dadbod
" Logging utility function for debugging
function! db#adapter#snowflakecli#log_command(cmd, error) abort
  " Log the constructed command
  echom "EXECUTING: " . join(a:cmd, ' ')

  " Log errors if any
  if !empty(a:error)
    echom "ERROR: " . a:error
  endif
endfunction
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

" Skip connection test - Snowflake CLI validates on first real query
" Returning v:false tells vim-dadbod to skip the auth test entirely
function! db#adapter#snowflakecli#auth_input() abort
  return v:false
endfunction

" Build command for interactive SQL shell
function! db#adapter#snowflakecli#interactive(url) abort
  let url = db#url#parse(a:url)
  let cmd = ['snow', 'sql']

  " Named connection shortcut - uses config from ~/.snowflake/config.toml
  if has_key(url.params, 'connection')
    let cmd += ['--connection', url.params.connection]
    
    " Allow database override even with named connection
    " First try params.database, then fall back to path
    if has_key(url.params, 'database') && !empty(url.params.database)
      let cmd += ['--database', url.params.database]
    elseif get(url, 'path', '') !~# '^/\=$'
      let db = substitute(url.path, '^/', '', '')
      if !empty(db)
        let cmd += ['--database', db]
      endif
    endif
    
    return cmd
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

" Build command for non-interactive query execution via stdin pipe
" This is called by vim-dadbod when it needs to pipe SQL through stdin
function! db#adapter#snowflakecli#filter(url) abort
  " Base command from interactive
  let cmd = db#adapter#snowflakecli#interactive(a:url)

  " For filter mode, we expect SQL to be piped via stdin
  " Use JSON format for better data visualization compatibility
  let cmd += ['--stdin', '--format', 'JSON']

  return cmd
endfunction

" Build command for executing SQL from a file
function! db#adapter#snowflakecli#input(url, in) abort
  return db#adapter#snowflakecli#interactive(a:url) + ['--filename', a:in, '--format', 'JSON']
endfunction

" Track which connections have been warmed up (SSO token cached)
let s:warmed_up = {}

" Warm up authentication by running a cheap query to cache the SSO token.
" This prevents multiple browser login prompts when DBUI opens.
function! s:ensure_auth(url) abort
  let key = db#url#parse(a:url).host
  if has_key(s:warmed_up, key)
    return
  endif
  let cmd = db#adapter#snowflakecli#interactive(a:url) + ['--format', 'CSV', '--query', 'SELECT 1']
  call db#systemlist(cmd)
  let s:warmed_up[key] = 1
endfunction

" Parse Snowflake SHOW TERSE results (tables, views) into name list
function! s:snowflake_parse_objects(lines) abort
  let names = []
  for line in a:lines
    if line =~# '^\s*$' || line =~# '^created_on\|^"created_on'
      continue
    endif
    let fields = split(line, ',')
    if len(fields) >= 2
      call add(names, substitute(fields[1], '^"\|"$', '', 'g'))
    endif
  endfor
  return names
endfunction

function! s:snowflake_merge_lists(...) abort
  let merged = []
  for lst in a:000
    for item in lst
      if index(merged, item) == -1
        call add(merged, item)
      endif
    endfor
  endfor
  return sort(merged)
endfunction

" Get list of tables for dadbod-ui integration
" This function is CRITICAL for dadbod-ui to show tables
function! db#adapter#snowflakecli#tables(url) abort
  " Warm up SSO token before making multiple queries
  call s:ensure_auth(a:url)

  " Build command directly from interactive (not filter) to avoid stdin conflicts
  " The --query flag is mutually exclusive with --stdin, so we bypass filter()
  let cmd = db#adapter#snowflakecli#interactive(a:url) + ['--format', 'CSV']

  " Tables
  let tables = []
  let out = db#systemlist(cmd + ['--query', 'SHOW TERSE TABLES'])
  if v:shell_error == 0
    let tables = s:snowflake_parse_objects(out)
  else
    let table_fallback = "SELECT table_name FROM information_schema.tables WHERE table_schema = CURRENT_SCHEMA() AND table_type IN ('BASE TABLE','VIEW') ORDER BY table_name"
    let out = db#systemlist(cmd + ['--query', table_fallback])
    if v:shell_error == 0
      let tables = filter(out[1:], 'v:val !~# "^\\s*$"')
    endif
  endif

  " Views
  let views = []
  let view_out = db#systemlist(cmd + ['--query', 'SHOW TERSE VIEWS'])
  if v:shell_error == 0
    let views = s:snowflake_parse_objects(view_out)
  else
    let view_fallback = "SELECT table_name FROM information_schema.views WHERE table_schema = CURRENT_SCHEMA() ORDER BY table_name"
    let view_rows = db#systemlist(cmd + ['--query', view_fallback])
    if v:shell_error == 0
      let views = filter(view_rows[1:], 'v:val !~# "^\\s*$"')
    endif
  endif

  return s:snowflake_merge_lists(tables, views)
endfunction

" Get list of databases for tab-completion
function! db#adapter#snowflakecli#complete_database(url) abort
  let pre = matchstr(a:url, '[^:]\+://.\{-\}/')
  " Warm up SSO token before querying
  call s:ensure_auth(pre)

  " Use interactive + format instead of filter to avoid stdin flag
  let cmd = db#adapter#snowflakecli#interactive(pre) + ['--format', 'CSV']

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
