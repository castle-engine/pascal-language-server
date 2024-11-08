// Pascal Language Server
// Copyright 2021 Philip Zander

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

unit uutils;

{$mode objfpc}{$H+}

interface

uses CustomCodeTool, CodeToolManager, CodeCache;

function MergePaths(Paths: array of string): string;
function GetConfigDirForApp(AppName, Vendor: string; Global: Boolean): string;
function URIToFileNameEasy(const UriStr: String): String;

{ Return prefix for error message describing filename, line, column
  from ECodeToolError, if any. }
function PositionForErrorPrefix(const E: ECodeToolError): String; overload;

{ Return prefix for error message describing filename, line, column
  from TCodeToolManager, if any. }
function PositionForErrorPrefix(const CodeToolBoss: TCodeToolManager): String; overload;

implementation

uses
  SysUtils, URIParser,
  ujsonrpc;

function MergePaths(Paths: array of string): string;
var
  i: Integer;
begin
  Result := '';
  for i := low(Paths) to high(Paths) do
  begin
    if (Result <> '') and (Paths[i] <> '') then
      Result := Result + ';' + Paths[i]
    else if (Result = '') and (Paths[i] <> '') then
      Result := Paths[i];
  end;
end;


// yuck
var
  _FakeAppName, _FakeVendorName: string;

function GetFakeAppName: string;
begin
  Result := _FakeAppName;
end;

function GetFakeVendorName: string;
begin
  Result := _FakeVendorName;
end;

function GetConfigDirForApp(AppName, Vendor: string; Global: Boolean): string;
var
  OldGetAppName:     TGetAppNameEvent;
  OldGetVendorName:  TGetVendorNameEvent;
begin
  _FakeAppName     := AppName;
  _FakeVendorName  := Vendor;
  OldGetAppName    := OnGetApplicationName;
  OldGetVendorName := OnGetVendorName;
  try
    OnGetApplicationName := @GetFakeAppName;
    OnGetVendorName      := @GetFakeVendorName;
    Result               := GetAppConfigDir(Global);
  finally
    OnGetApplicationName := OldGetAppName;
    OnGetVendorName      := OldGetVendorName;
  end;
end;

{ Convert URI (with file:// protocol) to a filename.
  Accepts also empty string, returning empty string in return.
  Other / invalid URIs result in an exception. }
function URIToFileNameEasy(const UriStr: String): String;
begin
  if UriStr = '' then
    Exit('');
  if not URIToFilename(UriStr, Result) then
    raise ERpcError.CreateFmt(
      jsrpcInvalidRequest,
      'Unable to convert URI to filename: %s', [UriStr]
    );
end;

const
  { Error prefix to display filename (may be ''), line, column.
    Note: line endings (#10, #13 or both) are ignored inside this, at least by VS Code.
    And \r \n are not interpreted as line endings, at least by VS Code.
    So we cannot make a newline break here. }
  SErrorPrefix = '%s(%d,%d): ';

{ Return prefix for error message describing position (line, column)
  from ECodeToolError, if any. }
function PositionForErrorPrefix(const E: ECodeToolError): String;

  function PosSet(const Pos: TCodeXYPosition): Boolean;
  begin
    Result := (Pos.X <> 0) and (Pos.Y <> 0);
  end;

  function PosToStr(const Pos: TCodeXYPosition): String;
  var
    CodeFileName: String;
  begin
    if Pos.Code <> nil then
      CodeFileName := ExtractFileName(Pos.Code.Filename)
    else
      CodeFileName := '';
    Result := Format(SErrorPrefix, [CodeFileName, Pos.Y, Pos.X]);
  end;

begin
  if E.Sender <> nil then
  begin
    if PosSet(E.Sender.ErrorNicePosition) then
      Exit(PosToStr(E.Sender.ErrorNicePosition));
    if PosSet(E.Sender.ErrorPosition) then
      Exit(PosToStr(E.Sender.ErrorPosition));
  end;
  Result := '';
end;

function PositionForErrorPrefix(const CodeToolBoss: TCodeToolManager): String;
var
  CodeFileName: String;
begin
  Result := '';
  if (CodeToolBoss.ErrorLine <> 0) and
     (CodeToolBoss.ErrorColumn <> 0) then
  begin
    if CodeToolBoss.ErrorCode <> nil then
      CodeFileName := ExtractFileName(CodeToolBoss.ErrorCode.Filename)
    else
      CodeFileName := '';
    Result := Format(SErrorPrefix, [
      CodeFileName,
      CodeToolBoss.ErrorLine,
      CodeToolBoss.ErrorColumn
    ]);
  end;
end;

end.

