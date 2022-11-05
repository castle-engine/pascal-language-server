{
  Copyright 2022-2022 Michalis Kamburelis

  Extensions to the Pascal Language Server specific to Castle Game Engine.
  See https://github.com/michaliskambi/elisp/tree/master/lsp
  about my notes about LSP + Pascal + Castle Game Engine + Emacs / VS Code.
  This file is reused with both forks:

  - Philip Zander (Isopod) fork
    original: https://github.com/Isopod/pascal-language-server
    CGE fork: https://github.com/castle-engine/pascal-language-server

  - Ryan Joseph (genericptr) fork
    original: https://github.com/genericptr/pascal-language-server
    CGE fork: https://github.com/michaliskambi/pascal-language-server-genericptr

  Distributed on permissive "modified BSD 3-clause",
  https://github.com/castle-engine/castle-engine/blob/master/doc/licenses/COPYING.BSD-3-clause.txt ,
  so that it can be combined with other licenses without issues. }

{ Extensions to the Pascal Language Server specific to Castle Game Engine. }
unit CastleLsp;

interface

uses IniFiles;

var
  UserConfig: TIniFile;

procedure InitializeUserConfig;

function CastleFpcOptions: String;

implementation

uses SysUtils, Classes
  {$ifdef UNIX}, BaseUnix{, UnixUtils - cannot be found, masked by UnixUtil?}, Users {$endif};

procedure InitializeUserConfig;
var
  FileName: String;
begin
  {$ifdef UNIX}
  { Special hack for Unix + VSCode integration in https://github.com/genericptr/pasls-vscode ,
    looks like it overrides the environment and runs LSP server without $HOME defined,
    so GetAppConfigDir will not work (it will return relative path ".config/....". instead
    of proper absolute "/home/michalis/.config/....").

    Emacs LSP client doesn't have this problem. }
  if GetEnvironmentVariable('HOME') = '' then
  begin
    FileName := '/home/' + GetUserName(FpGetUID) + '/.config/pasls/castle-pasls.ini';
  end else
  {$endif}
    FileName := IncludeTrailingPathDelimiter(GetAppConfigDir(false)) + 'castle-pasls.ini';

  //WriteLn('Reading config from ', FileName);
  UserConfig := TIniFile.Create(FileName);
end;

function CastleFpcOptions: String;

  function ReadOptionsFromCfg(CastleEnginePath: String): String;
  var
    CastleFpcCfg: TStringList;
    S, UntrimmedS: String;
  begin
    CastleEnginePath := IncludeTrailingPathDelimiter(CastleEnginePath);
    Result := '';

    CastleFpcCfg := TStringList.Create;
    try
      CastleFpcCfg.LoadFromFile(CastleEnginePath + 'castle-fpc.cfg');
      for UntrimmedS in CastleFpcCfg do
      begin
        S := Trim(UntrimmedS);
        if S.Startswith('-Fu', true) or
           S.Startswith('-Fi', true) then
        begin
          Insert(CastleEnginePath, S, 4);
          Result := Result + ' ' + S;
        end;
      end;
    finally FreeAndNil(CastleFpcCfg) end;
  end;

var
  CastleEnginePath: String;
begin
  CastleEnginePath := UserConfig.ReadString('castle', 'path', '');
  if CastleEnginePath = '' then
    CastleEnginePath := GetEnvironmentVariable('CASTLE_ENGINE_PATH');

  if CastleEnginePath <> '' then
    Result := ReadOptionsFromCfg(CastleEnginePath)
  else
    Result := '';
end;

finalization
  FreeAndNil(UserConfig);
end.
