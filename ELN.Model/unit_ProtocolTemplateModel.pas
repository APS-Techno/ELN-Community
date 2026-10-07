unit unit_ProtocolTemplateModel;

interface

uses
  SysUtils, Classes,
  System.Generics.Collections,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Engine.ObjectManager,
  Aurelius.Types.Nullable,
  unit_TELNModel,
  unit_Template,
  unit_Item,
  unit_TemplateTagsModel,
  unit_ELNDB_Dictionary;

type
  TTemplateModel = class(TELNModel)
  private
    FDic: TTemplateDictionary;
    FManager: TObjectManager;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;
    procedure OpenDataSet; override;

    function GetActiveTemplates: TTemplates;
    function GetAllTemplates: TTemplates;
    function GetTemplateById(Id: Integer): TTemplate;
    function GetTemplateHtml(Template: TTemplate): string;
    procedure SaveTemplate(Template: TTemplate);
    procedure DeleteTemplate(Id: Integer);

    // Equipment-type / equipment tag persistence (join tables)
    function LoadTagsFor(TemplateId: Integer): TTemplateTagsSnapshot;
    procedure SaveTagsFor(TemplateId: Integer; const Snap: TTemplateTagsSnapshot);

    // UserId 0 is an unattributed system import; interactive imports use the principal.
    procedure CreateDefaultTemplates(const TemplatesDir: string; UserId: Integer);
    procedure UpdateTemplateCategories(const TemplatesDir: string);
    procedure ReimportTemplates(const TemplatesDir: string; Overwrite: Boolean;
      UserId: Integer; Categories: TStrings = nil);

    // Auto-fill
    function BuildAutoFillData(Template: TTemplate; Item: TItem;
      const UserDisplayName: string): string;

    // Versioning
    function IsTemplateInUse(TemplateId: Integer): Boolean;
    function GetLatestVersions: TTemplates;
    function GetVersionHistory(RootId: Integer): TTemplates;
    /// <summary>Persist a template. If the template is already in use, a new
    /// version row is created and returned; otherwise the passed-in template
    /// is updated in place and returned.</summary>
    function SaveOrVersion(Template: TTemplate): TTemplate;
    function GetRootId(Template: TTemplate): Integer;
  end;

implementation

uses
  System.IOUtils, System.JSON, System.Rtti,
  unit_ProtocolTemplateHtmlGenerator,
  unit_Protocol,
  unit_ActionType,
  unit_Equipment,
  unit_EquipmentType,
  unit_ItemTypes,
  unit_ValueType,
  unit_ValueTypeModel,
  unit_TimeHelper;

{ TTemplateModel }

constructor TTemplateModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TTemplateDictionary.Create;
end;

destructor TTemplateModel.Destroy;
begin
  FDic.Free;
  inherited;
end;

procedure TTemplateModel.OpenDataSet;
begin
  // Dataset not used - model uses direct ObjectManager queries
end;

function TTemplateModel.GetActiveTemplates: TTemplates;
begin
  Result := FManager.Find<TTemplate>
    .Where(FDic.IsActive = True)
    .OrderBy(FDic.Category)
    .OrderBy(FDic.Name)
    .List;
end;

function TTemplateModel.GetAllTemplates: TTemplates;
begin
  Result := FManager.Find<TTemplate>
    .OrderBy(FDic.Category)
    .OrderBy(FDic.Name)
    .OrderBy(FDic.Version)
    .List;
end;

function TTemplateModel.GetTemplateById(Id: Integer): TTemplate;
begin
  Result := FManager.Find<TTemplate>(Id);
end;

function TTemplateModel.GetTemplateHtml(Template: TTemplate): string;
begin
  Result := TTemplateHtmlGenerator.GenerateHtml(Template.FormSchema);
end;

procedure TTemplateModel.SaveTemplate(Template: TTemplate);
begin
  FManager.SaveOrUpdate(Template);
  FManager.Flush;
end;

