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
        homeManagerModules.default = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.programs.try;
          in {
            options.programs.try = {
              enable = mkEnableOption "try - fresh directories for every vibe";
              
              package = mkOption {
                type = types.package;
                default = inputs.self.packages.${pkgs.system}.default;
                description = "The try package to use.";
              };
              
              path = mkOption {
                type = types.str;
                default = "~/src/tries";
                description = "Path where try directories will be stored.";
              };
            };
            
            config = mkIf cfg.enable {
              programs.bash.initContent = mkIf config.programs.bash.enable ''
                eval "$(${cfg.package}/bin/try init ${cfg.path})"
              '';
              
              programs.zsh.initContent = mkIf config.programs.zsh.enable ''
                eval "$(${cfg.package}/bin/try init ${cfg.path})"
              '';
              
              programs.fish.shellInit = mkIf config.programs.fish.enable ''
                eval (${cfg.package}/bin/try init ${cfg.path})
              '';
            };
          };
      };
      
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        packages.default = pkgs.stdenv.mkDerivation rec {
          pname = "try";
          version = "0.1.0";
          
          src = ./.;
          
          buildInputs = [ pkgs.ruby ];
          
          installPhase = ''
            mkdir -p $out/bin
            cp try.rb $out/bin/try
            chmod +x $out/bin/try
          '';
          
          meta = with pkgs.lib; {
            description = "Fresh directories for every vibe - lightweight experiments for people with ADHD";
            homepage = "https://github.com/tobi/try";
            license = licenses.mit;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };
        
        apps.default = {
          type = "app";
          program = "${self'.packages.default}/bin/try";
        };
      };
    };
}
