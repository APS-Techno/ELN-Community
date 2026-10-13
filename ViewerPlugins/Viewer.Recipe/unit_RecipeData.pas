unit unit_RecipeData;

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  unit_ELNPluginTypes;

type
  TRecipeParam = record
    Group, Name, Caption, Units, ParamType, Text: string;
  end;

  TRecipeStep = record
    Line: Integer;
    Verb: string;
    Args: TArray<string>;
  end;

  TRecipeData = class
  private
    FTitle: string;
    FRecipeType: string;
    FAuthor: string;
    FNotes: string;
    FScript: string;
    FParams: TArray<TRecipeParam>;
    FSteps: TArray<TRecipeStep>;
    procedure ParseScript;
  public
    procedure Clear;
    function LoadFromText(const XmlText: string): Boolean;
    function LoadFromFile(const AFileName: string): Boolean;
    function BuildKeyValues: TArray<TPluginKeyValue>;
    function BuildDetailedJson: TJSONObject;
    function CountVerb(const Verb: string): Integer;

    property Title: string read FTitle;
    property RecipeType: string read FRecipeType;
    property Author: string read FAuthor;
    property Notes: string read FNotes;
    property Script: string read FScript;
    property Params: TArray<TRecipeParam> read FParams;
    property Steps: TArray<TRecipeStep> read FSteps;
  end;

function TryParseRecipeNumber(const S: string; out V: Double): Boolean;

implementation

uses
  System.IOUtils, System.Variants, System.StrUtils, System.Generics.Collections,
  Xml.XMLDoc, Xml.XMLIntf;

function TryParseRecipeNumber(const S: string; out V: Double): Boolean;
var
  T: string;
  I: Integer;
begin
  V := 0;
  T := Trim(S);
  I := 1;
  if (I <= Length(T)) and CharInSet(T[I], ['+', '-']) then Inc(I);
  while (I <= Length(T)) and CharInSet(T[I], ['0'..'9', '.']) do Inc(I);
  if (I <= Length(T)) and CharInSet(T[I], ['e', 'E']) then
  begin
    Inc(I);
    if (I <= Length(T)) and CharInSet(T[I], ['+', '-']) then Inc(I);
    while (I <= Length(T)) and CharInSet(T[I], ['0'..'9']) do Inc(I);
  end;
  Result := TryStrToFloat(Copy(T, 1, I - 1), V, TFormatSettings.Invariant);
end;

function AttrOrChild(Node: IXMLNode; const Name: string): string;
var
  Child: IXMLNode;
begin
  Result := '';
  if not Assigned(Node) then Exit;
  if Node.HasAttribute(LowerCase(Name)) then
    Exit(VarToStr(Node.Attributes[LowerCase(Name)]));
  Child := Node.ChildNodes.FindNode(Name);
  if Assigned(Child) then
    Result := Child.Text;
end;

procedure TRecipeData.Clear;
begin
  FTitle := '';
  FRecipeType := '';
  FAuthor := '';
  FNotes := '';
  FScript := '';
  FParams := nil;
  FSteps := nil;
end;

function TRecipeData.LoadFromFile(const AFileName: string): Boolean;
begin
  try
    Result := LoadFromText(TFile.ReadAllText(AFileName));
  except
    Clear;
    Result := False;
  end;
end;

function TRecipeData.LoadFromText(const XmlText: string): Boolean;
var
  Doc: IXMLDocument;
  Root, Desc, ParamsNode, Grp, Prm, N: IXMLNode;
  G, I: Integer;
  GroupName: string;
  Rec: TRecipeParam;
begin
  Clear;
  Result := False;
  if Trim(XmlText) = '' then Exit;
  try
    Doc := LoadXMLData(XmlText);
  except
    Exit;
  end;
  Root := Doc.DocumentElement;
  if not Assigned(Root) or not SameText(Root.NodeName, 'Recipe') then Exit;

  Desc := Root.ChildNodes.FindNode('Description');
  if Assigned(Desc) then
  begin
    FTitle := AttrOrChild(Desc, 'Title');
    FAuthor := AttrOrChild(Desc, 'Author');
    FNotes := AttrOrChild(Desc, 'Notes');
    FRecipeType := AttrOrChild(Desc, 'Type');
  end;

  ParamsNode := Root.ChildNodes.FindNode('Parameters');
  if Assigned(ParamsNode) then
    for G := 0 to ParamsNode.ChildNodes.Count - 1 do
    begin
      Grp := ParamsNode.ChildNodes[G];
      if not SameText(Grp.NodeName, 'Group') then Continue;
      GroupName := VarToStr(Grp.Attributes['name']);
      for I := 0 to Grp.ChildNodes.Count - 1 do
      begin
        Prm := Grp.ChildNodes[I];
        if not SameText(Prm.NodeName, 'Param') then Continue;
        Rec.Group := GroupName;
        Rec.Name := VarToStr(Prm.Attributes['name']);
        Rec.Caption := VarToStr(Prm.Attributes['caption']);
        Rec.Units := VarToStr(Prm.Attributes['unit']);
        Rec.ParamType := VarToStr(Prm.Attributes['type']);
        Rec.Text := Trim(Prm.Text);
        FParams := FParams + [Rec];
      end;
    end;

  N := Root.ChildNodes.FindNode('Script');
  if Assigned(N) then
    FScript := N.Text;
  ParseScript;
  Result := True;
