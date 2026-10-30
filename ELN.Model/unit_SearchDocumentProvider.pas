unit unit_SearchDocumentProvider;

interface

uses
  System.SysUtils,
  Aurelius.Engine.ObjectManager,
  unit_NotebookStorage,
  unit_TextEmbedder,
  unit_SearchPassages,
  unit_PassageContext;

type
  TNotebookDocumentProvider = class(TInterfacedObject, ISearchDocumentSource)
  private
    FManager: TObjectManager;
    FContextMode: TPassageContextMode;
  public
    constructor Create(Manager: TObjectManager;
      ContextMode: TPassageContextMode = DefaultPassageContextMode);
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

  TStorageFileReader = class(TInterfacedObject, IFileContentReader)
  private
    FStorage: INotebookStorage;
  public
    constructor Create(const Storage: INotebookStorage);
    function ReadFile(const RelativePath: string; MaxBytes: Int64; out Bytes: TBytes;
      out Size: Int64): Boolean;
    function TryGetStamp(const RelativePath: string; out Size, LastWrite: Int64): Boolean;
  end;

implementation

uses
  System.Variants,
  System.TypInfo,
  System.Generics.Collections,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  Aurelius.Criteria.Projections,
  unit_Project,
  unit_ItemTypes,
  unit_Item,
  unit_LabEntry,
  unit_Protocol,
  unit_Tag,
  unit_FilePaths,
  unit_TextExtractorRegistry;

type
  TPassageSink = class
  private
    FPassages: TList<TSearchPassage>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const KeyBase: string; ProjectId, ItemId: Integer;
      FileId: Int64; Field: TPassageField; const Text, Context: string);
    function ToArray: TSearchPassages;
  end;

  TLiveItem = record
    ProjectId, FolderId, ParentId: Integer;
    FolderName: string;
    Parts: TPassageContextParts;
  end;

  TFolderNode = record
    ParentId: Integer;
    Title: string;
  end;

constructor TPassageSink.Create;
begin
  inherited Create;
  FPassages := TList<TSearchPassage>.Create;
end;

destructor TPassageSink.Destroy;
begin
  FPassages.Free;
  inherited;
end;

procedure TPassageSink.Add(const KeyBase: string; ProjectId, ItemId: Integer;
  FileId: Int64; Field: TPassageField; const Text, Context: string);
begin
  AppendTextPassages(FPassages, KeyBase, ProjectId, ItemId, FileId, Field, Text, Context);
end;

function TPassageSink.ToArray: TSearchPassages;
begin
  Result := FPassages.ToArray;
end;

function RowText(Row: TCriteriaResult; const Name: string): string;
begin
  Result := VarToStr(Row.Values[Name]);
end;

function RowInt(Row: TCriteriaResult; const Name: string): Int64;
begin
  Result := Row.Values[Name];
end;

procedure RaiseIfCancelled(const Cancelled: TCancelCheck);
begin
  if Assigned(Cancelled) and Cancelled() then
    raise EOperationCancelled.Create('Passage reading was cancelled');
end;

function ItemContext(Mode: TPassageContextMode; const Item: TLiveItem;
  Field: TPassageField): string;
begin
  Result := PassageContextFor(Mode, Item.Parts, Field);
end;

function FolderPathOf(FolderId: Integer; Nodes: TDictionary<Integer, TFolderNode>;
  Cache: TDictionary<Integer, TArray<string>>): TArray<string>;
var
  Node: TFolderNode;
  Cursor, Steps: Integer;
begin
  if Cache.TryGetValue(FolderId, Result) then Exit;
  Result := nil;
  Cursor := FolderId;
  Steps := Nodes.Count;
  while (Cursor > 0) and (Steps >= 0) and Nodes.TryGetValue(Cursor, Node) do
  begin
    Result := [Node.Title] + Result;
    Cursor := Node.ParentId;
    Dec(Steps);
  end;
  Cache.Add(FolderId, Result);
