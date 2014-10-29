func! s:ScrubPattern(s)
  " ^ makes no sense for \%l or \%c patterns.
  let scrubbed_pattern = substitute(a:s, '\v^\^', '\1', '')

  " Prevents multiple matches to pulse when using grouping patterns like:
  " /foo\|bar
  " Also handles very magic searches:
  " /\vfoo\|bar
  " Thanks to:
  " https://github.com/ivyl/vim-bling/commit/2bd2a7bae53a86d50b5d04b288294126c91ea372#diff-02a7de289c9f8db14e1cd349a2f52fc9
  let scrubbed_pattern = '\%(' . scrubbed_pattern

  if stridx(a:s, '\v') == 0
    let scrubbed_pattern .= ')'
  else
    let scrubbed_pattern .= '\)'
  endif

  return scrubbed_pattern
endf

func! s:Initialize()
  let gui_running = has('gui_running')

  " Color list:
  " http://vim.wikia.com/wiki/Xterm256_color_names_for_console_Vim
  " http://www.calmar.ws/vim/256-xterm-24bit-rgb-color-chart.html
  let color_list =  gui_running ?
        \ ['#3a3a3a', '#444444', '#4e4e4e', '#585858', '#606060'] :
        \ [237, 238, 239, 240, 241]

  let g:vim_search_pulse_color_list =
        \ get(g:, 'vim_search_pulse_color_list', color_list)

  " Approximative pulse duration in milliseconds
  let g:vim_search_pulse_duration = get(g:, 'vim_search_pulse_duration', 200)

  " Mode can be cursor_line, pattern
  let g:vim_search_pulse_mode =
        \ get(g:, 'vim_search_pulse_mode', 'cursor_line')

  let s:highlight_arg = gui_running ? 'guibg' : 'ctermbg'
  let s:oldc = synIDattr(synIDtrans(hlID('CursorLine')), 'bg')

  execute 'highlight SearchPulse '.s:highlight_arg.'=NONE'

  if s:oldc == -1
    let s:oldc = 'NONE'
  endif

  let s:iterator =
        \ g:vim_search_pulse_color_list +
        \ reverse(copy(g:vim_search_pulse_color_list))[1:]
  let s:sleep = g:vim_search_pulse_duration / len(s:iterator)
  let s:initialized = 1
endf

" Will pulse the cursor line on first search match using / or ?
func! search_pulse#PulseFirst()
  let t = getcmdtype()

  if t == '/' || t == '?'
    return "\<cr>:call search_pulse#Pulse()\<cr>"
  endif

  return "\<cr>"
endf

func! search_pulse#Pulse()
  if get(g:, 'vim_search_pulse_disable') != 0
    return
  endif
  if get(s:, 'initialized') == 0
    call s:Initialize()
  endif
  if g:vim_search_pulse_mode == 'pattern'
    call search_pulse#PulsePattern()
  elseif g:vim_search_pulse_mode == 'cursor_line'
    call search_pulse#PulseCursorLine()
  endif
endf

func! search_pulse#PulsePattern()
  let pos = getpos('.')
  let pattern =
        \ '\%' . pos[1] . 'l' .
        \ '\%' . pos[2] . 'c' .
        \ s:ScrubPattern(getreg('/'))

  if &ignorecase == 1 || &smartcase == 1
    let pattern = pattern . '\c'
  endif

  call s:HandleFoldOpening()

  let match_id = matchadd('SearchPulse', pattern)

  for c in s:iterator
    " Short circuit if there is 'typeahead'.
    if getchar(1) != 0
      break
    endif

    execute 'highlight SearchPulse ' . s:highlight_arg . '=' . c
    redraw
    execute 'sleep ' . s:sleep . 'm'
  endfor

  silent! call matchdelete(match_id)
endf

func! search_pulse#PulseCursorLine()
  if s:IsLineTooLong()
    return
  endif
  if s:IsPatternOnTheSameLine()
    return
  endif

  call s:HandleFoldOpening()

  " Save the line we are on to avoid pulsing the same line if pattern is on
  " the same line.
  let s:old_line = line('.')

  for c in s:iterator
    " In the loop, if a key is pressed,
    " restore old cursor line color and break
    if getchar(1) != 0
      call s:SetCursorLineColor(s:oldc)
      break
    endif

    call s:SetCursorLineColor(c)
    redraw
    execute 'sleep ' . s:sleep . 'm'
  endfor

  " Restore the old cursorline color
  call s:SetCursorLineColor(s:oldc)
endf

func! s:SetCursorLineColor(c)
  execute 'highlight CursorLine ' . s:highlight_arg . '=' . a:c
endf

" If the line has too many characters don't pulse, because it can be slow on
" very long lines.
func! s:IsLineTooLong()
  let cc = len(getline('.')) " Current line charecter count
  let ww = winwidth(0) " Current window width

  " Imagine you have wrapped lines,
  " the return of the ceil function is the line count
  if has('gui_macvim')
    " On macvim handles float regardless of the current locale
    " 1,0 is a float but 1.0 is a string
    " see https://groups.google.com/forum/#!topic/vim_mac/zIxXg4az9Eg
    let f = str2float('1.0')
    return ceil((cc * f) / (ww * f)) >= str2float('3.0')
  endif

  return ceil((cc * 1.0) / (ww * 1.0)) >= 3.0
endf

func! s:IsPatternOnTheSameLine()
  if !exists('s:old_line')
    let s:old_line = line('.')

    return 0
  endif

  return s:old_line == line('.')
endf

func! s:HandleFoldOpening()
  " The search command is part of a mapping so we have to control opening
  " folds. See :h 'foldopen'.
  if &foldopen =~# 'search'
    normal zv
  endif
endf
