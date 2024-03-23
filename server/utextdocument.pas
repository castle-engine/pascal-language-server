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

unit utextdocument;

{$mode objfpc}{$H+}

interface

uses
  jsonstream, ujsonrpc;

type
  TSyntaxErrorReportingMode = (
    sermShowMessage = 0,
    sermFakeCompletionItem = 1,
    sermErrorResponse = 2
  );

var
  SyntaxErrorReportingMode: TSyntaxErrorReportingMode = sermShowMessage;

procedure TextDocument_DidOpen(Rpc: TRpcPeer; Request: TRpcRequest);
procedure TextDocument_DidChange(Rpc: TRpcPeer; Request: TRpcRequest);
procedure TextDocument_SignatureHelp(Rpc: TRpcPeer; Request: TRpcRequest);
procedure TextDocument_Completion(Rpc: TRpcPeer; Request: TRpcRequest);
procedure TextDocument_Declaration(Rpc: TRpcPeer; Request: TRpcRequest);
procedure TextDocument_Definition(Rpc: TRpcPeer; Request: TRpcRequest);

implementation

uses
  Classes, SysUtils, URIParser, CodeToolManager, CodeCache, IdentCompletionTool,
  BasicCodeTools, PascalParserTool, CodeTree, FindDeclarationTool, LinkScanner,
  CustomCodeTool, udebug, uutils;

function ParseChangeOrOpen(
  Reader: TJsonReader; out Uri: string; out Content: string; IsChange: Boolean
): Boolean;
var
  Key:                  string;
  HaveUri, HaveContent: Boolean;
begin
  HaveUri     := false;
  HaveContent := false;
  if Reader.Dict then
    while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
    begin
      if (Key = 'textDocument') and Reader.Dict then
        while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
        begin
          if (Key = 'uri') and Reader.Str(Uri) then
            HaveUri := true
          else if not IsChange and (Key = 'text') and Reader.Str(Content) then
            HaveContent := true;
        end
      else if IsChange and (Key = 'contentChanges') and Reader.List then
        while Reader.Advance <> jsListEnd do
        begin
          if Reader.Dict then
            while (Reader.Advance <> jsDictEnd) and (Reader.Key(Key)) do
            begin
              if (Key = 'text') and Reader.Str(Content) then
                HaveContent := true;
            end;
        end;
    end;
  Result := HaveUri and HaveContent;
end;

procedure TextDocument_DidOpen(Rpc: TRpcPeer; Request: TRpcRequest);
var
  Code:    TCodeBuffer;
  UriStr:  string;
  Content, FileName: string;
begin
  if ParseChangeOrOpen(Request.Reader, UriStr, Content, false) then
  begin
    FileName := URIToFileNameEasy(UriStr);
    Code := CodeToolBoss.LoadFile(FileName, false, false);
    { When we can't found file try to create it, workaround for creating
      new source files in vscode }
    if Code = nil then
      Code := CodeToolBoss.CreateFile(FileName);
    if Code = nil then
      raise ERpcError.CreateFmt(
        jsrpcInvalidRequest,
        'Unable to load file: %s', [FileName]
      );
    Code.Source := Content;
  end;
end;

procedure TextDocument_DidChange(Rpc: TRpcPeer; Request: TRpcRequest);
var
  Code:    TCodeBuffer;
  UriStr:  string;
  Content, FileName: string;
begin
  if ParseChangeOrOpen(Request.Reader, UriStr, Content, true) then
  begin
    FileName := URIToFileNameEasy(UriStr);
    Code     := CodeToolBoss.FindFile(FileName);
    if Code = nil then
      raise ERpcError.CreateFmt(
        jsrpcInvalidRequest,
        'Unable to load file: %s', [FileName]
      );
    Code.Source := Content;
  end;
end;

