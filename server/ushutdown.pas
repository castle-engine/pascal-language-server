unit ushutdown;

{$mode ObjFPC}{$H+}

interface

uses
  jsonstream, ujsonrpc;

procedure Shutdown(Rpc: TRpcPeer; Request: TRpcRequest);

var
  WasShutdown: Boolean;

implementation

uses SysUtils, Classes, udebug;

{
  When client wants to stop lsp server send shutdown message and after
  it get response (null). Send second message exit to simply close the server.

  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#shutdown
}
procedure Shutdown(Rpc: TRpcPeer; Request: TRpcRequest);
var
  Response: TRpcResponse;
  Writer:   TJsonWriter;

begin
  DebugLog('Get shutdown message, waiting for exit...');
  WasShutdown := true;

  Response := nil;
  try
    Response := TRpcResponse.Create(Request.Id);
    Writer   := Response.Writer;

    Writer.Null;
    Rpc.Send(Response);
  finally
    FreeAndNil(Response);
  end;
end;

end.

