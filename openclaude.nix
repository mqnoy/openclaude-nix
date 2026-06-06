{ lib, buildNpmPackage, fetchurl, nodejs }:

let
  # Define the target version here
  version = "0.17.1"; # Replace with the latest version published to npm

  # Main package
  openclaude = buildNpmPackage rec {
    pname = "openclaude";
    inherit version;

    src = fetchurl {
      url = "https://registry.npmjs.org/@gitlawb/openclaude/-/openclaude-${version}.tgz";
      # Note: replace this with the actual tarball hash (run nix build once to let it fail and give you the hash)
      hash = "sha256-pCmFqEuJCw0DFGqYJiwq4qQVbTpowx2TXqvIVzZIlDg="; 
    };

    # Note: replace with the actual deps hash after running the update script
    npmDepsHash = "sha256-He96ga+N7lQrrxpsTX9rtvgOMaficq7mBuJG7hIs/Bw="; 
    
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


    installPhase = ''
      mkdir -p $out/lib/node_modules/@gitlawb/openclaude
      cp -a . $out/lib/node_modules/@gitlawb/openclaude/
      
      mkdir -p $out/bin
      ln -s $out/lib/node_modules/@gitlawb/openclaude/bin/openclaude $out/bin/openclaude
    '';

    meta = with lib; {
      description = "OpenClaude CLI tool";
      homepage = "https://github.com/Gitlawb/openclaude";
      mainProgram = "openclaude";
    };
  };
in
openclaude