type
  TStringSlice = record
    a, b:       Integer;
  end;

  TCompletionRec = record
    Text:       String;
    Identifier: TStringSlice;
    ResultType: TStringSlice;
    Parameters: array of TStringSlice;
    Desc:       String;
  end;

  TCompletionCallback =
    procedure (const Rec: TCompletionRec; Writer: TJsonWriter);

procedure GetCompletionRecords(
  Code: TCodeBuffer; X, Y: Integer; Prefix: string; Exact: Boolean;
  Callback: TCompletionCallback; Writer: TJsonWriter
);
var
  Identifier:       TIdentifierListItem;
  i, j, Count:      Integer;
  ResultType:       string;
  Segment:          string;
  node, paramsNode: TCodeTreeNode;
  SegmentLen:       Integer;
  Rec:              TCompletionRec;
  CodeTool: TCodeTool;
  CodeTreeNode: TCodeTreeNode;

  function AppendString(var S: string; Suffix: string): TStringSlice;
  begin
    Result.a := Length(S) + 1;
    Result.b := Length(S) + Length(Suffix) + 1;
    S        := S + Suffix;
  end;

begin
  assert(Code <> nil);

  { At first we have to check the file has unit <name>, without that
    do not try return code completion because it returns only errors. }
  CodeToolBoss.Explore(Code, CodeTool, false, false);

  if CodeTool = nil then
    raise ERpcError.Create(jsrpcRequestFailed, 'File explore don''t return code tool.');

  if CodeTool.Tree = nil then
    raise ERpcError.Create(jsrpcRequestFailed, 'Code tool tree is nil.');

  { This check fails when pas file is empty, return empty response }
  if CodeTool.Tree.Root = nil then
    Exit;

  { Next we have to check there is interface in the code if not
    hint only interface word, without this check code completion returns
    only "Line ..." errors when CodeToolBoss.GatherIdentifiers() is called }
  CodeTreeNode := CodeTool.FindInterfaceNode;
  if CodeTreeNode = nil then
  begin
    Rec.Text         := 'interface';
    Rec.Identifier.a := 0;
    Rec.Identifier.b := 0;
    Rec.ResultType.a := 0;
    Rec.ResultType.b := 0;
    Rec.Parameters   := nil;
    Rec.Desc         := '';
    Callback(Rec, Writer);
    Exit;
  end;

  { Main code completion code }
  CodeToolBoss.IdentifierList.Prefix := Prefix;

  if not CodeToolBoss.GatherIdentifiers(Code, X, Y) then
    raise ERpcError.Create(
      jsrpcRequestFailed,
      Format('Line %d: %s', [
        CodeToolBoss.ErrorLine,
        CodeToolBoss.ErrorMessage
      ])
    );

  Count := CodeToolBoss.IdentifierList.GetFilteredCount;

  for i := 0 to Count - 1 do
  begin
    Identifier       := CodeToolBoss.IdentifierList.FilteredItems[i];

    Rec.Text         := '';
    Rec.Identifier.a := 0;
    Rec.Identifier.b := 0;
    Rec.ResultType.a := 0;
    Rec.ResultType.b := 0;
    Rec.Parameters   := nil;
    Rec.Desc         := '';
    ResultType       := '';

    if (not Exact) or (CompareText(Identifier.Identifier, Prefix) = 0) then
    begin
      paramsNode := Identifier.Tool.GetProcParamList(identifier.Node);
      if Assigned(paramsNode) then
      begin
        ResultType :=
          Identifier.Tool.ExtractProcHead(
            identifier.Node,
            [
              phpWithoutName, phpWithoutParamList, phpWithoutSemicolon,
              phpWithResultType, phpWithoutBrackets, phpWithoutGenericParams,
              phpWithoutParamTypes
            ]
          ).Replace(':', '').Trim;

        node := paramsNode.firstChild;

        Rec.Identifier := AppendString(Rec.Text, Identifier.Identifier);
        AppendString(Rec.Text, ' (');

        SetLength(Rec.Parameters, paramsNode.ChildCount);

        for j := 0 to paramsNode.ChildCount - 1 do
        begin
          Segment := Identifier.Tool.ExtractNode(node, []);
          Segment := StringReplace(Segment, ':', ': ', [rfReplaceAll]);
          Segment := StringReplace(Segment, '=', ' = ', [rfReplaceAll]);

          Rec.Parameters[j] := AppendString(Rec.Text, Segment);

          SegmentLen := Pos(':', Segment) - 1;
          if SegmentLen <= 0 then
            SegmentLen := Length(Segment);

          if J <> paramsNode.ChildCount - 1 then
            Rec.Text := Rec.Text + ', ';

          node := node.NextBrother;
        end;

        AppendString(Rec.Text, ')');
      end
      else
        Rec.Identifier := AppendString(Rec.Text, Identifier.Identifier);

      if ResultType <> '' then
      begin
        AppendString(Rec.Text, ': ');
        Rec.ResultType := AppendString(Rec.Text, ResultType);
      end;

      Rec.Desc := Identifier.Node.DescAsString;

      Callback(Rec, Writer);
    end;
  end;
