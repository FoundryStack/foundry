defmodule Foundry.Desktop.PrepareSidecarTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../../..", __DIR__)
  @script Path.join(@root, "desktop/foundry-desktop/scripts/prepare_sidecar.sh")

  test "release preparation copies a standalone Burrito artifact" do
    tmp_dir = unique_tmp_dir!("standalone-sidecar")
    binaries_dir = Path.join(tmp_dir, "binaries")
    burrito_out_dir = Path.join(tmp_dir, "burrito_out")
    artifact_path = Path.join(burrito_out_dir, "foundry")

    File.mkdir_p!(binaries_dir)
    File.mkdir_p!(burrito_out_dir)
    File.cp!("/bin/sh", artifact_path)
    File.chmod!(artifact_path, 0o755)

    {_output, 0} =
      System.cmd("bash", [@script],
        cd: @root,
        env: sidecar_env(tmp_dir, binaries_dir, burrito_out_dir)
      )

    sidecar_path = Path.join(binaries_dir, "foundry-sidecar-aarch64-apple-darwin")

    assert File.exists?(sidecar_path)
    refute File.read!(sidecar_path) =~ "mix foundry.studio"
  end

  test "release preparation rejects a wrapper script artifact" do
    tmp_dir = unique_tmp_dir!("wrapper-rejected")
    binaries_dir = Path.join(tmp_dir, "binaries")
    burrito_out_dir = Path.join(tmp_dir, "burrito_out")
    artifact_path = Path.join(burrito_out_dir, "foundry")

    File.mkdir_p!(binaries_dir)
    File.mkdir_p!(burrito_out_dir)

    File.write!(
      artifact_path,
      "#!/usr/bin/env bash\nset -euo pipefail\nexec mix foundry.studio \"$@\"\n"
    )

    File.chmod!(artifact_path, 0o755)

    {output, exit_code} =
      System.cmd("bash", [@script],
        cd: @root,
        stderr_to_stdout: true,
        env: sidecar_env(tmp_dir, binaries_dir, burrito_out_dir)
      )

    assert exit_code != 0
    assert output =~ "not standalone"
  end

  test "dev fallback still produces a local mix wrapper when explicitly requested" do
    tmp_dir = unique_tmp_dir!("mix-fallback")
    binaries_dir = Path.join(tmp_dir, "binaries")
    burrito_out_dir = Path.join(tmp_dir, "burrito_out")

    File.mkdir_p!(binaries_dir)
    File.mkdir_p!(burrito_out_dir)

    {_output, 0} =
      System.cmd("bash", [@script],
        cd: @root,
        env:
          sidecar_env(tmp_dir, binaries_dir, burrito_out_dir)
          |> Kernel.++([{"FOUNDRY_DESKTOP_FORCE_MIX_FALLBACK", "1"}])
      )

    sidecar_path = Path.join(binaries_dir, "foundry-sidecar-aarch64-apple-darwin")
    sidecar_contents = File.read!(sidecar_path)

    assert sidecar_contents =~ "foundry.studio"
    assert sidecar_contents =~ "/mix\" foundry.studio"
    assert sidecar_contents =~ "MIX_BUILD_PATH"
  end

  defp sidecar_env(tmp_dir, binaries_dir, burrito_out_dir) do
    [
      {"FOUNDRY_DESKTOP_REPO_ROOT", tmp_dir},
      {"FOUNDRY_DESKTOP_BINARIES_DIR", binaries_dir},
      {"FOUNDRY_DESKTOP_BURRITO_OUT_DIR", burrito_out_dir},
      {"FOUNDRY_DESKTOP_HOST_TRIPLE", "aarch64-apple-darwin"},
      {"FOUNDRY_DESKTOP_SKIP_BURRITO_BUILD", "1"}
    ]
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
