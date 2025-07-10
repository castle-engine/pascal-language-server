# Castle Game Engine Pascal Language Server

This is an [LSP](https://microsoft.github.io/language-server-protocol/) for Pascal using [CodeTools](https://wiki.lazarus.freepascal.org/Codetools) from Lazarus under the hood. In simple terms: this application can provide code completion features, for Pascal code, to all text editors that may be _LSP clients_ (like _VS Code_, _Emacs_, _NeoVim_).

Distributed with [Castle Game Engine](https://castle-engine.io/). [Download](https://castle-engine.io/download) and install the engine and you will have the `bin/pasls` binary in the engine directory.

Cooperates with [Castle Game Engine VS Code extension](https://marketplace.visualstudio.com/items?itemName=castle-engine-team.castle-engine). Our VS Code extension can be used to build and run CGE projects, and it can integrate with this LSP server.

## History

We are fork of [Philip Zander LSP Pascal server](https://github.com/Isopod/pascal-language-server/).

Which was in turm forked from https://github.com/arjanadriaanse/pascal-language-server , but has since been mostly rewritten.

CGE fork contributes back improvements that are not CGE-specific (see e.g. https://github.com/Isopod/pascal-language-server/pull/1 , https://github.com/Isopod/pascal-language-server/pull/2 , https://github.com/Isopod/pascal-language-server/pull/4 ).

## Castle Game Engine LSP server improvements

- Works with [Castle Game Engine VS Code extension](https://marketplace.visualstudio.com/items?itemName=castle-engine-team.castle-engine) out-of-the-box. In this case, you should not need to use `castle-pasls.ini` -- just configure everything using VS Code extension settings.

- We add capability to configure the LSP server using `castle-pasls.ini` to:
    - Define _Castle Game Engine_ path that will make `pasls` aware of CGE units and autocomplete CGE API.
    - Add extra FPC options.
    - Provide custom Lazarus config location (useful if you install Lazarus by [fpcupdeluxe](https://castle-engine.io/fpcupdeluxe) but still want `pasls` to read Lazarus config -- this is optional).
    - Improve debugging by known log filename and more complete JSON logs.

- We add capability to configure the LSP server using `castle-pasls-paths.txt`, see below.

- We can also auto-detect _Castle Game Engine_ path in some situations:
    - If the LSP server binary is distributed in `bin` of _Castle Game Engine_.
    - Or if the environment 'CASTLE_ENGINE_PATH` is defined.
    - Or if you're on Unix and using `/usr/src/castle-engine/` or `/usr/local/src/castle-engine/`.

- We also pass (to code completion engine) _Castle Game Engine_ options that are also passed by [CGE build tool](https://castle-engine.io/build_tool) like `-Mobjfpc -Sm -Sc -Sg -Si -Sh`.

- We autodetect OS and CPU harder, and we fix OS=`windows` to proper `win64` or `win32` (common mistake, esp. because of https://github.com/genericptr/pasls-vscode/issues/1 ).

## Features

- Code completion
- Signature help
- Go to declaration
- Go to definition
- Automatic dependency resolution for `.lpk` and `.lpr` files
- Works with include files, as long as they specify `{%MainUnit xxx.pas}` at the top (just like for Lazarus CodeTools)
- Detection of _Castle Game Engine_ unit paths in a various ways

## Building

First, make sure, submodules are loaded:
```
git submodule update --init --recursive
```

To compile, open the project file in Lazarus or use the command line:

```sh
cd server
lazbuild pasls.lpi
```

It is recommended to use Free Pascal Compiler version 3.2.0 and Lazarus version
2.0.8 or later, older versions are not officially supported.

## Clients

### Neovim ≥ 0.5.0

For information on how to use the server from Neovim, see [client/nvim](client/nvim).

### Emacs

To use the server from `lsp-mode` in Emacs, install the separate
[`lsp-pascal`](https://github.com/arjanadriaanse/lsp-pascal) module.
Full example setup of it is documented in [Michalis notes about LSP + Pascal](https://github.com/michaliskambi/elisp/tree/master/lsp).

### VS Code

Install the [Castle Game Engine VS Code extension](https://marketplace.visualstudio.com/items?itemName=castle-engine-team.castle-engine).

### Other
Any editor that allows you to add custom LSP configurations should work.

## Configuration

In order for the language server to find all the units, it needs to know the
following parameters:

- location of the FPC standard library source files
- location of the FPC compiler executable
- location of the Lazarus install directory
- the OS you are compiling for
- the architecture you are compiling for

By default, the server will try to auto-detect these parameters from your
Lazarus config. It will search for config files in the following locations (the
exact paths will depend on your operating system):

- `<User settings directory>/lazarus` (e.g. `/home/user/.config/lazarus`)
- `<User home directory>/.lazarus` (e.g. `/home/user/.lazarus`)
- `<System settings directory>/lazarus` (e.g. `/etc/lazarus`)
- Custom directory specified in `castle-pasls.ini` as `config` in `[lazarus]` section (see below for example). This is useful in case your Lazarus config is in a special directory, as e.g. usually setup by fpcupdeluxe.

In addition, you can also specify these parameters manually in one of the
following ways:

1. Set the environment variables:

   - `PP` — Path to the FPC compiler executable
   - `FPCDIR` — Path of the source code of the FPC standard library
   - `LAZARUSDIR` — Path of your Lazarus installation
   - `FPCTARGET` — Target OS (e.g. Linux, Darwin, ...)
   - `FPCTARGETCPU` — Target architecture (e.g. x86_64, AARCH64, ...)

   This overrides auto-detected settings.

2. Or specify the locations via LSP `initializationOptions`. How this is done
   will depend on your client. The format is the following:
   ```json
   {
     "PP": "",
     "FPCDIR": "",
     "LAZARUSDIR": "",
     "FPCTARGET": "",
     "FPCTARGETCPU": ""
   }
   ```

   This overrides environment variables.

## Extra configuration in LSP initialization options

Additional keys in LSP initialization options can be used to influence the LSP server behavior. See the docs of your LSP client (text editor) to know how to pass initialization options.

- `syntaxErrorReportingMode` (integer): Determines how to report syntax errors. Syntax errors indicate that CodeTools cannot understand the surrounding Pascal code well enough to provide any code completion.

    - 0 (default): Show an error message. This relies on the LSP client (text editor) handling the `window/showMessage` message. Support in various text editor:

        - VS Code: works.

        - NeoVim (0.8.0): works, the message is shown for ~1 sec by default.

        - Emacs: works, the message is visible in [echo area](https://www.emacswiki.org/emacs/EchoArea) and the `*Messages*` buffer. You can filter out useless `No completion found` messages to make it perfect, see https://github.com/michaliskambi/elisp/blob/master/lsp/kambi-pascal-lsp.el for example.

    - 1: Return a fake completion item with the error message. This works well in VC Code and NeoVim -- while the completion item doesn't really complete anything, but the error message is clearly visible.

    - 2: Return an error to the LSP client. Some LSP clients will just hide the error, but some (like Emacs) will show it clearly and prominently.

## Extra configuration in castle-engine/pascal-language-server (castle-pasls.ini)

The `pasls` reads configuration file `castle-pasls.ini` in user config dir to enable some additional features.

Where exactly is the config file?

- On Unix: `$HOME/.config/pasls/castle-pasls.ini`
- On Windows: `C:/Users/<username>/AppData/Local/pasls/castle-pasls.ini`
- In general: Uncomment `WriteLn('Reading config from ', FileName);` in `server/castlelsp.pas`, run `pasls` manually, see the output.

Allowed options:

```
[log]
;; Where to write log (contains DebugLog output, allows to debug how everything in pasls behaves).
;; We will add suffix with process id, like '.pid123' .
;; By default none.
filename=/tmp/pasls-log.txt

;; Whether to dump full JSON request/response contents to log (may be quite long).
;; By default this is false (0), and JSON request/response logs are cut at 2000 characters.
;; You change it to true (1) to have full logs, useful at debugging.
full_json=1

[lazarus]
;; Custom directory with Lazarus config.
;; It should contain files like environmentoptions.xml, fpcdefines.xml .
;; See the log output to know if pasls read successfully XML files from there.
config=/home/michalis/installed/fpclazarus/current/config_lazarus/

[castle]
;; Castle Game Engine location.
;;
;; Set this to make pasls autocomplete CGE API by:
;; 1. knowing paths to all CGE units (derived from this CGE path),
;; 2. using default CGE compilation settings, like -Mobjfpc and -Sh (used by CGE build tool and editor).
;;
;; NOTE: Instead of setting the engine path here,
;; VS Code users should configure "Engine Path" in the VS Code extension settings.
path=/home/michalis/sources/castle-engine/castle-engine/

[extra_options]
;; Specify as many extra FPC options as you want.
;; Each extra option must have a consecutive number, we start from 1, and stop when
;; an option does not exist (or is an empty string).
option_1=-Fu/home/michalis/sources/castle-engine/castle-engine/tests/code/tester-fpcunit
option_2=-dSOME_DEFINE
option_3=-dSOMETHING_MORE
```

## Extra paths from `castle-pasls-paths.txt`

We also read `castle-pasls-paths.txt` file in the same directory as `castle-pasls.ini`.

The format of this is simpler: any line that is not empty and does not start with `#` (comment) is considered a path to add to FPC search paths. It is added as both units and include paths (causes both `-Fu` and `-Fi` for FPC).

This is useful e.g. to add paths to all your custom units, that you want to be available for autocompletion. It would be also possible to do this by extending `[extra_options]` in `castle-pasls.ini`, but that's sometimes too bothersome: you need to add them twice (if you want both `-Fu` and `-Fi`) and you need to remember to keep order of `option_xxx`.

Example:

```
# This is a comment, ignored.
# Add all my custom units.
/home/michalis/sources/my-units/
/home/michalis/sources/more-units-and-include-files/
/home/michalis/sources/more-units-and-include-files/subdirectory/
```

## Roadmap

### Wishlist

- Renaming of identifiers
- “Find all references”
- Signature help: Highlight active parameter
- Code formatting?

### Known bugs

- Signature help does not show all overloads
