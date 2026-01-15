class Try < Formula
  desc "Fresh directories for every vibe - lightweight experiments for people with ADHD"
  homepage "https://github.com/tobi/try"
  url "https://github.com/tobi/try/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "267f2b63561de396a8938c6f41e68e8cecc635d05c582a1f866c0bbf37676af2"
  version "1.0.0"

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