#!/bin/bash
#
# WSL
# In order to use the git-credential-manager (recommended) you must install Git for windows to its default location.

# Get the directory of the script.
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

#######################################
# Gets the latest release tag from a github repository.
# Arguments:
#   The user/repo url fragment of the project.
#######################################
function github_latest_tag() {
    curl -s "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name'
}

#######################################
# Gets the latest release asset from a github repo that matches a given regex.
# Arguments:
#   The user/repo url fragment of the project.
#
#   The regex to match the asset name against.
#######################################
function github_latest_asset() {
    local jsonText
    jsonText=$(curl -s "https://api.github.com/repos/$1/releases/latest")

    local matches
    matches=$(echo "$jsonText" | jq -r ".assets[] | select(.name | test(\"$2\")) | .browser_download_url")

    if [ -z "$matches" ]; then
        echo "Could not find an asset for $1 matching $2"
        return 1
    fi

    if [ "$(echo "$matches" | wc -l)" != 1 ]; then
        echo "Could not find a unique asset for $1 matching $2"
        return 1
    fi

    echo "$matches"
}

#######################################
# Installs a package using apt.
# Arguments:
#   List of Packages to install.
#######################################
function pkg() {
    echo "Installing: $*"

    sudo apt install -qy "$@"
}

#######################################
# Downloads a file to the a downloads folder in the SCRIPT_DIR.
# Globals:
#   SCRIPT_DIR
# Arguments:
#   URL to download
# Outputs
#   Writs the path to the downloaded file to stdout.
#######################################
function download() {
    local downloads
    downloads="$SCRIPT_DIR/downloads"

    mkdir -p "$downloads"

    local path
    path=$(wget --content-disposition -P "$downloads" "$1" |& grep -Po "(?<=^Saving to: ‘).*(?=’$)")

    echo "$downloads/$(basename "$path")"
}

#######################################
# Downloads and installs the given binary to the user's bin folder.
# Arguments:
#   URL to the binary to download.
#
#   Name of the command to install as. If it already exists, no action will be taken.
#######################################
function install_binary() {
    if command -v "$2"; then
        echo "Already installed: $2"
        return 0
    fi

    local path
    path=$(download "$1")

    chmod u+x "$path"

    mkdir -p ~/bin
    mv "$path" ~/bin/"$2"
}

#######################################
# Downloads and installs the given deb package.
# Arguments:
#   URL to the deb package to download.
#
#   Name of the command that will be installed. If it already exists, no action will be taken.
#######################################
function install_deb() {
    if command -v "$2"; then
        echo "Already installed: $2"
        return 0
    fi

    local path
    path=$(download "$1")

    pkg "$path"
}

#######################################
# Ensures a luarock is installed.
# Arguments:
#   The luarock to install.
#######################################
function ensure_luarock() {
    local current
    current=$(luarocks show --mversion "$1" 2>/dev/null)

    # shellcheck disable=SC2181
    if [ $? != 0 ]; then
        sudo luarocks install --lua-version 5.1 "$1"

        return 0
    fi

    local latest
    latest=$(luarocks search --porcelain "$1" | head -n 1 | cut -f 2)

    if [ "$current" != "$latest" ]; then
        sudo luarocks install --lua-version 5.1 "$1"

        return 0
    fi
}

#######################################
# Installs a font.
# Arguments:
#   Url to download the font from.
#######################################
function install_font() {
    mkdir -p ~/.local/share/fonts
    pushd ~/.local/share/fonts || return 1

    local font_zip
    font_zip=$(basename "$1")

    if ! [ -f "$font_zip" ]; then
        curl -LO "$1"
        unzip "$font_zip"

        # rebuild font cache
        fc-cache -f -v
    fi

    popd || return 1
}

#######################################
# Creates a python venv if it does not exist. Also ensures that the packages are installed.
# Arguments:
#   Name of the venv.
#
#   List of packages to install.
#######################################
function ensure_venv() {
    if ! [ -d "$HOME/.venvs/$1" ]; then
        pushd ~/.venvs || return 1

        python3 -m venv "$1"

        popd || return 1
    fi

    # shellcheck source=/dev/null
    source "$HOME/.venvs/$1/bin/activate"

    python3 -m pip install --upgrade "${@:2}"

    deactivate
}

#######################################
# Ensures that a given line is in a file. If not present, it will be added to the end.
# Arguments:
#   The file to check.
#   The line to check/add.
#######################################
function ensure_line() {
    escaped="$(printf '%s' "$2" | sed 's/[.[\*^$]/\\&/g')"
    if grep -q "^$escaped\$" "$1"; then
        return 0
    fi

    echo "$2" >>"$1"
}

#######################################
# Installs a given version of node.
# Arguments:
#   The version of node to install.
#######################################
function install_node() {
    # Install the node version manager if it is not present.
    if ! [ -f ~/.nvm/nvm.sh ]; then
        local latest
        latest=$(github_latest_tag nvm-sh/nvm)
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$latest/install.sh" | bash
    fi

    # shellcheck source=/dev/null
    source ~/.nvm/nvm.sh

    nvm install "$1"
}

# Setup user bin folder. Note that on Ubuntu this will be on the path.
# Note that if it did not exist, a re-login/source of .profile will be needed before it is added to
# the path
mkdir ~/bin
# shellcheck source=/dev/null
source ~/.profile

sudo apt update
sudo apt upgrade

pkg curl stow ca-certificates

