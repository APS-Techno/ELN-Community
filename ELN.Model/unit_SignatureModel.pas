unit unit_SignatureModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Hash,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  unit_Signature,
  unit_Item,
  unit_User,
  unit_ELNDB_Dictionary,
  unit_AuditLog;

type
  TSignatureModel = class
  private
    FManager: TObjectManager;
    FDic: TSignatureDictionary;
    function BuildItemContent(Item: TItem): string;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;

    function SignItem(Item: TItem; User: TUser;
      const Password, Meaning, Comment: string): Boolean;
    function IsSigned(ItemId: Integer): Boolean;
    function GetSignature(ItemId: Integer): TSignature;
    function GetSignedItemIds(ProjectID, FolderID: Integer): TList<Integer>;
    function ComputeItemHash(Item: TItem): string;
    function VerifyIntegrity(ItemId: Integer): Boolean;
  end;

function IsItemSignedCheck(Manager: TObjectManager; ItemId: Integer): Boolean;

implementation

uses
  System.Generics.Defaults,
  Aurelius.Criteria.Base,
  unit_LabEntry,
  unit_Protocol,
  unit_AuditHelper,
  Bcrypt,
  unit_TimeHelper;

function IsItemSignedCheck(Manager: TObjectManager; ItemId: Integer): Boolean;
var
  Dic: TSignatureDictionary;
  Sigs: TList<TSignature>;
begin
  Dic := TSignatureDictionary.Create;
  try
    Sigs := Manager.Find<TSignature>
      .Where(Dic.ItemId = ItemId)
      .Take(1)
      .List;
    try
      Result := Sigs.Count > 0;
    finally
      Sigs.Free;
    end;
  finally
    Dic.Free;
  end;
end;

{ TSignatureModel }

constructor TSignatureModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDic := TSignatureDictionary.Create;
end;

destructor TSignatureModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TSignatureModel.BuildItemContent(Item: TItem): string;
var
  SB: TStringBuilder;
  Entry: TLabEntry;
  AFile: unit_Item.TFile;
  Val: unit_Item.TValue;
  Entries: TList<TLabEntry>;
  Files: TList<unit_Item.TFile>;
  Values: TList<unit_Item.TValue>;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    // Item fields
    SB.Append('ITEM|')
      .Append(Item.Id).Append('|')
      .Append(Item.Title).Append('|')
      .Append(Item.Description).Append('|')
      .Append(Ord(Item.Level)).Append('|')
      .Append(Ord(Item.Type_)).Append('|');

    // Entries sorted by Id
    Entries := TList<TLabEntry>.Create;
    try
      for Entry in Item.Entries do
        Entries.Add(Entry);
      Entries.Sort(TComparer<TLabEntry>.Construct(
        function(const A, B: TLabEntry): Integer
        begin
          Result := A.Id - B.Id;
        end));
      for I := 0 to Entries.Count - 1 do
      begin
        Entry := Entries[I];
        SB.Append('ENTRY|')
          .Append(Entry.Id).Append('|');
        if Entry is TProtocol then
        begin
          SB.Append(TProtocol(Entry).Title).Append('|');
          SB.Append(TProtocol(Entry).FormData).Append('|');
        end;
      end;
    finally
      Entries.Free;
    end;

    // Files sorted by Id
    Files := TList<unit_Item.TFile>.Create;
    try
      for AFile in Item.Files do
        Files.Add(AFile);
      Files.Sort(TComparer<unit_Item.TFile>.Construct(
        function(const A, B: unit_Item.TFile): Integer
        begin
          Result := A.Id - B.Id;
        end));
      for I := 0 to Files.Count - 1 do
      begin
        AFile := Files[I];
        SB.Append('FILE|')
          .Append(AFile.Id).Append('|')
          .Append(AFile.Title).Append('|')
          .Append(AFile.Hash).Append('|');
      end;
    finally
      Files.Free;
    end;

    // Values sorted by Id
    Values := TList<unit_Item.TValue>.Create;
    try
      for Val in Item.Values do
        Values.Add(Val);
      Values.Sort(TComparer<unit_Item.TValue>.Construct(
        function(const A, B: unit_Item.TValue): Integer
        begin
          Result := A.Id - B.Id;
        end));
      for I := 0 to Values.Count - 1 do
      begin
        Val := Values[I];
        SB.Append('VALUE|')
          .Append(Val.Id).Append('|')
          .Append(FloatToStr(Val.Value)).Append('|')
          .Append(FloatToStr(Val.Tol)).Append('|');
      end;
    finally
      Values.Free;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TSignatureModel.ComputeItemHash(Item: TItem): string;