function TTemplateModel.LoadTagsFor(TemplateId: Integer): TTemplateTagsSnapshot;
begin
  if TemplateId <= 0 then
  begin
    SetLength(Result.EquipmentTypeIds, 0);
    SetLength(Result.EquipmentIds, 0);
    Exit;
  end;
  Result := TTemplateTagsModel.LoadTagsFor(FManager, TemplateId);
end;

procedure TTemplateModel.SaveTagsFor(TemplateId: Integer;
  const Snap: TTemplateTagsSnapshot);
begin
  if TemplateId <= 0 then Exit;
  TTemplateTagsModel.SaveTagsFor(FManager, TemplateId, Snap);
  FManager.Flush;
end;

procedure TTemplateModel.DeleteTemplate(Id: Integer);
var
  Template: TTemplate;
begin
  Template := FManager.Find<TTemplate>(Id);
  if Assigned(Template) then
  begin
    if IsTemplateInUse(Id) then
    begin
      // Soft-delete: mark inactive instead of removing
      Template.IsActive := False;
      Template.ModifiedDate := UTCNow;
      FManager.Flush;
    end
    else
    begin
      FManager.Remove(Template);
      FManager.Flush;
    end;
  end;
end;

function TTemplateModel.BuildAutoFillData(Template: TTemplate; Item: TItem;
  const UserDisplayName: string): string;
