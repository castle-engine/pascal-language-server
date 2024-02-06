unit UDocumentSymbolSupport;

{
  Implementation of DocumentSymbol

  Docs: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#documentSymbol
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, jsonstream, ujsonrpc, uutils;

type
  { Enumeration of symbol kinds based on
    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#symbolKind }
  TDocumentSymbolKind = (
    dskFile = 1,
    dskModule,
    dskNamespace,
    dskPackage,
    dskClass,
    dskMethod,
    dskProperty,
    dskField,
    dskConstructor,
    dskEnum,
    dskInterface,
    dskFunction,
    dskVariable,
    dskConstant,
    dskString,
    dskNumber,
    dskBoolean,
    dskArray,
    dskObject,
    dskKey,
    dskNull,
    dskEnumMember,
    dskStruct,
    dskEvent,
    dskOperator,
    dskTypeOperator
  );

  TSymbolTag = (
    stDeprecated
  );

  TSymbolTags = set of TSymbolTag;

  procedure TextDocument_DocumentSymbol(Rpc: TRpcPeer; Request: TRpcRequest);

implementation

uses ulogvscode, CodeToolManager, CodeCache, CodeTree, PascalParserTool{$ifdef WINDOWS}, LazUTF8{$endif};

function ParseDocumentSymbolRequest(Reader: TJsonReader): String;
var
  Key, Uri: String;
begin
  Uri := '';
  if Reader.Dict then
    while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
    begin
      if (Key = 'textDocument') and Reader.Dict then
        while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
        begin
          if Key = 'uri' then
          begin
            Reader.Str(Uri);
            break;
          end;
        end
    end;
  Result := URIToFileNameEasy(Uri);
end;

{ Responses for textDocument/documentSymbol method
  Docs: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_documentSymbol }
procedure TextDocument_DocumentSymbol(Rpc: TRpcPeer; Request: TRpcRequest);
var
  Filename: String;
  Code: TCodeBuffer;
  CodeTool: TCodeTool;
  CodeTreeNode: TCodeTreeNode;

  Node: TCodeTreeNode;

  Response: TRpcResponse;
  Writer:   TJsonWriter;

  StartCaret: TCodeXYPosition;
  EndCaret: TCodeXYPosition;
  ProcedureName: String;
begin
  Filename := ParseDocumentSymbolRequest(Request.Reader);
  LogInfo(Rpc, 'File name:' + Filename);
  Code := CodeToolBoss.FindFile(Filename);

  if Code = nil then
    raise ERpcError.CreateFmt(
      jsrpcInvalidRequest,
      'File not found: %s', [Filename]
    );

 { Based on lazarus TProcedureListForm.GetCodeTreeNode() }

  CodeToolBoss.Explore(Code, CodeTool, false, false);

  if CodeTool = nil then
    raise ERpcError.Create(jsrpcRequestFailed, 'File explore don''t return code tool.');

  if CodeTool.Tree = nil then
    raise ERpcError.Create(jsrpcRequestFailed, 'Code tool tree is nil.');

  { This check fails when pas file is empty, return null in response }
  if CodeTool.Tree.Root = nil then
  begin
    Response := nil;
    try
      Response := TRpcResponse.Create(Request.Id);
      Writer   := Response.Writer;
      Writer.Null;
      Rpc.Send(Response);
    finally
      FreeAndNil(Response);
    end;
    Exit;
  end;

  { Search for implementation node }
  try
     CodeTreeNode := CodeTool.FindImplementationNode;
  except
    on E: Exception do
      raise ERpcError.Create(jsrpcRequestFailed, 'FindImplementationNode exception: ' + E.Message);
  end;

  { When there is no implementation section try to parse interface }
  if CodeTreeNode = nil then
    CodeTreeNode := CodeTool.FindInterfaceNode;

  { This check fails there is no interface and implementation in file }
  if CodeTreeNode = nil then
  begin
    Response := nil;
    try
      Response := TRpcResponse.Create(Request.Id);
      Writer   := Response.Writer;
      Writer.Null;
      Rpc.Send(Response);
    finally
      FreeAndNil(Response);
    end;
    Exit;
  end;

  Response := nil;
  try
    Response := TRpcResponse.Create(Request.Id);
    Writer   := Response.Writer;

    Writer.List;
      { Based on lazarus TProcedureListForm.AddToGrid() and other functions }
      Node := CodeTreeNode;
      while Node <> nil do
      begin
        // LogInfo(Rpc, 'Node: ' + Node.DescAsString);
        if Node.Desc = ctnProcedure then
        begin
          { LogInfo(Rpc, CodeTool.ExtractProcHead(Node, [phpAddParentProcs,
            phpWithoutParamList, phpWithoutBrackets, phpWithoutSemicolon])); }

          { Get the real position in source file }
          CodeTool.CleanPosToCaret(Node.StartPos, StartCaret);
          CodeTool.CleanPosToCaret(Node.EndPos, EndCaret);

          { Inc file support: do not add procedures those demand jump to another
            include file that makes they do not work }

          //LogInfo(Rpc, 'Caret file name ' + StartCaret.Code.Filename);
          //LogInfo(Rpc, 'Filename ' + Filename);
          {$ifdef WINDOWS}
          if UTF8CompareText(StartCaret.Code.Filename, Filename) <> 0 then
          {$else}
          if StartCaret.Code.Filename <> Filename then
          {$endif}
          begin
            Node := Node.Next;
            continue;
          end;

          ProcedureName := CodeTool.ExtractProcHead(Node, [phpAddParentProcs,
              phpWithoutParamList, phpWithoutBrackets, phpWithoutSemicolon]);

          { Check procedure name is not empty, that makes vscode returns errors.
            Can happen when we start write new procedure. }
          if Trim(ProcedureName) = '' then
          begin
            Node := Node.Next;
            continue;
          end;

          Writer.Dict;
            Writer.Key('name');
            Writer.Str(ProcedureName);

            Writer.Key('kind');
            Writer.Number(Integer(dskMethod));


            Writer.Key('range');
            Writer.Dict;
              Writer.Key('start');
              Writer.Dict;
                Writer.Key('line');
                Writer.Number(StartCaret.Y);
                Writer.Key('character');
                Writer.Number(StartCaret.X);
              Writer.DictEnd;
              Writer.Key('end');
              Writer.Dict;
                Writer.Key('line');
                Writer.Number(EndCaret.Y);
                Writer.Key('character');
                Writer.Number(EndCaret.X);
              Writer.DictEnd;
            Writer.DictEnd;

            Writer.Key('selectionRange');
            Writer.Dict;
              Writer.Key('start');
              Writer.Dict;
                Writer.Key('line');
                Writer.Number(StartCaret.Y);
                Writer.Key('character');
                Writer.Number(StartCaret.X);
              Writer.DictEnd;
              Writer.Key('end');
              Writer.Dict;
                Writer.Key('line');
                Writer.Number(StartCaret.Y);
                Writer.Key('character');
                Writer.Number(StartCaret.X);
              Writer.DictEnd;
            Writer.DictEnd;

          Writer.DictEnd;
        end;
        Node := Node.Next;
      end;
    Writer.ListEnd;
    Rpc.Send(Response);
  finally
    FreeAndNil(Response);
  end;
end;

end.

