{ nvidia-patch-src
, nvidia-patch-drivers
, stdenvNoCC, fetchFromGitHub, fetchpatch, writeShellScriptBin
, lib
, lndir
, nvidia_x11 ? linuxPackages.nvidia_x11, linuxPackages ? { }
}: let
  nvpatch = writeShellScriptBin "nvpatch" ''
    set -eu
    patchScript=$1
    objdir=$2

    set -- -sl
    source $patchScript

    patch="''${patch_list[$nvidiaVersion]-}"
    object="''${object_list[$nvidiaVersion]-}"

    if [[ -z $patch || -z $object ]]; then
      echo "$nvidiaVersion not supported for $patchScript" >&2
      exit 1
    fi

    sed -e "$patch" $objdir/$object.$nvidiaVersion > $object.$nvidiaVersion
  '';
  driver = nvidia-patch-drivers.${nvidiaVersion} or {
    nvenc_patch = false;
    nvfbc_patch = false;
  };
  nvidiaVersion = nvidia_x11.version;
in stdenvNoCC.mkDerivation {
  pname = "nvidia-x11";
  version = nvidiaVersion + "+patch" + nvidia-patch-src.version or nvidia-patch-src.lastModifiedDate or "";
  src = nvidia-patch-src;

  nativeBuildInputs = [ nvpatch lndir ];
  patchedLibs = [
    "libnvidia-encode${stdenvNoCC.hostPlatform.extensions.sharedLibrary}"
    "libnvidia-fbc${stdenvNoCC.hostPlatform.extensions.sharedLibrary}"
  ];

  inherit nvidiaVersion nvidia_x11;
  nvidia_x11_bin = nvidia_x11.bin;
  nvidia_x11_lib32 = nvidia_x11.lib32; # XXX: no patches for 32bit?
  inherit (driver) nvenc_patch nvfbc_patch;

  outputs = [ "out" "bin" "lib32" ];

  buildPhase = ''
    runHook preBuild
    if [[ -n $nvenc_patch ]]; then
      nvpatch patch.sh $nvidia_x11/lib
    fi
    if [[ -n $nvfbc_patch ]]; then
      nvpatch patch-fbc.sh $nvidia_x11/lib
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    for f in $patchedLibs; do
      if [[ -e $f.$nvidiaVersion ]]; then
        install -Dm0755 -t $out/lib $f.$nvidiaVersion
      else
        echo WARN: $f not patched >&2
      fi
    done

    install -d $out $bin $lib32
    lndir -silent $nvidia_x11 $out

    ln -s $nvidia_x11_bin/* $bin/
    ln -s $nvidia_x11_lib32/* $lib32/

    runHook postInstall
  '';

  meta = with lib.licenses; {
    license = unfree;
    broken = !driver.nvenc_patch && !driver.nvfbc_patch;
  };
  passthru = rec {
    inherit driver;
    ci.cache.wrap = true;
    inherit (nvidia_x11) useProfiles persistenced settings bin lib32;
  };
}
