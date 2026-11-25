" editable-mark-list.vim - the mark list as an editable buffer
" Maintainer: Yogesh Dhamija <yogeshdhamija@outlook.com>
" Version 0.1

if(exists("g:loaded_editable_mark_list"))
    finish
endif
let g:loaded_editable_mark_list = 1

command! -bar MarkList call editableMarkList#Open()