# Disable login banners in the shell.
touch ~/.hushlogin

if [ -v WSL_DISTRO_NAME ]; then
    # Needed to run AppImages
    pkg libfuse2

    # Setup git to use the Git for windows credential manager.
    # https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-git#git-credential-manager-setup
    git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"
fi

pkg fish

# krohnkite
# TODO: check if kde is installed
# https://github.com/anametologin/krohnkite
if ! kpackagetool6 -t KWin/Script -s krohnkite; then
    url="$(github_latest_asset "anametologin/krohnkite" 'krohnkite-.+\\.kwinscript')"
    path=$(download "$url")
    kpackagetool6 -t KWin/Script -i "$path"
    rm "$path"

    # TODO: enable programmatically
    # TODO: map meta+d to decrease, meta+l to focus right

fi

# Node
install_node 22
npm install --global yarn

# Bun
if ! command -v bun; then
    curl -fsSL https://bun.sh/install | bash
fi

# Go
# rm -rf /usr/local/go
if ! [ -d "/usr/local/go" ]; then
    curl -LO https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
fi
ensure_line ~/.profile "export PATH=\$PATH:/usr/local/go/bin"

# Neovim
install_binary "https://github.com/neovim/neovim/releases/latest/download/nvim.appimage" nvim

# Setup python venvs
mkdir ~/.venvs
pkg python3-pip python3-venv

ensure_venv py3nvim \
    pynvim

# LazyVim deps
pkg clang fd-find chafa ripgrep cargo lynx

# fzf
# Install newer veresion of fzf than is available in the package manager.
if ! command -v fzf; then
    url="$(github_latest_asset "junegunn/fzf" 'linux_amd64\\.tar\\.gz')"
    path=$(download "$url")

    tar -C ~/bin -xzf "$path"
fi

pkg lua5.1 luarocks
ensure_luarock tiktoken_core

pkg perl
if ! command -v cpanm; then
    curl -L https://cpanmin.us | perl - --sudo App::cpanminus
fi
sudo cpanm -n Neovim::Ext

pkg ruby ruby-dev
sudo gem install neovim

npm install -g neovim prettier

# Fonts
install_font https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/ProggyClean.zip
install_font https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/Gohu.zip

# Terminals
# Note that you do not typlically want to run the terminal inside WSL.
if ! [ -v WSL_DISTRO_NAME ]; then
    pkg alacritty
fi

# LazyGit
if ! command -v lazygit; then
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    sudo install lazygit -D -t ~/bin/
fi

# Chrome
install_deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" google-chrome

# Discord
install_deb "https://discord.com/api/download?platform=linux&format=deb" discord

# VS Code
install_deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" code

# Install extensions, also ensures config directory is created so whole directory is not symlinked
# by stow.
extensions="
vscodevim.vim
plievone.vscode-template-literal-editor
ms-azuretools.vscode-docker
talhabalaj.actual-font-changer
vue.volar
nuxtr.nuxt-vscode-extentions
streetsidesoftware.code-spell-checker
mechatroner.rainbow-csv
oderwat.indent-rainbow
esbenp.prettier-vscode
ionutvmi.path-autocomplete
ms-vsliveshare.vsliveshare
bradlc.vscode-tailwindcss
gruntfuggly.todo-tree
dbaeumer.vscode-eslint
bierner.github-markdown-preview
saeris.markdown-github-alerts
catppuccin.catppuccin-vsc-pack
murloccra4ler.leap
yoavbls.pretty-ts-errors
ms-vscode.vscode-speech
lucafalasco.matcha
lucafalasco.matchalk
github.vscode-github-actions
ryu1kn.partial-diff
bocovo.dbml-erd-visualizer
"
for extension in $extensions; do
    code --install-extension "$extension"
done

# Stow the user settings, but if it already exists, overwrite the .dotfiles repo version so it can
# be merged/reverted.
pushd ~/.dotfiles || exit
stow --adopt vscode
popd || exit

# Obsidian
install_deb "$(github_latest_asset "obsidianmd/obsidian-releases" 'amd64\\.deb')" obsidian

# Docker
# May be needed on non-ubuntu distros to uninstall distro provided docker.
# for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done

# Get the gpg key if it is not already present.
if ! [ -f /etc/apt/keyrings/docker.asc ]; then
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
fi

# Add the repository to Apt sources:
if ! [ -f /etc/apt/sources.list.d/docker.list ]; then
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update
fi

pkg docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo groupadd docker
sudo usermod -aG docker "$USER"

# WezTerm

# Get the gpg key if it is not already present.
if ! [ -f /etc/apt/keyrings/wezterm-fury.gpg ]; then
    curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/wezterm-fury.gpg
fi

# Add the repository to Apt sources:
if ! [ -f /etc/apt/sources.list.d/wezterm.list ]; then
    echo 'deb [signed-by=/etc/apt/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
    sudo apt-get update
fi

pkg wezterm

# Sublime Merge

# Get the gpg key if it is not already present.
if ! [ -f /etc/apt/trusted.gpg.d/sublimehq-archive.gpg ]; then
    wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg >/dev/null
fi

pkg apt-transport-https

if ! [ -f /etc/apt/sources.list.d/sublime-text.list ]; then
    echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
    sudo apt-get update
fi

pkg sublime-merge

# Stow
pushd ~/.dotfiles || exit
stow nvim
stow alacritty
stow WezTerm
popd || exit
