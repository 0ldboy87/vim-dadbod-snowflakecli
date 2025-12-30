" dadbod-snowflakecli.vim - Snowflake CLI adapter for vim-dadbod
" Maintainer:   Adam
" Version:      1.0
" Description:  Modern Snowflake CLI (snow sql) adapter for vim-dadbod

if exists('g:loaded_dadbod_snowflakecli') || &cp
  finish
endif
let g:loaded_dadbod_snowflakecli = 1

" Default authenticator method
" Options: 'externalbrowser', 'oauth', 'snowflake_jwt', 'password'
if !exists('g:dadbod_snowflakecli_default_auth')
  let g:dadbod_snowflakecli_default_auth = 'externalbrowser'
endif

" Query timeout in milliseconds
" Default: 30000 (30 seconds)
if !exists('g:dadbod_snowflakecli_timeout')
  let g:dadbod_snowflakecli_timeout = 30000
endif
