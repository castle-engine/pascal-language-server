unit ULogVSCode;

{$mode ObjFPC}{$H+}

interface

uses
  sysutils, jsonstream, ujsonrpc;

type

  TVSCodeTraceValue = (
    tvOff = 0,
    tvMessages,
    tvVerbose
  );

  { https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#messageType }
  TVSCodeMessageLogType = (
    mltError = 1,
    mltWarning,
    mltInfo,
    mltLog,
  );

  function ParseSetTrace(const Request: TRpcRequest): TVSCodeTraceValue;
  { Log Trace to work you need to add :
    "pascal-language-server.trace.server": "verbose",
    "pascal-language-server.trace.server": "messages",
    to your settings.json.

    Default value is "pascal-language-server.trace.server": "off". }
  procedure LogTrace(const Rpc: TRpcPeer; const Message: String; const Verbose: String = '');

  { https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#window_logMessage}
  procedure LogError(const Rpc: TRpcPeer; const Message: String);
  procedure LogWarning(const Rpc: TRpcPeer; const Message: String);
  procedure LogInfo(const Rpc: TRpcPeer; const Message: String);
  procedure LogMessage(const Rpc: TRpcPeer; const LogType: TVSCodeMessageLogType; const Message: String);

var
  TraceValue: TVSCodeTraceValue = tvOff;


implementation

uses udebug;

{ https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#traceValue }
function ParseSetTrace(const Request: TRpcRequest): TVSCodeTraceValue;
var
  Reader: TJsonReader;
  Key: String;
  Value: String;
begin
  Reader := Request.Reader;

  if Reader.Dict then
  begin
    while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
    begin
      if Key = 'value' then
      begin
        Reader.Str(Value);

        if Value = 'off' then
          Exit(tvOff)
        else
        if Value = 'message' then
          Exit(tvMessages)
        else
        if Value = 'verbose' then
          Exit(tvVerbose)
        else
        begin
          DebugLog('ParseSetTrace uknown value: ' + Value);
          Exit(tvVerbose);
        end;
      end;
    end;
  end;
  Result := tvOff;
end;

{ https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#logTrace }
procedure LogTrace(const Rpc: TRpcPeer; const Message: String; const Verbose: String = '');
var
  Notif: TRpcResponse;
  Writer: TJsonWriter;
begin
  if TraceValue = tvOff then
    Exit;

  Notif := TRpcResponse.CreateNotification('$/logTrace');
  try
    Writer := Notif.Writer;
    Writer.Key('params');
    Writer.Dict;
      Writer.Key('message');
      Writer.Str(Message);
      if TraceValue = tvVerbose then
      begin
        Writer.Key('verbose');
        Writer.Str(Verbose);
      end;
    Writer.DictEnd;
    Rpc.Send(Notif);
  finally
    FreeAndNil(Notif);
  end;
end;

procedure LogError(const Rpc: TRpcPeer; const Message: String);
begin
  LogMessage(Rpc, mltError, Message);
end;

procedure LogWarning(const Rpc: TRpcPeer; const Message: String);
begin
  LogMessage(Rpc, mltWarning, Message);
end;

procedure LogInfo(const Rpc: TRpcPeer; const Message: String);
begin
  LogMessage(Rpc, mltInfo, Message);
end;

procedure LogMessage(const Rpc: TRpcPeer; const LogType: TVSCodeMessageLogType; const Message: String);
var
  Notif: TRpcResponse;
  Writer: TJsonWriter;
begin
  Notif := TRpcResponse.CreateNotification('window/logMessage');
  try
    Writer := Notif.Writer;
    Writer.Key('params');
    Writer.Dict;
      Writer.Key('type');
      Writer.Number(Integer(LogType));

      Writer.Key('message');
      Writer.Str(Message);
    Writer.DictEnd;
    Rpc.Send(Notif);
  finally
    FreeAndNil(Notif);
  end;
end;


end.

