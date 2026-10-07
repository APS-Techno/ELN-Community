unit unit_ServiceImport;

interface

uses
  SysUtils, Classes, Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_EquipmentType, unit_Equipment, unit_ActionType, unit_FileType, unit_ItemTypes;

const
  CSV_FILENAMES: array[0..6] of string = (
    'EquipmentTypes.csv',
    'ValueTypes.csv',
    'FileTypes.csv',
    'Equipment.csv',
    'ActionTypes.csv',
    'FileTypeLinks.csv',
    'ActionTypeEquipment.csv'
  );

  CSV_ENTITY_NAMES: array[0..6] of string = (
    'Equipment Types',
    'Value Types',
    'File Types',
    'Equipment',
    'Action Types',
    'File Type Links',
    'Action Type Equipment'
  );

type
  TImportFileInfo = record
    FileName: string;
    RowCount: Integer;
    Found: Boolean;
  end;

  TImportManifest = record
    FolderPath: string;
    Files: array[0..6] of TImportFileInfo;
    function TotalFiles: Integer;
    function TotalRows: Integer;
  end;

  TEntityImportResult = record
    EntityName: string;
    Inserted: Integer;
    Updated: Integer;
    Errors: Integer;
    ErrorMessages: TStringList;
  end;

  TImportResult = record
    Success: Boolean;
    Results: array[0..6] of TEntityImportResult;
    procedure Init;
  end;

  TImportLogEvent = procedure(const Msg: string) of object;

  TServiceImporter = class
  private
    FManager: TObjectManager;
    FPrincipalId: Integer;
    FOnLog: TImportLogEvent;
    function DetectDelimiter(const Line: string): Char;
    function SplitCSVLine(const Line: string; Delimiter: Char): TArray<string>;
    function ParseCSVFile(const FilePath: string): TList<TArray<string>>;
    procedure Log(const Msg: string);
    procedure ImportEquipmentTypes(const FolderPath: string; var R: TEntityImportResult);
    procedure ImportValueTypes(const FolderPath: string; var R: TEntityImportResult);
    procedure ImportFileTypes(const FolderPath: string; var R: TEntityImportResult);
    procedure ImportEquipment(const FolderPath: string; var R: TEntityImportResult);
    procedure ImportActionTypes(const FolderPath: string; var R: TEntityImportResult);
    procedure ImportFileTypeLinks(const FolderPath: string; var R: TEntityImportResult);
    procedure ImportActionTypeEquipment(const FolderPath: string; var R: TEntityImportResult);
    function FindEquipmentTypeByName(const Name: string): TEquipmentType;
    function FindEquipmentByModel(const ModelName: string): TEquipment;
    function FindActionTypeByTitle(const Title: string): TActionType;
    function FindFileTypeByExt(const Ext: string): TFileType;
    function ParseActionKind(const S: string): TActionKind;
    function ParseItemType(const S: string): TItemType;
  public
    constructor Create(AManager: TObjectManager; APrincipalId: Integer);
    function ScanFolder(const FolderPath: string): TImportManifest;
    function ImportAll(const FolderPath: string): TImportResult;
    property OnLog: TImportLogEvent read FOnLog write FOnLog;
  end;

implementation

uses
  unit_ValueType, unit_FileTypeLink, unit_ELNDB_Dictionary,
  unit_TimeHelper;

{ TImportManifest }

function TImportManifest.TotalFiles: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := Low(Files) to High(Files) do
    if Files[I].Found then
      Inc(Result);
end;

function TImportManifest.TotalRows: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := Low(Files) to High(Files) do
    if Files[I].Found then
      Inc(Result, Files[I].RowCount);
end;

{ TImportResult }

procedure TImportResult.Init;
var
  I: Integer;
begin
  Success := False;
  for I := Low(Results) to High(Results) do
  begin
    Results[I].EntityName := CSV_ENTITY_NAMES[I];
    Results[I].Inserted := 0;
    Results[I].Updated := 0;
    Results[I].Errors := 0;
    Results[I].ErrorMessages := TStringList.Create;
  end;