var
  CachedAT: TActionType;
  CachedEq: TEquipment;
  CachedParent: TItem;
  ATResolved, EqResolved, ParentResolved: Boolean;

  function GetActionType: TActionType;
  begin
    if not ATResolved then
    begin
      CachedAT := Item.ActionType;
      ATResolved := True;
    end;
    Result := CachedAT;
  end;

  function GetEquipment: TEquipment;
  var
    AT: TActionType;
    Eq: TEquipment;
    Equipments: TList<TEquipment>;
    EqTypeId: Integer;
  begin
    if not EqResolved then
    begin
      CachedEq := nil;
      AT := GetActionType;
      if Assigned(AT) then
      begin
        // Try direct Equipment link on ActionType
        CachedEq := AT.Equipment;
        // Fallback: find Equipment via ActionType.EquipmentType
        if not Assigned(CachedEq) and Assigned(AT.EquipmentType) then
        begin
          EqTypeId := AT.EquipmentType.Id;
          Equipments := FManager.Find<TEquipment>.List;
          try
            for Eq in Equipments do
              if Assigned(Eq.EquipmentType) and (Eq.EquipmentType.Id = EqTypeId) then
              begin
                CachedEq := Eq;
                Break;
              end;
          finally
            Equipments.Free;
          end;
        end;
      end;
      EqResolved := True;
    end;
    Result := CachedEq;
  end;

  function GetParentItem: TItem;
  begin
    if not ParentResolved then
    begin
      CachedParent := nil;
      if Item.Parent > 0 then
        CachedParent := FManager.Find<TItem>(Item.Parent);
      ParentResolved := True;
    end;
    Result := CachedParent;
  end;

  function FindValueBySymbol(AItem: TItem; const ASymbol: string;
    ARecType: TRecType): unit_Item.TValue; overload;
  var
    Val: unit_Item.TValue;
  begin
    Result := nil;
    if not Assigned(AItem) then Exit;
    for Val in AItem.Values do
      if (Val.ValueType.Symbol = ASymbol) and (Val.RecType = ARecType) then
        Exit(Val);
  end;

  function FindValueBySymbol(AItem: TItem; const ASymbol: string): unit_Item.TValue; overload;
  var
    Val: unit_Item.TValue;
  begin
    Result := nil;
    if not Assigned(AItem) then Exit;
    for Val in AItem.Values do
      if Val.ValueType.Symbol = ASymbol then
        Exit(Val);
  end;

  function FormatFilteredValues(AItem: TItem; ARecType: TRecType): string;
  var
    Val: unit_Item.TValue;
  begin
    Result := '';
    if not Assigned(AItem) then Exit;
    for Val in AItem.Values do
    begin
      if Val.RecType <> ARecType then Continue;
      if Result <> '' then
        Result := Result + ';  ';
      Result := Result + Val.ValueType.Symbol + ' = ' +
        FormatSIValue(Val.Value, Val.ValueType.Units);
    end;
  end;

  function ResolveAutoFill(const Source: string): string;
  var
    AT: TActionType;
    Eq: TEquipment;
    ParentItem: TItem;
    Val: unit_Item.TValue;
    Symbol: string;
  begin
    Result := '';
    if Source = 'item.title' then
      Result := Item.Title
    else if Source = 'item.description' then
      Result := Item.Description
    else if Source = 'item.type' then
      Result := TRttiEnumerationType.GetName(Item.Type_)
    else if Source = 'actionType.title' then
    begin
      AT := GetActionType;
      if Assigned(AT) then
        Result := AT.Title;
    end
    else if Source = 'actionType.description' then
    begin
      AT := GetActionType;
      if Assigned(AT) then
        Result := AT.Description;
    end
    else if Source = 'equipment.model' then
    begin
      Eq := GetEquipment;
      if Assigned(Eq) then
        Result := Eq.Model;
    end
    else if Source = 'equipment.manufacturer' then
    begin
      Eq := GetEquipment;
      if Assigned(Eq) then
        Result := Eq.Manufacturer;
    end
    else if Source = 'equipment.location' then
    begin
      Eq := GetEquipment;
      if Assigned(Eq) then
        Result := Eq.Location;
    end
    else if Source = 'parent.title' then
    begin
      ParentItem := GetParentItem;
      if Assigned(ParentItem) then
        Result := ParentItem.Title;
    end
    else if Source = 'parent.description' then
    begin
      ParentItem := GetParentItem;
      if Assigned(ParentItem) then
        Result := ParentItem.Description;
    end
    // conditions.all / conditions.<symbol> — EXP_CONDITION values only
    else if Source = 'conditions.all' then
      Result := FormatFilteredValues(Item, EXP_CONDITION)
    else if Source.StartsWith('conditions.') then
    begin
      Symbol := Source.Substring(11);
      Val := FindValueBySymbol(Item, Symbol, EXP_CONDITION);
      if Assigned(Val) then
        Result := FormatSIValue(Val.Value, Val.ValueType.Units);
    end
    // results.all / results.<symbol> — TEST_RESULT values only
    else if Source = 'results.all' then
      Result := FormatFilteredValues(Item, TEST_RESULT)
    else if Source.StartsWith('results.') then
    begin
      Symbol := Source.Substring(8);
      Val := FindValueBySymbol(Item, Symbol, TEST_RESULT);
      if Assigned(Val) then
        Result := FormatSIValue(Val.Value, Val.ValueType.Units);
    end
    // values.all / values.<symbol> — all values regardless of type
    else if Source = 'values.all' then
    begin
      if Item.Values.Count > 0 then
        Result := FormatValuesInline(Item.Values);
    end
    else if Source.StartsWith('values.') then
    begin
      Symbol := Source.Substring(7);
      Val := FindValueBySymbol(Item, Symbol);
      if Assigned(Val) then
        Result := FormatSIValue(Val.Value, Val.ValueType.Units);
    end
    else if Source = 'user.name' then
      Result := UserDisplayName
    else if Source = 'date.today' then
      Result := FormatDateTime('yyyy-mm-dd', Now);
  end;

var
  SchemaVal: TJSONValue;
  Root: TJSONObject;
  Sections, Rows, Fields: TJSONArray;
  Section, Row, Field: TJSONValue;
  FieldObj: TJSONObject;
  AutoFillVal: TJSONValue;
  FieldName, AutoFillSource, Resolved: string;
  ResultObj: TJSONObject;
