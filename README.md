# dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Setup

```bash
brew install stow
cd ~/src/dotfiles
stow nvim
```

Stow reads `.stowrc` in this repo which sets `--target` to `~`, so you don't need to pass `-t ~` manually.

To add a new config (e.g. tmux), mirror the home-relative path:

```
dotfiles/tmux/.config/tmux/tmux.conf
```

Then run `stow tmux`.

## Neo Vim

Neo Vim >= 12.0

```bash
brew install nvim rg fzf fd font-hack-nerd-font
cd ~/src/dotfiles
stow nvim
```

## ZSH

TODO: Add ZSH install steps

```bash
cd ~/src/dotfiles
stow zsh
```

Note: Secrets (`CLIENT_ID`, `CLIENT_SECRET`, etc.) are kept in `~/.zshenv` which is not managed by stow.