end;

{ TServiceImporter }

constructor TServiceImporter.Create(AManager: TObjectManager; APrincipalId: Integer);
begin
  inherited Create;
  if (AManager <> nil) and (APrincipalId <= 0) then
    raise EArgumentException.Create('An import author is required');
  FPrincipalId := APrincipalId;
  FManager := AManager;
  FOnLog := nil;
end;

procedure TServiceImporter.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Msg);
end;

function TServiceImporter.DetectDelimiter(const Line: string): Char;
begin
  if Pos(';', Line) > 0 then
    Result := ';'
  else
    Result := ',';
end;

function TServiceImporter.SplitCSVLine(const Line: string; Delimiter: Char): TArray<string>;
var
  Parts: TStringList;
  I: Integer;
begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := Delimiter;
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Line;
    SetLength(Result, Parts.Count);
    for I := 0 to Parts.Count - 1 do
      Result[I] := Trim(Parts[I]);
  finally
    Parts.Free;
  end;
end;

function TServiceImporter.ParseCSVFile(const FilePath: string): TList<TArray<string>>;
var
  Lines: TStringList;
  Delimiter: Char;
  Fields: TArray<string>;
  StartLine, I: Integer;
  FirstField: string;
begin
  Result := TList<TArray<string>>.Create;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FilePath, TEncoding.UTF8);
    if Lines.Count = 0 then
      Exit;

    Delimiter := DetectDelimiter(Lines[0]);

    // Detect header row: skip if first field is non-numeric
    StartLine := 0;
    if Lines.Count > 1 then
    begin
      Fields := SplitCSVLine(Lines[0], Delimiter);
      if Length(Fields) > 0 then
      begin
        FirstField := Fields[0];
        if (FirstField <> '') and not CharInSet(FirstField[1], ['0'..'9']) then
          StartLine := 1;
      end;
    end;

    for I := StartLine to Lines.Count - 1 do
    begin
      if Trim(Lines[I]) = '' then
        Continue;
      Fields := SplitCSVLine(Lines[I], Delimiter);
      Result.Add(Fields);
    end;
  finally
    Lines.Free;
  end;
end;

function TServiceImporter.ScanFolder(const FolderPath: string): TImportManifest;
var
  I: Integer;
  FilePath: string;
  Lines: TStringList;
  Delimiter: Char;
  Fields: TArray<string>;
  FirstField: string;
  DataRows, StartLine, J: Integer;
begin
  Result.FolderPath := FolderPath;
  for I := Low(CSV_FILENAMES) to High(CSV_FILENAMES) do
  begin
    Result.Files[I].FileName := CSV_FILENAMES[I];
    FilePath := IncludeTrailingPathDelimiter(FolderPath) + CSV_FILENAMES[I];
    Result.Files[I].Found := FileExists(FilePath);
    if Result.Files[I].Found then
    begin
      // Count data rows (exclude header and blank lines)
      Lines := TStringList.Create;
      try
        Lines.LoadFromFile(FilePath, TEncoding.UTF8);
        DataRows := 0;
        if Lines.Count > 0 then
        begin
          Delimiter := DetectDelimiter(Lines[0]);
          StartLine := 0;
          if Lines.Count > 1 then
          begin
            Fields := SplitCSVLine(Lines[0], Delimiter);
            if Length(Fields) > 0 then
            begin
              FirstField := Fields[0];
              if (FirstField <> '') and not CharInSet(FirstField[1], ['0'..'9']) then
                StartLine := 1;
            end;
          end;
          for J := StartLine to Lines.Count - 1 do
            if Trim(Lines[J]) <> '' then
              Inc(DataRows);
        end;
        Result.Files[I].RowCount := DataRows;
      finally
        Lines.Free;
      end;
      Log(Format('Found %s: %d rows', [CSV_FILENAMES[I], Result.Files[I].RowCount]));
    end
    else
    begin
      Result.Files[I].RowCount := 0;
      Log(Format('Not found: %s', [CSV_FILENAMES[I]]));
    end;
  end;
