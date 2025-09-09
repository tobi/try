class Try < Formula
  desc "Fresh directories for every vibe - lightweight experiments for people with ADHD"
  homepage "https://github.com/tobi/try"
  url "https://github.com/tobi/try/archive/refs/heads/main.tar.gz"
  sha256 "dd3753f38b5c35597c8c2528a19efd7e4289bbbe977d18e2e299a2a57b393a8e"
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