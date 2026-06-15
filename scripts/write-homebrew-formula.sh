#!/usr/bin/env bash

set -euo pipefail

version=""
sha256=""
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      version="${2:-}"
      shift 2
      ;;
    --sha256)
      sha256="${2:-}"
      shift 2
      ;;
    --output)
      output="${2:-}"
      shift 2
      ;;
    *)
      echo "usage: $0 --version <version> --sha256 <sha256> --output <path>" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$version" || -z "$sha256" || -z "$output" ]]; then
  echo "usage: $0 --version <version> --sha256 <sha256> --output <path>" >&2
  exit 1
fi

cat > "$output" <<EOF
class ApfelPlus < Formula
  desc "On-device Apple FoundationModels CLI and OpenAI-compatible server"
  homepage "https://github.com/tariqwest/apfel-plus"
  url "https://github.com/tariqwest/apfel-plus/releases/download/v${version}/apfel-plus-${version}-arm64-macos.tar.gz"
  sha256 "${sha256}"
  license "MIT"
  head "https://github.com/tariqwest/apfel-plus.git", branch: "main"

  depends_on arch: :arm64
  # macOS-only hard block. Unlike homebrew-core's formula (which builds from
  # source and has \`depends_on xcode: [..., :build]\`, naturally excluding Linux),
  # this tap installs a prebuilt macOS binary with no xcode build-dep. With only
  # \`depends_on macos: :tahoe\`, brew reports "macOS >= 26 (or Linux)" and an
  # arm64 Linux host would install a non-functional macOS binary. The bare
  # :macos is the only thing that hard-blocks Linux here, so the OSDependsOn
  # "redundant" cop is a false positive for this binary-install formula.
  depends_on :macos # rubocop:disable Homebrew/OSDependsOn
  depends_on macos: :tahoe

  def install
    bin.install "apfel-plus"
    man1.install "apfel-plus.1"

    # Ship the demo/ pipe-friendly examples (cmd, explain, gitsum, mac-narrator,
    # naming, oneliner, port, wtd) as apfel-plus-<name> companion commands. The
    # apfel-plus- prefix avoids global PATH collisions ('port' would shadow MacPorts).
    if File.directory?("demo")
      pkgshare.install "demo"
      %w[cmd explain gitsum mac-narrator naming oneliner port wtd].each do |d|
        target = pkgshare/"demo/#{d}"
        next unless target.exist?

        bin.install_symlink target => "apfel-plus-#{d}"
      end
    end
  end

  service do
    run [opt_bin/"apfel-plus", "--serve"]
    keep_alive true
    log_path var/"log/apfel-plus.log"
    error_log_path var/"log/apfel-plus.log"
  end

  def caveats
    s = <<~EOS
      apfel-plus requires:
        - macOS 26 Tahoe or newer (enforced by this formula)
        - Apple Silicon (M1 or later) - Tahoe is Apple Silicon only
        - Apple Intelligence enabled in System Settings > Apple Intelligence & Siri

      Verify everything is ready:
        apfel-plus --model-info

      If the model is unavailable, enable Apple Intelligence:
        https://support.apple.com/en-us/121115

      Companion demo commands (pipe-friendly bash scripts) installed:
        apfel-plus-cmd           natural language -> shell command
        apfel-plus-oneliner      complex awk/sed/find pipe chains
        apfel-plus-explain       explain a command, error, or code snippet
        apfel-plus-wtd           "what's this directory?" project orientation
        apfel-plus-naming        suggest names for functions/variables/classes
        apfel-plus-port          identify the process on a port
        apfel-plus-gitsum        plain-English summary of recent git activity
        apfel-plus-mac-narrator  dry-British-humor system narration
    EOS
    unless Hardware::CPU.arm?
      s += <<~EOS

        Note: Homebrew reports this process as non-arm64. If you are on a real
        Apple Silicon Mac (M1+), apfel-plus will still run - your brew install may
        be running under Rosetta. See:
        https://github.com/tariqwest/apfel-plus/issues
      EOS
    end
    s
  end

  test do
    assert_match "apfel-plus v#{version}", shell_output("#{bin}/apfel-plus --version")
    assert_path_exists man1/"apfel-plus.1"
    assert_path_exists bin/"apfel-plus-cmd"
    assert_predicate bin/"apfel-plus-cmd", :symlink?
  end
end
EOF
