{ lib, buildNpmPackage, fetchurl, nodejs, makeWrapper }:

let
  # Define the target version here
  version = "0.16.1"; # Replace with the latest version published to npm

  # Main package
  openclaude = buildNpmPackage rec {
    pname = "openclaude";
    inherit version;

    src = fetchurl {
      url = "https://registry.npmjs.org/@gitlawb/openclaude/-/openclaude-${version}.tgz";
      # Note: replace this with the actual tarball hash (run nix build once to let it fail and give you the hash)
      hash = "sha256-IfR0JP/if6N3tzwYMAgl3VqwysK5HhWZ/NvRUml6fEo="; 
    };

    # Note: replace with the actual deps hash after running the update script
    npmDepsHash = "sha256-qa+esnKtVo1K9mB3e4e4qx7zs2WLB9Q8/ymXFsfs+EU="; 
    
    inherit nodejs;
    makeCacheWritable = true;

    # Vendor the package-lock.json because the raw npm tarball doesn't include it
    postPatch = ''
      if [ -f "${./packages/openclaude/package-lock.json}" ]; then
        echo "Using vendored package-lock.json"
        cp "${./packages/openclaude/package-lock.json}" ./package-lock.json
      else
        echo "No vendored package-lock.json found, creating a minimal one"
        exit 1
      fi
    '';

    dontNpmBuild = true;
    dontNpmInstall = true;
    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      mkdir -p $out/lib/node_modules/@gitlawb/openclaude
      cp -a . $out/lib/node_modules/@gitlawb/openclaude/
      
      mkdir -p $out/bin
      
      # Wrap the entrypoint script. Check the package's bin/ or dist/ directory 
      # if the executable target differs slightly across versions.
      makeWrapper ${nodejs}/bin/node $out/bin/openclaude \
        --add-flags "$out/lib/node_modules/@gitlawb/openclaude/dist/cli.js"
    '';

    meta = with lib; {
      description = "OpenClaude CLI tool";
      homepage = "https://github.com/Gitlawb/openclaude";
      mainProgram = "openclaude";
    };
  };
in
openclaude