end;

procedure AddFullContext(Manager: TObjectManager; Live: TDictionary<Integer, TLiveItem>;
  const Cancelled: TCancelCheck);
var
  Nodes: TDictionary<Integer, TFolderNode>;
  Paths: TDictionary<Integer, TArray<string>>;
  ActionTypes: TDictionary<Integer, string>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Node: TFolderNode;
  Item, Parent: TLiveItem;
  Ids: TArray<Integer>;
  Id: Integer;
  Title: string;
begin
  Nodes := TDictionary<Integer, TFolderNode>.Create;
  Paths := TDictionary<Integer, TArray<string>>.Create;
  ActionTypes := TDictionary<Integer, string>.Create;
  try
    RaiseIfCancelled(Cancelled);
    Rows := Manager.Find<TFolder>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('ParentFolderID').As_('ParentId'))
        .Add(TProjections.Prop('Title').As_('Title')))
      .ListValues;
    try
      for Row in Rows do
      begin
        Node.ParentId := RowInt(Row, 'ParentId');
        Node.Title := RowText(Row, 'Title');
        Nodes.AddOrSetValue(RowInt(Row, 'Id'), Node);
      end;
    finally
      Rows.Free;
    end;

    RaiseIfCancelled(Cancelled);
    Rows := Manager.Find<TItem>
      .CreateAlias('FActionType', 'a')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('ItemId'))
        .Add(TProjections.Prop('a.Title').As_('Title')))
      .Where(Linq['IsDeleted'] = False)
      .ListValues;
    try
      for Row in Rows do
        ActionTypes.AddOrSetValue(RowInt(Row, 'ItemId'), RowText(Row, 'Title'));
    finally
      Rows.Free;
    end;

    Ids := Live.Keys.ToArray;
    for Id in Ids do
    begin
      Item := Live[Id];
      Item.Parts.FolderPath := FolderPathOf(Item.FolderId, Nodes, Paths);
      if ActionTypes.TryGetValue(Id, Title) then
        Item.Parts.ActionType := Title;
      if (Item.ParentId <> 0) and Live.TryGetValue(Item.ParentId, Parent) then
        Item.Parts.ParentTitle := Parent.Parts.ItemTitle;
      Live[Id] := Item;
    end;
  finally
    ActionTypes.Free;
    Paths.Free;
    Nodes.Free;
  end;
end;

constructor TNotebookDocumentProvider.Create(Manager: TObjectManager;
  ContextMode: TPassageContextMode);
begin
  inherited Create;
  if Manager = nil then
    raise EArgumentNilException.Create('Manager is required');
  FManager := Manager;
  FContextMode := ContextMode;
end;

function TNotebookDocumentProvider.IsItemLive(ItemId: Integer;
  out ProjectId: Integer): Boolean;
var
  Rows: TObjectList<TCriteriaResult>;
begin
  ProjectId := 0;
  Rows := FManager.Find<TItem>
    .Select(TProjections.ProjectionList
      .Add(TProjections.Prop('ProjectID').As_('ProjectId')))
    .Where((Linq['Id'] = ItemId) and (Linq['IsDeleted'] = False))
    .ListValues;
  try
    Result := Rows.Count > 0;
    if Result then
      ProjectId := RowInt(Rows[0], 'ProjectId');
  finally
    Rows.Free;
  end;
end;

constructor TStorageFileReader.Create(const Storage: INotebookStorage);
begin
  inherited Create;
  if Storage = nil then
    raise EArgumentNilException.Create('Storage is required');
  FStorage := Storage;
end;

function TStorageFileReader.ReadFile(const RelativePath: string; MaxBytes: Int64;
  out Bytes: TBytes; out Size: Int64): Boolean;
var
  Inspection: INotebookStorageInspection;
  Status: Integer;
