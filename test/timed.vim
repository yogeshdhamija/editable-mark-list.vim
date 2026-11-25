" Sourced by run.sh after startup, with no -s: see harness.vim for why.
"
" Each test is a list of steps, run one per timer tick, with Vim waiting for
" input in between the way it does for a person. A step types keys with
" feedkeys(..., 't'), which Vim then takes as typed; while ` waits for its
" mark, the next tick's step runs inside that wait, so it sees the list on
" screen, and types the mark.

let g:result_file = 'result-timed.txt'
let g:steps = []
let g:delay = 150

function! Step(cmd) abort
    call add(g:steps, a:cmd)
endfunction

function! RunSteps(...) abort
    if(empty(g:steps))
        call Finish()
        return
    endif
    let l:cmd = remove(g:steps, 0)
    try
        execute l:cmd
    catch
        call Ok(0, 'step threw ' . v:exception . ' at ' . v:throwpoint . ': ' . l:cmd)
    endtry
    call timer_start(g:delay, 'RunSteps')
endfunction

" A CTRL-C from feedkeys() leaves Vim's interrupt flag set, and the main loop
" then swallows the next key to get rid of the CTRL-C, which here getcharstr()
" has already read. Typed for real, it doesn't (checked by hand in a
" terminal). So a step that types CTRL-C is followed by one that types this,
" for the main loop to swallow instead.
let g:after_ctrl_c = 'call feedkeys("\<Ignore>", "t")'

" What ` must leave as it was, or as the built-in ` leaves it: the view, the
" alternate file, the jumplist, the '" and '' marks, and some window options.
" Buffers are named rather than numbered: each test makes its buffers anew.
function! State() abort
    let [l:jumps, l:at] = getjumplist()
    call map(l:jumps, '[bufname(v:val.bufnr), v:val.lnum, v:val.col]')
    return {'buf': bufname('%'), 'view': winsaveview(), 'alt': bufname('#'),
        \ 'jumps': [l:jumps, l:at], 'last': getpos("'\""), 'pc': getpos("''"),
        \ 'wrap': &l:wrap, 'cul': &l:cursorline, 'bufhidden': &l:bufhidden}
endfunction

" a.txt with marks a and b, the cursor on line 20, scrolled so the view is
" worth checking, and b.txt as the alternate.
function! Setup() abort
    call Reset()
    edit b.txt
    edit a.txt
    call cursor(5, 2)
    normal! ma
    call cursor(8, 1)
    normal! mb
    call cursor(15, 2)
    normal! zt
    call cursor(20, 2)
    setlocal wrap nocursorline
endfunction

" The same, for comparison, done without the plugin's mapping at all.
function! Native(keys) abort
    call Setup()
    execute 'normal! ' . a:keys
    return State()
endfunction


call Step("call Describe('` + mark: the list shows while ` waits, then the jump is the built-in one')")
call Step('let g:native = Native("`a") | call Setup() | call feedkeys("`", "t")')
call Step('call Is(&filetype, "marklist", "the list covers the window while ` waits") | call Ok(LineOf("a") > 0, "it shows mark a") | call feedkeys("a", "t")')
call Step('call Is(State(), g:native, "after the jump, everything is as the built-in `a leaves it")')

call Step("call Describe('` + CTRL-C: back where you were, nothing changed')")
call Step('call Setup() | let g:before = State() | call feedkeys("`", "t")')
call Step('call Is(&filetype, "marklist", "the list shows") | call feedkeys("\<C-c>", "t")')
call Step(g:after_ctrl_c)
call Step('call Is(State(), g:before, "everything as it was")')

call Step("call Describe('a second flash reuses the list, and leaves no trace either')")
call Step('call Setup() | let g:before = State() | call feedkeys("`", "t")')
call Step('call feedkeys("\<C-c>", "t")')
call Step(g:after_ctrl_c)
call Step('let g:lists = MarkLists() | call feedkeys("`", "t")')
call Step('call Is(&filetype, "marklist", "the list shows again") | call Is(MarkLists(), g:lists, "the same list buffer as the first time") | call feedkeys("\<C-c>", "t")')
call Step(g:after_ctrl_c)
call Step('call Is(State(), g:before, "everything as it was")')

call Step("call Describe('` + <Esc>: the list stays, in Normal mode')")
call Step('call Setup() | call feedkeys("`", "t")')
call Step('call feedkeys("\<Esc>", "t")')
call Step('call Is([&filetype, mode()], ["marklist", "n"], "in the list, in Normal mode") | call Is(bufname("#"), "a.txt", "with a.txt as the alternate") | call Is(line("."), 1, "on the first mark") | call feedkeys("jyy", "t")')
call Step('call Is(@", getline(2) . "\n", "`<Esc>jyy yanked the second line") | call feedkeys("Ggg", "t")')
call Step('call Is(line("."), 1, "gg went to the top") | call feedkeys("\<C-^>", "t")')
call Step('call Is([bufname("%"), line(".")], ["a.txt", 20], "CTRL-^ goes back")')