end;

procedure TRecipeData.ParseScript;
var
  Lines: TStringList;
  L: Integer;
  Line, Stmt: string;
  Step: TRecipeStep;
  Parts: TArray<string>;
  Words: TList<string>;
  W: string;
begin
  Lines := TStringList.Create;
  Words := TList<string>.Create;
  try
    Lines.Text := FScript;
    for L := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[L]);
      if (Line = '') or Line.StartsWith('#') or Line.StartsWith('//') then
        Continue;
      for Stmt in Line.Split([';']) do
      begin
        Parts := Trim(Stmt).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
        if Length(Parts) = 0 then Continue;
        Words.Clear;
        for W in Parts do
          Words.Add(W);
        Step.Line := L + 1;
        Step.Verb := LowerCase(Words[0]);
        Words.Delete(0);
        Step.Args := Words.ToArray;
        FSteps := FSteps + [Step];
      end;
    end;
  finally
    Words.Free;
    Lines.Free;
  end;
end;

function TRecipeData.CountVerb(const Verb: string): Integer;
var
  S: TRecipeStep;
begin
  Result := 0;
  for S in FSteps do
    if SameText(S.Verb, Verb) then
      Inc(Result);
end;

function TRecipeData.BuildKeyValues: TArray<TPluginKeyValue>;
var
  KV: TPluginKeyValue;
  P: TRecipeParam;
  V: Double;
begin
  Result := nil;
  for P in FParams do
    if TryParseRecipeNumber(P.Text, V) then
    begin
      KV.Name := P.Group + '.' + P.Name;
      KV.Value := V;
      KV.Units := P.Units;
      if P.Caption <> '' then
        KV.Description := P.Caption + ' (' + P.Group + ')'
      else
        KV.Description := P.Name + ' (' + P.Group + ')';
      KV.RecType := prCondition;
      KV.IsKey := True;
      Result := Result + [KV];
    end;
end;

function TRecipeData.BuildDetailedJson: TJSONObject;
const
  SETPOINT_VERBS: array[0..6] of string =
    ('loop', 'bias', 'set', 'mfc', 'pwait', 'deposit', 'power');
var
  JParams, JSteps, JArgs: TJSONArray;
  JParam, JStep, JCounts: TJSONObject;
  P: TRecipeParam;
  S: TRecipeStep;
  A, Verb: string;
  V: Double;
begin
  Result := TJSONObject.Create;
  Result.AddPair('title', FTitle);
  Result.AddPair('type', FRecipeType);
  Result.AddPair('author', FAuthor);
  Result.AddPair('notes', FNotes);

  JParams := TJSONArray.Create;
  for P in FParams do
  begin
    JParam := TJSONObject.Create;
    JParam.AddPair('group', P.Group);
    JParam.AddPair('name', P.Name);
    JParam.AddPair('caption', P.Caption);
    JParam.AddPair('unit', P.Units);
    JParam.AddPair('text', P.Text);
    if TryParseRecipeNumber(P.Text, V) then
      JParam.AddPair('value', JNum(V));
    JParams.AddElement(JParam);
  end;
  Result.AddPair('parameters', JParams);

  JCounts := TJSONObject.Create;
  for Verb in SETPOINT_VERBS do
    JCounts.AddPair(Verb, TJSONNumber.Create(CountVerb(Verb)));
  Result.AddPair('stepCounts', JCounts);
  Result.AddPair('stepTotal', TJSONNumber.Create(Length(FSteps)));

  JSteps := TJSONArray.Create;
  for S in FSteps do
  begin
    if not MatchText(S.Verb, SETPOINT_VERBS) then Continue;
    JStep := TJSONObject.Create;
    JStep.AddPair('line', TJSONNumber.Create(S.Line));
    JStep.AddPair('verb', S.Verb);
    JArgs := TJSONArray.Create;
    for A in S.Args do
      JArgs.Add(A);
    JStep.AddPair('args', JArgs);
    JSteps.AddElement(JStep);
  end;
  Result.AddPair('setpoints', JSteps);
  Result.AddPair('script', FScript);
end;

end.
