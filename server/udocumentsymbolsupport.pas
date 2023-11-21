unit UDocumentSymbolSupport;

{
  Implementation of DocumentSymbol

  Docs: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#documentSymbol
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, jsonstream, ujsonrpc, Generics.Collections, uutils, udebug;

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

  { https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#position }
  TPosition = record
    Line: Integer;
    Character: Integer;
  end;

  { https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#range }
  TRange = record
     Starts: TPosition;
     Ends: TPosition;
  end;


  TDocumentSymbol = class;
  TDocumentSymbolList = specialize TList<TDocumentSymbol>;

  { Class based on
    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#documentSymbol }
  TDocumentSymbol = class
  public
    Name: String;
    Detail: String;
    Kind: TDocumentSymbolKind;
    SymbolTags: TSymbolTags;
    Deprecated: Boolean;
    Range: TRange;
    SelectionRange: TRange;
    Children: TDocumentSymbolList;
  end;


  function Position(const ALine, ACharacter: Integer): TPosition;
  function Range(const AStarts, AEnds: TPosition): TRange;

  procedure TextDocument_DocumentSymbol(Rpc: TRpcPeer; Request: TRpcRequest);

implementation

uses ulogvscode, CodeToolManager, CodeCache, CodeTree, PascalParserTool;

function Position(const ALine, ACharacter: Integer): TPosition;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

function Range(const AStarts, AEnds: TPosition): TRange;
begin
  Result.Starts := AStarts;
  Result.Ends := AEnds;
end;


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

procedure TextDocument_DocumentSymbol(Rpc: TRpcPeer; Request: TRpcRequest);
var
  Filename: String;
  Code: TCodeBuffer;
  CodeTool: TCodeTool;
  CodeTreeNode: TCodeTreeNode;

  Node: TCodeTreeNode;

  Response: TRpcResponse;
  Writer:   TJsonWriter;
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

  if CodeTool.Tree.Root = nil then
    raise ERpcError.Create(jsrpcRequestFailed, 'Code tree root is nil.');

  { Search for implementation node }
  CodeTreeNode := CodeTool.FindImplementationNode;

  { TODO: More debug lazarus in this case does something like
    CodeTreeNode := CodeTool.Tree.Root, does it make sense for us? }
  if CodeTreeNode = nil then
    raise ERpcError.Create(jsrpcRequestFailed, 'Can''t find implementation section.');

  Response := nil;
  try
    Response := TRpcResponse.Create(Request.Id);
    Writer   := Response.Writer;

    Writer.List;
      { Based on lazarus TProcedureListForm.AddToGrid() }
      Node := CodeTreeNode;
      while Node <> nil do
      begin
        LogInfo(Rpc, 'Node: ' + Node.DescAsString);
        if Node.Desc = ctnProcedure then
        begin
          LogInfo(Rpc, CodeTool.ExtractProcHead(Node, [phpAddParentProcs,
            phpWithoutParamList, phpWithoutBrackets, phpWithoutSemicolon]));
          Writer.Dict;
            Writer.Key('name');
            Writer.Str(CodeTool.ExtractProcHead(Node, [phpAddParentProcs,
              phpWithoutParamList, phpWithoutBrackets, phpWithoutSemicolon]));

            Writer.Key('kind');
            Writer.Number(Integer(dskMethod));

            Writer.Key('range');
            Writer.Dict;
              Writer.Key('start');
              Writer.Dict;
                Writer.Key('line');
                Writer.Number(1);
                Writer.Key('character');
                Writer.Number(1);
              Writer.DictEnd;
              Writer.Key('end');
              Writer.Dict;
                Writer.Key('line');
                Writer.Number(1);
                Writer.Key('character');
                Writer.Number(5);
              Writer.DictEnd;
            Writer.DictEnd;

            Writer.Key('selectionRange');
            Writer.Dict;
              Writer.Key('start');
              Writer.Dict;
                Writer.Key('line');
                Writer.Number(1);
                Writer.Key('character');
                Writer.Number(1);
              Writer.DictEnd;
              Writer.Key('end');
              Writer.Dict;
                Writer.Key('line');
                Writer.Number(1);
                Writer.Key('character');
                Writer.Number(5);
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

