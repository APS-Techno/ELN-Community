unit unit_ReaderValueMappingModel;

interface

uses
  System.SysUtils, System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_ValueType, unit_ReaderValueMapping, unit_ReaderValueStatistics;

type
  TReaderValueResolution = record
    ValueType: TValueType;
    Factor: Double;
    LabelText: string;
    Reason: string;
    Statistics: TReaderValueStatistics;
    function Description(const Original: string): string;
  end;

  TReaderValueMappingModel = class
  private
    FManager: TObjectManager;
    FRows: TList<TReaderValueMapping>;
    FTypes: TList<TValueType>;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;
    function Resolve(const ReaderId, KeyName, ReaderUnits: string): TReaderValueResolution;
    procedure Validate(Row: TReaderValueMapping);
    procedure Remember(const ReaderId, KeyName, ReaderUnits: string;
      ValueType: TValueType; Factor: Double);
    class procedure CreateDefaultData(Manager: TObjectManager); static;
  end;

implementation

uses
  System.Math,
  unit_ValueSourceSeed;

function TReaderValueResolution.Description(const Original: string): string;
begin
  Result := Original;
  if LabelText <> '' then
    if Result = '' then
      Result := LabelText
    else
      Result := LabelText + ': ' + Result;
end;

constructor TReaderValueMappingModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FRows := Manager.Find<TReaderValueMapping>.List;
  FTypes := Manager.Find<TValueType>.List;
end;

destructor TReaderValueMappingModel.Destroy;
begin
  FRows.Free;
  FTypes.Free;
  inherited;
end;

const
  MaterialToken = '<Material>';
  AnyToken = '<Any>';

function IsToken(const Part: string): Boolean;
begin
  Result := (Part = MaterialToken) or (Part = AnyToken);
end;

function IsKeyPattern(const Pattern: string): Boolean;
begin
  Result := Pattern.Contains(MaterialToken) or Pattern.Contains(AnyToken);
end;

function PatternParts(const Pattern: string): TArray<string>;
var
  I: Integer;
  Literal, Token: string;
begin
  Result := nil;
  Literal := '';
  I := 1;
  while I <= Length(Pattern) do
  begin
    Token := '';
    if Copy(Pattern, I, Length(MaterialToken)) = MaterialToken then
      Token := MaterialToken
    else if Copy(Pattern, I, Length(AnyToken)) = AnyToken then
      Token := AnyToken;
    if Token = '' then
    begin
      Literal := Literal + Pattern[I];
      Inc(I);
      Continue;
    end;
    if Literal <> '' then
      Result := Result + [Literal];
    Literal := '';
    Result := Result + [Token];
    Inc(I, Length(Token));
  end;
  if Literal <> '' then
    Result := Result + [Literal];
end;

function LiteralLength(const Parts: TArray<string>): Integer;
var
  Part: string;
begin
  Result := 0;
  for Part in Parts do
    if not IsToken(Part) then
      Inc(Result, Length(Part));
end;

function MatchParts(const Parts: TArray<string>; Index: Integer;
  const Key: string; Position: Integer; var Material: string): Boolean;
var
  Part: string;
  Len: Integer;
begin
  if Index = Length(Parts) then
    Exit(Position = Length(Key) + 1);
  Part := Parts[Index];
  if not IsToken(Part) then
    Exit((Copy(Key, Position, Length(Part)) = Part) and
      MatchParts(Parts, Index + 1, Key, Position + Length(Part), Material));
  if (Part = MaterialToken) and (Material <> '') then
    Exit((Copy(Key, Position, Length(Material)) = Material) and
      MatchParts(Parts, Index + 1, Key, Position + Length(Material), Material));
  for Len := 1 to Length(Key) - Position + 1 do
  begin
    if Part = MaterialToken then
    begin
      Material := Copy(Key, Position, Len);
      if Trim(Material) = '' then
        Continue;
    end;
    if MatchParts(Parts, Index + 1, Key, Position + Len, Material) then
      Exit(True);
  end;
  if Part = MaterialToken then
    Material := '';
  Result := False;
end;

function LocationFreeKey(const Key: string): string;
var
  Location, StackText, LayerText: string;
  Start, LayerStart, Number: Integer;
begin
  Result := Key;
  Start := Key.LastIndexOf(' (stack ') + 1;
  if (Start = 0) or not Key.EndsWith(')') then
    Exit;
  Location := Copy(Key, Start + 8, Length(Key) - Start - 8);
  LayerStart := Pos(' layer ', Location);
  if LayerStart = 0 then
    StackText := Location
  else
  begin
    StackText := Copy(Location, 1, LayerStart - 1);
    LayerText := Copy(Location, LayerStart + 7, MaxInt);
    if not TryStrToInt(LayerText, Number) or (Number <= 0) or
      (IntToStr(Number) <> LayerText) then Exit;
  end;
  if not TryStrToInt(StackText, Number) or (Number <= 0) or
    (IntToStr(Number) <> StackText) then Exit;
  Result := Copy(Key, 1, Start - 1);
end;

function MatchKeyPattern(const Pattern, Key: string; out Material: string): Boolean;
begin
  Material := '';
  Result := MatchParts(PatternParts(Pattern), 0, LocationFreeKey(Key), 1, Material);
end;

function TReaderValueMappingModel.Resolve(const ReaderId, KeyName,
  ReaderUnits: string): TReaderValueResolution;