end;

function TServiceImporter.ImportAll(const FolderPath: string): TImportResult;
begin
  Result.Init;
  Log('Import started for folder: ' + FolderPath);

  Log('Importing Equipment Types...');
  ImportEquipmentTypes(FolderPath, Result.Results[0]);

  Log('Importing Value Types...');
  ImportValueTypes(FolderPath, Result.Results[1]);

  Log('Importing File Types...');
  ImportFileTypes(FolderPath, Result.Results[2]);

  Log('Importing Equipment...');
  ImportEquipment(FolderPath, Result.Results[3]);

  Log('Importing Action Types...');
  ImportActionTypes(FolderPath, Result.Results[4]);

  Log('Importing File Type Links...');
  ImportFileTypeLinks(FolderPath, Result.Results[5]);

  Log('Importing Action Type Equipment...');
  ImportActionTypeEquipment(FolderPath, Result.Results[6]);

  Result.Success := True;
  Log('Import completed.');
end;

procedure TServiceImporter.ImportEquipmentTypes(const FolderPath: string; var R: TEntityImportResult);
var
  Rows: TList<TArray<string>>;
  Row: TArray<string>;
  FilePath, TypeName: string;
  Existing: TList<TEquipmentType>;
  ET: TEquipmentType;
  Found: Boolean;
begin
  FilePath := IncludeTrailingPathDelimiter(FolderPath) + CSV_FILENAMES[0];
  if not FileExists(FilePath) then Exit;

  Rows := ParseCSVFile(FilePath);
  try
    for Row in Rows do
    begin
      if Length(Row) < 1 then Continue;
      TypeName := Row[0];
      if TypeName = '' then Continue;

      Found := False;
      Existing := FManager.Find<TEquipmentType>.List;
      for ET in Existing do
        if SameText(ET.Type_, TypeName) then
        begin
          if Length(Row) > 1 then ET.Description := Row[1];
          ET.ModifiedDate := UTCNow;
          FManager.Flush;
          Inc(R.Updated);
          Found := True;
          Log('  Updated: ' + TypeName);
          Break;
        end;

      if not Found then
      begin
        ET := TEquipmentType.Create;
        ET.Type_ := TypeName;
        if Length(Row) > 1 then ET.Description := Row[1];
        ET.CreatedDate := UTCNow;
        ET.CreatedBy := FPrincipalId;
        FManager.Save(ET);
        FManager.Flush;
        Inc(R.Inserted);
        Log('  Inserted: ' + TypeName);
      end;
    end;
  finally
    Rows.Free;
  end;
end;

procedure TServiceImporter.ImportValueTypes(const FolderPath: string; var R: TEntityImportResult);
var
  Rows: TList<TArray<string>>;
  Row: TArray<string>;
  FilePath, Symbol, Title: string;
  Existing: TList<TValueType>;
  VT: TValueType;
  Found: Boolean;
begin
  FilePath := IncludeTrailingPathDelimiter(FolderPath) + CSV_FILENAMES[1];
  if not FileExists(FilePath) then Exit;

  Rows := ParseCSVFile(FilePath);
  try
    for Row in Rows do
    begin
      if Length(Row) < 2 then Continue;
      Symbol := Row[0];
      Title := Row[1];
      if (Symbol = '') and (Title = '') then Continue;

      Found := False;
      Existing := FManager.Find<TValueType>.List;
      for VT in Existing do
        if SameText(VT.Symbol, Symbol) and SameText(VT.Title, Title) then
        begin
          if Length(Row) > 2 then VT.Units := Row[2];
          if Length(Row) > 3 then VT.CatID := StrToIntDef(Row[3], VT.CatID);
          VT.ModifiedDate := UTCNow;
          FManager.Flush;
          Inc(R.Updated);
          Found := True;
          Log('  Updated: ' + Symbol + ' (' + Title + ')');
          Break;
        end;

      if not Found then
      begin
        VT := TValueType.Create;
        VT.Symbol := Symbol;
        VT.Title := Title;
        if Length(Row) > 2 then VT.Units := Row[2] else VT.Units := '';
        if Length(Row) > 3 then VT.CatID := StrToIntDef(Row[3], 0);
        VT.CreatedDate := UTCNow;
        VT.CreatedBy := FPrincipalId;
        FManager.Save(VT);
        FManager.Flush;
        Inc(R.Inserted);
        Log('  Inserted: ' + Symbol + ' (' + Title + ')');
      end;
    end;
  finally
    Rows.Free;
  end;