end;

type
  TCompletionRequest = record
    X, Y:        Integer;
    FileName:    String;
    TriggerKind: Integer;
    TriggerChar: string;
    IsRetrigger: Boolean;
  end;

function ParseCompletionRequest(Reader: TJsonReader): TCompletionRequest;
var
  Key:    string;
  UriStr: string;
begin
  UriStr             := '';
  Result.TriggerKind := -1;
  Result.Y           := -1;
  Result.X           := -1;

  if Reader.Dict then
    while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
    begin
      if (Key = 'textDocument') and Reader.Dict then
        while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
        begin
          if Key = 'uri' then
            Reader.Str(UriStr);
        end
      else if (Key = 'position') and Reader.Dict then
        while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
        begin
          if Key = 'line' then
            Reader.Number(Result.Y)
          else if (Key = 'character') then
            Reader.Number(Result.X);
        end
      else if (Key = 'context') and Reader.Dict then
        while (Reader.Advance <> jsDictEnd) and Reader.Key(Key) do
        begin
          if Key = 'triggerKind' then
            Reader.Number(Result.TriggerKind)
          else if Key = 'triggerCharacter' then
            Reader.Str(Result.TriggerChar)
          else if Key = 'isRetrigger' then
            Reader.Bool(Result.IsRetrigger);
          //else if Key = 'activeSignatureHelp' then

        end;
    end;

  Result.FileName := URIToFileNameEasy(UriStr);
end;

// Identifier completion

procedure CompletionCallback(const Rec: TCompletionRec; Writer: TJsonWriter);
begin
  Writer.Dict;
    Writer.Key('insertText');
    Writer.Str(
      Copy(Rec.Text, Rec.Identifier.a, Rec.Identifier.b - Rec.Identifier.a)
    );

    Writer.Key('insertTextFormat');
    Writer.Number(1); // 1 = Plain Text

    Writer.Key('label');
    Writer.Str(Rec.Text);

    // text used to filter
    Writer.Key('filterText');
    Writer.Str(
      Copy(Rec.Text, Rec.Identifier.a, Rec.Identifier.b - Rec.Identifier.a)
    );

    Writer.Key('detail');
    Writer.Str(Rec.Desc);
  Writer.DictEnd;
end;

function GetPrefix(Code: TCodeBuffer; X, Y: integer): string;
var
  PStart, PEnd: integer;
  Line: String;
begin
  Line := Code.GetLine(Y);
  GetIdentStartEndAtPosition(Line, X + 1, PStart, PEnd);
  Result := Copy(Line, PStart, PEnd - PStart);
end;

{ Send a notification using LSP "window/showMessage".
  Internally it will create and destroy a necessary TRpcResponse instance.
  Remember that sending "window/showMessage" is *not* a response to LSP request for completions,
  so you still need to send something else as completion response. }
procedure ShowErrorMessage(const Rpc: TRpcPeer; const ErrorMessage: String);
var
  Writer: TJsonWriter;
  MessageNotification: TRpcResponse;
