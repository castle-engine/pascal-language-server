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

unit udebug;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

procedure InitLog(Destination: TStream);
procedure DebugLog(const Msg: string); overload;
procedure DebugLog(const Fmt: string; Args: array of const); overload;

implementation

var
  DebugOutput: TStream;

procedure InitLog(Destination: TStream);
begin
  DebugOutput := Destination;
end;

procedure DebugLog(const Msg: string);
begin
  if (DebugOutput <> nil) and (Msg <> '') then
    DebugOutput.WriteBuffer(Msg[1], Length(Msg));
end;

procedure DebugLog(const Fmt: string; Args: array of const);
var
  s: string;
begin
  s := Format(Fmt, Args) + LineEnding;
  DebugLog(s);
end;

end.

