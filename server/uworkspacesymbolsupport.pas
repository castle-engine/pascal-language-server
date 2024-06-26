unit UWorkspaceSymbolSupport;

{
  Implementation of WorkspaceSymbol

  Docs: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workspace_symbol
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, jsonstream, ujsonrpc, uutils;

type
  { Enumeration of symbol kinds based on
    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#symbolKind }
  TSymbolKind = (
    skFile = 1,
    skModule,
    skNamespace,
    skPackage,
    skClass,
    skMethod,
    skProperty,
    skField,
    skConstructor,
    skEnum,
    skInterface,
    skFunction,
    skVariable,
    skConstant,
    skString,
    skNumber,
    skBoolean,
    skArray,
    skObject,
    skKey,
    skNull,
    skEnumMember,
    skStruct,
    skEvent,
    skOperator,
    skTypeOperator
  );

  TSymbolTag = (
    stDeprecated
  );

  TSymbolTags = set of TSymbolTag;

  procedure WorkspaceSymbol(Rpc: TRpcPeer; Request: TRpcRequest; const Directories: TStrings);

implementation

uses ulogvscode, CodeToolManager, CodeCache, CodeTree, URIParser, PascalParserTool;

function ParseDocumentSymbolRequest(Reader: TJsonReader): String;
var
  Key, Uri: String;
begin
  Uri := '';
  if Reader.Dict then
    while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
    begin
      if Key = 'query' then
      begin
        Reader.Str(Uri);
        break;
      end;
    end;
  Result := URIToFileNameEasy(Uri);
end;

{ Responses for textDocument/documentSymbol method
  Docs: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workspace_symbol }
procedure WorkspaceSymbol(Rpc: TRpcPeer; Request: TRpcRequest; const Directories: TStrings);
var
  FileName, Query: String;
  Code: TCodeBuffer;
  CodeTool: TCodeTool;
  CodeTreeNode: TCodeTreeNode;

  Node: TCodeTreeNode;

  Response: TRpcResponse;
  Writer:   TJsonWriter;

  StartCaret: TCodeXYPosition;
  EndCaret: TCodeXYPosition;
  ProcedureName: String;

  Files: TStrings;
  FilesWithPaths: TStringList;
  I, J: Integer;
  Directory: String;
begin
  Query := ParseDocumentSymbolRequest(Request.Reader);
  LogInfo(Rpc, 'Query:' + Query);

  FilesWithPaths := TStringList.Create;
  try
    Files := TStringList.Create;
    try
      for I := 0 to Directories.Count - 1 do
      begin
        Directory := IncludeTrailingPathDelimiter(Directories[I]);
        //LogInfo(Rpc, 'Directory1:' + Directory);
        //LogInfo(Rpc, 'Directory2:' + Directories[I]);
        Files.Clear;

        CodeToolBoss.SourceCache.DirectoryCachePool.GetListing(Directory, Files, false);

        for J := 0 to Files.Count - 1 do
        begin
          FileName := Files[J];
          if LowerCase(ExtractFileExt(FileName)) <> '.pas' then
             continue;
          FilesWithPaths.Add(Directory + FileName);
          //LogInfo(Rpc, 'File:' + FileName);
          //LogInfo(Rpc, 'FileWithPaths:' + Directory + FileName);
        end;
      end;
    finally
      FreeAndNil(Files);
    end;

    Response := nil;
    try
      Response := TRpcResponse.Create(Request.Id);
      Writer   := Response.Writer;

      Writer.List;
      for I := 0  to FilesWithPaths.Count -1 do
      begin
        FileName := FilesWithPaths[I];

        Code := CodeToolBoss.FindFile(Filename);

        if Code = nil then
        begin
          Code := CodeToolBoss.LoadFile(FileName,false, false);
          if Code = nil then
            Continue;
        end;

        CodeToolBoss.Explore(Code, CodeTool, false, false);

        { This happens when opening include file without MainUnit,
          like https://github.com/castle-engine/castle-engine/blob/master/src/common_includes/castleconf.inc .
          Return empty response. }
        if CodeTool = nil then
          Continue;

        if CodeTool.Tree = nil then
          raise ERpcError.Create(jsrpcRequestFailed, 'Code tool tree is nil.');

        { This check fails when pas file is empty, return null in response }
        if CodeTool.Tree.Root = nil then
          Continue;

        CodeTreeNode := CodeTool.FindImplementationNode;
        { When there is no implementation section try to parse interface }
        if CodeTreeNode = nil then
          CodeTreeNode := CodeTool.FindInterfaceNode;

        if CodeTreeNode = nil then
          Continue;

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
              Writer.Number(Integer(skMethod));

              Writer.Key('location');
              Writer.Dict;
                Writer.Key('uri');
                Writer.Str(FilenameToURI(StartCaret.Code.Filename));
                Writer.Key('range');
                Writer.Dict;
                  Writer.Key('start');
                  Writer.Dict;
                    Writer.Key('line');
                    Writer.Number(StartCaret.Y - 1 );
                    Writer.Key('character');
                    Writer.Number(StartCaret.X);
                  Writer.DictEnd;
                  Writer.Key('end');
                  Writer.Dict;
                    Writer.Key('line');
                    Writer.Number(EndCaret.Y - 1);
                    Writer.Key('character');
                    Writer.Number(EndCaret.X);
                  Writer.DictEnd;
                Writer.DictEnd;
              Writer.DictEnd;
            Writer.DictEnd;
          end;
          Node := Node.Next;
        end;

      end;
      Writer.ListEnd;
      Rpc.Send(Response);
    finally
      FreeAndNil(Response);
    end;

  finally
    FreeAndNil(FilesWithPaths);
  end;
end;

end.

