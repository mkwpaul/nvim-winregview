" Syntax highlighting for Windows Registry value detail buffers

" Comments (lines starting with #)
syn match Comment "#.*"

" Section headers (## Data)
syn match Function "##.*"

" Field labels
syn match Identifier "^Path:"
syn match Identifier "^Name:"
syn match Identifier "^Type:"

" Registry type names
syn match Type "String"
syn match Type "ExpandString"
syn match Type "Binary"
syn match Type "DWord"
syn match Type "QWord"
syn match Type "MultiString"
syn match Type "None"

" Registry type codes in parentheses
syn match Special "(REG_[A-Z_]*)"

" Default value name
syn match Constant "(Default)"

" Hex values
syn match Number "0x[0-9A-Fa-f]\+"