begin
  MessageNotification := TRpcResponse.CreateNotification('window/showMessage');
  try
    Writer := MessageNotification.Writer;

    Writer.Key('params');
    Writer.Dict;
      Writer.Key('type');
      Writer.Number(1); // type = 1 means "error"
      Writer.Key('message');
      Writer.Str(ErrorMessage);
    Writer.DictEnd;

    Rpc.Send(MessageNotification);
  finally
    FreeAndNil(MessageNotification);
  end;
end;

procedure TextDocument_Completion(Rpc: TRpcPeer; Request: TRpcRequest);

  { Create TRpcResponse with fake completion item, just to show ErrorMessage to user. }
  function CreateResponseFakeCompletionItem(const ErrorMessage: String): TRpcResponse;
  var
    Writer:   TJsonWriter;
  begin
    Result := TRpcResponse.Create(Request.Id);
    Writer := Result.Writer;

    Writer.Dict;
      { Note that isIncomplete value is required.
        See spec: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#completionList
        Emacs actually throws Lisp errors when it is missing. }
      Writer.Key('isIncomplete');
      Writer.Bool(false);

      Writer.Key('items');
      Writer.List;

        // Unfortunately, there isn't really a good way to report errors to the
        // client. While there are error responses, those aren't shown to the
        // user. There is also the call window/showMessage, but this one is not
        // implemented by NeoVim. So we work around it by showing a fake
        // completion item.
        Writer.Dict;
          Writer.Key('label');
          Writer.Str(ErrorMessage);
          Writer.Key('insertText');
          Writer.Str('');
        Writer.DictEnd;

      Writer.ListEnd;

      //Writer.Key('activeParameter');
      //Writer.Key('activeSignature');
    Writer.DictEnd;
  end;

  { Create TRpcResponse with no completions. }
  function CreateResponseNoCompletions: TRpcResponse;
  var
    Writer:   TJsonWriter;
  begin
    Result := TRpcResponse.Create(Request.Id);
    Writer := Result.Writer;

    Writer.Dict;
      Writer.Key('isIncomplete');
      Writer.Bool(false); // the list is complete, we will not return more completions if you continue typing

      Writer.Key('items');
      Writer.List;
      Writer.ListEnd;
    Writer.DictEnd;
  end;

var
  Req:      TCompletionRequest;
  Code:     TCodeBuffer;
  Prefix:   string;
  Response: TRpcResponse;
  Writer:   TJsonWriter;
begin
  Response := nil;
  try
    try
      Req  := ParseCompletionRequest(Request.Reader);
      Code := CodeToolBoss.FindFile(Req.FileName);

      if Code = nil then
        raise ERpcError.CreateFmt(
          jsrpcInvalidRequest,
          'File not found: %s', [Req.FileName]
        );

      Prefix   := GetPrefix(Code, Req.X, Req.Y);
      DebugLog('Complete: %d, %d, "%s"', [Req.X, Req.Y, Prefix]);

      Response := TRpcResponse.Create(Request.Id);
      Writer   := Response.Writer;

      Writer.Dict;
        Writer.Key('isIncomplete');
        Writer.Bool(false);

        Writer.Key('items');
        Writer.List;
          GetCompletionRecords(
            Code, Req.X + 1, Req.Y + 1, Prefix, false,
            @CompletionCallback, Writer
          );
        Writer.ListEnd;
      Writer.DictEnd;

      Rpc.Send(Response);
    except
      on E: ERpcError do
      begin
        FreeAndNil(Response);

        case SyntaxErrorReportingMode of
          sermFakeCompletionItem:
            Response := CreateResponseFakeCompletionItem(E.Message);
          sermShowMessage:
            begin
              Response := CreateResponseNoCompletions;
              ShowErrorMessage(Rpc, E.Message);
            end;
          sermErrorResponse:
            Response := TRpcResponse.CreateError(Request.Id, 0, E.Message);
        end;
        Rpc.Send(Response);
      end;
    end;
  finally
    FreeAndNil(Response);
  end;
