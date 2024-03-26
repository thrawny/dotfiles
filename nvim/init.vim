"Basic stuff
set encoding=utf-8
set backspace=indent,eol,start
set ruler
set expandtab
set shiftwidth=2
set softtabstop=2
syntax on
set number
set numberwidth=3
set hidden
set cursorline
set tw=80
set mouse=a
set timeoutlen=1000 ttimeoutlen=10
set backupdir=~/.vim/backup//
set directory=~/.vim/swap//
set undodir=~/.vim/undo//
set backup
set noswapfile
set omnifunc=csscomplete#CompleteCSS
set autoread
set textwidth=0 wrapmargin=0

"Searching
" search as characters are entered
set incsearch
" highlight matches
set hlsearch
" dont wanna highlight searches whenever i source vimrc
nohlsearch
" ignore case sensitivity
set ignorecase
" we want smartcase though
set smartcase

" Looks
set guifont=Menlo\ Regular\ for\ Powerline:h12
let g:molokai_original = 1
colorscheme molokai
" Correct colors in terminal
" if !has("gui_running")
"   set term=screen-256color
" endif

" My own mappings
" Rebind <Leader> key
let mapleader = ","
inoremap {<CR> {<CR>}<Esc>ko
inoremap ({<CR> ({<CR>});<Esc>ko
" easier moving between buffers
map <Leader>n <esc>:bp<CR>
map <Leader>m <esc>:bn<CR>
" map sort function to a key
vnoremap <Leader>s :sort<CR>
map <Leader>lc :lclose<CR>
map <silent> <Leader>o :noh<ESC>
noremap Y y$
noremap <C-d> <C-d>zz
noremap <C-u> <C-u>zz
noremap n nzzzv
noremap N Nzzzv
noremap <Leader>, <C-^>zz
noremap <Leader>v :e $MYVIMRC<CR>
noremap <Leader>z :e ~/.zshrc<CR>
noremap <Leader>i :e ~/dotfiles/linux/i3/config<CR>
noremap <Leader>tm :e ~/.tmux.conf<CR>
noremap <Leader>sv :source $MYVIMRC<CR>
noremap <localleader>b :NERDTreeToggle<CR>
noremap <localleader>, ,
nnoremap <expr> gp '`[' . strpart(getregtype(), 0, 1) . '`]'
vnoremap // y/<C-R>"<CR>"

" Clipboard copy paste
noremap <space>y "*y
noremap <space>Y "*Y
noremap <space>p "*p
noremap <space>P "*P

au BufReadPost ~/.kube/config set syntax=yaml
au BufReadPost *yaml* set syntax=yaml

function! DoPrettyXML()
  " save the filetype so we can restore it later
  let l:origft = &ft
  set ft=
  " delete the xml header if it exists. This will
  " permit us to surround the document with fake tags
  " without creating invalid xml.
  1s/<?xml .*?>//e
  " insert fake tags around the entire document.
  " This will permit us to pretty-format excerpts of
  " XML that may contain multiple top-level elements.
  0put ='<PrettyXML>'
  $put ='</PrettyXML>'
  silent %!xmllint --format -
  " xmllint will insert an <?xml?> header. it's easy enough to delete
  " if you don't want it.
  " delete the fake tags
  2d
  $d
  " restore the 'normal' indentation, which is one extra level
  " too deep due to the extra tags we wrapped around the document.
  silent %<
  " back to home
  1
  " restore the filetype
  exe "set ft=" . l:origft
endfunction
command! FormatXML call DoPrettyXML()

command! FormatJson :%!python3 -m json.tool

