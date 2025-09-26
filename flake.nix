{
  description = "try - fresh directories for every vibe";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      flake = {
        homeModules.default = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.programs.try;
          in
          {
            options.programs.try = {
              enable = mkEnableOption "try - fresh directories for every vibe";

              package = mkOption {
                type = types.package;
                default = inputs.self.packages.${pkgs.system}.default;
                defaultText = literalExpression "inputs.self.packages.\${pkgs.system}.default";
                description = ''
                  The try package to use. Can be overridden to customize Ruby version:
                  
                  ```nix
                  programs.try.package = inputs.try.packages.${"$"}{pkgs.system}.default.override {
                    ruby = pkgs.ruby_3_3;
                  };
                  ```
                '';
              };

              path = mkOption {
                type = types.str;
                default = "~/src/tries";
                description = "Path where try directories will be stored.";
              };
            };

            config = mkIf cfg.enable {
              programs.bash.initExtra = mkIf config.programs.bash.enable ''
                eval "$(${cfg.package}/bin/try init ${cfg.path})"
              '';

              programs.zsh.initContent = mkIf config.programs.zsh.enable ''
                eval "$(${cfg.package}/bin/try init ${cfg.path})"
              '';

              programs.fish.shellInit = mkIf config.programs.fish.enable ''
                eval (${cfg.package}/bin/try init ${cfg.path} | string collect)
              '';
            };
          };

        # Backwards compatibility - deprecated
        homeManagerModules.default = builtins.trace 
          "WARNING: homeManagerModules is deprecated and will be removed in a future version. Please use homeModules instead."
          inputs.self.homeModules.default;
      };

      perSystem = { config, self', inputs', pkgs, system, ... }: {
        packages.default = pkgs.callPackage ({ ruby ? pkgs.ruby }: pkgs.stdenv.mkDerivation rec {
          pname = "try";
          version = "0.1.0";

          src = inputs.self;
          nativeBuildInputs = [ pkgs.makeBinaryWrapper ];

          installPhase = ''
            mkdir -p $out/bin
            cp try.rb $out/bin/try
            chmod +x $out/bin/try

            wrapProgram $out/bin/try \
              --prefix PATH : ${ruby}/bin
          '';

          meta = with pkgs.lib; {
            description = "Fresh directories for every vibe - lightweight experiments for people with ADHD";
            homepage = "https://github.com/tobi/try";
            license = licenses.mit;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        }) {};

        apps.default = {
          type = "app";
          program = "${self'.packages.default}/bin/try";
        };
      };
    };
}
