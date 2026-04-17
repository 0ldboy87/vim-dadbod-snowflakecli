# Vim-Dadbod Adapter Blueprint

This document provides a blueprint for creating a vim-dadbod adapter, detailing the required functions and their return types.

## Core Functions

### 1. `interactive`
**Definition:**
```vim
function! db#adapter#<adapter_name>#interactive(url) abort
```
**Purpose:** Builds the command for interactive database usage based on the connection URL.
**Return Type:**
- A list representing the shell command to execute for interactive usage.

### 2. `filter`
**Definition:**
```vim
function! db#adapter#<adapter_name>#filter(url) abort
```
**Purpose:** Filters additional flags or settings required for database interaction.
**Return Type:**
- A list representing the shell command with additional flags applied.

### 3. `input`
**Definition:**
```vim
function! db#adapter#<adapter_name>#input(url, in) abort
```
**Purpose:** Executes a SQL input file against the database.
**Return Type:**
- A list containing the command to execute the SQL input.

### 4. `complete_opaque`
**Definition:**
```vim
function! db#adapter#<adapter_name>#complete_opaque(url) abort
```
**Purpose:** Completes opaque database-specific identifiers.
**Return Type:**
- A list of completed identifiers or a forwarding call to `complete_database`.

### 5. `complete_database`
**Definition:**
```vim
function! db#adapter#<adapter_name>#complete_database(url) abort
```
**Purpose:** List available databases for autocompletion.
**Return Type:**
- A list of string database names.

## Optional Functions

### 6. `tables`
**Definition:**
```vim
function! db#adapter#<adapter_name>#tables(url) abort
```
**Purpose:** Lists tables within a specific database.
**Return Type:**
- A list of string table names.

### 7. `auth_pattern`
**Definition:**
```vim
function! db#adapter#<adapter_name>#auth_pattern() abort
```
**Purpose:** Specifies error patterns for authentication.
**Return Type:**
- A string containing a regex pattern.

### 8. `canonicalize`
**Definition:**
```vim
function! db#adapter#<adapter_name>#canonicalize(url) abort
```
**Purpose:** Converts and normalizes URL schemas and parameters.
**Return Type:**
- A string of the canonicalized URL.

## General Notes
1. Each adapter function should parse the URL, extract parameters, and create custom commands that follow the CLI conventions of the target database.
2. Shell commands should be returned as lists to ensure arguments and flags are handled safely.
3. Utilize `db#url#parse` to extract URL components effectively.

Follow this blueprint to ensure adherence to vim-dadbod standards when creating new adapters.

