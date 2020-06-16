defmodule RefactorTest do
  use ExUnit.Case

  # for [name: name, args: [unpiped, piped]] <- [
  #       [
  #         name: "with remote call",
  #         args: [
  #           "X.Y.foo(1, 2, 3)",
  #           "1 |> X.Y.foo(2, 3)"
  #         ]
  #       ],
  #       [
  #         name: "with local call",
  #         args: [
  #           "foo(1, 2)",
  #           "1 |> foo(2)"
  #         ]
  #       ],
  #       [
  #         name: "with 1 nested function",
  #         args: [
  #           "foo(bar(x))",
  #           "bar(x) |> foo()"
  #         ]
  #       ],
  #       [
  #         name: "with a indentation",
  #         args: [
  #           "  foo(1)",
  #           "  1 |> foo()"
  #         ]
  #       ],
  #       [
  #         name: "with a pipe",
  #         args: [
  #           "foo(1) |> bar()",
  #           "1 |> foo() |> bar()"
  #         ]
  #       ],
  #       [
  #         name: "3 element tuples are unaffected",
  #         args: [
  #           "{:ok, 1, 2}",
  #           "{:ok, 1, 2}"
  #         ]
  #       ]
  #     ] do
  #   @tag capture_log: true
  #   test "pipe/1 #{name}" do
  #     assert Refactor.pipe(unquote(unpiped)) == unquote(piped)
  #   end

  #   @tag capture_log: true
  #   test "unpipe/1 #{name}" do
  #     assert Refactor.unpipe(unquote(piped)) == unquote(unpiped)
  #   end
  # end

  test "foobar" do
    # Strategy for replacement:
    # Accept source code for entire buffer, line and column number and intended transform
    # Locate ast node that the cursor is positioned over
    # apply the transform to that node
    # relay instructions for how to alter the document to add those changes
    expected = """
    defmodule Foo do
      def bar() do
        # Foo bar
        1 |> foo()
      end
    end
    """

    {source, cursor} =
      text_and_cursor("""
      defmodule Foo do
        def bar() do
          # Foo bar
          foo(1)
           ^
        end
      end
      """)

    line_length = 98
    {lnum, cnum} = cursor

    transform = fn ast ->
      Refactor.update_ast_at_cursor(ast, lnum, cnum, &Refactor.do_pipe/1)
    end

    assert expected |> String.trim_trailing() ==
             Formatter.to_algebra!(source, transform: transform)
             |> Inspect.Algebra.format(line_length)
             |> to_string()
  end

  test "get_ast_at_cursor/3" do
    assert Refactor.get_ast_at_cursor("[1, 2, 3, foo(x)]", 1, 0) |> Macro.to_string() ==
             "[1, 2, 3, foo(x)]"

    assert Refactor.get_ast_at_cursor("[1, 2, 3, foo(x)]", 1, 10) |> Macro.to_string() ==
             "[1, 2, 3, foo(x)]"

    assert Refactor.get_ast_at_cursor("[1, 2, 3, foo(x)]", 1, 11) |> Macro.to_string() ==
             "foo(x)"

    assert Refactor.get_ast_at_cursor("[1, 2, 3, foo(x)]", 1, 14) |> Macro.to_string() ==
             "foo(x)"

    assert Refactor.get_ast_at_cursor("[1, 2, 3, foo(x)]", 1, 15) |> Macro.to_string() ==
             "x"

    assert Refactor.get_ast_at_cursor("[1, 2, 3, foo(x)]", 1, 16) |> Macro.to_string() ==
             "foo(x)"

    assert Refactor.get_ast_at_cursor("[1, 2, 3, foo(x)]", 1, 17) |> Macro.to_string() ==
             "[1, 2, 3, foo(x)]"
  end

  @tag capture_log: true
  test "update_ast_at_cursor/4" do
    [src, line, col] =
      text_and_cursor("""
      [1, 2, 3, foo(x)]
                ^
      """)

    assert Refactor.update_ast_at_cursor(src, line, col, &Refactor.do_pipe/1)
           |> Macro.to_string() == "[1, 2, 3, x |> foo()]"

    [src, line, col] =
      text_and_cursor("""
      [1, 2, 3, foo(x)]
                 ^
      """)

    assert Refactor.update_ast_at_cursor(src, line, col, &Refactor.do_pipe/1)
           |> Macro.to_string() == "[1, 2, 3, x |> foo()]"

    expected = "[1, 2, 3, x |> foo()]"

    [
      """
      [1, 2, 3, foo(x)]
                ^
      """,
      """
      [1, 2, 3, foo(x)]
                 ^
      """,
      """
      [1, 2, 3, foo(x)]
                  ^
      """,
      """
      [1, 2, 3, foo(x)]
                   ^
      """,
      """
      [1, 2, 3, foo(x)]
                     ^
      """
    ]
    |> Enum.map(&text_and_cursor/1)
    |> Enum.map(fn [src, line, col] ->
      assert Refactor.update_ast_at_cursor(src, line, col, &Refactor.do_pipe/1)
             |> Macro.to_string() == expected
    end)
  end

  test "at_cursor_pos?/2" do
    ast =
      {:foo, [closing: [line: 4, column: 10], line: 4, column: 5],
       [{:__block__, [token: "1", line: 4, column: 9], [1]}]}

    cursor = {4, 6}

    assert Refactor.at_cursor_pos?(ast, cursor) == true
  end

  test "text_and_cursor/1" do
    input = """
    defmodule Foo do
      def bar() do
        x
        ^
      end
    end
    """

    expected = """
    defmodule Foo do
      def bar() do
        x
      end
    end
    """

    assert {actual, {line, col}} = text_and_cursor(input)
    assert line == 3
    assert col == 5
    assert actual == expected
  end

  def text_and_cursor(string) do
    string
    |> String.split("\n")
    |> Enum.reduce(
      {:cont, [], 0},
      fn
        line, {:halt, lines, cursor} ->
          {:halt, [line | lines], cursor}

        line, {:cont, lines, lnum} ->
          if Regex.match?(~r/^ *\^ *$/, line) do
            cnum =
              line
              |> String.codepoints()
              |> Enum.find_index(&(&1 == "^"))

            {:halt, lines, {lnum, cnum + 1}}
          else
            {:cont, [line | lines], lnum + 1}
          end
      end
    )
    |> case do
      {:halt, lines, cursor} ->
        {Enum.join(Enum.reverse(lines), "\n"), cursor}

      _ ->
        raise """
        Coudn't locate a cursor in text. Make sure there is a line that only
        includes a caret (^) indicating that the cursor is located at this
        column on the line above.

        Input:
        #{String.duplicate(">", 20)}
        #{string}
        #{String.duplicate("<", 20)}
        """
    end
  end
end
