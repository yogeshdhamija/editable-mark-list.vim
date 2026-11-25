" Location: autoload/editableMarkList.vim
" Maintainer: Yogesh Dhamija <yogeshdhamija@outlook.com>

if(exists("g:autoloaded_editable_mark_list"))
    finish
endif
let g:autoloaded_editable_mark_list = 1

" The list is a plain modifiable scratch buffer, one line per mark, so
" anything that edits text works on it: dd, d2j, Vd, :g/foo/d, p. After every
" change the lines are compared with the marks the list last showed -- a line
" that disappeared deletes its mark, and a line that appeared puts back a mark
" deleted from a list earlier. Only the leading mark character is ever read
" back from the text; everything else is redrawn from reality, so a mangled
" line is swept away rather than misread.
"
" Undo is the plugin's own, not Vim's: a history of which marks each edit
" deleted and restored, and where they were, which u and CTRL-R step back and
" forth through. See s:undo.
"
" editableMarkList#Pick() is ` with the list on show: the list replaces the
" current window while Vim waits for the mark, and then the built-in ` runs.
" See s:flash.

" The marks the list shows, in the order it shows them, by section.
let s:sections = [
    \ ['Local (a-z)', 'abcdefghijklmnopqrstuvwxyz'],
    \ ['Global (A-Z)', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'],
    \ ['Numbered (0-9, previous sessions)', '0123456789'],
    \ ['Special', '"^.[]<>'],
    \ ]
let s:all_marks = join(map(copy(s:sections), 'v:val[1]'), '')

" What ` and ' accept after them: every mark the list shows, and ' and `,
" the position before the latest jump. The list leaves those two out: they
" belong to a window rather than a buffer, and getmarklist() reports the
" current window's, which in the list is the list's own.
let s:jump_marks = s:all_marks . "'`"

let s:special_desc = {
    \ '"': 'position when last exiting buffer',
    \ '^': 'position of last insert',
    \ '.': 'position of last change',
    \ '[': 'start of last change or yank',
    \ ']': 'end of last change or yank',
    \ '<': 'start of last visual selection',
    \ '>': 'end of last visual selection',
    \ }

" Marks a line can't delete: setpos() can't set ^ or . again, so deleting
" them couldn't be undone. Deleting one of their lines puts it back, with a
" message.
let s:readonly = '^.'

" A-Z and 0-9 are global: one per Vim, in whatever file. The rest belong to
" one buffer.
function! s:IsGlobal(mark) abort
    return a:mark =~# '^[A-Z0-9]$'
endfunction

" The mark character a line is for, or '' if it is for none: the first
" non-blank character, standing on its own.
function! s:ParseMark(line) abort
    let l:c = matchstr(a:line, '^\s*\zs\S\ze\%(\s\|$\)')
    return len(l:c) == 1 && stridx(s:all_marks, l:c) >= 0 ? l:c : ''
endfunction

" A mark as the list keeps it: {'mark': character, 'buf': buffer number,
" 'file': full path, 'pos': [lnum, col, off]}. 'buf' is the buffer a local
" mark belongs to; for a global mark, the buffer it is in, or 0 when that file
" has no buffer (a mark from viminfo or ShaDa). 'file' is only for global marks.
function! s:Info(mark, buf, file, pos) abort
    return {'mark': a:mark, 'buf': a:buf, 'file': a:file, 'pos': a:pos[1:3]}
endfunction

" Every mark the list would show for a:origin, as {character: info}: its local
" and special marks, and the global ones.
function! s:Marks(origin) abort
    let l:marks = {}
    if(a:origin > 0 && bufexists(a:origin))
        for l:m in getmarklist(a:origin)
            let l:c = strpart(l:m.mark, 1)
            if(len(l:c) == 1 && !s:IsGlobal(l:c) && stridx(s:all_marks, l:c) >= 0)
                let l:marks[l:c] = s:Info(l:c, a:origin, '', l:m.pos)
            endif
        endfor
    endif
    for l:m in getmarklist()
        let l:c = strpart(l:m.mark, 1)
        if(s:IsGlobal(l:c))
            let l:marks[l:c] = s:Info(l:c, l:m.pos[0], get(l:m, 'file', ''), l:m.pos)
        endif
    endfor
    return l:marks
endfunction

" Where a:info's mark is now, as an info, or {} if it isn't set.
function! s:Current(info) abort
    if(s:IsGlobal(a:info.mark))
        return get(s:Marks(0), a:info.mark, {})
    endif
    if(a:info.buf <= 0 || !bufexists(a:info.buf))
        return {}
    endif
    return get(s:Marks(a:info.buf), a:info.mark, {})
endfunction

" The text of a mark's line. Local and special marks show their line number;
" global ones the file too. Then the text of the line, when the buffer is
" loaded, or for a special mark what it is.
function! s:Format(info) abort
    let l:c = a:info.mark
    let l:lnum = a:info.pos[0]
    if(s:IsGlobal(l:c))
        let l:name = empty(a:info.file) ? '[No Name]' : fnamemodify(a:info.file, ':~:.')
        let l:line = printf(' %s  %s:%d', l:c, l:name, l:lnum)
        let l:text = a:info.buf > 0 && bufloaded(a:info.buf)
            \ ? get(getbufline(a:info.buf, l:lnum), 0, '') : ''
    else
        let l:line = printf(' %s  %5d', l:c, l:lnum)
        let l:text = has_key(s:special_desc, l:c)
            \ ? s:special_desc[l:c] : get(getbufline(a:info.buf, l:lnum), 0, '')
    endif
    let l:text = trim(l:text)
    return empty(l:text) ? l:line : l:line . '  ' . l:text
endfunction

" The list for a:origin: [lines, marks, headers]. marks is {character: info}
" for the marks on those lines; headers is [[lnum, title]], the section titles
" and the line each goes above.
function! s:Layout(origin) abort
    let l:marks = s:Marks(a:origin)
    let l:lines = []
    let l:headers = []
    for [l:title, l:chars] in s:sections
        let l:first = 1
        for l:c in split(l:chars, '\zs')
            if(has_key(l:marks, l:c))
                if(l:first)
                    call add(l:headers, [len(l:lines) + 1, l:title])
                    let l:first = 0
                endif
                call add(l:lines, s:Format(l:marks[l:c]))
            endif
        endfor
    endfor
    return [l:lines, l:marks, l:headers]
endfunction

" ---------------------------------------------------------------- the flash

" While ` waits for its mark, the list covers the window it was pressed in:
" {'win': that window, 'origin': the buffer it was showing, and what to put
" back afterwards}. Empty the rest of the time.
"
" Going there and back is done with noautocmd keepalt keepjumps, so that it
" leaves no trace: no autocmds see the buffer being left and entered again,
" and the alternate file and jumplist are untouched. The view and the '" mark
" are saved and put back by hand: leaving a buffer sets '", and coming back
" puts the cursor line wherever the window likes.
let s:flash = {}

" Whether the list may cover the current window. Some windows can't change
" buffer (the command-line window, Neovim's 'winfixbuf'), and others would be
" left wrong by it: a diff window would diff the list, and a popup or quickfix
" window is no place for it.
function! s:CanFlash() abort
    if(!empty(getcmdwintype()))
        return 0
    endif
    if(exists('*win_gettype') && win_gettype() !=# '')
        return 0
    endif
    if(exists('+winfixbuf') && &l:winfixbuf)
        return 0
    endif
    return !&l:diff
endfunction

" Shows the list over the current window. Returns whether it did.
function! s:FlashOpen() abort
    let s:flash = {'win': win_getid(), 'origin': bufnr('%'), 'view': winsaveview(),
        \ 'last': getpos("'\""), 'bufhidden': &l:bufhidden}
    try
        " A 'bufhidden' of wipe, delete or unload would destroy the buffer as
        " soon as the list replaced it.
        setlocal bufhidden=hide
        let l:reuse = s:ReusableList()
        if(l:reuse)
            execute 'noautocmd keepalt keepjumps buffer' l:reuse
        else
            execute 'noautocmd keepalt keepjumps buffer' bufadd('')
            call s:Setup()
        endif
        call s:WindowOptions()
        call s:Render(bufnr('%'))
        call cursor(1, 1)
        call s:RevealHints()
        call s:CursorRow()
        redraw
        echo '`'
        return 1
    catch
        call s:FlashClose()
        return 0
    endtry
endfunction

" Puts back the buffer the list covered, as it was.
function! s:FlashClose() abort
    if(empty(s:flash))
        return
    endif
    let l:flash = s:flash
    let s:flash = {}
    if(win_getid() == l:flash.win && bufnr('%') != l:flash.origin && bufexists(l:flash.origin))
        execute 'noautocmd keepalt keepjumps buffer' l:flash.origin
    endif
    call setbufvar(l:flash.origin, '&bufhidden', l:flash.bufhidden)
    if(bufnr('%') == l:flash.origin)
        call winrestview(l:flash.view)
        call setpos("'\"", l:flash.last)
    endif
    " Clears the ` prompt. The redraw first is what keeps this from being a
    " second line of messages after it, which would leave Vim wanting a
    " hit-enter -- and the key fed back after this, when it's <CR>, would be
    " taken for that.
    redraw
    echo ''
endfunction

function! s:GetChar() abort
    if(exists('*getcharstr'))
        return getcharstr()
    endif
    let l:c = getchar()
    return type(l:c) == v:t_number ? nr2char(l:c) : l:c
endfunction

" ` (or ' with a:1 set to it) with the list on show. The list covers the
" window while Vim waits for the next key, then:
"   a mark	the built-in ` runs, as if the list had never been there
"   <Esc>	the list stays, in Normal mode
"   CTRL-C	back where you were
"   anything else	the list stays, and the key runs there
" Nothing is drawn when the mark is already typed ahead, or a register is
" executing: fast typing and macros go straight through. The key read here is
" all a macro records besides the `, so replaying one runs this again and
" reads the same key.
function! editableMarkList#Pick(...) abort
    let l:key = a:0 ? a:1 : '`'
    let l:in_list = &filetype ==# 'marklist'
    let l:flashed = 0
    if(!l:in_list && empty(s:flash) && reg_executing() ==# '' && !getchar(1) && s:CanFlash())
        let l:flashed = s:FlashOpen()
    endif
    try
        let l:c = s:GetChar()
    catch /^Vim:Interrupt$/
        let l:c = "\<C-c>"
    finally
        if(l:flashed)
            call s:FlashClose()
        endif
    endtry

    if(len(l:c) == 1 && stridx(s:jump_marks, l:c) >= 0)
        if(l:in_list)
            call s:JumpTo(l:c, l:key)
        else
            " Not 't': this key is not typed, so it is neither recorded into
            " a register again nor taken for user input. 'i' puts it before
            " whatever else is typed ahead, the rest of a macro included, so
            " that an error here stops the macro as the built-in ` would.
            call feedkeys(l:key . l:c, 'in')
        endif
        return
    endif
    if(l:c ==# "\<C-c>")
        return
    endif
    if(!l:in_list)
        " Where the list can't go, any other key just ends the wait, as it
        " did before the list existed.
        if(!s:CanFlash())
            return
        endif
        call editableMarkList#Open()
    endif
    if(l:c !=# "\<Esc>")
        " Remapped, so that the list's own keys apply.
        call feedkeys(l:c, 'mi')
    endif
endfunction

" ---------------------------------------------------------------- jumping

" Runs the built-in a:key (` or ') for a:mark from the list's origin: the
" local marks the list shows are that buffer's. Like \bb, keepalt, and the
" jump leaves the list in the jumplist, so CTRL-O comes back to it. The
" alternate file is put back to what it was before the list, so for a local
" mark, CTRL-^ afterwards behaves as if the list was never there.
"
" ' and ` are the position before the latest jump, and the latest jump was
" the one into the list: they go back to where the cursor was in the origin,
" which is just going back to it.
function! s:JumpTo(mark, key) abort
    let l:origin = get(b:, 'editable_mark_list_origin', -1)
    if(l:origin > 0 && bufexists(l:origin) && l:origin != bufnr('%'))
        let l:alt = get(w:, 'editable_mark_list_alt', [])
        execute 'keepalt buffer' l:origin
        if(len(l:alt) == 2 && l:alt[0] == l:origin && l:alt[1] > 0
            \ && l:alt[1] != l:origin && bufexists(l:alt[1]))
            silent! let @# = l:alt[1]
        endif
    endif
    if(a:mark ==# "'" || a:mark ==# '`')
        return
    endif
    call feedkeys(a:key . a:mark, 'in')
endfunction

function! editableMarkList#JumpUnderCursor() abort
    let l:c = s:ParseMark(getline('.'))
    if(empty(l:c))
        echo 'No mark under cursor'
        return
    endif
    call s:JumpTo(l:c, '`')
endfunction

" ---------------------------------------------------------------- hints

" The hints: what the keys do. They are virtual text above line 1 -- an
" extmark in Neovim, a text property in Vim -- so they are not part of the
" buffer: they cannot be edited, deleted or yanked, and are never read back as
" an entry. The section titles are drawn the same way, above the first entry
" of each section. Vim got text above a line in 9.0.0438, but it did not work
" with 'nowrap' until 9.0.0451. Anything older goes without either.
let s:hints_supported = has('nvim-0.6') || (has('textprop') && has('patch-9.0.0451'))

" Linked here rather than in the syntax file: they have to exist even with
" syntax off, since Vim refuses a property type with an unknown highlight.
" A colorscheme clears links like these, hence the autocmd below.
function! s:DefineHighlights() abort
    highlight default link markListHint Comment
    highlight default link markListHintKey Special
    highlight default link markListHeader Title
endfunction
call s:DefineHighlights()

if(has('nvim'))
    let s:ns = nvim_create_namespace('editable-mark-list')
elseif(s:hints_supported)
    for s:type in ['markListHint', 'markListHeader']
        if(empty(prop_type_get(s:type)))
            call prop_type_add(s:type, {'highlight': s:type})
        endif
    endfor
    unlet s:type
endif

let s:sep = [' | ', 'markListHint']

" The hints, as lines of [text, highlight group] chunks -- Neovim's
" virt_lines format -- ending in a rule across the window, so they read as a
" header rather than running straight into the list.
function! s:HintLines(width) abort
    let l:live = [
        \ [['see ', 'markListHint'], [':h :MarkList', 'markListHintKey']],
        \ [['Updates Live!', 'markListHint']],
        \ ]
    let l:keys = [
        \ [['<CR>', 'markListHintKey'], [' to jump', 'markListHint']],
        \ [['delete line', 'markListHintKey'], [' to :delmarks', 'markListHint']],
        \ [['u', 'markListHintKey'], [' to undo', 'markListHint']],
        \ ]
    let l:hints = s:Wrap(l:live, a:width) + s:Wrap(l:keys, a:width)
    " Box drawing where the encoding has it. Measured rather than counted as
    " one cell: it is two wide with 'ambiwidth' double.
    let l:rule = &encoding ==# 'utf-8' ? "─" : '-'
    call add(l:hints, [[repeat(l:rule, max([1, a:width / strdisplaywidth(l:rule)])), 'markListHint']])
    return l:hints
endfunction

" Lays a:items -- each a list of chunks -- out in as few lines as fit
" a:width, with s:sep between them. Neither editor wraps a virtual line, it
" is cut off at the edge of the window. An item too wide for a line of its own
" is still cut off.
function! s:Wrap(items, width) abort
    let l:lines = []
    " Wide enough that the first item starts a line.
    let l:used = a:width
    for l:item in a:items
        let l:item_width = strdisplaywidth(join(map(copy(l:item), 'v:val[0]'), ''))
        let l:with_sep = strdisplaywidth(s:sep[0]) + l:item_width
        if(l:used + l:with_sep > a:width)
            call add(l:lines, copy(l:item))
            let l:used = l:item_width
        else
            call extend(l:lines[-1], [s:sep] + l:item)
            let l:used += l:with_sep
        endif
    endfor
    return l:lines
endfunction

" Cleared and redrawn whole, but only when something they depend on changed:
" the sections, the width, the setting, or the text. The text because in Vim
" a property belongs to its line, so dd on a line takes whatever is above it
" along. Checking first matters because a list on screen is rendered after
" every command (see SafeState below).
function! s:DrawHints(list_buf, headers, winid) abort
    if(!s:hints_supported)
        return
    endif
    " The hints start where the text does, after any number or sign column.
    let l:info = get(getwininfo(a:winid), 0, {})
    let l:width = get(l:info, 'width', winwidth(0)) - get(l:info, 'textoff', 0)
    let l:show = get(g:, 'editable_mark_list_hints', 1)
    let l:state = [a:headers, l:width, l:show, getbufvar(a:list_buf, 'changedtick')]
    if(getbufvar(a:list_buf, 'editable_mark_list_drawn', []) ==# l:state)
        return
    endif

    " {lnum: virtual lines above it}
    let l:above = {}
    if(l:show)
        let l:above[1] = s:HintLines(l:width)
    endif
    let l:first = 1
    for [l:lnum, l:title] in a:headers
        let l:lines = get(l:above, l:lnum, [])
        if(!l:first)
            " A blank line between sections.
            call add(l:lines, [[' ', 'markListHint']])
        endif
        call add(l:lines, [[l:title, 'markListHeader']])
        let l:above[l:lnum] = l:lines
        let l:first = 0
    endfor

    if(has('nvim'))
        call nvim_buf_clear_namespace(a:list_buf, s:ns, 0, -1)
        for [l:lnum, l:lines] in items(l:above)
            call nvim_buf_set_extmark(a:list_buf, s:ns, str2nr(l:lnum) - 1, 0,
                \ {'virt_lines': l:lines, 'virt_lines_above': v:true})
        endfor
        " The number of lines above line 1 may have changed. win_execute
        " keeps this script's context, so s: resolves in there.
        call win_execute(a:winid, 'call s:RevealHints()')
    else
        for l:type in ['markListHint', 'markListHeader']
            call prop_remove({'type': l:type, 'bufnr': a:list_buf, 'all': 1})
        endfor
        " Added top to bottom: that is the order Vim draws them in. One color
        " per line, since a text property has only the one highlight.
        for l:lnum in sort(map(keys(l:above), 'str2nr(v:val)'), 'n')
            for l:chunks in l:above[l:lnum]
                call prop_add(l:lnum, 0, {'bufnr': a:list_buf, 'text_align': 'above',
                    \ 'type': l:chunks[0][1] ==# 'markListHeader' ? 'markListHeader' : 'markListHint',
                    \ 'text': join(map(copy(l:chunks), 'v:val[0]'), '')})
            endfor
        endfor
    endif
    call setbufvar(a:list_buf, 'editable_mark_list_above', sort(map(keys(l:above), 'str2nr(v:val)'), 'n'))
    call setbufvar(a:list_buf, 'editable_mark_list_drawn', l:state)
endfunction

" Neovim draws lines above line 1 as filler, like diff mode's, and shows
" them only once the window is scrolled up into them -- which neither opening
" the list nor gg does. So scroll it there whenever the top of the list is
" on screen. Vim draws them as part of line 1 and needs none of this.
function! s:RevealHints() abort
    if(!has('nvim') || line('w0') != 1)
        return
    endif
    let l:height = 0
    for l:mark in nvim_buf_get_extmarks(0, s:ns, [0, 0], [0, -1], {'details': v:true})
        let l:height += len(get(l:mark[3], 'virt_lines', []))
    endfor
    if(winsaveview().topfill != l:height)
        call winrestview({'topfill': l:height})
    endif
endfunction

" Vim draws text above a line as part of that line, and 'cursorline' along
" with it: with the cursor on the first entry of a section, the title and
" everything else above it would be highlighted too. A text property cannot
" take that back, since highlights only ever add up. So in Vim, on those
" lines, the row is highlighted with a match instead, which covers the line's
" own text and nothing above it. The line number is the exception: with
" 'cursorlineopt' at "number", Vim highlights it on the line's own row only,
" so where the option includes the number, that is all it is cut down to. A
" match belongs to the window rather than the buffer, so this also runs on
" every BufEnter and WinEnter, to take it away from a window that has moved on
" to some other buffer.
function! s:CursorRow() abort
    if(has('nvim') || !s:hints_supported)
        return
    endif
    let l:in_list = &filetype ==# 'marklist'
    let l:above = l:in_list && index(get(b:, 'editable_mark_list_above', []), line('.')) >= 0
    if(l:in_list && !l:above)
        call s:HighlightRow()
    elseif(l:above && &l:cursorlineopt =~# '\<\%(number\|both\)\>')
        setlocal cursorlineopt=number
    elseif(l:above)
        setlocal nocursorline
    endif
    let l:id = get(w:, 'editable_mark_list_cursor_row', 0)
    if(l:id && (!l:above || get(w:, 'editable_mark_list_cursor_row_line', 0) != line('.')))
        silent! call matchdelete(l:id)
        let w:editable_mark_list_cursor_row = 0
        let l:id = 0
    endif
    if(l:above && !l:id)
        let w:editable_mark_list_cursor_row = matchaddpos('CursorLine', [line('.')])
        let w:editable_mark_list_cursor_row_line = line('.')
    endif
endfunction

" 'cursorline' on, and highlighting the row and not just the line number.
" A 'cursorlineopt' of only "number" -- a way of keeping 'cursorline' quiet
" everywhere else -- would leave nothing but the number to show which mark
" the cursor is on. So "line" is added, keeping whatever else the option has.
function! s:HighlightRow() abort
    setlocal cursorline
    if(exists('+cursorlineopt') && &l:cursorlineopt !~# '\<\%(line\|screenline\|both\)\>')
        setlocal cursorlineopt+=line
    endif
endfunction

" How a window showing a list looks: the cursor's row highlighted, to show
" which mark <CR> or dd will act on. Line numbers and the sign column are left
" as the window has them. These are window options, so they are set each time
" a list is shown in a window rather than once for the buffer, and with
" :setlocal, so a window that moves on to another buffer goes back to its
" usual values (see |local-options|).
function! s:WindowOptions() abort
    setlocal nowrap
    call s:HighlightRow()
    " Which takes the row highlight off again where there are titles above,
    " in Vim.
    call s:CursorRow()
endfunction

" ---------------------------------------------------------------- drawing

" Every list buffer there is, as {buffer number: 1}.
let s:lists = {}

" The buffer whose local marks a:winid's list shows: the buffer the list
" replaced, which is the window's alternate file -- or, while ` waits, the
" buffer the list is covering. -1 if there is none.
function! s:Origin(winid) abort
    if(!empty(s:flash) && s:flash.win == a:winid)
        return s:flash.origin
    endif
    if(a:winid == win_getid())
        let l:alt = bufnr('#')
    else
        let s:alt = -1
        call win_execute(a:winid, 'let s:alt = bufnr("#")')
        let l:alt = s:alt
    endif
    return l:alt > 0 && getbufvar(l:alt, '&filetype') !=# 'marklist' ? l:alt : -1
endfunction

" Whether no window is showing this buffer.
function! s:Hidden(buf) abort
    return empty(win_findbuf(a:buf))
endfunction

" An abandoned list to take over, or 0. 'bufhidden' is hide rather than wipe
" so that jumping away leaves the list intact to jump back to (a wiped buffer
" has its jumplist entries dropped, so CTRL-O would skip straight past it).
" That means abandoned lists accumulate unless they are reused, which is what
" this is for. Lists still on screen are left alone so that each window keeps
" its own: each shows the local marks of the buffer it replaced.
function! s:ReusableList() abort
    for l:b in sort(map(keys(s:lists), 'str2nr(v:val)'), 'n')
        if(bufexists(l:b) && getbufvar(l:b, '&filetype') ==# 'marklist' && s:Hidden(l:b))
            return l:b
        endif
    endfor
    return 0
endfunction

" Which mark the cursor is on in each window showing a:list_buf, as {winid:
" mark}. A window whose cursor is on a line with no mark is left out.
function! s:CursorEntries(list_buf) abort
    let l:entries = {}
    for l:winid in win_findbuf(a:list_buf)
        let l:c = s:ParseMark(get(getbufline(a:list_buf, line('.', l:winid)), 0, ''))
        if(!empty(l:c))
            let l:entries[l:winid] = l:c
        endif
    endfor
    return l:entries
endfunction

" Puts each window's cursor back on the mark it was on, wherever that mark is
" now. One that is gone leaves the cursor where it is.
function! s:RestoreCursorEntries(list_buf, entries) abort
    let l:marks = map(getbufline(a:list_buf, 1, '$'), 's:ParseMark(v:val)')
    for [l:winid, l:c] in items(a:entries)
        let l:lnum = index(l:marks, l:c) + 1
        if(l:lnum && l:lnum != line('.', str2nr(l:winid)))
            call win_execute(str2nr(l:winid), 'call cursor(' . l:lnum . ', col("."))')
        endif
    endfor
endfunction

" Redraws a:list_buf from reality, in the first window showing it. A hidden
" list is left alone: it is redrawn when it is shown again. Remembers what it
" drew -- the origin and the marks on the lines -- for s:Apply, which works
" out what an edit deleted from that rather than from reality: a mark set
" since, which the lines never showed, is not one the edit deleted.
function! s:Render(list_buf) abort
    " Jumping to a buffer relists it, so CTRL-O back into the list undoes the
    " 'nobuflisted' it was created with. Reasserting it here catches that.
    call setbufvar(a:list_buf, '&buflisted', 0)
    let l:winid = get(win_findbuf(a:list_buf), 0, 0)
    if(!l:winid)
        return
    endif
    let l:origin = s:Origin(l:winid)
    let [l:lines, l:marks, l:headers] = s:Layout(l:origin)
    if(empty(l:lines))
        let l:lines = ['']
        let l:headers = [[1, 'No marks set']]
    endif
    let l:old_lines = getbufline(a:list_buf, 1, '$')
    if(l:lines !=# l:old_lines)
        " The lines may have moved, so each window's cursor is kept on the
        " mark it was on, rather than the line number.
        let l:cursors = s:CursorEntries(a:list_buf)
        call setbufline(a:list_buf, 1, l:lines)
        if(len(l:old_lines) > len(l:lines))
            silent call deletebufline(a:list_buf, len(l:lines) + 1, '$')
        endif
        call s:RestoreCursorEntries(a:list_buf, l:cursors)
    endif
    call setbufvar(a:list_buf, 'editable_mark_list_origin', l:origin)
    call setbufvar(a:list_buf, 'editable_mark_list_shown', l:marks)
    call s:DrawHints(a:list_buf, l:headers, l:winid)
    if(l:winid == win_getid())
        call s:CursorRow()
    endif
    " Every redraw would otherwise leave the list looking dirty. Nothing is
    " ever lost by clearing this: the text is regenerated from the marks on
    " the next render.
    call setbufvar(a:list_buf, '&modified', 0)
    call setbufvar(a:list_buf, 'editable_mark_list_tick', getbufvar(a:list_buf, 'changedtick'))
endfunction

" Every list on screen, redrawn from reality.
function! s:UpdateAll() abort
    for l:b in map(keys(s:lists), 'str2nr(v:val)')
        if(!bufexists(l:b))
            call remove(s:lists, l:b)
        elseif(!s:Hidden(l:b))
            call s:Render(l:b)
        endif
    endfor
endfunction

" s:UpdateAll for the events that fire while the user may be in the middle of
" editing a list: one being typed into, or with an edit not yet applied, is
" left alone. Redrawing it then would wipe out the edit.
function! s:UpdateIdle() abort
    if(empty(s:lists))
        return
    endif
    let l:here = bufnr('%')
    if(has_key(s:lists, l:here) && (mode() !~# '^n'
        \ || b:changedtick != get(b:, 'editable_mark_list_tick', -1)))
        let l:skip = l:here
    else
        let l:skip = 0
    endif
    for l:b in map(keys(s:lists), 'str2nr(v:val)')
        if(!bufexists(l:b))
            call remove(s:lists, l:b)
        elseif(l:b != l:skip && !s:Hidden(l:b))
            call s:Render(l:b)
        endif
    endfor
endfunction

augroup EditableMarkListGlobal
    autocmd!
    " Nothing fires when a mark is set (ma) or moves (lines added above it),
    " so lists on screen are redrawn whenever Vim is about to wait for a key.
    " Cheap: a redraw that changes nothing touches nothing.
    if(exists('##SafeState'))
        autocmd SafeState * call s:UpdateIdle()
    else
        autocmd CursorHold,CursorHoldI * call s:UpdateIdle()
    endif
    autocmd BufEnter,WinEnter * call s:UpdateIdle()
    autocmd BufWipeout * call s:Forget(str2nr(expand('<abuf>')))
    autocmd ColorScheme * call s:DefineHighlights()
    autocmd BufEnter,WinEnter * call s:CursorRow()
    " The hints are laid out to fit the window, so lay them out again when it
    " changes size.
    autocmd VimResized * call s:UpdateIdle()
    if(exists('##WinResized'))
        autocmd WinResized * call s:UpdateIdle()
    endif
augroup END

" ---------------------------------------------------------------- editing

" The undo history, shared by every list: the changes made from lists,
" oldest first, each as {'deleted': [infos], 'restored': [infos]} -- where
" each mark was when it was deleted, or where it was put back. u takes the
" last one off s:undo and does the opposite, and moves it to s:redo. CTRL-R
" does it again, and moves it back.
"
" Vim's own undo is off in the list ('undolevels' -1). It works on text, and
" the text is a poor record of the marks: the list redraws itself whenever
" anything changes, and every redraw would be an undo step too, which s:Apply
" would then act on as if it were an edit.
let s:undo = []
let s:redo = []

" Where each mark deleted from a list was, by s:Key(), so that a line put
" back (p after dd, or typed) can put its mark back. Only the latest for each.
let s:deleted = {}

function! s:Key(info) abort
    return s:IsGlobal(a:info.mark) ? a:info.mark : a:info.buf . a:info.mark
endfunction

" Deletes a:info's mark, wherever it is now. Returns where that was, or {} if
" it wasn't set.
function! s:Delete(info) abort
    let l:now = s:Current(a:info)
    if(empty(l:now))
        return {}
    endif
    if(s:IsGlobal(l:now.mark))
        execute 'delmarks' l:now.mark
    else
        " A line number of 0 deletes a mark. Unlike :delmarks, this reaches
        " a buffer other than the current one.
        call setpos("'" . l:now.mark, [l:now.buf, 0, 0, 0])
    endif
    let s:deleted[s:Key(l:now)] = l:now
    return l:now
endfunction

" Sets a:info's mark back where a:info says, unless it has been set again
" since: then the newer one is kept. Returns whether it did.
function! s:Restore(info) abort
    if(!empty(s:Current(a:info)))
        return 0
    endif
    let l:buf = a:info.buf
    if(s:IsGlobal(a:info.mark))
        " The buffer may be gone, or the number now someone else's. A file
        " with no buffer gets an unlisted one, which is all a mark needs.
        if(l:buf <= 0 || !bufexists(l:buf)
            \ || fnamemodify(bufname(l:buf), ':p') !=# fnamemodify(a:info.file, ':p'))
            if(empty(a:info.file))
                return 0
            endif
            let l:buf = bufadd(a:info.file)
        endif
    elseif(l:buf <= 0 || !bufexists(l:buf))
        return 0
    endif
    return setpos("'" . a:info.mark, [l:buf] + a:info.pos) == 0
endfunction

" Deletes the marks in a:delete and puts back those in a:restore. Returns
" what actually changed, in the form the history keeps.
function! s:Change(delete, restore) abort
    let l:done = {'deleted': [], 'restored': []}
    for l:info in a:delete
        let l:was = s:Delete(l:info)
        if(!empty(l:was))
            call add(l:done.deleted, l:was)
        endif
    endfor
    for l:info in a:restore
        if(s:Restore(l:info))
            call add(l:done.restored, l:info)
        endif
    endfor
    return l:done
endfunction

" Adds a change made from a list to the history. Like any new change, it
" starts a new future: nothing undone before it can be redone after it.
function! s:Record(change) abort
    if(empty(a:change.deleted) && empty(a:change.restored))
        return
    endif
    call add(s:undo, a:change)
    let s:redo = []
    " As many as Vim would keep.
    if(len(s:undo) > max([1, &g:undolevels]))
        call remove(s:undo, 0)
    endif
endfunction

" A wiped buffer's local marks went with it and can't come back, so they are
" dropped from the history, and a change left with nothing in it goes too: u
" skips straight past it. Global marks stay: their file can get a buffer
" again. A wiped list is forgotten.
function! s:Forget(buf) abort
    if(has_key(s:lists, a:buf))
        call remove(s:lists, a:buf)
    endif
    let l:gone = '!s:IsGlobal(v:val.mark) && v:val.buf == ' . a:buf
    for l:history in [s:undo, s:redo]
        for l:change in l:history
            call filter(l:change.deleted, '!(' . l:gone . ')')
            call filter(l:change.restored, '!(' . l:gone . ')')
        endfor
        call filter(l:history, '!empty(v:val.deleted) || !empty(v:val.restored)')
    endfor
    call filter(s:deleted, '!(' . l:gone . ')')
endfunction

function! s:Warn(errors) abort
    if(!empty(a:errors))
        echohl WarningMsg
        echomsg join(a:errors, ' | ')
        echohl None
    endif
endfunction

" Applies an edit to the list: compares its lines with the marks it last
" showed.
function! s:Apply() abort
    let l:shown = get(b:, 'editable_mark_list_shown', {})
    let l:origin = get(b:, 'editable_mark_list_origin', -1)
    let l:visible = {}
    for l:line in getline(1, '$')
        let l:c = s:ParseMark(l:line)
        if(!empty(l:c))
            let l:visible[l:c] = 1
        endif
    endfor

    let l:delete = []
    let l:kept = []
    for l:c in sort(keys(l:shown))
        if(!has_key(l:visible, l:c))
            if(stridx(s:readonly, l:c) >= 0)
                call add(l:kept, l:c)
            else
                call add(l:delete, l:shown[l:c])
            endif
        endif
    endfor
    let l:restore = []
    for l:c in sort(keys(l:visible))
        if(!has_key(l:shown, l:c))
            let l:key = s:IsGlobal(l:c) ? l:c : l:origin . l:c
            if(has_key(s:deleted, l:key))
                call add(l:restore, s:deleted[l:key])
            endif
        endif
    endfor

    let l:change = s:Change(l:delete, l:restore)
    call s:Record(l:change)
    " Redraw from reality. This converges: the redraw fires one more
    " TextChanged, which then finds text and reality already agreeing. It is
    " also what puts back a line whose mark can't be deleted, and sweeps
    " away one that matches no mark. Every list, not just this one: they all
    " show the same global marks.
    call s:UpdateAll()
    if(!empty(l:kept))
        call s:Warn(["Marks ^ and . can't be deleted from the list"])
    endif
endfunction

" Moves up to a:count changes from a:from to a:to, undoing them if a:undo is
" set and redoing them otherwise. a:none is what to say when a:from is empty.
function! s:Step(from, to, count, undo, none) abort
    if(empty(a:from))
        echo a:none
        return
    endif
    let l:back = []
    let l:gone = []
    let l:i = 0
    while(l:i < a:count && !empty(a:from))
        let l:change = remove(a:from, -1)
        if(a:undo)
            let l:done = s:Change(l:change.restored, l:change.deleted)
            " Redoing this change means deleting again what this put back, and
            " putting back what this deleted, from where it was just now.
            call add(a:to, {'deleted': l:done.restored, 'restored': l:done.deleted})
        else
            let l:done = s:Change(l:change.deleted, l:change.restored)
            call add(a:to, l:done)
        endif
        call extend(l:back, l:done.restored)
        call extend(l:gone, l:done.deleted)
        let l:i += 1
    endwhile
    call s:UpdateAll()

    " Onto the topmost mark that came back, as Vim's undo puts the cursor on
    " the topmost line it changed.
    let l:marks = map(getline(1, '$'), 's:ParseMark(v:val)')
    let l:top = 0
    for l:info in l:back
        let l:lnum = index(l:marks, l:info.mark) + 1
        if(l:lnum && (!l:top || l:lnum < l:top))
            let l:top = l:lnum
        endif
    endfor
    if(l:top)
        call cursor(l:top, 1)
    endif

    let l:said = []
    for [l:verb, l:infos] in [['restored', l:back], ['deleted', l:gone]]
        if(!empty(l:infos))
            call add(l:said, l:verb . ' ' . len(l:infos) . (len(l:infos) == 1 ? ' mark' : ' marks'))
        endif
    endfor
    if(!empty(l:said))
        echo (a:undo ? 'Undo: ' : 'Redo: ') . join(l:said, ', ')
    endif
endfunction

function! editableMarkList#Undo(count) abort
    call s:Step(s:undo, s:redo, a:count, 1, 'Already at oldest change')
endfunction

function! editableMarkList#Redo(count) abort
    call s:Step(s:redo, s:undo, a:count, 0, 'Already at newest change')
endfunction

" ---------------------------------------------------------------- opening

" Makes the current buffer, a new one, into a list. Not :enew -- see
" editableMarkList#Open().
function! s:Setup() abort
    " Deliberately 'nobuflisted': a listed list would join :bufdo and the
    " :bnext rotation, show up in the buffer list, and :mksession would write
    " a `badd [Mark List]` that restores as a bogus empty file.
    setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
    " Vim's undo is replaced by the list's own -- see s:undo.
    setlocal undolevels=-1
    " Purely cosmetic (statusline); harmless to skip if the name is taken
    " because another list window is open.
    silent! execute 'file' fnameescape('[Mark List]')
    setlocal filetype=marklist
    let s:lists[bufnr('%')] = 1
    augroup EditableMarkList
        autocmd! * <buffer>
        autocmd TextChanged,InsertLeave <buffer> call s:Apply()
        " For gg and the like. Every redraw reveals them too, which covers
        " opening the list and coming back to it.
        autocmd CursorMoved <buffer> call s:RevealHints() | call s:CursorRow()
        " Coming back to the list (CTRL-O), or showing it in another window.
        autocmd BufWinEnter <buffer> call s:WindowOptions()
    augroup END
    nnoremap <buffer> <CR> <Cmd>call editableMarkList#JumpUnderCursor()<CR>
    " ` and ' jump to the marks the list shows: its origin's, not its own.
    nnoremap <buffer> ` <Cmd>call editableMarkList#Pick('`')<CR>
    nnoremap <buffer> ' <Cmd>call editableMarkList#Pick("'")<CR>
    nnoremap <buffer> u <Cmd>call editableMarkList#Undo(v:count1)<CR>
    nnoremap <buffer> <C-R> <Cmd>call editableMarkList#Redo(v:count1)<CR>
endfunction

function! editableMarkList#Open() abort
    " Re-entrancy: :MarkList from inside a list redraws it in place rather
    " than nesting a second one.
    if(&filetype !=# 'marklist')
        " The window's alternate before the list, for s:JumpTo to put back.
        let l:alt = [bufnr('%'), bufnr('#')]
        let l:reuse = s:ReusableList()
        if(l:reuse)
            " :buffer makes the buffer this window was
            " showing its alternate, which is what the list shows the local
            " marks of. The list's own mappings, autocmds and options came
            " with the buffer, which was hidden rather than wiped.
            execute 'buffer' l:reuse
        else
            " A new buffer, rather than :enew, which takes over the buffer
            " this window is showing when that is an empty [No Name] one: the
            " list would replace the very buffer it shows the marks of.
            execute 'buffer' bufadd('')
            call s:Setup()
        endif
        let w:editable_mark_list_alt = l:alt
    endif
    call s:WindowOptions()
    call s:Render(bufnr('%'))
    call cursor(1, 1)
    call s:RevealHints()
    call s:CursorRow()
endfunction