begin
  Result := '';
  if not Assigned(Template) or not Assigned(Item) then
    Exit;

  CachedAT := nil;
  CachedEq := nil;
  CachedParent := nil;
  ATResolved := False;
  EqResolved := False;
  ParentResolved := False;

  SchemaVal := TJSONObject.ParseJSONValue(Template.FormSchema);
  if not Assigned(SchemaVal) then
    Exit;

  ResultObj := TJSONObject.Create;
  try
    try
      if not (SchemaVal is TJSONObject) then
        Exit;
      Root := TJSONObject(SchemaVal);

      Sections := Root.GetValue('sections') as TJSONArray;
      if not Assigned(Sections) then
        Exit;

      for Section in Sections do
      begin
        if not (Section is TJSONObject) then
          Continue;
        Rows := TJSONObject(Section).GetValue('rows') as TJSONArray;
        if not Assigned(Rows) then
          Continue;

        for Row in Rows do
        begin
          if not (Row is TJSONObject) then
            Continue;
          Fields := TJSONObject(Row).GetValue('fields') as TJSONArray;
          if not Assigned(Fields) then
            Continue;

          for Field in Fields do
          begin
            if not (Field is TJSONObject) then
              Continue;
            FieldObj := TJSONObject(Field);

            AutoFillVal := FieldObj.GetValue('autoFill');
            if not Assigned(AutoFillVal) then
              Continue;

            AutoFillSource := AutoFillVal.Value;
            if AutoFillSource = '' then
              Continue;

            FieldName := '';
            if FieldObj.GetValue('name') <> nil then
              FieldName := FieldObj.GetValue('name').Value;
            if FieldName = '' then
              Continue;

            Resolved := ResolveAutoFill(AutoFillSource);
            if Resolved <> '' then
              ResultObj.AddPair(FieldName, Resolved);
          end;
        end;
      end;

      if ResultObj.Count > 0 then
        Result := ResultObj.ToJSON;
    finally
      SchemaVal.Free;
    end;
  finally
    ResultObj.Free;
  end;
end;

procedure TTemplateModel.ReimportTemplates(const TemplatesDir: string;
  Overwrite: Boolean; UserId: Integer; Categories: TStrings);
var
  Files: TArray<string>;
  FileName, Schema, Name, Description, Category, ParentDir, Err: string;
  JsonVal: TJSONValue;
  Root: TJSONObject;
  AllTemplates: TTemplates;
  ExistingMap: TDictionary<string, TTemplate>;
  T, ExistingT: TTemplate;
  Updated: Boolean;
begin
  if UserId < 0 then
    raise EArgumentException.Create('Template import author cannot be negative');
  if not TDirectory.Exists(TemplatesDir) then
    Exit;

  // Build name -> template map from DB (all versions, active and inactive)
  ExistingMap := TDictionary<string, TTemplate>.Create;
  try
    AllTemplates := FManager.Find<TTemplate>.List;
    try
      for T in AllTemplates do
        ExistingMap.AddOrSetValue(LowerCase(T.Name), T);
    finally
      AllTemplates.Free;
    end;

    Files := TDirectory.GetFiles(TemplatesDir, '*.json', TSearchOption.soAllDirectories);
    Updated := False;

    for FileName in Files do
    begin
      // Filter by category (parent directory name) if categories specified
      if Assigned(Categories) and (Categories.Count > 0) then
      begin
        ParentDir := TPath.GetFileName(TPath.GetDirectoryName(FileName));
        if Categories.IndexOf(ParentDir) < 0 then
          Continue;
      end;

      Schema := TFile.ReadAllText(FileName, TEncoding.UTF8);
      Err := TTemplateHtmlGenerator.ValidateSchema(Schema);
      if Err <> '' then
        Continue;

      Name := TPath.GetFileNameWithoutExtension(FileName);
      Description := '';
      Category := '';

      JsonVal := TJSONObject.ParseJSONValue(Schema);
      if Assigned(JsonVal) then
      try
        if JsonVal is TJSONObject then
        begin
          Root := TJSONObject(JsonVal);
          if Root.GetValue('title') <> nil then
            Name := Root.GetValue('title').Value;
          if Root.GetValue('description') <> nil then
            Description := Root.GetValue('description').Value;
          if Root.GetValue('category') <> nil then
            Category := Root.GetValue('category').Value;
        end;
      finally
        JsonVal.Free;
      end;

      if ExistingMap.TryGetValue(LowerCase(Name), ExistingT) then
      begin
        if Overwrite then
        begin
          ExistingT.FormSchema := Schema;
          ExistingT.Description := Description;
          ExistingT.Category := Category;
          ExistingT.ModifiedDate := UTCNow;
          Updated := True;
        end;
      end
      else
      begin
        T := TTemplate.Create;
        T.Name := Name;
        T.Description := Description;
        T.Category := Category;
        T.FormSchema := Schema;
        T.IsActive := True;
        T.CreatedDate := UTCNow;
        FManager.Save(T);
        ExistingMap.AddOrSetValue(LowerCase(Name), T);
        Updated := True;
      end;
    end;

    if Updated then
      FManager.Flush;
  finally
    ExistingMap.Free;
  end;
