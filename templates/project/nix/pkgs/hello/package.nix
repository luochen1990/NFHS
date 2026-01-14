{ stdenv, lib }:
stdenv.mkDerivation {
  pname = "hello";
  version = "1.0.0";
  dontUnpack = true;
  buildPhase = ''
    echo "Hello from embedded project!"
  '';
  installPhase = ''
    mkdir -p $out/bin
    echo '#!/bin/sh' > $out/bin/hello
    echo 'echo "Hello from embedded project!"' >> $out/bin/hello
    chmod +x $out/bin/hello
  '';
  meta.description = "Hello world example package";
}
