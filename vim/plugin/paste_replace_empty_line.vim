function! PasteReplaceEmptyLine()
  let line = getline('.')
  let paste_reg = @"
  if line == '' && EndsWithNewLineBreak(paste_reg)
    normal! V]p
    let @" = paste_reg
  else
    normal! ]p
  endif
endfunction

function! EndsWithNewLineBreak(paste_reg)
  return strlen(a:paste_reg) == match(a:paste_reg, '\n$') + 1
endfunction
