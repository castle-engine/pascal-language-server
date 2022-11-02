// Pascal Language Server
// Copyright 2022-2022 (of this file) Michalis Kamburelis

// This file is part of Pascal Language Server.

// Pascal Language Server is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation, either version 3 of
// the License, or (at your option) any later version.

// Pascal Language Server is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with Pascal Language Server.  If not, see
// <https://www.gnu.org/licenses/>.

{ Support configuration using ini file. }
unit UConfig;

interface

uses IniFiles;

var
  UserConfig: TIniFile;

procedure InitializeUserConfig;

implementation

uses SysUtils
  {$ifdef UNIX}, BaseUnix{, UnixUtils - cannot be found, masked by UnixUtil?}, Users {$endif};

procedure InitializeUserConfig;
var
  FileName: String;
begin
  {$ifdef UNIX}
  { Special hack for Unix where LSP server is run without $HOME defined,
    so GetAppConfigDir will not work (it will return relative path ".config/....".). }
  if true {GetEnvironmentString('HOME') = ''} then
  begin
    FileName := '/home/' + GetUserName(FpGetUID) + '/.config/pasls/castle-pasls.ini';
  end else
  {$endif}
    FileName := IncludeTrailingPathDelimiter(GetAppConfigDir(false)) + 'castle-pasls.ini';

  //WriteLn('Reading config from ', FileName);
  UserConfig := TIniFile.Create(FileName);
end;

finalization
  FreeAndNil(UserConfig);
end.
