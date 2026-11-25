" Loaded with -u, so it stands in for the whole vimrc.
"
" There are two sets of tests, run one after the other by run.sh:
"
" driver.ex is *typed* into Vim with `vim -s`, rather than sourced:
" TextChanged is checked when Vim returns to its main input loop, so a `dd`
" inside a sourced script or a function never fires it and the plugin never
" sees the edit. Only real keystrokes exercise the real path.
"
" timed.vim covers what `vim -s` can't. Under -s there is always more input
" waiting, so ` never draws the list (it skips that when the mark is already
" typed ahead) and SafeState never fires. timed.vim types its keys from
" timers instead, with gaps in between where Vim waits for input as it does
" for a person.
"
" This file is the scaffolding both call into.

set nocompatible
set hidden
set noswapfile nobackup nowritebackup
" Nothing may ever wait for a keypress: the driver is a fixed keystroke
" stream, and a hit-enter prompt would eat the next test's input.
set nomore report=9999 shortmess=aoOtTWAIcFs noerrorbells belloff=all
" A typed <Esc> is otherwise taken for the start of a key code until
" 'timeoutlen' runs out, a whole second, and timed.vim's next step runs first.
set ttimeout ttimeoutlen=10
execute 'set runtimepath^=' . fnameescape($EML_ROOT)
runtime plugin/editable-mark-list.vim
" The mapping the docs suggest.
nnoremap ` <Cmd>call editableMarkList#Pick()<CR>

let g:pass = 0
let g:fail = 0
let g:log = []
let g:result_file = 'result.txt'

" Flushed after every assertion, not just at the end: if the driver desyncs
" and Vim sits waiting for input that never comes, the partial file is the
" only evidence of how far the run got.
function! Flush() abort
    call writefile(g:log, g:result_file)
endfunction

function! Describe(name) abort
    call add(g:log, '')
    call add(g:log, a:name)
    call Flush()
endfunction

function! Ok(cond, msg) abort
    if(a:cond)
        let g:pass += 1
        call add(g:log, '  ok    ' . a:msg)
    else
        let g:fail += 1
        call add(g:log, '  FAIL  ' . a:msg)
    endif
    call Flush()
endfunction

function! Is(got, want, msg) abort
    if(a:got ==# a:want)
        call Ok(1, a:msg)
    else
        call Ok(0, a:msg . '  [got ' . string(a:got) . ', want ' . string(a:want) . ']')
    endif
endfunction

function! Skip(msg) abort
    call add(g:log, '  skip  ' . a:msg)
    call Flush()
endfunction

" Each test starts from nothing: no buffers, lists included, and no global
" marks. Local marks go with their buffers.
function! Reset() abort
    silent! only
    silent! %bwipeout!
    delmarks A-Z0-9
endfunction

" The mark on each line of the current list, top to bottom ('' for a line
" with none).
function! Shown() abort
    return map(getline(1, '$'), 'matchstr(v:val, ''^\s*\zs\S\ze\%(\s\|$\)'')')
endfunction

function! LineOf(mark) abort
    return index(Shown(), a:mark) + 1
endfunction

function! GotoMark(mark) abort
    let l:n = LineOf(a:mark)
    call Ok(l:n > 0, 'the list has a line for mark ' . a:mark)
    if(l:n > 0)
        call cursor(l:n, 1)
    endif
endfunction

" Where a mark is, or [] if it isn't set: [lnum, col] for a local mark of
" the buffer named a:1, [file name, lnum] for a global mark.
function! Where(mark, ...) abort
    if(a:mark =~# '^[A-Z0-9]$')
        for l:m in getmarklist()
            if(l:m.mark ==# "'" . a:mark)
                return [fnamemodify(l:m.file, ':t'), l:m.pos[1]]
            endif
        endfor
        return []
    endif
    let l:buf = bufnr(a:1)
    if(l:buf < 0)
        return []
    endif
    for l:m in getmarklist(l:buf)
        if(l:m.mark ==# "'" . a:mark)
            return [l:m.pos[1], l:m.pos[2]]
        endif
    endfor
    return []
endfunction

function! MarkLists() abort
    return filter(range(1, bufnr('$')), 'bufexists(v:val) && getbufvar(v:val, "&filetype") ==# "marklist"')
endfunction

" Same test as the plugin's: Neovim's extmarks, or Vim's text properties
" once they can go above a line and work with 'nowrap'.
let g:hints_supported = has('nvim-0.6') || (has('textprop') && has('patch-9.0.0451'))

" Every virtual line in the current buffer as [lnum, text], in the order on
" screen: the line it is drawn above, and what it says.
function! Above() abort
    let l:found = []
    if(has('nvim'))
        let l:ns = nvim_create_namespace('editable-mark-list')
        for l:mark in nvim_buf_get_extmarks(0, l:ns, 0, -1, {'details': v:true})
            for l:chunks in get(l:mark[3], 'virt_lines', [])
                call add(l:found, [l:mark[1] + 1, join(map(copy(l:chunks), 'v:val[0]'), '')])
            endfor
        endfor
    elseif(g:hints_supported)
        " prop_list() gives text above a line last-drawn first: the opposite
        " of the order on screen.
        let l:by_line = {}
        for l:prop in prop_list(1, {'end_lnum': -1, 'types': ['markListHint', 'markListHeader']})
            if(get(l:prop, 'text_align', '') ==# 'above')
                let l:by_line[l:prop.lnum] = [l:prop.text] + get(l:by_line, l:prop.lnum, [])
            endif
        endfor
        for l:lnum in sort(map(keys(l:by_line), 'str2nr(v:val)'), 'n')
            call extend(l:found, map(l:by_line[l:lnum], '[l:lnum, v:val]'))
        endfor
    endif
    return l:found
endfunction

" What the virtual lines above line a:lnum say, one string per line.
function! AboveLine(lnum) abort
    return map(filter(Above(), 'v:val[0] == ' . a:lnum), 'v:val[1]')
endfunction

" The lines the plugin highlights with a match in place of 'cursorline', in
" Vim, as matchaddpos() positions.
function! CursorRowMatches() abort
    return map(filter(getmatches(), 'v:val.group ==# "CursorLine"'), 'v:val.pos1')
endfunction

function! Finish() abort
    call add(g:log, '')
    call add(g:log, printf('%d passed, %d failed', g:pass, g:fail))
    call writefile(g:log, g:result_file)
    if(g:fail > 0)
        cquit
    endif
    qall!
endfunction