end;

procedure TServiceImporter.ImportFileTypes(const FolderPath: string; var R: TEntityImportResult);
var
  Rows: TList<TArray<string>>;
  Row: TArray<string>;
  FilePath, Ext: string;
  Existing: TList<TFileType>;
  FT: TFileType;
  Found: Boolean;
begin
  FilePath := IncludeTrailingPathDelimiter(FolderPath) + CSV_FILENAMES[2];
  if not FileExists(FilePath) then Exit;

  Rows := ParseCSVFile(FilePath);
  try
    for Row in Rows do
    begin
      if Length(Row) < 1 then Continue;
      Ext := Row[0];
      if Ext = '' then Continue;

      Found := False;
      Existing := FManager.Find<TFileType>.List;
      for FT in Existing do
        if SameText(FT.Ext, Ext) then
        begin
          if Length(Row) > 1 then FT.Description := Row[1];
          FT.ModifiedDate := UTCNow;
          FManager.Flush;
          Inc(R.Updated);
          Found := True;
          Log('  Updated: ' + Ext);
          Break;
        end;

      if not Found then
      begin
        FT := TFileType.Create;
        FT.Ext := Ext;
        if Length(Row) > 1 then FT.Description := Row[1];
        FT.CreatedDate := UTCNow;
        FT.CreatedBy := FPrincipalId;
        FManager.Save(FT);
        FManager.Flush;
        Inc(R.Inserted);
        Log('  Inserted: ' + Ext);
      end;
    end;
  finally
    Rows.Free;
  end;
end;

{ FK Lookup Helpers }

function TServiceImporter.FindEquipmentTypeByName(const Name: string): TEquipmentType;
var
  List: TList<TEquipmentType>;
  ET: TEquipmentType;
begin
  Result := nil;
  List := FManager.Find<TEquipmentType>.List;
  for ET in List do
    if SameText(ET.Type_, Name) then
      Exit(ET);
end;

function TServiceImporter.FindEquipmentByModel(const ModelName: string): TEquipment;
var
  List: TList<TEquipment>;
  E: TEquipment;
begin
  Result := nil;
  List := FManager.Find<TEquipment>.List;
  for E in List do
    if SameText(E.Model, ModelName) then
      Exit(E);
end;

function TServiceImporter.FindActionTypeByTitle(const Title: string): TActionType;
var
  List: TList<TActionType>;
  AT: TActionType;
begin
  Result := nil;
  List := FManager.Find<TActionType>.List;
  for AT in List do
    if SameText(AT.Title, Title) then
      Exit(AT);
end;

function TServiceImporter.FindFileTypeByExt(const Ext: string): TFileType;
var
  List: TList<TFileType>;
  FT: TFileType;
begin
  Result := nil;
  List := FManager.Find<TFileType>.List;
  for FT in List do
    if SameText(FT.Ext, Ext) then
      Exit(FT);
end;

{ Enum Parsers }

const
  ActionKindNames: array[0..5] of string =
    ('Synthesys', 'Testing', 'Measurement', 'Analysis', 'Simulation', 'Other');
  ItemTypeNames: array[0..8] of string =
    ('Synthesis', 'Treatment', 'Measurement', 'Testing', 'Characterization',
     'Computing', 'Specimen', 'Model', 'Other');

function TServiceImporter.ParseActionKind(const S: string): TActionKind;
var
  I: Integer;
begin
  Result := TActionKind.Other;
  for I := Low(ActionKindNames) to High(ActionKindNames) do
    if SameText(ActionKindNames[I], S) then
      Exit(TActionKind(I));
