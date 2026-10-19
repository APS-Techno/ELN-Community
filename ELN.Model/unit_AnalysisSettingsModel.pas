unit unit_AnalysisSettingsModel;

interface

uses
  System.SysUtils,
  Aurelius.Engine.ObjectManager,
  unit_User,
  unit_Item,
  unit_ProjectAccessPolicy;

type
  TAnalysisApplyStatus = (aasApplied, aasConflict, aasDenied, aasSigned,
    aasHashMismatch, aasInvalid, aasTooLarge);

  TAnalysisSettingsModel = class
  private
    FManager: TObjectManager;
    function ExecuteCommand(const ASQL: string;
      const ANames, AValues: array of string): Integer;
    function ReadRow(const AKey: string; out AValue: string): Boolean;
    function InsertRow(const AKey, AValue: string; out ACurrent: string): Boolean;
    function SwapRow(const AKey, AExpected, ANew: string;
      out ACurrent: string): Boolean;
  public
    const
      MaxKeyLength = 100;
      MaxJsonLength = 2000;

    constructor Create(Manager: TObjectManager);

    class function FileKey(const ReaderId: string; FileId: Int64): string; static;
    class function ValueKey(const ReaderId: string; ValueId: Integer): string; static;
    class function ContentHash(const FileName: string): string; static;
    class function CompleteSnapshot(const Json, ReaderId, KeyName: string;
      FileId: Int64; ValueId: Integer): string; static;

    function LoadSelection(const ReaderId: string; FileId: Int64;
      out Json: string): Boolean;
    procedure CurrentSelection(const ReaderId: string; FileId: Int64;
      const FilePath: string; out Hash, Json: string);
    function ApplySelection(Access: IProjectAccessPolicy; User: TUser;
      const ReaderId: string; FileId: Int64;
      const ExpectedJson, NewJson, CurrentHash: string;
      out CurrentJson: string): TAnalysisApplyStatus;
    function LoadSnapshot(Value: TValue; out Json: string): Boolean;
    procedure SaveSnapshot(const ReaderId: string; ValueId: Integer;
      const Json: string);
    procedure DeleteForValue(const ReaderId: string; ValueId: Integer);
    procedure DeleteForFile(FileId: Int64);
    procedure DeleteForItemRows(ItemId: Integer);
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Hash,
  System.JSON,
  System.Variants,
  Data.DB,
  Aurelius.Drivers.Interfaces,
  unit_SignatureModel;

const
  KeyPrefix = 'analysis:';

function ParseObject(const AJson: string): TJSONObject;
var
  Parsed: TJSONValue;
begin
  Result := nil;
  Parsed := TJSONObject.ParseJSONValue(AJson);
  if Parsed is TJSONObject then
    Result := TJSONObject(Parsed)
  else
    Parsed.Free;
end;

function TextField(AObject: TJSONObject; const AName: string;
  out AText: string): Boolean;
var
  Field: TJSONValue;
begin
  Field := AObject.Values[AName];
  Result := (Field is TJSONString) and not (Field is TJSONNumber);
  if Result then
    AText := Field.Value;
end;

function IntegerField(AObject: TJSONObject; const AName: string;
  out ANumber: Int64): Boolean;
var
  Field: TJSONValue;
begin
  Field := AObject.Values[AName];
  Result := (Field is TJSONNumber) and TryStrToInt64(Field.Value, ANumber);
end;

constructor TAnalysisSettingsModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
end;

class function TAnalysisSettingsModel.FileKey(const ReaderId: string;
  FileId: Int64): string;
begin
  Result := KeyPrefix + ReaderId + ':file:' + IntToStr(FileId);
end;

class function TAnalysisSettingsModel.ValueKey(const ReaderId: string;
  ValueId: Integer): string;
begin
  Result := KeyPrefix + ReaderId + ':value:' + IntToStr(ValueId);
end;

class function TAnalysisSettingsModel.ContentHash(const FileName: string): string;
begin
  Result := UpperCase(THashMD5.GetHashStringFromFile(FileName));
end;

class function TAnalysisSettingsModel.CompleteSnapshot(const Json, ReaderId,
  KeyName: string; FileId: Int64; ValueId: Integer): string;
var
  Snapshot: TJSONObject;
  Text: string;
  Number: Int64;
