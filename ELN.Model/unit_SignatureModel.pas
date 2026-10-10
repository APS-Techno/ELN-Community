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
  TSignatureIntegrityState = (sisUnsigned, sisVerified, sisMismatch,
    sisLegacyUnverifiable);

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
    function GetIntegrityState(ItemId: Integer): TSignatureIntegrityState;
    function VerifyIntegrity(ItemId: Integer): Boolean;
  end;

function IsItemSignedCheck(Manager: TObjectManager; ItemId: Integer): Boolean;

implementation

uses
  System.Generics.Defaults,
  System.Math,
  System.NetEncoding,
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

function FramedText(const S: string): string;
begin
  Result := IntToStr(Length(S)) + ':' + S;
end;

function DoubleBits(const Value: Double): string;
var
  Bits: Int64;
begin
  Move(Value, Bits, SizeOf(Bits));
  Result := IntToHex(Bits, 16);
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
    SB.Append('ELN-SIGNATURE-2|ITEM|')
      .Append(IntToStr(Item.Id)).Append('|')
      .Append(FramedText(Item.Title)).Append('|')
      .Append(FramedText(Item.Description)).Append('|')
      .Append(IntToStr(Ord(Item.Level))).Append('|')
      .Append(IntToStr(Ord(Item.Type_))).Append('|');

    Entries := TList<TLabEntry>.Create;
    try
      for Entry in Item.Entries do
        Entries.Add(Entry);
      Entries.Sort(TComparer<TLabEntry>.Construct(
        function(const A, B: TLabEntry): Integer
        begin
          Result := CompareValue(A.Id, B.Id);
        end));
      for I := 0 to Entries.Count - 1 do
      begin
        Entry := Entries[I];
        SB.Append('ENTRY|')
          .Append(IntToStr(Entry.Id)).Append('|');
        if Entry is TProtocol then
        begin
          SB.Append('PROTOCOL|').Append(FramedText(TProtocol(Entry).Title)).Append('|');
          SB.Append(FramedText(TProtocol(Entry).FormData)).Append('|');
        end;
      end;
    finally
      Entries.Free;
    end;

    Files := TList<unit_Item.TFile>.Create;
    try
      for AFile in Item.Files do
        Files.Add(AFile);
      Files.Sort(TComparer<unit_Item.TFile>.Construct(
        function(const A, B: unit_Item.TFile): Integer
        begin
          if A.Id < B.Id then Result := -1
          else if A.Id > B.Id then Result := 1
          else Result := 0;
        end));
      for I := 0 to Files.Count - 1 do
      begin
        AFile := Files[I];
        SB.Append('FILE|')
          .Append(IntToStr(AFile.Id)).Append('|')
          .Append(FramedText(AFile.Title)).Append('|')
          .Append(FramedText(AFile.Hash)).Append('|');
      end;
    finally
      Files.Free;
    end;

    Values := TList<unit_Item.TValue>.Create;
    try
      for Val in Item.Values do
        Values.Add(Val);
      Values.Sort(TComparer<unit_Item.TValue>.Construct(
        function(const A, B: unit_Item.TValue): Integer
        begin
          Result := CompareValue(A.Id, B.Id);
        end));
      for I := 0 to Values.Count - 1 do
      begin
        Val := Values[I];
        SB.Append('VALUE|')
          .Append(IntToStr(Val.Id)).Append('|')
          .Append(DoubleBits(Val.Value)).Append('|')
          .Append(DoubleBits(Val.Tol)).Append('|');
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
  // Prefix plus Base64 fits the existing 64-character column without migration.
  Result := 'v2:' + TNetEncoding.Base64.EncodeBytesToString(
    THashSHA2.GetHashBytes(Content, SHA256));
end;

function TSignatureModel.SignItem(Item: TItem; User: TUser;
  const Password, Meaning, Comment: string): Boolean;
var
  RehashNeeded: Boolean;
  Sig: TSignature;
  Hash: string;
begin
  Result := False;

  if not TBCrypt.CheckPassword(Password, User.Password, RehashNeeded) then
    Exit;

  if IsSigned(Item.Id) then
    Exit;

  Hash := ComputeItemHash(Item);

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
    if FolderID <= 0 then
      Items := FManager.Find<TItem>
        .Where((ItemDic.ProjectID = ProjectID) and (ItemDic.FolderID <= 0)
          and (ItemDic.IsDeleted = False))
        .List
    else
      Items := FManager.Find<TItem>
        .Where((ItemDic.ProjectID = ProjectID) and (ItemDic.FolderID = FolderID)
          and (ItemDic.IsDeleted = False))
        .List;
    try
      if Items.Count = 0 then
        Exit;

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

function TSignatureModel.GetIntegrityState(ItemId: Integer): TSignatureIntegrityState;
var
  Reader: TObjectManager;
  Signatures: TSignatureModel;
  Sig: TSignature;
  Item: TItem;
begin
  // A new identity map also reloads entries/files/values; refreshing only Item
  // would leave previously loaded collections available to the old manager.
  Reader := TObjectManager.Create(FManager.Connection);
  try
    Signatures := TSignatureModel.Create(Reader);
    try
      Sig := Signatures.GetSignature(ItemId);
      if not Assigned(Sig) then
        Exit(sisUnsigned);
      // Old delimiter/locale-dependent hashes cannot prove integrity. Preserve
      // the signature and its write lock, but never silently upgrade its seal.
      if Copy(Sig.ContentHash, 1, 3) <> 'v2:' then
        Exit(sisLegacyUnverifiable);
      Item := Reader.Find<TItem>(ItemId);
      if not Assigned(Item) then
        Exit(sisMismatch);
      if Sig.ContentHash = ComputeItemHash(Item) then
        Result := sisVerified
      else
        Result := sisMismatch;
    finally
      Signatures.Free;
    end;
  finally
    Reader.Free;
  end;
end;

function TSignatureModel.VerifyIntegrity(ItemId: Integer): Boolean;
begin
  Result := GetIntegrityState(ItemId) = sisVerified;
end;

end.
