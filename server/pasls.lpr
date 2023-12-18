// Pascal Language Server
// Copyright 2020 Arjan Adriaanse
//           2021 Philip Zander

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

program pasls;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, iostream, streamex, StreamIO,
  udebug, ubufferedreader, jsonstream,
  upackages, ujsonrpc, uinitialize, utextdocument, uutils,
  CastleLsp, ULogVSCode, UDocumentSymbolSupport, ushutdown;

var
  ShouldExit: Boolean;

procedure SendError(
  Rpc: TRpcPeer; Id: TRpcId; Code: Integer; const Msg: string
);
var
  Response: TRpcResponse;
begin
  Response := nil;
  try
    Response := TRpcResponse.CreateError(Id, Code, Msg);
    Rpc.Send(Response);
  finally
    FreeAndNil(Response);
  end;
end;

procedure Dispatch(Rpc: TRpcPeer; Request: TRpcRequest);
begin
  { When there was shutdown request all other request should
   return InvalidRequest response, this is done by throwing ERpcError exception.
   more info: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#shutdown}
  if WasShutdown and (Request.Method <> 'exit') then
    raise ERpcError.CreateFmt(
      jsrpcInvalidRequest,
      'Request after shutdown: (method: %s)', [Request.Method]);

  if Request.Method = 'initialize' then
    Initialize(Rpc, Request)
  else if Request.Method = 'initialized' then
  else if Request.Method = 'shutdown' then
    Shutdown(Rpc, Request)
  else if Request.Method = 'textDocument/didOpen' then
    TextDocument_DidOpen(Rpc, Request)
  else if Request.Method = 'textDocument/didChange' then
    TextDocument_DidChange(Rpc, Request)
  else if Request.Method = 'textDocument/didClose' then
  else if Request.Method = 'textDocument/completion' then
    TextDocument_Completion(Rpc, Request)
  else if Request.Method = 'textDocument/signatureHelp' then
    TextDocument_SignatureHelp(Rpc, Request)
  else if Request.Method = 'textDocument/declaration' then
    TextDocument_Declaration(Rpc, Request)
  else if Request.Method = 'textDocument/definition' then
    TextDocument_Definition(Rpc, Request)
  else if Request.Method = 'textDocument/documentSymbol' then
    TextDocument_DocumentSymbol(Rpc, Request)
  else if Request.Method = 'exit' then
  begin
    ShouldExit := true;
    DebugLog('Get exit message, exiting...');
  end
  else if Request.Method = '$/cancelRequest' then
  else if Request.Method = '$/setTrace' then
    TraceValue := ParseSetTrace(Request)
  else
    raise ERpcError.CreateFmt(
      jsrpcMethodNotFound, 'Method not found: %s', [Request.Method]
    );
end;

procedure Main(Rpc: TRpcPeer);
var
  Request: TRpcRequest;
begin
  while True do
  begin
    Request := nil;
    try
      Request := Rpc.Receive;

      if Request = nil then
      begin  
        DebugLog('** End of stream, exiting **');
        exit;
      end;

      if ShouldExit then
      begin
        DebugLog('Main - exit');
        Exit;
      end;

      try
        Dispatch(Rpc, Request);
      except
        on E: ERpcError do
          SendError(Rpc, Request.Id, E.Code, E.Message);
      end;
    finally
      FreeAndNil(Request);
    end;
  end;
end;


var
  InputStream:    TStream;
  OutputStream:   TStream;
  DebugStream:    TStream;
  Transcript:     TStream;
  Tee:            TStream;

  RpcPeer:        TRpcPeer;

  TranscriptPath: string  = '';
  LogPath:        string  = '';
  SaveReplay:     Boolean = false;
  LoadReplay:     Boolean = false;

procedure PrintUsage;
begin
  // TODO: Implement
end;

procedure ParseOptions;
var
  i: integer;
begin
  i := 1;
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '--save-log') and (i < ParamCount) then
    begin
      LogPath        := ParamStr(i + 1);
      Inc(i);
    end
    else if (ParamStr(i) = '--save-replay') and (i < ParamCount) then
    begin
      SaveReplay     := true;
      TranscriptPath := ParamStr(i + 1);
      Inc(i);
    end
    else if (ParamStr(i) = '--replay') and (i < ParamCount) then
    begin
      LoadReplay     := true;
      TranscriptPath := ParamStr(i + 1);
      Inc(i);
    end
    else
    begin
      PrintUsage;
      break;
    end;
    Inc(i);
  end;
end;

{ Dump current exception backtrace. Copied from CastleClassUtils. }
function DumpExceptionBackTraceToString: String;
var
  TextFile: Text;
  StringStream: TStringStream;
begin
  StringStream := TStringStream.Create('');
  try
    AssignStream(TextFile, StringStream);
    Rewrite(TextFile);
    try
      DumpExceptionBackTrace(TextFile);
    finally CloseFile(TextFile) end;
    Result := StringStream.DataString;
  finally FreeAndNil(StringStream) end;
end;

begin
  InputStream    := nil;
  OutputStream   := nil;
  DebugStream    := nil;
  Transcript     := nil;
  Tee            := nil;
  RpcPeer        := nil;
  ShouldExit     := false;
  WasShutdown    := false;

  ParseOptions;

  InitializeUserConfig;
  if LogPath = '' then
  begin
    LogPath := UserConfig.ReadString('log', 'filename', '');
    { If log specifies a filename, add suffix to make it unique per process,
      so that each pasls process doesn't try to open and write to the same file. }
    if LogPath <> '' then
      LogPath := LogPath + '.pid' + IntToStr(GetProcessID);
  end;

  if LogPath <> '' then
    try
      if LogPath = '-' then
        DebugStream := TIOStream.Create(iosError)
      else
        DebugStream := TFileStream.Create(LogPath, fmCreate);
    except
      DebugStream := TIOStream.Create(iosError);
    end;

  InitLog(DebugStream);

  if LoadReplay and SaveReplay then
  begin
    DebugLog('You specified both --save-replay and --replay. Ignoring.');
    LoadReplay := false;
    SaveReplay := false;
  end;

  try
    InputStream  := TIOStream.Create(iosInput);
    OutputStream := TIOStream.Create(iosOutput);

    if SaveReplay then
    begin
      try
        Transcript := TFileStream.Create(TranscriptPath, fmCreate);
      except
        DebugLog(
          'Could not create replay file "%s".',
          [TranscriptPath]
        );
        FreeAndNil(Transcript);
      end;
      Tee          := TTeeStream.Create(InputStream, Transcript);
      RpcPeer      := TRpcPeer.Create(Tee, OutputStream);
    end 
    else if LoadReplay then
    begin
      InputStream  := TFileStream.Create(TranscriptPath, fmOpenRead);
      RpcPeer      := TRpcPeer.Create(InputStream, OutputStream);
    end
    else
    begin
      RpcPeer      := TRpcPeer.Create(InputStream, OutputStream);
    end;

    try
      Main(RpcPeer);
    except
      on E: Exception do
        DebugLog('FATAL EXCEPTION: ' + E.Message +
          LineEnding + LineEnding +
          DumpExceptionBackTraceToString);
    end;
  finally
    FreeAndNil(InputStream);
    FreeAndNil(OutputStream);
    FreeAndNil(DebugStream);
    FreeAndNil(Transcript);
    FreeAndNil(Tee);
    FreeAndNil(RpcPeer);
  end;

end.
