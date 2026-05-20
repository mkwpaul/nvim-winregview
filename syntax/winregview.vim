" Syntax highlighting for Windows Registry key view buffers

" Comments (lines starting with #)
syn match Comment "#.*"

" Section headers (## Subkeys, ## Values)
syn match Function "##.*"

" Parent navigation hint
syn match Special "\.\. (parent:.*)"

" Registry key entries
syn match Directory "\[KEY\]"

" Registry value type tags
syn match Type "\[String\s*\]"
syn match Type "\[ExpandString\s*\]"
syn match Type "\[Binary\s*\]"
syn match Type "\[DWord\s*\]"
syn match Type "\[QWord\s*\]"
syn match Type "\[MultiString\s*\]"
syn match Type "\[None\s*\]"

" Default value name
syn match Identifier "(Default)"

" Trailing backslash for keys
syn match Delimiter "\\\s*$"

" Empty message
syn match Comment "(No subkeys or values)"
