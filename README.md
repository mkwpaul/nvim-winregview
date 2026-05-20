# nvim-winregview

A Neovim plugin for browsing and viewing the Windows Registry,
similar to browsing files in a directory.

Inspired by oil.nvim.

Vibe-coded. (Its not that complicated)

## Features

- Browse Windows Registry keys hierarchically
- View registry values with type and data information
- Navigate using familiar Vim keybindings (`<CR>`, `-`, `q`)
- Read-only viewing (safe to explore without accidental modifications)
- Uses native Windows `reg.exe` utility (no external dependencies)
- Async operations (non-blocking)

## Requirements

- Neovim >= 0.9.0
- Windows OS
- `reg.exe` (included with Windows)

## Installation

Add the repo using the plugin-manager of your choice.
There are no options.

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
- `q` - Close the buffer
- Standard Vim navigation (`j`, `k`, `gg`, `G`, `/`, etc.)

### URL Format

The plugin uses custom URL schemes for navigation:

```
winreg:///key/HKEY_LOCAL_MACHINE\Software\Microsoft
winreg:///value/HKLM\Software\Microsoft#value=ProductName
```

You can also use these URLs directly with `:edit`:

```vim
:edit winreg:///key/HKLM\Software
```

## Registry Root Keys

The plugin supports all standard Windows registry root keys:

| Full Name | Abbreviation |
|-----------|--------------|
| HKEY_CLASSES_ROOT | HKCR |
| HKEY_CURRENT_USER | HKCU |
| HKEY_LOCAL_MACHINE | HKLM |
| HKEY_USERS | HKU |
| HKEY_CURRENT_CONFIG | HKCC |

## Registry Value Types

The plugin recognizes and displays these registry value types:

- `String` (REG_SZ)
- `ExpandString` (REG_EXPAND_SZ)
- `Binary` (REG_BINARY)
- `DWord` (REG_DWORD)
- `QWord` (REG_QWORD)
- `MultiString` (REG_MULTI_SZ)
- `None` (REG_NONE)

## Example Workflow

1. Start at the root:
   ```vim
   :WinReg
   ```

2. Navigate to a root key by pressing `<CR>` on `HKEY_LOCAL_MACHINE\`

3. Browse subkeys by pressing `<CR>` on any `[KEY]` entry

4. View a registry value by pressing `<CR>` on any value entry

5. Go back with `-` or close with `q`

## Buffer Types

### Registry Key Buffer (`filetype=winregview`)

Shows a formatted list of subkeys and values:

```
# Registry Key: HKEY_CURRENT_USER\Software

.. (parent: HKEY_CURRENT_USER)

## Subkeys (3)

[KEY]  Microsoft\
[KEY]  Adobe\
[KEY]  Google\

## Values (2)

[String]        AppName       My Application
[DWord]         Version       1
```

### Registry Value Buffer (`filetype=winregvalue`)

Shows detailed information about a specific registry value:

```
# Registry Value

Path:  HKEY_CURRENT_USER\Software\MyApp
Name:  Version
Type:  DWord (REG_DWORD)

## Data

0x1
```

## Limitations

- **Read-only**: This plugin is intentionally read-only for safety. Use Windows `regedit.exe` to make modifications.
- **Permissions**: Some registry keys require administrator privileges. Run Neovim as administrator to access protected keys.
- **Binary Data**: Binary values are displayed as-is from `reg.exe` output (usually hex format).
- **Large Keys**: Keys with thousands of subkeys/values may take time to load.

## Safety

This plugin is **read-only** and uses `reg.exe query` commands exclusively. It cannot modify, create, or delete any registry keys or values. This makes it safe to explore the Windows Registry without risk of system damage.

## Troubleshooting

### "Access Denied" errors

Some registry keys require administrator privileges. Run Neovim as administrator:

```powershell
# Run PowerShell as Administrator, then:
nvim
```

### reg.exe not found

The `reg.exe` utility should be included with Windows. Verify it's in your PATH:

```powershell
reg.exe /?
```

### Buffer doesn't load / shows error

Check the error message with `:messages`. Common issues:
- Invalid registry path
- Access denied (requires admin rights)
- Registry key doesn't exist

## Configuration

The plugin works out of the box with no configuration required. However, you can customize keybindings:

```lua
-- Add custom keybindings for quick access to common registry locations
vim.api.nvim_create_user_command('RegRun', function()
  vim.cmd('WinReg HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run')
end, { desc = 'Open Run registry key' })

vim.api.nvim_create_user_command('RegUninstall', function()
  vim.cmd('WinReg HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall')
end, { desc = 'Open Uninstall registry key' })

-- Add a keymap to quickly open registry from normal mode
vim.keymap.set('n', '<leader>wr', ':WinReg<CR>', { desc = 'Open Windows Registry' })
```