begin
  Bytes := nil;
  Size := 0;
  if Supports(FStorage, INotebookStorageInspection, Inspection) then
  begin
    if not Inspection.TryGetFileInfo(RelativePath, Status, Size) then Exit(False);
    if Size > MaxBytes then Exit(True);
  end
  else if not FStorage.Exists(RelativePath) then
    Exit(False);
  Bytes := FStorage.ReadBytes(RelativePath);
  Size := Length(Bytes);
  if Size > MaxBytes then
    Bytes := nil;
  Result := True;
end;

function TStorageFileReader.TryGetStamp(const RelativePath: string;
  out Size, LastWrite: Int64): Boolean;
var
  Stamp: INotebookStorageStamp;
begin
  Size := 0;
  LastWrite := 0;
  Result := False;
  if Supports(FStorage, INotebookStorageStamp, Stamp) then
    try
      Result := Stamp.TryGetFileStamp(RelativePath, Size, LastWrite);
    except
      on Exception do
        Result := False;
    end;
end;

function TNotebookDocumentProvider.ReadSnapshot(
  const Cancelled: TCancelCheck): TSearchSnapshot;
var
  Files: TList<TFileTextRequest>;
  Request: TFileTextRequest;
  Sink: TPassageSink;
  Live: TDictionary<Integer, TLiveItem>;
  Folders: TDictionary<Integer, string>;
  ProjectTitles: TDictionary<Integer, string>;
  EntryItem: TDictionary<Integer, Integer>;
  TagNames: TDictionary<Integer, string>;
  ItemTags: TObjectDictionary<Integer, TList<string>>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Item: TLiveItem;
  ItemId, EntryId: Integer;
  FileId: Int64;
  Names: TList<string>;
  Name, Ext, Title, RelativePath: string;
  Kind: Int64;
  Pair: TPair<Integer, TList<string>>;
  Supported: Boolean;
  I: Integer;