end;

// Signature help

procedure SignatureCallback(const Rec: TCompletionRec; Writer: TJsonWriter);
var
  i: Integer;
begin
  Writer.Dict;
    Writer.Key('label');
    Writer.Str(Rec.Text);

    Writer.Key('parameters');
    Writer.List;
      for i := low(Rec.Parameters) to high(Rec.Parameters) do
      begin
        Writer.Dict;
          Writer.Key('label');
          Writer.List;
            Writer.Number(Rec.Parameters[i].a);
            Writer.Number(Rec.Parameters[i].b);
          Writer.ListEnd;
          // Writer.Key('documentation');
        Writer.DictEnd;
      end;
    Writer.ListEnd;

    //Writer.Key('documentation');
    //Writer.Key('activeParameter');
  Writer.DictEnd;
end;

procedure TextDocument_SignatureHelp(Rpc: TRpcPeer; Request: TRpcRequest);
var
  Code:     TCodeBuffer;
  ProcName: string;
  Req:      TCompletionRequest;
  Response: TRpcResponse;
  Writer:   TJsonWriter;

  function GetProcName(Code: TCodeBuffer; var X, Y: Integer): string;
  var
    CodeContexts: TCodeContextInfo;
    ProcStart:    Integer;
  begin
    Result := '';

    CodeToolBoss.FindCodeContext(Code, X + 1, Y + 1, CodeContexts);

    if not Assigned(CodeContexts) then
      raise ERpcError.Create(jsrpcRequestFailed, CodeToolBoss.ErrorMessage);

    ProcStart := CodeContexts.StartPos;

    (*
      Testcase:
      - edit castle-engine/src/transform/castletransform_physics.inc
      - in TCastleCollider.CustomSerialization...
      - write ReadWriteBoolean and then type opening parenthesis "("

      Without the safeguard below, we have an occasional crash after LSP request
      {"jsonrpc":"2.0","method":"textDocument/signatureHelp","params":{"textDocument":{"uri":"file:///home/michalis/sources/castle-engine/castle-engine/src/transform/castletransform_physics.inc"},"position":{"line":1597,"character":21}},"id":2}

      The request looks OK (file uri, line and column numbers are OK).
      Debugging, the Code.Source value is also OK, contains the correct file text.
      But the ProcStart has weirdly large value, way beyond the file size.

      With the fix below, it only results in warning:
        Warning: GetProcName impossible, ProcStart (586344) beyond Length(Code.Source) (122268)
      Otherwise LSP server could crash with range check error when doing
      Code.Source[ProcStart] later.
    *)
    if ProcStart > Length(Code.Source) then
    begin
      DebugLog('Warning: GetProcName impossible, ProcStart (%d) beyond Length(Code.Source) (%d)', [
        ProcStart,
        Length(Code.Source)
      ]);
      Exit('');
    end;

    // Find closest opening parenthesis
    while (ProcStart > 1) and (Code.Source[ProcStart] <> '(') do
      Dec(ProcStart);

    // ProcStart point to the parenthesis before the first parameter.
    // But we actually need a position *inside* the procedure identifier.
    // Note that there may be whitespace, even newlines, between the first
    // parenthesis and the procedure.
    while (ProcStart > 1) and
          (Code.Source[ProcStart] in ['(', ' ', #13, #10, #9]) do
      Dec(ProcStart);

    Code.AbsoluteToLineCol(ProcStart, Y, X);

    Result := CodeContexts.ProcName;
  end;
begin
  Response := nil;
  try
    try
      Req  := ParseCompletionRequest(Request.Reader);
      Code := CodeToolBoss.FindFile(Req.FileName);

      if Code = nil then
        raise ERpcError.CreateFmt(
          jsrpcInvalidRequest,
          'File not found: %s', [Req.FileName]
        );

      ProcName := GetProcName(Code, Req.X, Req.Y);

      Response := TRpcResponse.Create(Request.Id);
      Writer   := Response.Writer;

      Writer.Dict;
        Writer.Key('signatures');
        Writer.List;
          GetCompletionRecords(
            Code, Req.X, Req.Y, ProcName, true, @SignatureCallback, Writer
          );
        Writer.ListEnd;

        //Writer.Key('activeParameter');
        //Writer.Key('activeSignature');
      Writer.DictEnd;

      Rpc.Send(Response);
    except
      on E: ERpcError do
      begin
        // Unfortunately, there isn't really a good way to report errors to the
        // client. While there are error responses, those aren't shown to the
        // user. There is also the call window/showMessage, but this one is not
        // implemented by NeoVim. So we work around it by showing a fake
        // completion item.
        FreeAndNil(Response);
        Response := TRpcResponse.Create(Request.Id);
        Writer := Response.Writer;
        Writer.Dict;
          Writer.Key('signatures');
          Writer.List;
            Writer.Dict;
              Writer.key('label');
              Writer.Str(e.Message);
            Writer.DictEnd;
          Writer.ListEnd;

          //Writer.Key('activeParameter');
          //Writer.Key('activeSignature');
        Writer.DictEnd;
        Rpc.Send(Response);
      end;
    end;
  finally
    FreeAndNil(Response);
  end;
end;

// Go to declaration

type
  TJumpTarget = (jmpDeclaration, jmpDefinition);

procedure TextDocument_JumpTo(
  Rpc: TRpcPeer; Request: TRpcRequest; Target: TJumpTarget
);
var
  Req:               TCompletionRequest;
  Response:          TRpcResponse;
  Writer:            TJsonWriter;

  Code:              TCodeBuffer;
  CurPos:            TCodeXYPosition;
  NewPos:            TCodeXYPosition;

  // Find declaration
  FoundDeclaration:  Boolean;
  ExprType:          TExpressionType;

  // Determine type
  IsProc:            Boolean;
  CleanPos:          Integer;
  Tool:              TCodeTool;
  Node:              TCodeTreeNode;

  // JumpToMethod
  FoundMethod:       Boolean;
  NewTopLine,
  BlockTopLine,
  BlockBottomLine:   Integer;
  RevertableJump:    Boolean;

  Success:           Boolean;

begin
  Response := nil;
  Success  := false;
  IsProc   := false;
  Node     := nil;

  try
    Req := ParseCompletionRequest(Request.Reader);

    Code := CodeToolBoss.FindFile(Req.FileName);

    if Code = nil then
      raise ERpcError.CreateFmt(
        jsrpcInvalidRequest,
        'File not found: %s', [Req.FileName]
      );

    if not CodeToolBoss.InitCurCodeTool(Code) then
      raise ERpcError.CreateFmt(
        jsrpcRequestFailed,
        'Could not initialize code tool', []
      );

    CurPos.Code := Code;
    CurPos.X    := Req.X + 1;
    CurPos.Y    := Req.Y + 1;

    DebugLog(
      'Find declaration/definition: %d, %d "%s"',
      [Req.X, Req.Y, GetPrefix(Code, Req.X, Req.Y)]
    );

    try
      // Find declaration
      FoundDeclaration :=
        (Target in [jmpDeclaration, jmpDefinition]) and
        CodeToolBoss.CurCodeTool.FindDeclaration(
          CurPos, DefaultFindSmartHintFlags+[fsfSearchSourceName],
          ExprType, NewPos, NewTopLine

        );
      if FoundDeclaration then
      begin
        CurPos  := NewPos;
        Success := true;

        // Determine type
        if CodeToolBoss.InitCurCodeTool(CurPos.Code) then
        begin
          Tool := CodeToolBoss.CurCodeTool;
          assert(Assigned(Tool));
          if Tool.CaretToCleanPos(CurPos, CleanPos) = 0 then
            Node := Tool.FindDeepestNodeAtPos(CleanPos, false);
          if Assigned(Node) then
            IsProc := Node.Desc in [ctnProcedure, ctnProcedureHead];
        end;
      end;

      // Try to jump to method implementation
      FoundMethod :=
        FoundDeclaration and IsProc and (Target = jmpDefinition) and
        CodeToolBoss.JumpToMethod(
          CurPos.Code, CurPos.X, CurPos.Y, NewPos.Code, NewPos.X, NewPos.Y,
          NewTopline, BlockTopLine, BlockBottomLine, RevertableJump
        );

      if FoundMethod then
      begin
        CurPos  := NewPos;
        Success := true;
      end;
    except
      on E: ECodeToolError do
      begin
        // exeption raised when we search identifier in some comments words
        // has id 20170421200105 so we then do not show message window in vscode
        if E.Id <> 20170421200105 then
        begin
          ShowErrorMessage(Rpc, E.Message);
        end;
      end;
      { ELinkScannerError is raised from FindDeclaration e.g. when include file is missing.
        Without capturing it here, trying to jump to declarations when there's an error
        would crash pasls server. }
      on E: ELinkScannerError do
        ShowErrorMessage(Rpc, E.Message);
    end;

    Response := TRpcResponse.Create(Request.Id);
    Writer   := Response.Writer;

    (*It is possible to get here Sucess and CurPos.Code = nil.

      Testcase: ctrl + click on TFloatRectangle.Empty in comment like this:

      { Image region to which we should limit the display.
        Empty (following @link(TFloatRectangle.Empty)) means using the whole image.

      Logging shows:

      {"jsonrpc":"2.0","id":9,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///home/michalis/sources/castle-engine/castle-engine/src/base_rendering/castleglimages_persistentimage.inc"},"position":{"line":230,"character":46}}}
      Find declaration/definition: 46, 230 "write"
      TextDocument_JumpTo debug: CurPos.Code<>nil False
      FATAL EXCEPTION: Access violation

        $0000000000492077  TEXTDOCUMENT_JUMPTO,  line 780 of utextdocument.pas
        $0000000000492320  TEXTDOCUMENT_DEFINITION,  line 825 of utextdocument.pas
        $000000000040169A  DISPATCH,  line 64 of pasls.lpr
        $00000000004017DA  MAIN,  line 90 of pasls.lpr
        $00000000004022AC  main,  line 239 of pasls.lpr

      TODO: debug this to the end, why Code can be nil?
      Quickly looking at how it is used above, and NewPos and how CodeTools
      set it -- I don't see how it can.
    *)
    if Success and (CurPos.Code = nil) then
      Success := false;

    if Success then
    begin
      Writer.Dict;
        Writer.Key('uri');
        Writer.Str(FileNameToURI(CurPos.Code.Filename));

        Writer.Key('range');
        Writer.Dict;
          Writer.Key('start');
          Writer.Dict;
            Writer.Key('line');
            Writer.Number(CurPos.Y - 1);

            Writer.Key('character');
            Writer.Number(CurPos.X - 1);
          Writer.DictEnd;

          Writer.Key('end');
          Writer.Dict;
            Writer.Key('line');
            Writer.Number(CurPos.Y - 1);

            Writer.Key('character');
            Writer.Number(CurPos.X - 1);
          Writer.DictEnd;
        Writer.DictEnd;
      Writer.DictEnd;
    end
    else
    begin
      Writer.Null;
    end;

    Rpc.Send(Response);
  finally
    FreeAndNil(Response);
  end;
end;

procedure TextDocument_Declaration(Rpc: TRpcPeer; Request: TRpcRequest);
begin
  TextDocument_JumpTo(Rpc, Request, jmpDeclaration);
end;

procedure TextDocument_Definition(Rpc: TRpcPeer; Request: TRpcRequest);
begin
  TextDocument_JumpTo(Rpc, Request, jmpDefinition);
end;

end.

