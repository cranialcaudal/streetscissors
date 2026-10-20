defmodule Web.PrintDepthTest do
  # Application config: not async.
  use ExUnit.Case, async: false

  alias Web.Scanner.Pipeline

  setup do
    previous = Application.get_env(:web, :print_depth)
    on_exit(fn -> Application.put_env(:web, :print_depth, previous) end)
    dir = Path.join(System.tmp_dir!(), "print_depth_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "prints are eight bits unless sixteen are asked for, and then every roll scans deep",
       %{dir: dir} do
    Application.put_env(:web, :print_depth, 8)
    assert Pipeline.print_depth() == 8
    refute Pipeline.deep?(dir)

    Application.put_env(:web, :print_depth, 16)
    assert Pipeline.print_depth() == 16
    assert Pipeline.deep?(dir)
  end
end
