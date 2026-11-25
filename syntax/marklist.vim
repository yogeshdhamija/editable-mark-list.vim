" Location: syntax/marklist.vim
" Maintainer: Yogesh Dhamija <yogeshdhamija@outlook.com>

if(exists("b:current_syntax"))
    finish
endif

" Each line is a mark character, then for a local or special mark its line
" number, or for a global one its file and line number, then the text of that
" line or what the special mark is. The section titles and hints are virtual
" text, not lines, so they are highlighted where they are drawn.
"
" Everything after the mark character is anchored with a lookbehind rather
" than ^: the engine resumes scanning after the mark's match, where ^ can no
" longer match.
syntax match markListMark /^\s*\zs[a-zA-Z0-9"^.[\]<>]\ze\%(\s\|$\)/
syntax match markListLnum /\%(^\s*[a-z"^.[\]<>]\s\+\)\@<=\d\+/
syntax match markListFile /\%(^\s*[A-Z0-9]\s\+\)\@<=.\{-}:\d\+\%(\s\s\|$\)\@=/
syntax match markListDescription /\%(^\s*["^.[\]<>]\s\+\d\+\s\+\)\@<=\S.*/

highlight default link markListMark Identifier
highlight default link markListLnum Number
highlight default link markListFile Directory
highlight default link markListDescription Comment

let b:current_syntax = "marklist"
