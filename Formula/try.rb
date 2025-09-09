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

  test do
    system "#{bin}/try", "--help"
  end
end