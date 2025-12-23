class Try < Formula
  desc "Fresh directories for every vibe - lightweight experiments for people with ADHD"
  homepage "https://github.com/tobi/try"
  url "https://github.com/tobi/try/archive/08f70fa34761e308acc0546b723d038e41aa0fee.tar.gz"
  sha256 "818b3c7f37410fe1bb719f5ae75d57a59808eef0e9ec36009a01e08ebfa3d558"
  version "main"

  depends_on "ruby"

  def install
    bin.install "try.rb" => "try"
  end

  def caveats
    <<~EOS
      To set up try with your shell, add one of the following to your shell configuration:

      For bash/zsh:
        eval "$(try init ~/src/tries)"

      For fish:
        eval "(try init ~/src/tries | string collect)"

      You can change ~/src/tries to any directory where you want your experiments stored.
    EOS
  end

  test do
    system "#{bin}/try", "--help"
  end
end