begin
  if Length(Json) > MaxJsonLength then
    raise EArgumentException.Create('The analysis snapshot is too large');
  Snapshot := ParseObject(Json);
  if Snapshot = nil then
    raise EArgumentException.Create('The analysis snapshot is not a JSON object');
  try
    if Snapshot.Values['reader_id'] <> nil then
      if not TextField(Snapshot, 'reader_id', Text) or (Text <> ReaderId) then
        raise EArgumentException.Create('The analysis snapshot names another reader');
    if Snapshot.Values['key_name'] <> nil then
      if not TextField(Snapshot, 'key_name', Text) or (Text <> KeyName) then
        raise EArgumentException.Create('The analysis snapshot names another key');
    if Snapshot.Values['file_id'] <> nil then
      if not IntegerField(Snapshot, 'file_id', Number) or (Number <> FileId) then
        raise EArgumentException.Create('The analysis snapshot names another file');
    Snapshot.RemovePair('reader_id').Free;
    Snapshot.RemovePair('key_name').Free;
    Snapshot.RemovePair('file_id').Free;
    Snapshot.RemovePair('value_id').Free;
    Snapshot.AddPair('value_id', TJSONNumber.Create(ValueId));
    Snapshot.AddPair('file_id', TJSONNumber.Create(FileId));
    Snapshot.AddPair('reader_id', ReaderId);
    Snapshot.AddPair('key_name', KeyName);
    Result := Snapshot.ToJSON;
  finally
    Snapshot.Free;
  end;
  if Length(Result) > MaxJsonLength then
    raise EArgumentException.Create('The analysis snapshot is too large');
end;

function TAnalysisSettingsModel.ExecuteCommand(const ASQL: string;
  const ANames, AValues: array of string): Integer;
var
  Statement: IDBStatement;
  Params: TObjectList<TDBParam>;
  I: Integer;
begin
  Params := TObjectList<TDBParam>.Create(True);
  try
    for I := 0 to High(ANames) do
      Params.Add(TDBParam.Create(ANames[I], ftString, AValues[I]));
    Statement := FManager.Connection.CreateStatement;
    Statement.SetSQLCommand(ASQL);
    Statement.SetParams(Params);
    Result := Statement.Execute;
  finally
    Params.Free;
  end;
end;

function TAnalysisSettingsModel.ReadRow(const AKey: string;
  out AValue: string): Boolean;
var
  Statement: IDBStatement;
  Rows: IDBResultSet;
  Params: TObjectList<TDBParam>;
begin
  AValue := '';
  Params := TObjectList<TDBParam>.Create(True);
  try
    Params.Add(TDBParam.Create('key', ftString, AKey));
    Statement := FManager.Connection.CreateStatement;
    Statement.SetSQLCommand(
      'SELECT SettingValue FROM DBSettings WHERE SettingKey = :key');
    Statement.SetParams(Params);
    Rows := Statement.ExecuteQuery;
    Result := Rows.Next;
    if Result then
      AValue := VarToStr(Rows.GetFieldValue(0));
  finally
    Params.Free;
  end;
end;

function TAnalysisSettingsModel.InsertRow(const AKey, AValue: string;
  out ACurrent: string): Boolean;
begin
  ACurrent := '';
  try
    ExecuteCommand(
      'INSERT INTO DBSettings (SettingKey, SettingValue) VALUES (:key, :val)',
      ['key', 'val'], [AKey, AValue]);
    ACurrent := AValue;
    Result := True;
  except
    on Exception do
    begin
      if not ReadRow(AKey, ACurrent) then
        raise;
      Result := False;
    end;
  end;
end;

function TAnalysisSettingsModel.SwapRow(const AKey, AExpected, ANew: string;
  out ACurrent: string): Boolean;
begin
  ExecuteCommand('UPDATE DBSettings SET SettingValue = :new ' +
    'WHERE SettingKey = :key AND SettingValue = :expected',
    ['new', 'key', 'expected'], [ANew, AKey, AExpected]);
  Result := ReadRow(AKey, ACurrent) and (ACurrent = ANew);
end;

function TAnalysisSettingsModel.LoadSelection(const ReaderId: string;
  FileId: Int64; out Json: string): Boolean;
begin
  Result := ReadRow(FileKey(ReaderId, FileId), Json);
end;

procedure TAnalysisSettingsModel.CurrentSelection(const ReaderId: string;
  FileId: Int64; const FilePath: string; out Hash, Json: string);
begin
  Hash := ContentHash(FilePath);
  if not LoadSelection(ReaderId, FileId, Json) then
    Json := '';
end;

function TAnalysisSettingsModel.ApplySelection(Access: IProjectAccessPolicy;
  User: TUser; const ReaderId: string; FileId: Int64;
  const ExpectedJson, NewJson, CurrentHash: string;
  out CurrentJson: string): TAnalysisApplyStatus;
var
  FileEntity: unit_Item.TFile;
  Selection: TJSONObject;
  Key, SelectionHash: string;
  Trans: IDBTransaction;
  Swapped: Boolean;