call Step("call Describe('` + <Esc> typed ahead: the same, without the flash')")
call Step('call Setup() | call feedkeys("`\<Esc>jyy", "t")')
call Step('call Is([&filetype, line(".")], ["marklist", 2], "in the list, and j ran there") | call Is(@", getline(2) . "\n", "yy too")')

call Step("call Describe('` + another key: the list stays, and the key runs there')")
call Step('call Setup() | call feedkeys("`", "t")')
call Step('call feedkeys("\<Down>", "t")')
call Step('call Is([&filetype, line(".")], ["marklist", 2], "<Down> moved down the list")')
call Step('call Setup() | call feedkeys("`", "t")')
call Step('call feedkeys("\<CR>", "t")')
call Step('call Is([bufname("%"), line("."), col(".")], ["a.txt", 5, 2], "<CR> jumped to the first mark")')

call Step("call Describe('` + mark typed ahead: no flash, same result')")
call Step('let g:native = Native("`b") | call Setup() | call feedkeys("`b", "t")')
call Step('call Is(State(), g:native, "as the built-in `b leaves it")')
call Step('call Setup() | call feedkeys("`Z", "t")')
call Step('call Is([bufname("%"), line(".")], ["a.txt", 20], "an unset mark goes nowhere") | call Ok(v:errmsg =~# "E20", "with the built-in error")')

call Step("call Describe('macros')")
call Step('call Setup() | call setreg("q", "") | call feedkeys("qq`axq", "t")')
call Step('call Is(getreg("q"), "`ax", "recording `a stores `a, once") | call Is(getline(5), "a", "and x ran at mark a") | call cursor(20, 1) | call feedkeys("`b@q", "t")')
call Step('call Is([line("."), getline(5)], [5, ""], "replaying it jumps to a and runs x")')
call Step('call Setup() | call setreg("q", "`Zx") | call feedkeys("@q", "t")')
call Step('call Is([line("."), getline(20)], [20, "a20"], "a macro stops at an unset mark, as the built-in ` does")')
call Step('call Setup() | call setreg("q", "`\<Esc>j") | call feedkeys("@q", "t")')
call Step('call Is([&filetype, line(".")], ["marklist", 2], "a macro with `<Esc> stays in the list, like typing it does")')

call Step("call Describe(':normal')")
call Step('call Setup() | execute "normal `a" | call Is([line("."), col(".")], [5, 2], ":normal `a jumps")')

call Step("call Describe('a buffer that wipes itself when hidden survives the flash')")
call Step('call Reset() | enew | setlocal buftype=nofile bufhidden=wipe | call setline(1, ["keep me", "x"]) | call cursor(2, 1) | execute "normal! ma" | let g:scratch = bufnr("%") | call feedkeys("`", "t")')
call Step('call Is(&filetype, "marklist", "the list shows") | call feedkeys("\<C-c>", "t")')
call Step(g:after_ctrl_c)
call Step('call Is([bufnr("%"), getline(1), &l:bufhidden], [g:scratch, "keep me", "wipe"], "still there, bufhidden as it was") | call feedkeys("`", "t")')
call Step('call feedkeys("a", "t")')
call Step('call Is([bufnr("%"), line(".")], [g:scratch, 2], "and jumping within it works")')

call Step("call Describe('an empty buffer is not taken over by the flash')")
call Step('call Reset() | let g:empty = bufnr("%") | call feedkeys("`", "t")')
call Step('call Ok(bufnr("%") != g:empty, "the list is a buffer of its own") | call feedkeys("\<C-c>", "t")')
call Step(g:after_ctrl_c)
call Step('call Is([bufnr("%"), &buftype, &filetype], [g:empty, "", ""], "back in the empty buffer, untouched")')

call Step("call Describe('no flash where the window cannot switch buffers')")
call Step('call Setup() | diffthis | call feedkeys("`", "t")')
call Step('call Is(bufname("%"), "a.txt", "a diff window keeps its buffer") | call feedkeys("a", "t")')
call Step('call Is(line("."), 5, "and the jump still works") | diffoff')

call Step("call Describe('the list updates live')")
call Step('call Setup() | split | MarkList | let g:list = bufnr("%") | wincmd w | call feedkeys("10Gmc", "t")')
call Step('call Ok(match(getbufline(g:list, 1, "$"), "^ c     10") >= 0, "a mark set in another window shows up") | call feedkeys("ggOnew\<Esc>", "t")')
call Step('call Ok(match(getbufline(g:list, 1, "$"), "^ a      6  a5") >= 0, "and moves with its line") | call feedkeys(":delmarks c\<CR>", "t")')
call Step('call Is(match(getbufline(g:list, 1, "$"), "^ c "), -1, ":delmarks takes it away") | only')

call timer_start(g:delay, 'RunSteps')
