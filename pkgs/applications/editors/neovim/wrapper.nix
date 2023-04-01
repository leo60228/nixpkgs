{ stdenv, symlinkJoin, lib, makeWrapper
, writeText
, nodePackages
, python3
, python3Packages
, callPackage
, neovimUtils
, vimUtils
}:
neovim:

let
  wrapper = {
      extraName ? ""
    # should contain all args but the binary. Can be either a string or list
    , wrapperArgs ? []
    # a limited RC script used only to generate the manifest for remote plugins
    , manifestRc ? null
    , withPython2 ? false
    , withPython3 ? true,  python3Env ? python3
    , withNodeJs ? false
    , rubyEnv ? null
    , vimAlias ? false
    , viAlias ? false

    # additional argument not generated by makeNeovimConfig
    # it will append "-u <customRc>" to the wrapped arguments
    # set to false if you want to control where to save the generated config
    # (e.g., in ~/.config/init.vim or project/.nvimrc)
    , wrapRc ? true
    , neovimRcContent ? ""
    # entry to load in packpath
    , packpathDirs
    , ...
  }@args:
  let

    wrapperArgsStr = if lib.isString wrapperArgs then wrapperArgs else lib.escapeShellArgs wrapperArgs;

    # "--add-flags" (lib.escapeShellArgs flags)
    # wrapper args used both when generating the manifest and in the final neovim executable
    commonWrapperArgs = (lib.optionals (lib.isList wrapperArgs) wrapperArgs)
      # vim accepts a limited number of commands so we join them all
          ++ [
            "--add-flags" ''--cmd "lua ${providerLuaRc}"''
            # (lib.intersperse "|" hostProviderViml)
          ] ++ lib.optionals (packpathDirs.myNeovimPackages.start != [] || packpathDirs.myNeovimPackages.opt != []) [
            "--add-flags" ''--cmd "set packpath^=${vimUtils.packDir packpathDirs}"''
            "--add-flags" ''--cmd "set rtp^=${vimUtils.packDir packpathDirs}"''
          ]
          ;

    providerLuaRc = neovimUtils.generateProviderRc args;
    # providerLuaRc = "toto";

    # If configure != {}, we can't generate the rplugin.vim file with e.g
    # NVIM_SYSTEM_RPLUGIN_MANIFEST *and* NVIM_RPLUGIN_MANIFEST env vars set in
    # the wrapper. That's why only when configure != {} (tested both here and
    # when postBuild is evaluated), we call makeWrapper once to generate a
    # wrapper with most arguments we need, excluding those that cause problems to
    # generate rplugin.vim, but still required for the final wrapper.
    finalMakeWrapperArgs =
      [ "${neovim}/bin/nvim" "${placeholder "out"}/bin/nvim" ]
      ++ [ "--set" "NVIM_SYSTEM_RPLUGIN_MANIFEST" "${placeholder "out"}/rplugin.vim" ]
      ++ lib.optionals wrapRc [ "--add-flags" "-u ${writeText "init.vim" neovimRcContent}" ]
      ++ commonWrapperArgs
      ;
  in
  assert withPython2 -> throw "Python2 support has been removed from the neovim wrapper, please remove withPython2 and python2Env.";

  symlinkJoin {
      name = "neovim-${lib.getVersion neovim}${extraName}";
      # Remove the symlinks created by symlinkJoin which we need to perform
      # extra actions upon
      postBuild = lib.optionalString stdenv.isLinux ''
        rm $out/share/applications/nvim.desktop
        substitute ${neovim}/share/applications/nvim.desktop $out/share/applications/nvim.desktop \
          --replace 'Name=Neovim' 'Name=Neovim wrapper'
      ''
      + lib.optionalString withPython3 ''
        makeWrapper ${python3Env.interpreter} $out/bin/nvim-python3 --unset PYTHONPATH
      ''
      + lib.optionalString (rubyEnv != null) ''
        ln -s ${rubyEnv}/bin/neovim-ruby-host $out/bin/nvim-ruby
      ''
      + lib.optionalString withNodeJs ''
        ln -s ${nodePackages.neovim}/bin/neovim-node-host $out/bin/nvim-node
      ''
      + lib.optionalString vimAlias ''
        ln -s $out/bin/nvim $out/bin/vim
      ''
      + lib.optionalString viAlias ''
        ln -s $out/bin/nvim $out/bin/vi
      ''
      + lib.optionalString (manifestRc != null) (let
        manifestWrapperArgs =
          [ "${neovim}/bin/nvim" "${placeholder "out"}/bin/nvim-wrapper" ] ++ commonWrapperArgs;
      in ''
        echo "Generating remote plugin manifest"
        export NVIM_RPLUGIN_MANIFEST=$out/rplugin.vim
        makeWrapper ${lib.escapeShellArgs manifestWrapperArgs} ${wrapperArgsStr}

        # Some plugins assume that the home directory is accessible for
        # initializing caches, temporary files, etc. Even if the plugin isn't
        # actively used, it may throw an error as soon as Neovim is launched
        # (e.g., inside an autoload script), causing manifest generation to
        # fail. Therefore, let's create a fake home directory before generating
        # the manifest, just to satisfy the needs of these plugins.
        #
        # See https://github.com/Yggdroot/LeaderF/blob/v1.21/autoload/lfMru.vim#L10
        # for an example of this behavior.
        export HOME="$(mktemp -d)"
        # Launch neovim with a vimrc file containing only the generated plugin
        # code. Pass various flags to disable temp file generation
        # (swap/viminfo) and redirect errors to stderr.
        # Only display the log on error since it will contain a few normally
        # irrelevant messages.
        if ! $out/bin/nvim-wrapper \
          -u ${writeText "manifest.vim" manifestRc} \
          -i NONE -n \
          -V1rplugins.log \
          +UpdateRemotePlugins +quit! > outfile 2>&1; then
          cat outfile
          echo -e "\nGenerating rplugin.vim failed!"
          exit 1
        fi
        rm "${placeholder "out"}/bin/nvim-wrapper"
      '')
      + ''
        rm $out/bin/nvim
        touch $out/rplugin.vim
        makeWrapper ${lib.escapeShellArgs finalMakeWrapperArgs} ${wrapperArgsStr}
      '';

    paths = [ neovim ];

    preferLocalBuild = true;

    nativeBuildInputs = [ makeWrapper ];
    passthru = {
      inherit providerLuaRc packpathDirs;
      unwrapped = neovim;
      initRc = neovimRcContent;

      tests = callPackage ./tests {
      };
    };

    meta = neovim.meta // {
      # To prevent builds on hydra
      hydraPlatforms = [];
      # prefer wrapper over the package
      priority = (neovim.meta.priority or 0) - 1;
    };
  };
in
  lib.makeOverridable wrapper
