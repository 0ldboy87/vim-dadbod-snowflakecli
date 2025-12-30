# vim-dadbod-snowflakecli

Modern Snowflake CLI adapter for [vim-dadbod](https://github.com/tpope/vim-dadbod), using the `snow sql` command.

## Features

- Full integration with vim-dadbod and dadbod-ui
- Uses modern Snowflake CLI (`snow`) instead of legacy `snowsql`
- Supports all authentication methods:
  - External browser (SSO/SAML)
  - Username/password
  - OAuth tokens
  - Key pair (JWT)
  - Named connections from config file
- Table listing support for dadbod-ui
- Query parameter support for warehouse, role, schema
- Proper CSV output parsing for reliable results

## Why This Plugin?

The existing `snowflake://` adapter in vim-dadbod uses the legacy `snowsql` CLI, which is:
- Slow on macOS
- Maintenance mode (no active development)
- Limited authentication options
- Missing table listing functionality

This plugin provides:
- Modern `snow sql` CLI support (faster, actively developed)
- Better authentication options (SSO, OAuth)
- Full dadbod-ui integration with table browsing
- Improved output formatting and parsing

## Prerequisites

### 1. vim-dadbod

This plugin extends vim-dadbod. Install dadbod first from the [official repository](https://github.com/tpope/vim-dadbod).

### 2. Snowflake CLI

The Snowflake CLI (`snow`) must be installed and available in your PATH.

**Installation Options:**

**Homebrew (macOS/Linux):**
```bash
brew tap snowflakedb/snowflake-cli
brew install snowflake-cli
```

**pip:**
```bash
pip install snowflake-cli-labs
```

**Binary Download:**
See [Snowflake CLI Releases](https://github.com/Snowflake-Labs/snowflake-cli/releases)

**Verify Installation:**
```bash
snow --version
```

## Installation

Install both vim-dadbod and vim-dadbod-snowflakecli using your preferred plugin manager:

### vim-plug
```vim
Plug 'tpope/vim-dadbod'
Plug 'yourusername/vim-dadbod-snowflakecli'

" Optional but recommended for visual database browsing
Plug 'kristijanhusak/vim-dadbod-ui'
```

### packer.nvim
```lua
use {
  'yourusername/vim-dadbod-snowflakecli',
  requires = {'tpope/vim-dadbod'}
}

-- Optional
use 'kristijanhusak/vim-dadbod-ui'
```

### lazy.nvim
```lua
{
  'yourusername/vim-dadbod-snowflakecli',
  dependencies = {'tpope/vim-dadbod'},
}

-- Optional
{ 'kristijanhusak/vim-dadbod-ui' }
```

### Native Packages (Vim)
```bash
mkdir -p ~/.vim/pack/db/start
cd ~/.vim/pack/db/start
git clone https://github.com/tpope/vim-dadbod.git
git clone https://github.com/yourusername/vim-dadbod-snowflakecli.git
```

### Native Packages (Neovim)
```bash
mkdir -p ~/.local/share/nvim/site/pack/db/start
cd ~/.local/share/nvim/site/pack/db/start
git clone https://github.com/tpope/vim-dadbod.git
git clone https://github.com/yourusername/vim-dadbod-snowflakecli.git
```

## Usage

### URL Format

```
snowflakecli://[user[:password]@][account]/[database][?params]
```

**Account Format:** Use `organization-account` format, not the full URL.
- Correct: `myorg-myaccount`
- Incorrect: `myaccount.snowflakecomputing.com`

### Authentication Methods

#### 1. External Browser (Recommended)

Best for SSO/SAML authentication. Opens your browser for authentication.

```vim
:DB snowflakecli://myuser@myorg-myaccount/mydb?authenticator=externalbrowser
```

With additional parameters:
```vim
:DB snowflakecli://myuser@myorg-myaccount/mydb?authenticator=externalbrowser&warehouse=compute_wh&role=analyst
```

**Note:** Requires GUI environment. Won't work in headless SSH sessions without X forwarding.

#### 2. Username/Password

```vim
:DB snowflakecli://myuser:mypassword@myorg-myaccount/mydb
```

**Security Note:** Passwords in URLs are visible in vim history. Consider using named connections instead (see below).

#### 3. OAuth Token

```vim
:DB snowflakecli://myuser@myorg-myaccount/mydb?authenticator=oauth&token=YOUR_OAUTH_TOKEN
```

**Note:** URL-encode the token if it contains special characters.

#### 4. Key Pair (JWT)

```vim
:DB snowflakecli://myuser@myorg-myaccount/mydb?authenticator=snowflake_jwt&private_key_path=/path/to/key.pem
```

**Note:** URL-encode the path (e.g., `/` becomes `%2F`).

#### 5. Named Connection (Recommended)

Best practice: Store credentials in `~/.snowflake/config.toml` and reference by name.

**Create connection:**
```bash
snow connection add
# Follow interactive prompts
```

**Or edit config file directly:**
```toml
# ~/.snowflake/config.toml
[connections.dev]
account = "myorg-myaccount"
user = "myuser"
authenticator = "externalbrowser"
warehouse = "compute_wh"
database = "dev_db"

[connections.prod]
account = "myorg-myaccount"
user = "myuser"
authenticator = "snowflake_jwt"
private_key_path = "/home/user/.ssh/snowflake_key.pem"
warehouse = "prod_wh"
database = "prod_db"
```

**Use in vim:**
```vim
:DB snowflakecli://myorg-myaccount/mydb?connection=dev
:DB snowflakecli://myorg-myaccount/mydb?connection=prod
```

### Query Parameters

All query parameters map to `snow sql` command-line flags:

| Parameter | Maps To | Example |
|-----------|---------|---------|
| `authenticator` | `--authenticator` | `externalbrowser`, `oauth`, `snowflake_jwt` |
| `warehouse` | `--warehouse` | `compute_wh` |
| `role` | `--role` | `analyst`, `admin` |
| `schema` | `--schema` | `public`, `analytics` |
| `connection` | `--connection` | `dev`, `prod` (from config file) |
| `token` | `--token` | OAuth token value |
| `private_key_path` | `--private-key-path` | `/path/to/key.pem` |

### Basic Examples

**Save connection for reuse:**
```vim
:DB g:snowflake_dev = snowflakecli://myuser@myorg-myaccount/dev_db?authenticator=externalbrowser&warehouse=compute_wh
```

**Interactive console:**
```vim
:DB g:snowflake_dev
```

**Run query:**
```vim
:DB g:snowflake_dev SELECT * FROM customers LIMIT 10
```

**Run visual selection:**
```vim
" Select SQL in visual mode, then:
:'<,'>DB g:snowflake_dev
```

**Run query from file:**
```vim
:DB g:snowflake_dev < query.sql
```

**Ad-hoc query:**
```vim
:DB snowflakecli://myuser@myorg-myaccount/mydb?authenticator=externalbrowser SELECT CURRENT_USER(), CURRENT_DATABASE()
```

### dadbod-ui Integration

This plugin fully supports [vim-dadbod-ui](https://github.com/kristijanhusak/vim-dadbod-ui) for visual database browsing.

**Open dadbod-ui:**
```vim
:DBUI
```

**Add connection:**
1. Press `A` (Add connection)
2. Enter URL: `snowflakecli://myuser@myorg-myaccount/mydb?authenticator=externalbrowser&warehouse=compute_wh`
3. Press Enter

**Browse database:**
- Expand connection to see databases
- Expand database to see schemas
- Expand schema to see tables
- Select table to see structure
- Press `<Leader>S` on table to SELECT * FROM table

## Configuration

Optional global variables (add to your `.vimrc` or `init.vim`):

```vim
" Default authenticator method (default: 'externalbrowser')
let g:dadbod_snowflakecli_default_auth = 'externalbrowser'

" Query timeout in milliseconds (default: 30000 = 30 seconds)
let g:dadbod_snowflakecli_timeout = 60000
```

## Troubleshooting

### "snow: command not found"

**Problem:** Snowflake CLI is not installed or not in PATH.

**Solution:**
1. Install Snowflake CLI (see [Prerequisites](#2-snowflake-cli))
2. Verify: `snow --version`
3. If installed but not found, add to PATH:
   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   export PATH="$PATH:/path/to/snow"
   ```

### External browser doesn't open

**Problem:** Running in headless environment (SSH without X forwarding).

**Solution:**
1. Use username/password auth instead:
   ```vim
   :DB snowflakecli://user:pass@account/db
   ```
2. Or use named connection with cached credentials:
   ```bash
   # On local machine with browser
   snow connection add --connection dev --authenticator externalbrowser
   # Authenticate once, then connection is cached
   ```
3. Or enable X forwarding in SSH:
   ```bash
   ssh -X user@host
   ```

### Tables not showing in dadbod-ui

**Problem:** Schema not specified or insufficient privileges.

**Solution:**
1. Specify schema explicitly:
   ```vim
   :DB snowflakecli://user@account/db?authenticator=externalbrowser&schema=public
   ```
2. Check privileges:
   ```sql
   SHOW GRANTS TO USER myuser;
   ```
3. Debug table listing:
   ```vim
   :echo db#adapter#snowflakecli#tables('snowflakecli://user@account/db?authenticator=externalbrowser&schema=public')
   ```

### Authentication fails

**Problem:** Invalid account format or credentials.

**Solutions:**

1. **Check account format:**
   - Use `organization-account` format
   - Example: `myorg-myaccount` not `myaccount.snowflakecomputing.com`
   - Find in Snowflake web UI: Account → Account dropdown

2. **Verify credentials:**
   - Test with `snow` CLI directly:
     ```bash
     snow sql --account myorg-myaccount --user myuser --authenticator externalbrowser --query "SELECT 1"
     ```

3. **Check user permissions:**
   - Ensure user has access to database/warehouse
   - Contact Snowflake admin if needed

### Key pair authentication fails

**Problem:** Invalid key file or permissions.

**Solutions:**

1. **Check file permissions:**
   ```bash
   chmod 600 ~/.ssh/snowflake_key.pem
   ```

2. **Verify key format:**
   - Must be encrypted private key in PEM format
   - Generate if needed:
     ```bash
     openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_key.pem
     ```

3. **Test key with snow CLI:**
   ```bash
   snow sql --account myorg-myaccount --user myuser \
     --authenticator snowflake_jwt \
     --private-key-path ~/.ssh/snowflake_key.pem \
     --query "SELECT 1"
   ```

### URL encoding issues

**Problem:** Special characters in password/path break parsing.

**Solution:** URL-encode special characters:
- `/` → `%2F`
- `:` → `%3A`
- `@` → `%40`
- `#` → `%23`
- `?` → `%3F`

**Example:**
```vim
" Password: my#pass@123
:DB snowflakecli://user:my%23pass%40123@account/db
```

## Comparison with Legacy snowflake:// Adapter

| Feature | snowflake:// (snowsql) | snowflakecli:// (snow) |
|---------|------------------------|------------------------|
| CLI Tool | Legacy `snowsql` | Modern `snow sql` |
| Performance | Slow (esp. on macOS) | Fast |
| SSO/Browser Auth | Limited support | Full support |
| OAuth | No | Yes |
| Table Listing | No (missing `tables()`) | Yes |
| dadbod-ui Integration | No | Yes |
| Active Development | Maintenance mode | Active |
| Output Formats | TSV | CSV, JSON, TABLE |
| Named Connections | Limited | Full support |

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with multiple auth methods
5. Submit a pull request

## License

Same as Vim itself. See `:help license` in Vim.

## Credits

- Adapter pattern based on [vim-dadbod](https://github.com/tpope/vim-dadbod) by Tim Pope
- Snowflake CLI by Snowflake Inc.

## Links

- [vim-dadbod](https://github.com/tpope/vim-dadbod) - The base database plugin
- [vim-dadbod-ui](https://github.com/kristijanhusak/vim-dadbod-ui) - Visual database browser
- [Snowflake CLI Documentation](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index)
- [Snowflake CLI on GitHub](https://github.com/Snowflake-Labs/snowflake-cli)
