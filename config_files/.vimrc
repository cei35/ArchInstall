syntax on
set number
set cursorline
set showmatch
set undofile
set undodir=~/.vim/undodir

set tabstop=4
set shiftwidth=4
set expandtab
set smartindent
set noignorecase
set incsearch

set foldmethod=indent
set foldlevel=99
set clipboard=unnamedplus

let mapleader = " "

nnoremap <leader>w :wq<cr>
nnoremap <leader>q :q<cr>
nnoremap <leader>e: E<cr>
nnoremap <leader>a: set autoread!
nnoremap <leader>h :nohlsearch!<cr>
nnoremap <leader>s : %s/\<<C-r><C-w>\>//g<Left><Left>
nnoremap <leader>r :set relativenumber!<cr>

