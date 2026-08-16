# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "try-cli"
  spec.version       = File.read(File.expand_path("VERSION", __dir__)).strip
  spec.authors       = ["Tobi Lutke"]
  spec.email         = ["tobi@lutke.com"]

  spec.summary       = "Experiments deserve a home"
  spec.description   = "A CLI tool for managing experimental projects. Creates dated directories for your tries, with fuzzy search and easy navigation."
  spec.homepage      = "https://pages.tobi.lutke.com/try/"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/tobi/try"
  spec.metadata["documentation_uri"] = "https://pages.tobi.lutke.com/try/"
  spec.metadata["changelog_uri"] = "https://github.com/tobi/try/releases"

  # Generate the single-file script at build time. VERSION is read above from
  # the repo; it is not shipped inside the installed gem.
  Dir.chdir(__dir__) do
    system("make", "dist/try.rb") or raise "failed to generate dist/try.rb (make dist)"
  end

  files = ["bin/try", "dist/try.rb"]
  files << "LICENSE" if File.file?(File.expand_path("LICENSE", __dir__))
  # Local `make native && gem build` may include the AOT binary. Release CI
  # must not run `make native`, so the published gem stays portable Ruby.
  native = File.expand_path("dist/try", __dir__)
  files << "dist/try" if File.file?(native) && File.executable?(native)

  spec.files         = files
  spec.bindir        = "bin"
  spec.executables   = ["try"]
  spec.require_paths = ["dist"]
end