end;

function TServiceImporter.ParseItemType(const S: string): TItemType;
var
  I: Integer;
begin
  Result := TItemType.Other;
  for I := Low(ItemTypeNames) to High(ItemTypeNames) do
    if SameText(ItemTypeNames[I], S) then
      Exit(TItemType(I));
end;

{ Import Dependent Entities }

procedure TServiceImporter.ImportEquipment(const FolderPath: string; var R: TEntityImportResult);
var
  Rows: TList<TArray<string>>;
  Row: TArray<string>;
  FilePath, ModelName: string;
  ET: TEquipmentType;
  E: TEquipment;
begin
  FilePath := IncludeTrailingPathDelimiter(FolderPath) + CSV_FILENAMES[3];
  if not FileExists(FilePath) then Exit;

  Rows := ParseCSVFile(FilePath);
  try
    for Row in Rows do
    begin
      if Length(Row) < 2 then Continue;
      ModelName := Row[1];
      if ModelName = '' then Continue;

      ET := nil;
      if Row[0] <> '' then
      begin
        ET := FindEquipmentTypeByName(Row[0]);
        if ET = nil then
        begin
          Inc(R.Errors);
          Log('  Error: EquipmentType "' + Row[0] + '" not found for "' + ModelName + '"');
          Continue;
        end;
      end;

      E := FindEquipmentByModel(ModelName);
      if Assigned(E) then
      begin
        E.EquipmentType := ET;
        if Length(Row) > 2 then E.Manufacturer := Row[2];
        if Length(Row) > 3 then E.Location := Row[3];
        E.ModifiedDate := UTCNow;
        FManager.Flush;
        Inc(R.Updated);
        Log('  Updated: ' + ModelName);
      end
      else
      begin
        E := TEquipment.Create;
        E.EquipmentType := ET;
        E.Model := ModelName;
        if Length(Row) > 2 then E.Manufacturer := Row[2] else E.Manufacturer := '';
        if Length(Row) > 3 then E.Location := Row[3] else E.Location := '';
        E.CreatedDate := UTCNow;
        E.CreatedBy := FPrincipalId;
        FManager.Save(E);
        FManager.Flush;
        Inc(R.Inserted);
        Log('  Inserted: ' + ModelName);
      end;
    end;
  finally
    Rows.Free;
  end;
end;

procedure TServiceImporter.ImportActionTypes(const FolderPath: string; var R: TEntityImportResult);
var
  Rows: TList<TArray<string>>;
  Row: TArray<string>;
  FilePath, Title: string;
  ET: TEquipmentType;
  AT: TActionType;
begin
  FilePath := IncludeTrailingPathDelimiter(FolderPath) + CSV_FILENAMES[4];
  if not FileExists(FilePath) then Exit;

  Rows := ParseCSVFile(FilePath);
  try
    for Row in Rows do
    begin
      if Length(Row) < 1 then Continue;
      Title := Row[0];
      if Title = '' then Continue;

      AT := FindActionTypeByTitle(Title);
      if Assigned(AT) then
      begin
        if Length(Row) > 1 then AT.Kind := ParseActionKind(Row[1]);
        if Length(Row) > 2 then AT.ItemType := ParseItemType(Row[2]);
        if (Length(Row) > 3) and (Row[3] <> '') then
        begin
          ET := FindEquipmentTypeByName(Row[3]);
          if Assigned(ET) then AT.EquipmentType := ET
          else Log('  Warning: EquipmentType "' + Row[3] + '" not found for "' + Title + '"');
        end;
        AT.ModifiedDate := UTCNow;
        FManager.Flush;
        Inc(R.Updated);
        Log('  Updated: ' + Title);
      end
      else
      begin
        AT := TActionType.Create;
        AT.Title := Title;
        if Length(Row) > 1 then AT.Kind := ParseActionKind(Row[1]) else AT.Kind := TActionKind.Other;
        if Length(Row) > 2 then AT.ItemType := ParseItemType(Row[2]) else AT.ItemType := TItemType.Other;
        if (Length(Row) > 3) and (Row[3] <> '') then
        begin
          ET := FindEquipmentTypeByName(Row[3]);
          if Assigned(ET) then AT.EquipmentType := ET;
        end;
        AT.CreatedDate := UTCNow;
        AT.CreatedBy := FPrincipalId;
        FManager.Save(AT);
        FManager.Flush;
        Inc(R.Inserted);
        Log('  Inserted: ' + Title);
      end;
    end;
  finally
    Rows.Free;
  end;
