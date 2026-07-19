HISTCONTROL=ignoreboth
HISTSIZE=20000
HISTFILESIZE=50000

export EDITOR='vim'
export VISUAL='vim'
export SUDO_EDITOR='vim'

PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
unset color_prompt force_color_prompt

alias ll='ls -alhF'
alias py='python3'
alias ..='cd ..'
alias vrc='vim ~/.bashrc'
alias src='source ~/.bashrc'
alias sve='sudoedit' #Only for adm profiles
alias grepmac='grep -Pi "\b([0-9a-f]{2}[:/-]){5}[0-9a-f]{2}\b "'
alias grepip='grep -P "\b((25[0-5]|2[0-4[0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"'

shopt -s checkwinsize
shopt -s histappend
shopt -s autocd
shopt -s globstar
shopt -s extglob
shopt -s lastpipe
set +m

case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi


ex() {
    if [[ -f "$1"  ]]; then
        case "$1" in
            *.tar.bz2)  tar xjf "$1"    ;;
            *.tar.gz)   tar xzf "$1"    ;;
            *.bz2)      bunzip2 "$1"    ;;
            *.rar)      unrar x "$1"    ;;
            *.gz)       gunzip "$1"     ;;
            *.tar)      tar xf "$1"     ;;
            *.tbz2)     tar xjf "$1"    ;;
            *.tgz)      tar xzf "$1"    ;;
            *.zip)      unzip "$1"      ;;
            *.Z)        uncompress "$1" ;;
            *.7z)       7z x "$1"       ;;
            *)          echo "'$1' can't extract using ex" ;;
        esac
    else
        echo "'$1' Invalid file"
    fi
}        

mcd() {
    mkdir -p "$1" && cd "$1"
}

bind 'set vi-ins-mode-string \1\e[6 q\2'
bind 'set vi-cmd-mode-string \1\e[6 q\2'