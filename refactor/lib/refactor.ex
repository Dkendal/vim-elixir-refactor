defmodule Refactor do
  use NVim.Plugin
  require Logger

  defmacro is_ast(term), do: is_list(term) or is_tuple(term)

  def init(init_arg) do
    {:ok, init_arg}
  end

  def debug(x) do
    Logger.debug(inspect(x, pretty: true))
  end

  def at_cursor_pos?(ast, {lnum, cnum}), do: at_cursor_pos?(ast, lnum, cnum)

  def at_cursor_pos?(
        {_, [closing: [line: l2, column: c2], line: l1, column: c1], _},
        line,
        col
      )
      when line in l1..l2 and col in c1..c2 do
    true
  end

  def at_cursor_pos?(
        {_, [closing: _, line: line, column: col], _},
        line,
        col
      ) do
    true
  end

  def at_cursor_pos?(
        {_, [line: line, column: col], _},
        line,
        col
      ) do
    true
  end

  def at_cursor_pos?(ast, line, col) do
    false
  end

  defcommand elixir_hello_world(state) do
    NVim.vim_command("echo \"hello world\"")
    {:ok, nil, state}
  end

  defcommand nvim_elixir_host_start_observer(state) do
    :observer.start()
    {:ok, nil, state}
  end

  defcommand elixir_hello_world(line, col, state), eval: "line('.')", eval: "col('.')" do
    {:ok, nil, state}
  end

  defcommand elixir_refactor_pipe(buf, source, line, col, state),
    eval: "bufnr('')",
    eval: "getline(1, '$')",
    eval: "line('.')",
    eval: "col('.')" do

    line_length = 98

    transform = fn ast ->
      update_ast_at_cursor(ast, line, col, &do_pipe/1)
    end

    # TODO don't join and split so many times
    lines =
      source
      |> Enum.join("\n")
      |> Formatter.to_algebra!(transform: transform)
      |> Inspect.Algebra.format(line_length)
      |> to_string()
      |> String.split("\n")

    # TODO replace only the affected lines, rather than the entire buffer
    NVim.buffer_set_lines(buf, 0, -1, false, lines)

    {:ok, nil, state}
  end

  # defcommand elixir_refactor_unpipe(state) do
  #   with {:ok, line} <- NVim.vim_get_current_line(),
  #        {:ok, new_line} <- unpipe(line) do
  #     NVim.nvim_set_current_line(new_line)
  #     {:ok, nil, state}
  #   else
  #     _ ->
  #       {:ok, nil, state}
  #   end
  # end

  def preserve_indent(new, old) do
    lpad = String.duplicate(" ", count_left_just(old))
    lpad <> new
  end

  def transform_src(line, fun) do
    with {:ok, ast} <- string_to_quoted(line) do
      new_ast = fun.(ast)
      lpad = String.duplicate(" ", count_left_just(line))
      line = lpad <> Macro.to_string(new_ast)
      {:ok, line}
    else
      _ ->
        {:ok, line}
    end
  end

  @doc """
  Evaluate `transform_fun` on the AST node at the specified line and column.
  Returns the modified AST.
  """
  def update_ast_at_cursor(source, target_line, target_col, transform_fun)
      when is_binary(source) do
    opts = [columns: true, token_metadata: true]

    with {:ok, ast} <- Code.string_to_quoted(source, opts) do
      update_ast_at_cursor(ast, target_line, target_col, transform_fun)
    end
  end

  def update_ast_at_cursor(ast, target_line, target_col, transform_fun) when is_ast(ast) do
    do_walk = fn
      term, :cont ->
        with true <- at_cursor_pos?(term, target_line, target_col),
             transformed_term = transform_fun.(term),
             true <- transformed_term != term do
          {transformed_term, :halt}
        else
          _ ->
            {term, :cont}
        end

      # with {:ok, col_range} <- columns(term),
      #      true <- target_line == line,
      #      true <- target_col in col_range,
      #      new_term = transform_fun.(term),
      #      true <- new_term != term do
      #   {new_term, :halt}
      # else
      #   _ ->
      #     {term, :cont}
      # end

      term, state ->
        {term, state}
    end

    {ast, _} = Macro.postwalk(ast, :cont, do_walk)

    ast
  end

  def columns({{:., _, [{:__aliases__, alias_meta, _}, _]}, call_meta, _}) do
    open = get_in(alias_meta, [:column])
    close = get_in(call_meta, [:closing, :column])
    {:ok, open..close}
  end

  def columns({_, meta, _}) do
    case {get_in(meta, [:column]), get_in(meta, [:closing, :column])} do
      {nil, _} ->
        :error

      {_, nil} ->
        :error

      {open, close} ->
        {:ok, open..close}
    end
  end

  def get_ast_at_cursor(source, target_line, target_col) when is_binary(source) do
    opts = [columns: true, token_metadata: true]

    with {:ok, ast} <- Code.string_to_quoted(source, opts) do
      get_ast_at_cursor(ast, target_line, target_col)
    end
  end

  def get_ast_at_cursor(ast, target_line, target_col) when is_ast(term) do
    do_walk = fn
      {_, meta, _} = term, best_match ->
        line = get_in(meta, [:line])
        column = get_in(meta, [:column])

        # Guess the end of the token
        closing_column =
          get_in(meta, [:closing, :column]) ||
            term |> Macro.to_string() |> String.length() |> Kernel.+(column - 1)

        if line == target_line and target_col in column..closing_column do
          {term, term}
        else
          {term, best_match}
        end

      term, best_match ->
        {term, best_match}
    end

    {_, match} = Macro.prewalk(ast, ast, do_walk)

    match
  end

  def pipe(source, line \\ 1, col \\ 1) do
    source
    |> update_ast_at_cursor(line, col, &do_pipe/1)
    |> Macro.to_string()
    |> preserve_indent(source)
  end

  def unpipe(source, line \\ 1, col \\ 1) do
    source
    |> update_ast_at_cursor(line, col, &do_unpipe/1)
    |> Macro.to_string()
    |> preserve_indent(source)
  end

  def do_pipe({:|>, _, [left | right]}) do
    {:|>, [], [do_pipe(left) | right]}
  end

  # Handle local calls and special forms
  def do_pipe({fun, _, [hd | tail] = list} = ast) when is_atom(fun) do
    if Macro.special_form?(fun, length(list)) do
      ast
    else
      {:|>, [], [hd, {fun, [], tail}]}
    end
  end

  # Handle remote calls
  def do_pipe({fun, _, [hd | tail]}) do
    {:|>, [], [hd, {fun, [], tail}]}
  end

  # Base case, just return the ast
  def do_pipe(ast) do
    ast
  end

  def do_unpipe({:|>, _, [{:|>, _, _} = left | right]}) do
    {:|>, [], [do_unpipe(left) | right]}
  end

  def do_unpipe({:|>, _, [left, {fun, _, tail}]}) do
    {fun, [], [left | tail]}
  end

  def do_unpipe(term) do
    term
  end

  def count_left_just(string, count \\ 0)
  def count_left_just("", count), do: count
  def count_left_just(" " <> rest, count), do: count_left_just(rest, count + 1)
  def count_left_just(_, count), do: count

  @quoting_opts [columns: true]

  def string_to_quoted(line) do
    Code.string_to_quoted(line, @quoting_opts)
  end
end
