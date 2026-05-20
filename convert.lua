--
-- small script to generate help files from the readme file
-- invoked manually via `:so convert.lua`
require('ts-vimdoc').docgen({
	input_file='README.md',
	output_file = 'doc/tfvc.txt',
	project_name='tfvc',
})

-- and also regenerate tags
vim.cmd.helptags "./doc/"

vim.print 'converted!'