end;

function TTemplateModel.IsTemplateInUse(TemplateId: Integer): Boolean;
var
  ProtoDic: TProtocolDictionary;
  Protocols: TList<TProtocol>;
begin
  ProtoDic := TProtocolDictionary.Create;
  try
    Protocols := FManager.Find<TProtocol>
      .Where(ProtoDic.TemplateId = TemplateId)
      .List;
    try
      Result := Protocols.Count > 0;
    finally
      Protocols.Free;
    end;
  finally
    ProtoDic.Free;
  end;
end;

function TTemplateModel.GetRootId(Template: TTemplate): Integer;
begin
  if Template.ParentId.HasValue then
    Result := Template.ParentId.Value
  else
    Result := Template.Id;
end;

function TTemplateModel.GetLatestVersions: TTemplates;
var
  AllActive: TTemplates;
  T: TTemplate;
  RootId: Integer;
  RootMap: TDictionary<Integer, TTemplate>;
begin
  // Get all active templates, then pick the highest version per root family
  AllActive := FManager.Find<TTemplate>
    .Where(FDic.IsActive = True)
    .OrderBy(FDic.Name)
    .List;

  RootMap := TDictionary<Integer, TTemplate>.Create;
  try
    for T in AllActive do
    begin
      RootId := GetRootId(T);
      if RootMap.ContainsKey(RootId) then
      begin
        if T.Version > RootMap[RootId].Version then
          RootMap[RootId] := T;
      end
      else
        RootMap.Add(RootId, T);
    end;

    Result := TTemplates.Create;
    for T in RootMap.Values do
      Result.Add(T);
  finally
    RootMap.Free;
    // Don't free AllActive — objects are managed by ObjectManager
  end;
end;

function TTemplateModel.GetVersionHistory(RootId: Integer): TTemplates;
begin
  // Return all versions: the root itself (Id=RootId) + all with ParentId=RootId
  Result := FManager.Find<TTemplate>
    .Where((FDic.Id = RootId) or (FDic.ParentId = RootId))
    .OrderBy(FDic.Version)
    .List;
end;

function TTemplateModel.SaveOrVersion(Template: TTemplate): TTemplate;
var
  RootId: Integer;
  NewVersion: TTemplate;
begin
  if (Template.Id > 0) and IsTemplateInUse(Template.Id) then
  begin
    // Template is in use — create a new version row
    RootId := GetRootId(Template);
    NewVersion := TTemplate.Create;
    NewVersion.Name := Template.Name;
    NewVersion.Description := Template.Description;
    NewVersion.Category := Template.Category;
    NewVersion.FormSchema := Template.FormSchema;
    NewVersion.IsActive := True;
    NewVersion.Version := Template.Version + 1;
    NewVersion.ParentId := RootId;
    NewVersion.CreatedDate := UTCNow;

    // Deactivate the old version so it doesn't appear in latest lists
    // but existing protocols still reference it by ID
    Template.IsActive := False;
    Template.ModifiedDate := UTCNow;

    FManager.Save(NewVersion);
    FManager.Flush;
    Result := NewVersion;
  end
  else
  begin
    // Not in use — update in place
    Template.ModifiedDate := UTCNow;
    FManager.SaveOrUpdate(Template);
    FManager.Flush;
    Result := Template;
  end;
end;

procedure TTemplateModel.CreateDefaultTemplates(const TemplatesDir: string;
  UserId: Integer);
