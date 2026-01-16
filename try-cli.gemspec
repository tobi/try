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

  spec.files = Dir[
    "lib/**/*",
    "bin/*",
    "try.rb",
    "VERSION",
    "LICENSE*",
    "README.md"
  ]
  spec.bindir        = "bin"
  spec.executables   = ["try"]
  spec.require_paths = ["lib", "."]
end
