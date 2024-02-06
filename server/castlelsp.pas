{
  Copyright 2022-2024 Michalis Kamburelis

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
  so that it can be combined with any other licenses without issues. }

{ Extensions to the Pascal Language Server specific to Castle Game Engine. }
unit CastleLsp;

interface

uses Classes, IniFiles;

var
  UserConfig: TIniFile;
  WorkspacePaths: TStringList;
  WorkspaceAndEnginePaths: TStringList;
  EngineDeveloperMode: Boolean;

procedure InitializeUserConfig;

{ Concatenated (by space) additional FPC options to pass to CodeTools.

  Contains:
  - extra CGE paths (derived from the single CGE path from castle-pasls.ini file)
  - extra CGE options (like -Mobjfpc)
  - extra free FPC options from castle-pasls.ini file
}
function ExtraFpcOptions: String;

procedure ParseWorkspacePaths(const ProjectSearchPaths, ProjectDirectory: String);

implementation

{$ifdef UNIX} {$define UNIX_WITH_USERS_UNIT} {$endif}
{ FPC 3.2.2 on Darwin doesn't contain Users. }
{$ifdef DARWIN} {$undef UNIX_WITH_USERS_UNIT} {$endif}

uses
  {$ifdef MSWINDOWS} Windows, {$endif}
  {$ifdef UNIX_WITH_USERS_UNIT} BaseUnix, {UnixUtils, - cannot be found, masked by UnixUtil?} Users, {$endif}
  SysUtils,
  UDebug;

procedure InitializeUserConfig;
var
  FileName: String;
begin
  {$ifdef UNIX_WITH_USERS_UNIT}
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

function ExtraFpcOptions: String;

  { Quote arguments passed to FPC in case they contain spaces.

    There's no cleaner way unfortunately: parameters of CodeTools API,
    like FPCOptions, are taken as a single string, with all parameters glued
    by a space.
    (it would be cleaned if CodeTools API would be changed to take TStringList.)

    So we have to quote parameters that contain spaces.
    We add " around, which seems to work with FPC 3.2.2. }
  function QuoteFpcOption(const S: String): String;
  begin
    if Pos(' ', S) <> 0 then
    begin
      if Pos('"', S) <> 0 then
        DebugLog('  WARNING: Parameter "%s" contains both spaces and double quotes, cannot quote it reliably for FPC', [S]);
      Result := '"' + S + '"';
    end else
      Result := S;
  end;

  { Check is Path a sensible CGE sources path.
    Requires Path to end with PathDelim. }
  function CheckCastlePath(const Path: String): Boolean;
  begin
    Result :=
      DirectoryExists(Path + 'src') and
      DirectoryExists(Path + 'tools' + PathDelim + 'build-tool' + PathDelim + 'data');
  end;

  function GetCastleEnginePathFromEnv: String;
  begin
    Result := GetEnvironmentVariable('CASTLE_ENGINE_PATH');
    if Result = '' then
      Exit;

    Result := IncludeTrailingPathDelimiter(Result);
    if CheckCastlePath(Result) then
      Exit;

    Result := '';
  end;

  function ExeName: String;
  {$if defined(LINUX)}
  var
    ExeLinkName: String;
  begin
    ExeLinkName := '/proc/' + IntToStr(FpGetpid) + '/exe';
    Result := FpReadLink(ExeLinkName);
  {$elseif defined(MSWINDOWS)}
  var
    S: UnicodeString;
  begin
    SetLength(S, MAX_PATH);
    if GetModuleFileNameW(0, PWideChar(@S[1]), MAX_PATH) = 0 then
    begin
      // WritelnWarning('GetModuleFileNameW failed. We will use old method to determine ExeName, which will fail if parent directory contains local characters');
      Exit(ParamStr(0)); // fallback to old method
    end;
    SetLength(S, StrLen(PWideChar(S))); // It's only null-terminated after WinAPI call, set actual length for Pascal UnicodeString
    Result := UTF8Encode(S);
  {$else}
  begin
    Result := ParamStr(0); // On non-Windows OSes, using ParamStr(0) for this is not reliable, but at least it's some default
  {$endif}
  end;

  function GetCastleEnginePathFromExeName: String;
  var
    ToolDir: String;
  begin
    ToolDir := ExtractFileDir(ExeName);

    { in case we're inside macOS bundle, use bundle path.
      This makes detection in case of CGE editor work OK. }
    {$ifdef DARWIN}
    // TODO: copy BundlePath from CGE? Or use CGE units here?
    // if BundlePath <> '' then
    //   ToolDir := ExtractFileDir(ExclPathDelim(BundlePath));
    {$endif}

    { Check ../ of current exe, makes sense in released CGE version when
      tools are precompiled in bin/ subdirectory. }
    Result := IncludeTrailingPathDelimiter(ExtractFileDir(ToolDir));
    if CheckCastlePath(Result) then
      Exit;
    { Check ../../ of current exe, makes sense in development when
      each tool is compiled by various scripts in tools/xxx/ subdirectory. }
    Result := IncludeTrailingPathDelimiter(ExtractFileDir(ExtractFileDir(ToolDir)));
    if CheckCastlePath(Result) then
      Exit;

    Result := '';
  end;

  function GetCastleEnginePathSystemWide: String;
  begin
    {$ifdef UNIX}
    Result := '/usr/src/castle-engine/';
    if CheckCastlePath(Result) then
      Exit;

    Result := '/usr/local/src/castle-engine/';
    if CheckCastlePath(Result) then
      Exit;
    {$endif}

    Result := '';
  end;

  function GetCastleEnginePath: String;
  begin
    // try to find CGE on $CASTLE_ENGINE_PATH
    Result := GetCastleEnginePathFromEnv;
    // try to find CGE on path relative to current exe
    if Result = '' then
      Result := GetCastleEnginePathFromExeName;
    // try to find CGE on system-wide paths
    if Result = '' then
      Result := GetCastleEnginePathSystemWide;
  end;

  function CastleOptionsFromCfg(CastleEnginePath: String): String;
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
          Result := Result + ' ' + QuoteFpcOption(S);
        end;
      end;
    finally FreeAndNil(CastleFpcCfg) end;
  end;

const
  { Add the same syntax options as are specified by CGE build tool in
    castle-engine/tools/build-tool/code/toolcompile.pas .

    This is necessary to allow pasls to understand Pascal units that don't include
    castleconf.inc but still rely in CGE Pascal configuration, which means:
    all example and applications.
    E.g. examples/fps_game/code/gameenemy.pas uses generics and relies on ObjFpc mode. }
  CastleOtherOptions = ' -Mobjfpc -Sm -Sc -Sg -Si -Sh';
var
  CastleEnginePath, ExtraOption: String;
  ExtraOptionIndex: Integer;
begin
  Result := CastleOtherOptions;

  CastleEnginePath := UserConfig.ReadString('castle', 'path', '');
  if CastleEnginePath = '' then
    CastleEnginePath := GetCastleEnginePath;
  if CastleEnginePath <> '' then
  begin
    DebugLog('  Castle Game Engine path detected: %s', [CastleEnginePath]);
    Result := Result + CastleOptionsFromCfg(CastleEnginePath);
  end else
  begin
    DebugLog('  WARNING: Castle Game Engine path not detected, completion of CGE API will not work.', [CastleEnginePath]);
  end;

  ExtraOptionIndex := 1;
  while true do
  begin
    ExtraOption := UserConfig.ReadString('extra_options', 'option_' + IntToStr(ExtraOptionIndex), '');
    if ExtraOption = '' then
      Break;
    Inc(ExtraOptionIndex);
    Result := Result + ' ' + QuoteFpcOption(ExtraOption);
  end;
end;


procedure ParseWorkspacePaths(const ProjectSearchPaths, ProjectDirectory: String);
var
  I: Integer;
begin
  if Trim(ProjectSearchPaths) = '' then
    Exit;

  WorkspacePaths.Text := ProjectSearchPaths;
  for I := 0 to WorkspacePaths.Count -1 do
    WorkspacePaths[I] := IncludeTrailingPathDelimiter(ProjectDirectory) + WorkspacePaths[I];

  WorkspacePaths.Insert(0, ProjectDirectory);
end;


initialization
  WorkspacePaths := TStringList.Create;
  WorkspaceAndEnginePaths := TStringList.Create;

finalization
  FreeAndNil(WorkspaceAndEnginePaths);
  FreeAndNil(WorkspacePaths);
  FreeAndNil(UserConfig);
end.
