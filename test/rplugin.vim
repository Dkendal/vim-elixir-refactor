" elixir plugins
call remote#host#RegisterPlugin('elixir', './rplugin/elixir/refactor.ez', [
      \ {'sync': 1, 'name': 'ElixirHelloWorld', 'opts': {}, 'type': 'command'},
      \ {'sync': 1, 'name': 'ElixirRefactorPipe', 'opts': {'eval': '[bufnr(''''),getline(1, ''$''),line(''.''),col(''.'')]'}, 'type': 'command'},
      \ {'sync': 1, 'name': 'NvimElixirHostStartObserver', 'opts': {}, 'type': 'command'},
     \ ])
call remote#host#RegisterPlugin('elixir', '/home/dylan/dot-files/nvim/.config/nvim/rplugin/elixir/foobar.ex', [
      \ {'sync': 1, 'name': 'ElixirFooBar', 'opts': {}, 'type': 'command'},
     \ ])


" perl plugins


" node plugins


" python3 plugins


" ruby plugins


" python plugins