end;

{ Import Relations }

procedure TServiceImporter.ImportFileTypeLinks(const FolderPath: string; var R: TEntityImportResult);
var
  Rows: TList<TArray<string>>;
  Row: TArray<string>;
  FilePath: string;
  AT: TActionType;
  FT: TFileType;
  Links: TList<TFileTypeLink>;
  Link: TFileTypeLink;
  Found: Boolean;
  LinkDic: TFileTypeLinkDictionary;
begin
  FilePath := IncludeTrailingPathDelimiter(FolderPath) + CSV_FILENAMES[5];
  if not FileExists(FilePath) then Exit;

  Rows := ParseCSVFile(FilePath);
  try
    for Row in Rows do
    begin
      if Length(Row) < 2 then Continue;
      if (Row[0] = '') or (Row[1] = '') then Continue;

      AT := FindActionTypeByTitle(Row[0]);
      if AT = nil then
      begin
        Inc(R.Errors);
        Log('  Error: ActionType "' + Row[0] + '" not found');
        Continue;
      end;

      FT := FindFileTypeByExt(Row[1]);
      if FT = nil then
      begin
        Inc(R.Errors);
        Log('  Error: FileType "' + Row[1] + '" not found');
        Continue;
      end;

      // Check if link already exists
      LinkDic := TFileTypeLinkDictionary.Create;
      try
        Links := FManager.Find<TFileTypeLink>
          .Where((LinkDic.ActionType.Id = AT.Id) and (LinkDic.FileType_.Id = FT.Id))
          .List;
        Found := Links.Count > 0;
      finally
        LinkDic.Free;
      end;

      if Found then
      begin
        Inc(R.Updated);
        Log('  Exists: ' + Row[0] + ' -> ' + Row[1]);
      end
      else
      begin
        Link := TFileTypeLink.Create;
        Link.ActionType := AT;
        Link.FileType := FT;
        Link.CreatedDate := UTCNow;
        Link.CreatedBy := FPrincipalId;
        FManager.Save(Link);
        FManager.Flush;
        Inc(R.Inserted);
        Log('  Linked: ' + Row[0] + ' -> ' + Row[1]);
      end;
    end;
  finally
    Rows.Free;
  end;
end;

procedure TServiceImporter.ImportActionTypeEquipment(const FolderPath: string; var R: TEntityImportResult);
var
  Rows: TList<TArray<string>>;
  Row: TArray<string>;
  FilePath: string;
  AT: TActionType;
  E: TEquipment;
begin
  FilePath := IncludeTrailingPathDelimiter(FolderPath) + CSV_FILENAMES[6];
  if not FileExists(FilePath) then Exit;

  Rows := ParseCSVFile(FilePath);
  try
    for Row in Rows do
    begin
      if Length(Row) < 2 then Continue;
      if (Row[0] = '') or (Row[1] = '') then Continue;

      AT := FindActionTypeByTitle(Row[0]);
      if AT = nil then
      begin
        Inc(R.Errors);
        Log('  Error: ActionType "' + Row[0] + '" not found');
        Continue;
      end;

      E := FindEquipmentByModel(Row[1]);
      if E = nil then
      begin
        Inc(R.Errors);
        Log('  Error: Equipment "' + Row[1] + '" not found');
        Continue;
      end;

      AT.Equipment := E;
      FManager.Flush;
      Inc(R.Updated);
      Log('  Assigned: ' + Row[0] + ' -> ' + Row[1]);
    end;
  finally
    Rows.Free;
  end;
end;

end.