var
  Row, Best: TReaderValueMapping;
  Material, BestLabel: string;
  Specificity, BestSpecificity: Integer;
  VT: TValueType;
begin
  Result := Default(TReaderValueResolution);
  Result.Factor := 1;
  Best := nil;
  BestLabel := '';
  BestSpecificity := -1;
  for Row in FRows do
  begin
    if (Row.ReaderId <> ReaderId) or IsKeyPattern(Row.KeyPattern) or
      (Row.KeyPattern <> KeyName) then
      Continue;
    if Row.ReaderUnits = ReaderUnits then
    begin
      Best := Row;
      BestLabel := Row.LabelText;
      Break;
    end;
    Result.Reason := 'Reader unit does not match mapping: expected "' +
      Row.ReaderUnits + '", received "' + ReaderUnits + '"';
  end;
  if Best = nil then
    for Row in FRows do
    begin
      if (Row.ReaderId <> ReaderId) or not IsKeyPattern(Row.KeyPattern) or
        not MatchKeyPattern(Row.KeyPattern, KeyName, Material) then
        Continue;
      if Row.ReaderUnits <> ReaderUnits then
      begin
        if Best = nil then
          Result.Reason := 'Reader unit does not match mapping: expected "' +
            Row.ReaderUnits + '", received "' + ReaderUnits + '"';
        Continue;
      end;
      Specificity := LiteralLength(PatternParts(Row.KeyPattern));
      if Specificity <= BestSpecificity then
        Continue;
      Best := Row;
      BestSpecificity := Specificity;
      if Material <> '' then
        BestLabel := Material
      else
        BestLabel := Row.LabelText;
    end;
  if Best <> nil then
  begin
    Result.ValueType := Best.ValueType;
    Result.Factor := Best.Factor;
    Result.LabelText := BestLabel;
    Result.Reason := '';
    Exit;
  end;
  for VT in FTypes do
    if SameText(VT.Title, KeyName) and SameText(VT.Units, ReaderUnits) then
    begin
      Result.ValueType := VT;
      Result.Reason := '';
      Exit;
    end;
  if Result.Reason = '' then
    Result.Reason := 'No mapping or matching value type';
end;

procedure TReaderValueMappingModel.Validate(Row: TReaderValueMapping);
var
  Other: TReaderValueMapping;
begin
  if (Trim(Row.ReaderId) = '') or (Trim(Row.KeyPattern) = '') or
    (Length(Row.ReaderId) > 100) or (Length(Row.KeyPattern) > 255) or
    (Length(Row.ReaderUnits) > 100) or (Length(Row.LabelText) > 255) then
    raise EArgumentException.Create('Reader ID and key are required; mapping text exceeds its limit');
  if (Row.ValueType = nil) or IsNan(Row.Factor) or IsInfinite(Row.Factor) or
    (Row.Factor = 0) then
    raise EArgumentException.Create('A target value type and finite nonzero factor are required');
  if Row.KeyPattern.Contains('<') then
  begin
    for var Part in PatternParts(Row.KeyPattern) do
      if not IsToken(Part) and Part.Contains('<') then
        raise EArgumentException.Create('Only the <Material> and <Any> placeholders are supported');
    if LiteralLength(PatternParts(Row.KeyPattern)) = 0 then
      raise EArgumentException.Create('A key pattern needs fixed text besides its placeholders');
  end;
  for Other in FRows do
    if (Other <> Row) and ((Row.Id = 0) or (Other.Id <> Row.Id)) and
      (Other.ReaderId = Row.ReaderId) and
      (Other.KeyPattern = Row.KeyPattern) and (Other.ReaderUnits = Row.ReaderUnits) then
      raise EArgumentException.Create('This reader, key, and unit mapping already exists');
end;

procedure TReaderValueMappingModel.Remember(const ReaderId, KeyName,
  ReaderUnits: string; ValueType: TValueType; Factor: Double);
var
  Candidate, Existing, Row: TReaderValueMapping;
begin
  Existing := nil;
  for Row in FRows do
    if (Row.ReaderId = ReaderId) and (Row.KeyPattern = KeyName) and
      (Row.ReaderUnits = ReaderUnits) then
      Existing := Row;
  Candidate := TReaderValueMapping.Create;
  try
    if Existing <> nil then
      Candidate.Id := Existing.Id;
    Candidate.ReaderId := ReaderId;
    Candidate.KeyPattern := KeyName;
    Candidate.ReaderUnits := ReaderUnits;
    Candidate.ValueType := ValueType;
    Candidate.Factor := Factor;
    Validate(Candidate);
  finally
    Candidate.Free;
  end;
  if Existing = nil then
  begin
    Row := TReaderValueMapping.Create;
    Row.ReaderId := ReaderId;
    Row.KeyPattern := KeyName;
    Row.ReaderUnits := ReaderUnits;
    Row.ValueType := ValueType;
    Row.Factor := Factor;
    FManager.Save(Row);
    FRows.Add(Row);
  end
  else
  begin
    Existing.ValueType := ValueType;
    Existing.Factor := Factor;
  end;
  FManager.Flush;
end;

class procedure TReaderValueMappingModel.CreateDefaultData(Manager: TObjectManager);
begin
  TValueSourceSeed.SeedDefaults(Manager);
end;

end.