var
  Files: TArray<string>;
  FileName, Schema, Name, Description, Category, Err: string;
  JsonVal: TJSONValue;
  Root: TJSONObject;
  T: TTemplate;
  Existing: TTemplates;
begin
  if UserId < 0 then
    raise EArgumentException.Create('Template author cannot be negative');
  Existing := FManager.Find<TTemplate>.Take(1).List;
  try
    if Existing.Count > 0 then
      Exit;
  finally
    Existing.Free;
  end;

  if not TDirectory.Exists(TemplatesDir) then
    Exit;

  Files := TDirectory.GetFiles(TemplatesDir, '*.json', TSearchOption.soAllDirectories);
  for FileName in Files do
  begin
    Schema := TFile.ReadAllText(FileName, TEncoding.UTF8);

    Err := TTemplateHtmlGenerator.ValidateSchema(Schema);
    if Err <> '' then
      Continue;

    Name := TPath.GetFileNameWithoutExtension(FileName);
    Description := '';
    Category := '';

    JsonVal := TJSONObject.ParseJSONValue(Schema);
    if Assigned(JsonVal) then
    try
      if JsonVal is TJSONObject then
      begin
        Root := TJSONObject(JsonVal);
        if Root.GetValue('title') <> nil then
          Name := Root.GetValue('title').Value;
        if Root.GetValue('description') <> nil then
          Description := Root.GetValue('description').Value;
        if Root.GetValue('category') <> nil then
          Category := Root.GetValue('category').Value;
      end;
    finally
      JsonVal.Free;
    end;

    T := TTemplate.Create;
    T.Name := Name;
    T.Description := Description;
    T.Category := Category;
    T.FormSchema := Schema;
    T.IsActive := True;
    T.CreatedDate := UTCNow;
    FManager.Save(T);
  end;

  FManager.Flush;
end;

procedure TTemplateModel.UpdateTemplateCategories(const TemplatesDir: string);
var
  Templates: TTemplates;
  T: TTemplate;
  Files: TArray<string>;
  FileName, Schema, Title, Category: string;
  JsonVal: TJSONValue;
  Root: TJSONObject;
  CategoryMap: TDictionary<string, string>; // title -> category
  Updated: Boolean;
begin
  // Find templates with empty category
  Templates := FManager.Find<TTemplate>
    .Where(FDic.Category = '')
    .List;
  try
    if Templates.Count = 0 then
      Exit;
  finally
    Templates.Free;
  end;

  if not TDirectory.Exists(TemplatesDir) then
    Exit;

  // Build a map of title -> category from JSON files on disk
  CategoryMap := TDictionary<string, string>.Create;
  try
    Files := TDirectory.GetFiles(TemplatesDir, '*.json', TSearchOption.soAllDirectories);
    for FileName in Files do
    begin
      Schema := TFile.ReadAllText(FileName, TEncoding.UTF8);
      JsonVal := TJSONObject.ParseJSONValue(Schema);
      if Assigned(JsonVal) then
      try
        if JsonVal is TJSONObject then
        begin
          Root := TJSONObject(JsonVal);
          Title := '';
          Category := '';
          if Root.GetValue('title') <> nil then
            Title := Root.GetValue('title').Value;
          if Root.GetValue('category') <> nil then
            Category := Root.GetValue('category').Value;
          if (Title <> '') and (Category <> '') then
            CategoryMap.AddOrSetValue(LowerCase(Title), Category);
        end;
      finally
        JsonVal.Free;
      end;
    end;

    if CategoryMap.Count = 0 then
      Exit;

    // Update templates that have empty category and match by name
    Templates := FManager.Find<TTemplate>
      .Where(FDic.Category = '')
      .List;
    try
      Updated := False;
      for T in Templates do
      begin
        if CategoryMap.ContainsKey(LowerCase(T.Name)) then
        begin
          T.Category := CategoryMap[LowerCase(T.Name)];
          Updated := True;
        end;
      end;
      if Updated then
        FManager.Flush;
    finally
      Templates.Free;
    end;
  finally
    CategoryMap.Free;
  end;
end;

end.
