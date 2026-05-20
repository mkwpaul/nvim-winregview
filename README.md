# nvim-winregview

A Neovim plugin for browsing and viewing the Windows Registry,
similar to browsing files in a directory.

Vibe-coded. (It's a pretty simple plugin)

## Features

- Browse Windows Registry keys hierarchically
- View registry values with type and data information
- Read-only viewing (safe to explore without accidental modifications)
- Uses native Windows `reg.exe` utility (no external dependencies)
- Async operations (non-blocking)

## Requirements

- Neovim >= 0.9.0
- Windows OS

## Installation

Add the repo using the plugin-manager of your choice, or manually with git clone and vim.opt.rtp:append('C:/path/to/nvim-winregview/')
There are no options or configuration.

## Usage

### Opening the Registry

Use the `:WinReg` command to open the Windows Registry:

```vim
" Open registry root (shows HKEY_* root keys)
:WinReg

" Open a specific registry path
:WinReg HKEY_LOCAL_MACHINE\Software

" Using abbreviations
:WinReg HKLM\Software\Microsoft

" Using forward slashes also works
:WinReg HKCU/Software
```

### Navigation Keybindings

Once in a registry view buffer:

- `<CR>` (Enter) - Navigate into subkey / View registry value
- `-` - Go to parent key
- `W` - Toggle between WOW6432Node (32-bit) and normal (64-bit) registry view, not applicable to all paths
- `q` - Close the buffer

### URL Format

The plugin uses custom URL schemes for navigation:

```
winreg:///key/HKEY_LOCAL_MACHINE\Software\Microsoft
winreg:///value/HKLM\Software\Microsoft#value=ProductName
```

You can also use these URLs directly with `:edit` and everything else that opens buffers.

```vim
:edit winreg:///key/HKLM\Software
```
Reload a buffer with `:edit!`.

## Limitations

- **Read-only**: This plugin is only queries the registry and never writes to it.
- **Permissions**: Some registry keys require administrator privileges. Run Neovim as administrator to access protected keys.
- **Binary Data**: Binary values are displayed as-is from `reg.exe` output (usually hex format).
- **Large Keys**: Keys with thousands of subkeys/values may take time to load.
