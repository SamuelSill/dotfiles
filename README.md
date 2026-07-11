# dotfiles

My personal setup - all in one repo.

## Install (standalone)

```sh
git clone --recursive git@github.com:SamuelSill/dotfiles.git
cd dotfiles
./install.py
```

### Uninstall

```sh
stow -D --dir "$PWD/stow" --target "$HOME" config   # remove the ~/.config symlinks
```
Then remove the `# >>> dotfiles hook >>>` block from `~/.zshrc`.

