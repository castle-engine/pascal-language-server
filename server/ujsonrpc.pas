// Pascal Language Server
// Copyright 2020 Arjan Adriaanse

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

unit ujsonrpc;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ubufferedreader, jsonstream;

type
  TRpcIdKind = (ridString, ridInteger, ridNull);

  TRpcRequest = class;

  TRpcId = record
    Kind: TRpcIdKind;
    Str:  string;
    Int:  Integer;
  end;

  TRpcRequest = class
  protected
    FBuffer: TMemoryStream;
  public
    Method:  string;
    Id:      TRpcId;
    Reader:  TJsonReader;

    function   AsString: string;
    destructor Destroy; override;
  end;

  { Send message to LSP client (response to a previous request or notification). }
  TRpcResponse = class
  private
    procedure InternalCreate;
    procedure InternalCreateId(const Id: TRpcId);
  protected
    FBuffer: TMemoryStream;
    FFinalized: Boolean;
    procedure Finalize;
  public
    Writer: TJsonWriter;
    constructor Create(Id: TRpcId);
    constructor CreateError(Id: TRpcId; Code: Integer; const Msg: string);
    constructor CreateRequest(const Method: string; Id: TRpcId);
    { Create JSON-RPC notification.
      Note that notifications, following json-rpc (ver 2), do not have "id"
      and the other side does not reply to them (see https://www.jsonrpc.org/specification#notification ). }
    constructor CreateNotification(const Method: string);
    function    AsString: string;
    destructor  Destroy; override;
  end;

  TRpcPeer = class
  protected
    FInput:  TBufferedReader;
    FOutput: TStream;
  public
    constructor Create(Input: TStream; Output: TStream);

    function    Receive: TRpcRequest;
    procedure   Send(Response: TRpcResponse);
  end;

  { ERpcException }

  ERpcError = class(Exception)
  public
    Code: Integer;
    constructor Create(ACode: Integer; const Msg: string);
    constructor CreateFmt(
      ACode: Integer; const Fmt: string; args: array of const
    );
  end;

const
  jsrpcServerNotInitialized = -32002;
  jsrpcParseError           = -32700;
  jsrpcRequestCancelled     = -32800;
  jsrpcContentModified      = -32801;
  jsrpcInvalidRequest       = -32600;
  jsrpcMethodNotFound       = -32601;
  jsrpcRequestFailed        = -32803;

{ Return null response, that signals "no error, but also no result". }
procedure SendNullResponse(const Rpc: TRpcPeer; const Request: TRpcRequest);

implementation

uses
  CastleLsp, udebug;

procedure WriteRpcId(Writer: TJsonWriter; const Id: TRPcId);
begin
  case Id.Kind of
    ridString:  Writer.Str(Id.Str);
    ridInteger: Writer.Number(Id.Int);
    else        Writer.Null;
  end;
end;

{ TRpcRequest }

destructor TRpcRequest.Destroy;
begin
  FreeAndNil(Reader);
  FreeAndNil(FBuffer);
end;

function TRpcRequest.AsString: string;
begin
  SetLength(Result, FBuffer.Size);
  Move(PByte(FBuffer.Memory)^, Result[1], FBuffer.Size);
end;

{ TRpcResponse }

procedure TRpcResponse.InternalCreate;
begin
  inherited Create;
  FBuffer := TMemoryStream.Create;
  Writer := TJsonWriter.Create(FBuffer);
end;

procedure TRpcResponse.InternalCreateId(const Id: TRpcId);
begin
  InternalCreate;
  Writer.Dict;
    Writer.Key('jsonrpc');
    Writer.Str('2.0');
    Writer.Key('id');
    WriteRpcId(Writer, Id);
end;

constructor TRpcResponse.Create(Id: TRpcId);
begin
  InternalCreateId(Id);
  Writer.Key('result');
end;

constructor TRpcResponse.CreateError(
  Id: TRpcId; Code: Integer; const Msg: string
);
begin
  InternalCreateId(Id);

  Writer.Key('error');
  Writer.Dict;
    Writer.Key('code');
    Writer.Number(Code);

    Writer.Key('message');
    Writer.Str(Msg);
  Writer.DictEnd;
end;

constructor TRpcResponse.CreateRequest(const Method: string; Id: TRpcId);
begin
  InternalCreateId(Id);
  Writer.Key('method');
  Writer.Str(Method);
end;

constructor TRpcResponse.CreateNotification(const Method: string);
begin
  InternalCreate;
  Writer.Dict;
    Writer.Key('jsonrpc');
    Writer.Str('2.0');
    Writer.Key('method');
    Writer.Str(Method);
end;

destructor TRpcResponse.Destroy;
begin
  FreeAndNil(Writer);
  FreeAndNil(FBuffer);
  inherited;
end;

procedure TRpcResponse.Finalize;
begin
  if not FFinalized then
    Writer.DictEnd;
  FFinalized := true;
end;

function TRpcResponse.AsString: string;
begin
  SetLength(Result, FBuffer.Size);
  Move(PByte(FBuffer.Memory)^, Result[1], FBuffer.Size);
end;

{ TRpcPeer }

constructor TRpcPeer.Create(Input: TStream; Output: TStream);
begin
  FInput  := TBufferedReader.Create(Input);;
  FOutput := Output;
end;

function TRpcPeer.Receive: TRpcRequest;
var
  Buffer:           TMemoryStream;
  Reader:           TJsonReader;
  Header, Key, Val: string;
  Idx, Len:         Integer;

  Version:          string;
  Method:           string;
  Id:               TRpcId;

  CutLength:        Integer;
  LogFullJson:      Boolean;
begin
  Result := nil;
  Buffer := nil;
  Reader := nil;

  try
    Header := FInput.ReadLine;
    if Header = '' then
      exit;

    Len := 0;
    while Header <> '' do
    begin
      Idx := Pos(':', Header);
      Key := Copy(Header, 1, Idx - 1);
      Delete(Header, 1, Idx);
      Val := Trim(Header);
      if Key = 'Content-Length' then
        Len := StrToInt(Val);
      Header := FInput.ReadLine;
    end;

    if Len = 0 then
      raise EParserError.Create('Invalid request body.');

    Buffer := TBytesStream.Create();
    Buffer.SetSize(Len);
    FInput.BlockRead(PByte(Buffer.Memory)^, Len);

    // 1st pass: Extract meta data
    Reader := TJsonReader.Create(Buffer);

    if Reader.Dict then
      while (Reader.Advance <> jsDictEnd) and Reader.key(Key) do
      begin
        if Key = 'jsonrpc' then
          Reader.Str(Version)
        else if Key = 'method' then
          Reader.Str(Method)
        else if (Key = 'id') and Reader.Str(Id.Str) then
          Id.Kind := ridString
        else if (Key = 'id') and Reader.Number(Id.Int) then
          Id.Kind := ridInteger
        else if (Key = 'id') and Reader.Null then
          Id.Kind := ridNull;
      end;

    if Reader.LastError <> jeNoError then
      raise ERpcError.CreateFmt(
        jsrpcParseError,
        'Invalid Request. JSON error @%d: %s',
        [Reader.LastErrorPosition, Reader.LastErrorMessage]
      );

    if (Version <> '2.0') then
      raise ERpcError.Create(
        jsrpcInvalidRequest,
        'No or invalid jsonrpc version specified. Must be 2.0.'
      );

    if (Method = '') then
      raise ERpcError.Create(
        jsrpcInvalidRequest,
        'No method specified.'
      );

    FreeAndNil(Reader);

    // 2nd pass: Seek to params
    Buffer.Position := 0;
    Reader          := TJsonReader.Create(Buffer);
    if Reader.Dict then
      while Reader.Advance <> jsDictEnd do
        if Reader.Key(Key) and (Key = 'params') then
          break;

    // Workaround if no params were supplied (probably unnecessary)
    if Reader.State = jsEOF then
    begin
      FreeAndNil(Reader);
      FreeAndNil(Buffer);
      Buffer := TStringStream.Create('null');
      Reader := TJsonReader.Create(Buffer);
    end;

    Result         := TRpcRequest.Create;
    Result.Method  := Method;
    Result.Id      := Id;
    Result.Reader  := Reader;
    Result.FBuffer := Buffer;

    LogFullJson := UserConfig.ReadBool('log', 'full_json', false);
    if LogFullJson then
      CutLength := MaxInt
    else
      CutLength := 2000;

    DebugLog('> Request: ' + LineEnding + '%s', [
      // Use TrimRight as the Response may contain some newline in undefined convention (Unix or Windows)
      TrimRight(Copy(Result.AsString, 1, CutLength))
    ]);
  except
    FreeAndNil(Result);
    FreeAndNil(Reader);
    FreeAndNil(Buffer);
  end;
end;

procedure TRpcPeer.Send(Response: TRpcResponse);
const
  ContentType: string = 'application/vscode-jsonrpc; charset=utf-8';
  procedure WriteString(const S: string);
  begin
    FOutput.WriteBuffer(S[1], Length(S) * sizeof(S[1]));
  end;
var
  CutLength:        Integer;
  LogFullJson:      Boolean;
begin
  Response.Finalize;

  WriteString(Format(
    'Content-Type: %s'#13#10'Content-Length:%d'#13#10#13#10,
    [ContentType, Response.FBuffer.Size]
  ));
  FOutput.WriteBuffer(
    PByte(Response.FBuffer.Memory)^,
    Response.FBuffer.Size
  );

  if FOutput is THandleStream then
    FileFlush(THandleStream(FOutput).Handle);

  LogFullJson := UserConfig.ReadBool('log', 'full_json', false);
  if LogFullJson then
    CutLength := MaxInt
  else
    CutLength := 2000;

  DebugLog('< Response: ' + LineEnding + '%s', [
    // Use TrimRight as the Response may contain some newline in undefined convention (Unix or Windows)
    TrimRight(Copy(Response.AsString, 1, CutLength))
  ]);
end;

constructor ERpcError.Create(ACode: Integer; const Msg: string);
begin
  inherited Create(Msg);
  Code := ACode;
end;

constructor ERpcError.CreateFmt(
  ACode: Integer; const Fmt: string; args: array of const
);
begin
  inherited CreateFmt(Fmt, args);
  Code := ACode;
end;

procedure SendNullResponse(const Rpc: TRpcPeer; const Request: TRpcRequest);
var
  Response: TRpcResponse;
  Writer:   TJsonWriter;
begin
  Response := TRpcResponse.Create(Request.Id);
  try
    Writer := Response.Writer;
    Writer.Null;
    Rpc.Send(Response);
  finally
    FreeAndNil(Response);
  end;
end;

end.