begin
  Sink := TPassageSink.Create;
  Files := TList<TFileTextRequest>.Create;
  Live := TDictionary<Integer, TLiveItem>.Create;
  Folders := TDictionary<Integer, string>.Create;
  ProjectTitles := TDictionary<Integer, string>.Create;
  EntryItem := TDictionary<Integer, Integer>.Create;
  TagNames := TDictionary<Integer, string>.Create;
  ItemTags := TObjectDictionary<Integer, TList<string>>.Create([doOwnsValues]);
  try
    RaiseIfCancelled(Cancelled);
    Rows := FManager.Find<TProject>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('Title').As_('Title'))
        .Add(TProjections.Prop('FileFolder').As_('FileFolder')))
      .ListValues;
    try
      for Row in Rows do
      begin
        Folders.AddOrSetValue(RowInt(Row, 'Id'), RowText(Row, 'FileFolder'));
        ProjectTitles.AddOrSetValue(RowInt(Row, 'Id'), RowText(Row, 'Title'));
      end;
    finally
      Rows.Free;
    end;

    RaiseIfCancelled(Cancelled);
    Rows := FManager.Find<TItem>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('ProjectID').As_('ProjectId'))
        .Add(TProjections.Prop('FolderID').As_('FolderId'))
        .Add(TProjections.Prop('ParentID').As_('ParentId'))
        .Add(TProjections.Prop('Type_').As_('Kind'))
        .Add(TProjections.Prop('Title').As_('Title'))
        .Add(TProjections.Prop('Description').As_('Description'))
        .Add(TProjections.Prop('Properties').As_('Properties')))
      .Where(Linq['IsDeleted'] = False)
      .ListValues;
    try
      for Row in Rows do
      begin
        ItemId := RowInt(Row, 'Id');
        Item := Default(TLiveItem);
        Item.ProjectId := RowInt(Row, 'ProjectId');
        Item.FolderId := RowInt(Row, 'FolderId');
        Item.ParentId := RowInt(Row, 'ParentId');
        Title := RowText(Row, 'Title');
        Item.FolderName := TItem.MakeFolderName(ItemId, Title);
        ProjectTitles.TryGetValue(Item.ProjectId, Item.Parts.ProjectTitle);
        Item.Parts.ItemTitle := Title;
        Kind := RowInt(Row, 'Kind');
        if (Kind >= 0) and (Kind <= Ord(High(TItemType))) then
          Item.Parts.ItemKind := GetEnumName(TypeInfo(TItemType), Integer(Kind));
        Live.Add(ItemId, Item);
      end;
      AddFullContext(FManager, Live, Cancelled);
      for Row in Rows do
      begin
        ItemId := RowInt(Row, 'Id');
        Item := Live[ItemId];
        Name := 'item:' + IntToStr(ItemId);
        Sink.Add(Name + ':title', Item.ProjectId, ItemId, 0, pfItemTitle, RowText(Row, 'Title'),
          ItemContext(FContextMode, Item, pfItemTitle));
        Sink.Add(Name + ':description', Item.ProjectId, ItemId, 0,
          pfItemDescription, RowText(Row, 'Description'),
          ItemContext(FContextMode, Item, pfItemDescription));
        Sink.Add(Name + ':properties', Item.ProjectId, ItemId, 0,
          pfItemProperties, RowText(Row, 'Properties'),
          ItemContext(FContextMode, Item, pfItemProperties));
      end;
    finally
      Rows.Free;
    end;

    RaiseIfCancelled(Cancelled);
    Rows := FManager.Find<TTag>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('Name').As_('Name')))
      .ListValues;
    try
      for Row in Rows do
        TagNames.AddOrSetValue(RowInt(Row, 'Id'), RowText(Row, 'Name'));
    finally
      Rows.Free;
    end;
    Rows := FManager.Find<TItemTag>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('ItemId').As_('ItemId'))
        .Add(TProjections.Prop('TagId').As_('TagId')))
      .ListValues;
    try
      for Row in Rows do
      begin
        ItemId := RowInt(Row, 'ItemId');
        if not Live.ContainsKey(ItemId) then Continue;
        if not TagNames.TryGetValue(RowInt(Row, 'TagId'), Name) then Continue;
        if not ItemTags.TryGetValue(ItemId, Names) then
        begin
          Names := TList<string>.Create;
          ItemTags.Add(ItemId, Names);
        end;
        Names.Add(Name);
      end;
    finally
      Rows.Free;
    end;
    for Pair in ItemTags do
    begin
      Pair.Value.Sort;
      Name := '';
      for I := 0 to Pair.Value.Count - 1 do
      begin
        if I > 0 then Name := Name + ', ';
        Name := Name + Pair.Value[I];
      end;
      Sink.Add('item:' + IntToStr(Pair.Key) + ':tags', Live[Pair.Key].ProjectId,
        Pair.Key, 0, pfItemTags, Name, ItemContext(FContextMode, Live[Pair.Key], pfItemTags));
    end;

    RaiseIfCancelled(Cancelled);
    Rows := FManager.Find<TItem>
      .CreateAlias('FEntries', 'e')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('ItemId'))
        .Add(TProjections.Prop('e.Id').As_('EntryId')))
      .Where(Linq['IsDeleted'] = False)
      .ListValues;
    try
      for Row in Rows do
        if not VarIsNull(Row.Values['EntryId']) then
          EntryItem.AddOrSetValue(RowInt(Row, 'EntryId'), RowInt(Row, 'ItemId'));
    finally
      Rows.Free;
    end;
    Rows := FManager.Find<TLabEntry>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('Title').As_('Title')))
      .ListValues;
    try
      for Row in Rows do
      begin
        EntryId := RowInt(Row, 'Id');
        if not EntryItem.TryGetValue(EntryId, ItemId) then Continue;
        Sink.Add('entry:' + IntToStr(EntryId) + ':title', Live[ItemId].ProjectId,
          ItemId, 0, pfEntryTitle, RowText(Row, 'Title'),
          ItemContext(FContextMode, Live[ItemId], pfEntryTitle));
      end;
    finally
      Rows.Free;
    end;

    RaiseIfCancelled(Cancelled);
    Rows := FManager.Find<TProtocol>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('FormData').As_('FormData')))
      .ListValues;
    try
      for Row in Rows do
      begin
        EntryId := RowInt(Row, 'Id');
        if not EntryItem.TryGetValue(EntryId, ItemId) then Continue;
        Sink.Add('entry:' + IntToStr(EntryId) + ':form', Live[ItemId].ProjectId,
          ItemId, 0, pfProtocolForm, RowText(Row, 'FormData'),
          ItemContext(FContextMode, Live[ItemId], pfProtocolForm));
      end;
    finally
      Rows.Free;
    end;

    RaiseIfCancelled(Cancelled);
    Rows := FManager.Find<TValue>
      .CreateAlias('Item', 'i')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('i.Id').As_('ItemId'))
        .Add(TProjections.Prop('Description').As_('Description')))
      .ListValues;
    try
      for Row in Rows do
      begin
        ItemId := RowInt(Row, 'ItemId');
        if not Live.TryGetValue(ItemId, Item) then Continue;
        Sink.Add('value:' + RowText(Row, 'Id') + ':description', Item.ProjectId,
          ItemId, 0, pfValueDescription, RowText(Row, 'Description'),
          ItemContext(FContextMode, Item, pfValueDescription));
      end;
    finally
      Rows.Free;
    end;

    RaiseIfCancelled(Cancelled);
    Rows := FManager.Find<unit_Item.TFile>
      .CreateAlias('FItem', 'i')
      .CreateAlias('FFileType', 'ft')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('i.Id').As_('ItemId'))
        .Add(TProjections.Prop('Title').As_('Title'))
        .Add(TProjections.Prop('ft.Ext').As_('Ext')))
      .ListValues;
    try
      for Row in Rows do
      begin
        ItemId := RowInt(Row, 'ItemId');
        if not Live.TryGetValue(ItemId, Item) then Continue;
        FileId := RowInt(Row, 'Id');
        Ext := RowText(Row, 'Ext');
        Name := unit_Item.TFile.MakeFullName(FileId, RowText(Row, 'Title'), Ext);
        Sink.Add('file:' + IntToStr(FileId) + ':name', Item.ProjectId, ItemId,
          FileId, pfFileName, Name, ItemContext(FContextMode, Item, pfFileName));
        Supported := False;
        for I := Low(SupportedFileTextExtensions) to High(SupportedFileTextExtensions) do
          if SameText(Ext, SupportedFileTextExtensions[I]) then
            Supported := True;
        if not Supported then Continue;
        if not Folders.TryGetValue(Item.ProjectId, RelativePath) then Continue;
        Request.FileId := FileId;
        Request.ItemId := ItemId;
        Request.ProjectId := Item.ProjectId;
        Request.Ext := Ext;
        Request.Context := ItemContext(FContextMode, Item, pfFileText);
        Request.RelativePath := AttachmentRelativePath(RelativePath, Item.FolderName, Name);
        Files.Add(Request);
      end;
    finally
      Rows.Free;
    end;

    Result.Passages := Sink.ToArray;
    Result.Files := Files.ToArray;
    SetLength(Result.ItemContexts, Live.Count);
    I := 0;
    for ItemId in Live.Keys do
    begin
      Result.ItemContexts[I] := TItemContextEntry.Make(ItemId,
        PassageContextPartsToJson(Live[ItemId].Parts));
      Inc(I);
    end;
  finally
    ItemTags.Free;
    TagNames.Free;
    EntryItem.Free;
    Folders.Free;
    ProjectTitles.Free;
    Live.Free;
    Sink.Free;
    Files.Free;
  end;
end;

end.
