export EDITOR=nano
export PAGER=most

#export LANG="ru_RU.UTF-8"
#export LC_CTYPE="ru_RU.UTF-8"
#export LC_COLLATE="POSIX"
#export LC_ALL="ru_RU.UTF-8"
#export MM_CHARSET=UTF-8

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include bashrc if it exists
    if [ -f "/etc/bashrc" ]; then
        . "/etc/bashrc"
    fi
fi