var
  Content: string;
begin
  Content := BuildItemContent(Item);
  Result := THashSHA2.GetHashString(Content, SHA256);
end;

function TSignatureModel.SignItem(Item: TItem; User: TUser;
  const Password, Meaning, Comment: string): Boolean;
var
  RehashNeeded: Boolean;
  Sig: TSignature;
  Hash: string;
begin
  Result := False;

  // Verify password
  if not TBCrypt.CheckPassword(Password, User.Password, RehashNeeded) then
    Exit;

  // Check not already signed
  if IsSigned(Item.Id) then
    Exit;

  // Compute hash
  Hash := ComputeItemHash(Item);

  // Create signature record
  Sig := TSignature.Create;
  Sig.ItemId := Item.Id;
  Sig.UserId := User.Id;
  Sig.UserName := User.FirstName + ' ' + User.LastName;
  Sig.SignedDate := UTCNow;
  Sig.Meaning := Meaning;
  Sig.Comment := Comment;
  Sig.ContentHash := Hash;

  FManager.Save(Sig);
  FManager.Flush;

  RecordAudit(FManager, aetSignature, Item.Id, aoCreate, User.Id,
    Format('Signed item "%s" (%s)', [Item.Title, Meaning]));

  Result := True;
end;

function TSignatureModel.IsSigned(ItemId: Integer): Boolean;
begin
  Result := IsItemSignedCheck(FManager, ItemId);
end;

function TSignatureModel.GetSignature(ItemId: Integer): TSignature;
var
  Sigs: TList<TSignature>;
begin
  Result := nil;
  Sigs := FManager.Find<TSignature>
    .Where(FDic.ItemId = ItemId)
    .OrderBy('SignedDate', False)
    .Take(1)
    .List;
  try
    if Sigs.Count > 0 then
      Result := Sigs[0];
  finally
    Sigs.Free;
  end;
end;

function TSignatureModel.GetSignedItemIds(ProjectID, FolderID: Integer): TList<Integer>;
var
  ItemDic: TItemDictionary;
  Items: TList<TItem>;
  Sigs: TList<TSignature>;
  Sig: TSignature;
  Ids: TArray<Variant>;
  Seen: TDictionary<Integer, Boolean>;
  I: Integer;
begin
  Result := TList<Integer>.Create;

  ItemDic := TItemDictionary.Create;
  try
    Items := FManager.Find<TItem>
      .Where((ItemDic.ProjectID = ProjectID) and (ItemDic.FolderID = FolderID)
        and (ItemDic.IsDeleted = False))
      .List;
    try
      if Items.Count = 0 then
        Exit;

      // Collapse the previous N+1 (one SELECT per item) into a single
      // SELECT ... WHERE ItemId IN (...) that returns every signature for
      // the items in the current folder at once.
      SetLength(Ids, Items.Count);
      for I := 0 to Items.Count - 1 do
        Ids[I] := Items[I].Id;

      Sigs := FManager.Find<TSignature>
        .Where(FDic.ItemId._In(Ids))
        .List;
      try
        Seen := TDictionary<Integer, Boolean>.Create;
        try
          for Sig in Sigs do
            if not Seen.ContainsKey(Sig.ItemId) then
            begin
              Seen.Add(Sig.ItemId, True);
              Result.Add(Sig.ItemId);
            end;
        finally
          Seen.Free;
        end;
      finally
        Sigs.Free;
      end;
    finally
      Items.Free;
    end;
  finally
    ItemDic.Free;
  end;
end;

function TSignatureModel.VerifyIntegrity(ItemId: Integer): Boolean;
var
  Sig: TSignature;
  Item: TItem;
  CurrentHash: string;
begin
  Result := False;
  Sig := GetSignature(ItemId);
  if not Assigned(Sig) then Exit;

  Item := FManager.Find<TItem>(ItemId);
  if not Assigned(Item) then Exit;

  CurrentHash := ComputeItemHash(Item);
  Result := SameText(Sig.ContentHash, CurrentHash);
end;

end.