begin
  CurrentJson := '';
  FileEntity := FManager.Find<unit_Item.TFile>(FileId);
  if (FileEntity = nil) or (FileEntity.Item = nil) then
    Exit(aasInvalid);
  if (Access = nil) or
    not Access.CanWrite(FManager, User, FileEntity.Item.ProjectID) then
    Exit(aasDenied);
  if IsItemSignedCheck(FManager, FileEntity.Item.Id) then
    Exit(aasSigned);
  if Length(NewJson) > MaxJsonLength then
    Exit(aasTooLarge);
  Key := FileKey(ReaderId, FileId);
  if (ReaderId = '') or (Length(Key) > MaxKeyLength) then
    Exit(aasInvalid);
  Selection := ParseObject(NewJson);
  if Selection = nil then
    Exit(aasInvalid);
  try
    if not TextField(Selection, 'file_hash', SelectionHash) then
      Exit(aasInvalid);
  finally
    Selection.Free;
  end;
  if (CurrentHash = '') or not SameText(SelectionHash, CurrentHash) then
    Exit(aasHashMismatch);

  Trans := FManager.Connection.BeginTransaction;
  try
    if ExpectedJson = '' then
      Swapped := InsertRow(Key, NewJson, CurrentJson)
    else
      Swapped := SwapRow(Key, ExpectedJson, NewJson, CurrentJson);
    if Swapped then
      Trans.Commit
    else
      Trans.Rollback;
  except
    try
      Trans.Rollback;
    except
    end;
    raise;
  end;
  if Swapped then
    Result := aasApplied
  else
    Result := aasConflict;
end;

function TAnalysisSettingsModel.LoadSnapshot(Value: TValue;
  out Json: string): Boolean;
var
  Stored, Text: string;
  Snapshot: TJSONObject;
  Number: Int64;
begin
  Json := '';
  Result := False;
  if (Value = nil) or (Value.Id <= 0) or (Value.ReaderId = '') then
    Exit;
  if not ReadRow(ValueKey(Value.ReaderId, Value.Id), Stored) then
    Exit;
  Snapshot := ParseObject(Stored);
  if Snapshot = nil then
    Exit;
  try
    Result :=
      IntegerField(Snapshot, 'value_id', Number) and (Number = Value.Id) and
      TextField(Snapshot, 'reader_id', Text) and (Text = Value.ReaderId) and
      TextField(Snapshot, 'key_name', Text) and (Text = Value.KeyName);
    if Result and Value.SourceFileId.HasValue then
      Result := IntegerField(Snapshot, 'file_id', Number) and
        (Number = Value.SourceFileId.Value);
  finally
    Snapshot.Free;
  end;
  if Result then
    Json := Stored;
end;

procedure TAnalysisSettingsModel.SaveSnapshot(const ReaderId: string;
  ValueId: Integer; const Json: string);
var
  Key: string;
begin
  Key := ValueKey(ReaderId, ValueId);
  if Length(Key) > MaxKeyLength then
    raise EArgumentException.Create('The analysis snapshot key is too long');
  ExecuteCommand('DELETE FROM DBSettings WHERE SettingKey = :key',
    ['key'], [Key]);
  ExecuteCommand(
    'INSERT INTO DBSettings (SettingKey, SettingValue) VALUES (:key, :val)',
    ['key', 'val'], [Key, Json]);
end;

procedure TAnalysisSettingsModel.DeleteForValue(const ReaderId: string;
  ValueId: Integer);
begin
  if ReaderId = '' then
    Exit;
  ExecuteCommand('DELETE FROM DBSettings WHERE SettingKey = :key',
    ['key'], [ValueKey(ReaderId, ValueId)]);
end;

procedure TAnalysisSettingsModel.DeleteForFile(FileId: Int64);
begin
  ExecuteCommand('DELETE FROM DBSettings WHERE SettingKey LIKE :pattern',
    ['pattern'], [KeyPrefix + '%:file:' + IntToStr(FileId)]);
end;

procedure TAnalysisSettingsModel.DeleteForItemRows(ItemId: Integer);
var
  Statement: IDBStatement;
  Rows: IDBResultSet;
  ValueIds: TList<Integer>;
  ValueReaders: TList<string>;
  FileIds: TList<Int64>;
  I: Integer;
begin
  ValueIds := TList<Integer>.Create;
  ValueReaders := TList<string>.Create;
  FileIds := TList<Int64>.Create;
  try
    Statement := FManager.Connection.CreateStatement;
    Statement.SetSQLCommand('SELECT Id, ReaderId FROM DataValues WHERE ItemID = ' +
      IntToStr(ItemId));
    Rows := Statement.ExecuteQuery;
    while Rows.Next do
    begin
      ValueIds.Add(StrToInt(VarToStr(Rows.GetFieldValue(0))));
      ValueReaders.Add(VarToStr(Rows.GetFieldValue(1)));
    end;
    Rows := nil;
    Statement := FManager.Connection.CreateStatement;
    Statement.SetSQLCommand('SELECT Id FROM Files WHERE ItemID = ' +
      IntToStr(ItemId));
    Rows := Statement.ExecuteQuery;
    while Rows.Next do
      FileIds.Add(StrToInt64(VarToStr(Rows.GetFieldValue(0))));
    Rows := nil;
    for I := 0 to ValueIds.Count - 1 do
      DeleteForValue(ValueReaders[I], ValueIds[I]);
    for I := 0 to FileIds.Count - 1 do
      DeleteForFile(FileIds[I]);
  finally
    FileIds.Free;
    ValueReaders.Free;
    ValueIds.Free;
  end;
end;

end.
