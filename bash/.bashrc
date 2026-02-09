# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source ~/.local/share/omarchy/default/bash/rc

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

. "$HOME/.local/share/../bin/env"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/chabandou/miniforge3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/chabandou/miniforge3/etc/profile.d/conda.sh" ]; then
        . "/home/chabandou/miniforge3/etc/profile.d/conda.sh"
    else
        export PATH="/home/chabandou/miniforge3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<


# >>> mamba initialize >>>
# !! Contents within this block are managed by 'mamba shell init' !!
export MAMBA_EXE='/home/chabandou/miniforge3/bin/mamba';
export MAMBA_ROOT_PREFIX='/home/chabandou/miniforge3';
__mamba_setup="$("$MAMBA_EXE" shell hook --shell bash --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias mamba="$MAMBA_EXE"  # Fallback on help from mamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<

# Re-enable hashing (disabled by Omarchy for mise compatibility)
# This suppresses "bash: hash: hashing disabled" warnings from conda
set -h
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export PATH="$PATH:$HOME/Android/Sdk/platform-tools"

# Add bun to PATH
export PATH="/home/chabandou/.cache/.bun/bin:$PATH"

# Added by Codex to expose conda
export PATH="$HOME/miniforge3/condabin:$PATH"
