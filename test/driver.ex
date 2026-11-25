# Typed into Vim as keystrokes by run.sh -- see harness.vim for why.
#
# Only lines beginning with ':' are fed to Vim; everything else is a comment.
# Never use a bare :normal, it swallows the rest of the line including the
# bars. :execute "normal! ..." instead.
#
# The fixtures a.txt, b.txt and c.txt have 30 lines each: a1 to a30, and so
# on.


The list replaces the current window and shows the marks of the buffer it
replaced, then the global ones, then the special ones.

:call Describe('opening the list')
:call Reset()
:edit b.txt
:edit a.txt
:call cursor(5, 2) | execute "normal! ma"
:call cursor(9, 1) | execute "normal! mz"
:edit c.txt
:call cursor(12, 1) | execute "normal! mQ"
:edit a.txt
:call cursor(20, 1)
:let g:wins = winnr('$')
:MarkList
:call Is(&filetype, 'marklist', 'the current window now holds the list')
:call Is(winnr('$'), g:wins, 'no new window was opened')
:call Is(bufname('#'), 'a.txt', 'the buffer it replaced is the alternate')
:call Is(&buflisted, 0, 'the list is not listed')
:call Is(getline(1), ' a      5  a5', "a local mark: its line number and that line's text")
:call Is(getline(2), ' z      9  a9', 'local marks in order')
:call Is(getline(3), ' Q  c.txt:12  c12', 'a global mark: its file and line, and the text when loaded')
:call Is(Shown()[3:], ['"', '[', ']'], 'then the special marks that are set')
:call Ok(getline(LineOf('"')) =~# 'position when last exiting buffer', 'special marks say what they are')
:call Is(LineOf("'"), 0, "not ', which belongs to the window")
:call Is(line('.'), 1, 'the cursor starts on the first mark')

:call Describe('the hints and section titles are drawn above the lines')
:if g:hints_supported | call Is(AboveLine(1)[0:1], ['see :h :MarkList | Updates Live!', '<CR> to jump | delete line to :delmarks | u to undo'], 'the hints come first') | endif
:if g:hints_supported | call Ok(AboveLine(1)[2] =~# '^\%(─\|-\)\+$', 'then a rule') | endif
:if g:hints_supported | call Is(AboveLine(1)[3:], ['Local (a-z)'], 'then the first section title') | endif
:if g:hints_supported | call Is(AboveLine(3), [' ', 'Global (A-Z)'], 'each section has its title above its first mark') | endif
:if g:hints_supported | call Is(AboveLine(4), [' ', 'Special'], 'the special marks too') | endif
:if !g:hints_supported | call Skip('hints need Neovim or Vim 9.0.0451') | endif
:let g:editable_mark_list_hints = 0
:MarkList
:if g:hints_supported | call Is(AboveLine(1), ['Local (a-z)'], 'with the hints off, the titles stay') | endif
:unlet g:editable_mark_list_hints
:MarkList
:if g:hints_supported | call Is(len(AboveLine(1)), 4, 'and the hints come back') | endif


Only the leading mark character of a line is ever read. Mangled lines are
swept away, and a mark character on a line of its own counts only when it
stands alone.

:call Describe('only the mark character is read back')
:call Reset()
:edit a.txt
:call cursor(5, 1) | execute "normal! ma"
:MarkList
:let g:before = getline(1, '$')
:execute "normal! Ojunk\<Esc>"
:call Is(getline(1, '$'), g:before, 'a line for no mark is swept away')
:call Is(Where('a', 'a.txt'), [5, 1], 'and a is untouched')
:call cursor(1, 1) | execute "normal! A garbage\<Esc>"
:call Is(getline(1, '$'), g:before, 'text added after the mark is redrawn')
:call Is(Where('a', 'a.txt'), [5, 1], 'a still untouched')


<CR> jumps to the mark on the cursor's line, as the built-in ` would from
the buffer the list replaced. The alternate file is the one from before the
list, so CTRL-^ behaves as if the list was never there.

:call Describe('<CR> jumps to a local mark')
:call Reset()
:edit b.txt
:edit a.txt
:call cursor(5, 2) | execute "normal! ma"
:call cursor(20, 1)
:MarkList
:call GotoMark('a')
:execute "normal \<CR>"
:call Is(bufname('%'), 'a.txt', 'back in a.txt')
:call Is([line('.'), col('.')], [5, 2], 'at mark a, column too')
:call Is(bufname('#'), 'b.txt', 'the alternate is what it was before the list')
:execute "normal! \<C-O>"
:call Is([bufname('%'), line('.')], ['a.txt', 20], 'CTRL-O goes back to where the cursor was')
:execute "normal! \<C-O>"
:call Is(&filetype, 'marklist', 'and again to the list')

:call Describe('<CR> jumps to a global mark in another file')
:call Reset()
:edit c.txt
:call cursor(12, 3) | execute "normal! mQ"
:edit a.txt
:MarkList
:call GotoMark('Q')
:execute "normal \<CR>"
:call Is([bufname('%'), line('.'), col('.')], ['c.txt', 12, 3], 'in c.txt at mark Q')
:call Is(bufname('#'), 'a.txt', 'with the buffer the list replaced as the alternate')

:call Describe('` and '' in the list jump to the marks it shows')
:call Reset()
:edit a.txt
:call cursor(7, 2) | execute "normal! mb"
:call cursor(1, 1)
:MarkList
:execute "normal `b"
:call Is([bufname('%'), line('.'), col('.')], ['a.txt', 7, 2], '`b jumped to mark b of a.txt')
:MarkList
:execute "normal 'b"
:call Is([bufname('%'), line('.'), col('.')], ['a.txt', 7, 1], "'b to its line")
:MarkList
:execute "normal \<CR>"
:call Is([bufname('%'), line('.')], ['a.txt', 7], '<CR> on the first line jumps to b')


Deleting a line deletes its mark. u puts it back exactly where it was, and
CTRL-R deletes it again.

:call Describe('deleting a line deletes its mark')
:call Reset()
:edit a.txt
:call cursor(5, 2) | execute "normal! ma"
:call cursor(9, 1) | execute "normal! mz"
:MarkList
:call GotoMark('a')
:execute "normal! dd"
:call Is(Where('a', 'a.txt'), [], 'dd deleted mark a')
:call Is(LineOf('a'), 0, 'its line is gone')
:call Is(Where('z', 'a.txt'), [9, 1], 'and nothing else')
:execute "normal u"
:call Is(Where('a', 'a.txt'), [5, 2], 'u put it back, column and all')
:call Is(LineOf('a'), 1, 'its line is back')
:call Is(line('.'), 1, 'with the cursor on it')
:execute "normal \<C-R>"
:call Is(Where('a', 'a.txt'), [], 'CTRL-R deleted it again')
:execute "normal u"
:call Is(Where('a', 'a.txt'), [5, 2], 'and u brought it back again')

:call Describe('putting a deleted line back puts its mark back')
:call GotoMark('a')
:execute "normal! dd"
:call Is(Where('a', 'a.txt'), [], 'dd deleted mark a')
:execute "normal! p"
:call Is(Where('a', 'a.txt'), [5, 2], 'p put it back where it was')
:call GotoMark('a')
:execute "normal! dd"
:execute "normal! o a\<Esc>"
:call Is(Where('a', 'a.txt'), [5, 2], 'so does typing the mark on a line of its own')
:execute "normal! o b\<Esc>"
:call Is(LineOf('b'), 0, 'a mark never deleted from a list is just swept away')

:call Describe('deleting several lines at once')
:call Reset()
:edit a.txt
:call cursor(2, 1) | execute "normal! ma"
:call cursor(3, 1) | execute "normal! mb"
:call cursor(4, 1) | execute "normal! mA"
:MarkList
:silent g/^/d
:call Is([Where('a', 'a.txt'), Where('b', 'a.txt'), Where('A')], [[], [], []], ':g/^/d deleted every mark it could')
:call Is(Shown(), [''], 'nothing left: an empty list')
:execute "normal u"
:call Is([Where('a', 'a.txt'), Where('b', 'a.txt'), Where('A')], [[2, 1], [3, 1], ['a.txt', 4]], 'one u puts them all back')

:call Describe('global marks')
:call Reset()
:edit c.txt
:call cursor(12, 3) | execute "normal! mQ"
:edit a.txt
:MarkList
:call GotoMark('Q')
:execute "normal! dd"
:call Is(Where('Q'), [], 'dd deleted mark Q')
:bwipeout c.txt
:call Is(bufexists('c.txt'), 0, 'c.txt has no buffer any more')
:execute "normal u"
:call Is(Where('Q'), ['c.txt', 12], 'u put Q back in c.txt anyway')
:call Is(buflisted(bufnr('c.txt')), 0, 'without listing c.txt')

:call Describe("the marks the list can't delete")
:call Reset()
:edit a.txt
:call cursor(3, 1) | execute "normal! ix\<Esc>"
:call cursor(5, 1)
:MarkList
:let g:before = getline(1, '$')
:call GotoMark('^')
:execute "normal! dd"
:call Is(getline(1, '$'), g:before, '^ comes back')
:call Ok(v:statusmsg =~# "can't be deleted" || execute('messages') =~# "can't be deleted", 'with a message')
:call GotoMark('"')
:execute "normal! dd"
:call Is(LineOf('"'), 0, '" can be deleted')
:execute "normal u"
:call Ok(LineOf('"') > 0, 'and put back')


The list works out what an edit deleted from what it showed, not from the
marks as they are now: a mark set since it was last drawn isn't one the
edit deleted. Here the list is left stale on purpose, with noautocmd.

:call Describe('a mark the list never showed is not deleted')
:call Reset()
:edit a.txt
:call cursor(5, 1) | execute "normal! ma"
:split
:MarkList
:noautocmd wincmd w
:call cursor(8, 1) | execute "normal! mb"
:noautocmd wincmd w
:call Is(&filetype, 'marklist', 'back in the list, which is stale')
:call Is(LineOf('b'), 0, "it doesn't show b yet")
:call GotoMark('a')
:execute "normal! dd"
:call Is(Where('a', 'a.txt'), [], 'dd deleted a')
:call Is(Where('b', 'a.txt'), [8, 1], 'but not b')
:call Ok(LineOf('b') > 0, 'which the redraw now shows')
:only


Each window's list shows the local marks of the buffer it replaced.

:call Describe('two lists, each with its own buffer')
:call Reset()
:edit a.txt
:call cursor(5, 1) | execute "normal! ma"
:MarkList
:let g:first = bufnr('%')
:split
:edit b.txt
:call cursor(6, 1) | execute "normal! mb"
:MarkList
:call Ok(bufnr('%') != g:first, 'the second list is a buffer of its own')
:call Is([LineOf('a'), LineOf('b')], [0, 1], "it shows b.txt's marks")
:wincmd w
:call Is([LineOf('a'), LineOf('b')], [1, 0], "the first still shows a.txt's")
:only


An abandoned list is reused rather than piling up.

:call Describe('lists are reused')
:call Reset()
:edit a.txt
:MarkList
:execute "normal! \<C-^>"
:MarkList
:execute "normal! \<C-^>"
:MarkList
:call Is(len(MarkLists()), 1, 'one list, opened three times')


The list doesn't take over an empty [No Name] buffer the way :enew would.

:call Describe('an empty buffer is not taken over')
:call Reset()
:let g:empty = bufnr('%')
:MarkList
:call Ok(bufnr('%') != g:empty, 'the list is a new buffer')
:call Is([bufexists(g:empty), getbufvar(g:empty, '&filetype')], [1, ''], 'the empty one is still there, untouched')


In Vim, text above a line is drawn as part of it, cursorline included, so
on a line with a title above it the row is highlighted with a match instead.

:call Describe('the cursor row (Vim)')
:call Reset()
:edit a.txt
:call cursor(5, 1) | execute "normal! ma"
:call cursor(6, 1) | execute "normal! mb"
:MarkList
:if !has('nvim') && g:hints_supported | call Is(CursorRowMatches(), [[1]], 'on line 1, a match') | endif
:execute "normal! j"
:if !has('nvim') && g:hints_supported | call Is([CursorRowMatches(), &l:cursorline], [[], 1], "on line 2, 'cursorline'") | endif
:execute "normal! j"
:if !has('nvim') && g:hints_supported | call Is(CursorRowMatches(), [[3]], 'on the first special mark, under its title, a match again') | endif
:if has('nvim') || !g:hints_supported | call Skip('Vim with hints only') | endif


:call Finish()
