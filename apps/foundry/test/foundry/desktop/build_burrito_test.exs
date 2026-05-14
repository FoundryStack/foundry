defmodule Foundry.Desktop.BuildBurritoTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../../..", __DIR__)
  @script Path.join(@root, "scripts/release/build_burrito.sh")

  test "macOS prefers a compatible Zig already on PATH" do
    tmp_dir = unique_tmp_dir!("zig-path-preferred")
    path_zig = Path.join([tmp_dir, "path-zig", "zig"])

    write_fake_zig!(path_zig, version: "0.15.2", libc_exit: 0)

    bash = """
    source "#{@script}"
    ROOT_DIR="#{tmp_dir}"
    PATH="#{Path.dirname(path_zig)}:/usr/bin:/bin"
    FOUNDRY_BURRITO_ZIG_CANDIDATES="#{path_zig}"
    export FOUNDRY_BURRITO_ZIG_CANDIDATES
    export PATH
    uname() {
      case "$1" in
        -s) echo Darwin ;;
        -m) echo arm64 ;;
        *) command uname "$@" ;;
      esac
    }
    ensure_burrito_zig
    command -v zig
    """

    {output, 0} = System.cmd("bash", ["-lc", bash], cd: @root)

    assert String.trim(output) == path_zig
  end

  test "macOS ignores an incompatible PATH Zig and falls back to the vendored Zig" do
    tmp_dir = unique_tmp_dir!("zig-vendored-fallback")
    path_zig = Path.join([tmp_dir, "path-zig", "zig"])

    vendored_zig =
      Path.join([
        tmp_dir,
        ".foundry",
        "tools",
        "zig",
        "0.15.2",
        "aarch64-macos",
        "zig-aarch64-macos-0.15.2",
        "zig"
      ])

    write_fake_zig!(path_zig, version: "0.16.0", libc_exit: 0)
    write_fake_zig!(vendored_zig, version: "0.15.2", libc_exit: 0)

    bash = """
    source "#{@script}"
    ROOT_DIR="#{tmp_dir}"
    PATH="#{Path.dirname(path_zig)}:/usr/bin:/bin"
    FOUNDRY_BURRITO_ZIG_CANDIDATES="#{path_zig}"
    export FOUNDRY_BURRITO_ZIG_CANDIDATES
    export PATH
    uname() {
      case "$1" in
        -s) echo Darwin ;;
        -m) echo arm64 ;;
        *) command uname "$@" ;;
      esac
    }
    ensure_burrito_zig
    command -v zig
    """

    {output, 0} = System.cmd("bash", ["-lc", bash], cd: @root)

    assert String.trim(output) == vendored_zig
  end

  test "macOS exits with a clear message when vendored Zig also fails the smoke test" do
    tmp_dir = unique_tmp_dir!("zig-macos-failure")
    path_zig = Path.join([tmp_dir, "path-zig", "zig"])

    vendored_zig =
      Path.join([
        tmp_dir,
        ".foundry",
        "tools",
        "zig",
        "0.15.2",
        "aarch64-macos",
        "zig-aarch64-macos-0.15.2",
        "zig"
      ])

    write_fake_zig!(path_zig, version: "0.16.0", libc_exit: 1)
    write_fake_zig!(vendored_zig, version: "0.15.2", libc_exit: 1)

    bash = """
    source "#{@script}"
    ROOT_DIR="#{tmp_dir}"
    PATH="#{Path.dirname(path_zig)}:/usr/bin:/bin"
    FOUNDRY_BURRITO_ZIG_CANDIDATES="#{path_zig}"
    export FOUNDRY_BURRITO_ZIG_CANDIDATES
    export PATH
    uname() {
      case "$1" in
        -s) echo Darwin ;;
        -m) echo arm64 ;;
        *) command uname "$@" ;;
      esac
    }
    ensure_burrito_zig
    """

    {output, exit_code} = System.cmd("bash", ["-lc", bash], cd: @root, stderr_to_stdout: true)

    assert exit_code != 0
    assert output =~ "not compatible with the current macOS toolchain"
    assert output =~ "Zig 0.16.x is not supported"
    assert output =~ "brew install zig@0.15"
  end

  test "Linux keeps preferring the vendored required Zig when PATH Zig is a different version" do
    tmp_dir = unique_tmp_dir!("zig-linux-pinned")
    path_zig = Path.join([tmp_dir, "path-zig", "zig"])

    vendored_zig =
      Path.join([
        tmp_dir,
        ".foundry",
        "tools",
        "zig",
        "0.15.2",
        "x86_64-linux",
        "zig-x86_64-linux-0.15.2",
        "zig"
      ])

    write_fake_zig!(path_zig, version: "0.16.0", libc_exit: 0)
    write_fake_zig!(vendored_zig, version: "0.15.2", libc_exit: 0)

    bash = """
    source "#{@script}"
    ROOT_DIR="#{tmp_dir}"
    PATH="#{Path.dirname(path_zig)}:/usr/bin:/bin"
    export PATH
    uname() {
      case "$1" in
        -s) echo Linux ;;
        -m) echo x86_64 ;;
        *) command uname "$@" ;;
      esac
    }
    ensure_burrito_zig
    command -v zig
    """

    {output, 0} = System.cmd("bash", ["-lc", bash], cd: @root)

    assert String.trim(output) == vendored_zig
  end

  defp write_fake_zig!(path, opts) do
    version = Keyword.fetch!(opts, :version)
    libc_exit = Keyword.fetch!(opts, :libc_exit)

    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      """
      #!/usr/bin/env bash
      set -euo pipefail
      case "${1:-}" in
        version)
          echo "#{version}"
          ;;
        libc)
          exit #{libc_exit}
          ;;
        *)
          exit 0
          ;;
      esac
      """
    )

    File.chmod!(path, 0o755)
  end

  defp unique_tmp_dir!(label) do
    base_dir =
      System.tmp_dir!()
      |> Path.join("foundry-#{label}-#{System.unique_integer([:positive])}")

    File.rm_rf!(base_dir)
    File.mkdir_p!(base_dir)
    on_exit(fn -> File.rm_rf!(base_dir) end)
    base_dir
  end
end
