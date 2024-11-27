{ nvidia-patch-src
, nvidia-patch-drivers
, stdenvNoCC, writeShellScriptBin
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

    patch=
    if [[ -v patch_list["$nvidiaVersion"] ]]; then
      patch="''${patch_list["$nvidiaVersion"]}"
    fi

    object=
    if [[ -v object_list["$nvidiaVersion"] ]]; then
      object="''${object_list["$nvidiaVersion"]}"
    fi

    if [[ -z $object ]]; then
      if [[ $patchScript = *patch.sh ]]; then
        object="libnvidia-encode${stdenvNoCC.hostPlatform.extensions.sharedLibrary}"
      elif [[ $patchScript = *patch-fbc.sh ]]; then
        object="libnvidia-fbc${stdenvNoCC.hostPlatform.extensions.sharedLibrary}"
      fi
    fi

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
  hasFirmware = lib.elem "firmware" nvidia_x11.outputs;
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
  ${if hasFirmware then "nvidia_x11_firmware" else null} = nvidia_x11.firmware;
  inherit (driver) nvenc_patch nvfbc_patch;

  outputs = [ "out" "bin" "lib32" ]
    ++ lib.optional hasFirmware "firmware";

  nvidiaPatchRootPattern = ''\[ "\$(id.* -ne 0 \]'';
  postPatch = ''
    sed -i patch.sh \
      -e "s/$nvidiaPatchRootPattern/false/"
    if [[ -e patch-fbc.sh ]]; then
      sed -i patch-fbc.sh \
        -e "s/$nvidiaPatchRootPattern/false/"
    fi
  '';

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

    if [[ -n ''${firmware-} ]]; then
      install -d $firmware
      ln -s $nvidia_x11_firmware/* $firmware/
    fi

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
    ${if hasFirmware then "firmware" else null} = nvidia_x11.firmware;
  };
}
