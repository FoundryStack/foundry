template_path = Path.expand("../../packaging/homebrew/foundry.rb.eex", __DIR__)
version = System.fetch_env!("FOUNDRY_RELEASE_VERSION")
macos_url = System.fetch_env!("FOUNDRY_MACOS_URL")
macos_sha = System.fetch_env!("FOUNDRY_MACOS_SHA")
macos_silicon_url = System.fetch_env!("FOUNDRY_MACOS_SILICON_URL")
macos_silicon_sha = System.fetch_env!("FOUNDRY_MACOS_SILICON_SHA")
linux_url = System.fetch_env!("FOUNDRY_LINUX_URL")
linux_sha = System.fetch_env!("FOUNDRY_LINUX_SHA")

template = EEx.eval_file(template_path,
  assigns: [
    version: version,
    macos_url: macos_url,
    macos_sha: macos_sha,
    macos_silicon_url: macos_silicon_url,
    macos_silicon_sha: macos_silicon_sha,
    linux_url: linux_url,
    linux_sha: linux_sha
  ]
)

IO.write(template)
