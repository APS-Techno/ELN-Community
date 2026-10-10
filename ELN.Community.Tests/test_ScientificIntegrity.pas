unit test_ScientificIntegrity;

interface

uses
  System.SysUtils, DUnitX.TestFramework, unit_LocalNotebook, unit_Item;

type
  [TestFixture]
  TScientificIntegrityTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FProjectId: Integer;
    function NewItem: TItem;
    procedure CheckAtomicApplication(const Structure: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SignatureFramesTextFields;
    [Test] procedure SignatureIgnoresDecimalLocale;
    [Test] procedure SignatureReadsCommittedContent;
    [Test] procedure SignatureSortsAdjacentAndWidelySeparatedInt64FileIds;
    [Test] procedure LegacySignatureIsUnverifiableAndUnchanged;
    [Test] procedure VersionedTemplateKeepsHistoricalSchema;
    [Test] procedure UnusedTemplateSavesDraftInPlace;
    [Test] procedure ConcentrationDimensionsCannotMix;
    [Test] procedure FailedPackageLeavesNoTrackedImports;
    [Test] procedure FailedItemTemplateRollsBackTreeAndAudit;
    [Test] procedure FailedFolderTemplateRollsBackTreeAndAudit;
    [Test] procedure WrappedActionTypesRoundTripByName;
    [Test] procedure FolderTemplateUpdatesLoadedHostFolders;
    [Test] procedure FolderTemplateKeepsHostDraftsWhileUpdatingFolders;
    [Test] procedure RootSignatureCacheIncludesLegacyAndCanonicalRows;
    [Test] procedure TemplatesNormalizeNewRootsAndRecognizeLegacyFolders;
    [Test] procedure PackageImportNormalizesNegativeRoot;
  end;

implementation

uses
  System.IOUtils, System.Classes, System.JSON, System.Generics.Collections,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Drivers.Interfaces,
  unit_Project, unit_ProjectModel, unit_ItemTypes, unit_Protocol,
  unit_Template, unit_ProtocolTemplateModel, unit_Signature,
  unit_FileType, unit_ValueType,
  unit_SignatureModel, unit_UnitConverter, unit_PackageImport,
  unit_ExperimentTemplate, unit_ExperimentTemplateModel, unit_ActionType,
  unit_AuditLog;

const
  Password = 'Synthetic-Scientific-Integrity-Only!';

procedure TScientificIntegrityTests.Setup;
var
  Projects: TProjectsModel;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'eln-science-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'attachments'), 'Synthetic', 'Scientist', Password);
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    FProjectId := Projects.AddProject('Scientific fixture', '', FNotebook.Principal).Id;
  finally
    Projects.Free;
  end;
end;

procedure TScientificIntegrityTests.TearDown;
begin
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then TDirectory.Delete(FRoot, True);
end;

function TScientificIntegrityTests.NewItem: TItem;
var
  Id: Integer;
begin
  Result := TItem.Create;
  Result.Title := 'Synthetic specimen';
  Result.ProjectID := FProjectId;
  Result.Level := TItemLevel.Item;
  Result.Type_ := TItemType.Specimen;
  Result.CreatedBy := FNotebook.Principal.Id;
  Result.CreatedDate := Now;
  FNotebook.Manager.Save(Result);
  FNotebook.Manager.Flush;
  Id := Result.Id;
  FNotebook.Manager.Evict(Result);
  Result.Free;
  Result := FNotebook.Manager.Find<TItem>(Id);
end;

procedure TScientificIntegrityTests.SignatureFramesTextFields;
var
  Item: TItem;
  Signatures: TSignatureModel;
  Original: string;
begin
  Item := NewItem;
  Signatures := TSignatureModel.Create(FNotebook.Manager);
  try
    Item.Title := 'a|b';
    Item.Description := 'c';
    Original := Signatures.ComputeItemHash(Item);
    Item.Title := 'a';
    Item.Description := 'b|c';
    Assert.AreNotEqual(Original, Signatures.ComputeItemHash(Item),
      'Moving delimiters between covered fields must change integrity');
  finally
    Signatures.Free;
  end;
end;

procedure TScientificIntegrityTests.SignatureIgnoresDecimalLocale;
var
  Item: TItem;
  Value: unit_Item.TValue;
  Signatures: TSignatureModel;
  Original: string;
  SavedSeparator: Char;
begin
  Item := NewItem;
  Value := unit_Item.TValue.Create;
  Signatures := TSignatureModel.Create(FNotebook.Manager);
  SavedSeparator := FormatSettings.DecimalSeparator;
  try
    Value.Value := 1.5;
    Value.Tol := 0.125;
    Item.Values.Add(Value);
    FormatSettings.DecimalSeparator := '.';
    Original := Signatures.ComputeItemHash(Item);
    FormatSettings.DecimalSeparator := ',';
    Assert.AreEqual(Original, Signatures.ComputeItemHash(Item));
  finally
    FormatSettings.DecimalSeparator := SavedSeparator;
    Item.Values.Remove(Value);
    Value.Free;
    Signatures.Free;
  end;
end;

procedure TScientificIntegrityTests.SignatureSortsAdjacentAndWidelySeparatedInt64FileIds;
var
  Item: TItem;
  A, B, C: unit_Item.TFile;
  Signatures: TSignatureModel;
  Original: string;
begin
  Item := NewItem;
  A := unit_Item.TFile.Create;
  B := unit_Item.TFile.Create;
  C := unit_Item.TFile.Create;
  Signatures := TSignatureModel.Create(FNotebook.Manager);
  try
    A.Id := 9007199254740993;
    B.Id := 2147483648;
    C.Id := 9007199254740992;
    A.Title := 'a'; B.Title := 'b'; C.Title := 'c';
    Item.Files.Add(A);
    Item.Files.Add(B);
    Item.Files.Add(C);
    Original := Signatures.ComputeItemHash(Item);
    Item.Files.Exchange(0, 2);
    Assert.AreEqual(Original, Signatures.ComputeItemHash(Item),
      'File enumeration order cannot alter a canonical signature');
  finally
    Item.Files.Remove(A);
    Item.Files.Remove(B);
    Item.Files.Remove(C);
    C.Free;
    B.Free;
    A.Free;
    Signatures.Free;
  end;
end;

procedure TScientificIntegrityTests.SignatureReadsCommittedContent;
var
  Item: TItem;
  Protocol: TProtocol;
  AFile: unit_Item.TFile;
  FileType: TFileType;
  Value: unit_Item.TValue;
  ValueType: TValueType;
  Other: TObjectManager;
  Signatures: TSignatureModel;
begin
  Item := NewItem;
  Protocol := TProtocol.Create;
  Protocol.Title := 'Original entry';
  Protocol.FormData := '{}';
  Protocol.CreatedDate := Now;
  Item.Entries.Add(Protocol);
  FileType := TFileType.Create;
  FileType.Ext := '.txt';
  FileType.CreatedDate := Now;
  FNotebook.Manager.Save(FileType);
  ValueType := TValueType.Create;
  ValueType.Symbol := 'T';
  ValueType.Title := 'Temperature';
  ValueType.Units := 'K';
  ValueType.CreatedDate := Now;
  FNotebook.Manager.Save(ValueType);
  AFile := unit_Item.TFile.Create;
  AFile.Title := 'Original attachment';
  AFile.Hash := 'original-hash';
  AFile.FileType := FileType;
  AFile.Item := Item;
  AFile.CreatedDate := Now;
  Item.Files.Add(AFile);
  Value := unit_Item.TValue.Create;
  Value.ValueType := ValueType;
  Value.Item := Item;
  Value.Value := 1.5;
  Value.CreatedDate := Now;
  Item.Values.Add(Value);
  FNotebook.Manager.Flush;
  Signatures := TSignatureModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Signatures.SignItem(Item, FNotebook.Principal, Password, 'Authorship', ''));
    Assert.IsTrue(Signatures.VerifyIntegrity(Item.Id));
    Other := TObjectManager.Create(FNotebook.Connection);
    try
      Other.Find<TItem>(Item.Id).Description := 'Changed in another manager';
      Other.Flush;
      Assert.IsFalse(Signatures.VerifyIntegrity(Item.Id), 'Cached item cannot verify external change');
      Other.Find<TItem>(Item.Id).Description := Item.Description;
      Other.Flush;
      Assert.IsTrue(Signatures.VerifyIntegrity(Item.Id));
      Other.Find<TProtocol>(Protocol.Id).FormData := '{"result":42}';
      Other.Flush;
      Assert.IsFalse(Signatures.VerifyIntegrity(Item.Id), 'Cached collection cannot hide external change');
      Other.Find<TProtocol>(Protocol.Id).FormData := Protocol.FormData;
      Other.Flush;
      Assert.IsTrue(Signatures.VerifyIntegrity(Item.Id));
      Other.Find<unit_Item.TFile>(AFile.Id).Hash := 'changed-hash';
      Other.Flush;
      Assert.IsFalse(Signatures.VerifyIntegrity(Item.Id), 'Cached file cannot hide changed bytes');
      Other.Find<unit_Item.TFile>(AFile.Id).Hash := AFile.Hash;
      Other.Flush;
      Assert.IsTrue(Signatures.VerifyIntegrity(Item.Id));
      Other.Find<unit_Item.TValue>(Value.Id).Value := 2.5;
      Other.Flush;
      Assert.IsFalse(Signatures.VerifyIntegrity(Item.Id), 'Cached value cannot hide changed result');
    finally
      Other.Free;
    end;
  finally
    Signatures.Free;
  end;
end;

procedure TScientificIntegrityTests.LegacySignatureIsUnverifiableAndUnchanged;
var
  Item: TItem;
  Sig: TSignature;
  Signatures: TSignatureModel;
  Original: string;
  Observer: TObjectManager;
begin
  Item := NewItem;
  Original := StringOfChar('a', 64);
  Sig := TSignature.Create;
  Sig.ItemId := Item.Id;
  Sig.UserId := FNotebook.Principal.Id;
  Sig.UserName := 'Synthetic Scientist';
  Sig.SignedDate := Now;
  Sig.Meaning := 'Authorship';
  Sig.ContentHash := Original;
  FNotebook.Manager.Save(Sig);
  FNotebook.Manager.Flush;
  Signatures := TSignatureModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Signatures.GetIntegrityState(Item.Id) = sisLegacyUnverifiable);
    Assert.IsFalse(Signatures.VerifyIntegrity(Item.Id));
    Assert.IsTrue(Signatures.IsSigned(Item.Id), 'Legacy signature still locks mutations');
    Assert.AreEqual(Original, Sig.ContentHash, 'Verification must not reseal legacy records');
    Observer := TObjectManager.Create(FNotebook.Connection);
    try
      Assert.AreEqual(Original, Observer.Find<TSignature>(Sig.Id).ContentHash,
        'The committed legacy signature must remain unchanged');
    finally
      Observer.Free;
    end;
  finally
    Signatures.Free;
  end;
end;

procedure TScientificIntegrityTests.VersionedTemplateKeepsHistoricalSchema;
var
  Templates: TTemplateModel;
  Original, Draft, Saved: TTemplate;
  Item: TItem;
  Protocol: TProtocol;
  Observer: TObjectManager;
begin
  Templates := TTemplateModel.Create(FNotebook.Manager);
  try
    Original := TTemplate.Create;
    Original.Name := 'History';
    Original.FormSchema := '{"sections":[{"title":"Old field"}]}';
    Templates.SaveTemplate(Original);
    Item := NewItem;
    Protocol := TProtocol.Create;
    Protocol.Title := 'Historical result';
    Protocol.TemplateId := Original.Id;
    Protocol.CreatedDate := Now;
    Item.Entries.Add(Protocol);
    FNotebook.Manager.Flush;
    Draft := Templates.CreateDraft(Original.Id);
    try
      Draft.FormSchema := '{"sections":[{"title":"New field"}]}';
      Saved := Templates.SaveOrVersion(Original.Id, Draft);
      Assert.AreNotEqual(Original.Id, Saved.Id);
      Observer := TObjectManager.Create(FNotebook.Connection);
      try
        Assert.AreEqual('{"sections":[{"title":"Old field"}]}',
          Observer.Find<TTemplate>(Original.Id).FormSchema);
        Assert.AreEqual(Draft.FormSchema, Observer.Find<TTemplate>(Saved.Id).FormSchema);
        Assert.AreEqual(Original.Id, Observer.Find<TProtocol>(Protocol.Id).TemplateId.Value);
      finally
        Observer.Free;
      end;
    finally
      Draft.Free;
    end;
  finally
    Templates.Free;
  end;
end;

procedure TScientificIntegrityTests.UnusedTemplateSavesDraftInPlace;
var
  Templates: TTemplateModel;
  Original, Draft, Saved: TTemplate;
begin
  Templates := TTemplateModel.Create(FNotebook.Manager);
  try
    Original := TTemplate.Create;
    Original.Name := 'Unused';
    Original.FormSchema := '{}';
    Templates.SaveTemplate(Original);
    Draft := Templates.CreateDraft(Original.Id);
    try
      Draft.FormSchema := '{"sections":[]}';
      Saved := Templates.SaveOrVersion(Original.Id, Draft);
      Assert.AreEqual(Original.Id, Saved.Id);
      Assert.AreEqual(Draft.FormSchema, Saved.FormSchema);
    finally
      Draft.Free;
    end;
  finally
    Templates.Free;
  end;
end;

procedure TScientificIntegrityTests.ConcentrationDimensionsCannotMix;
var
  Value: Double;
begin
  Assert.WillRaise(procedure begin TUnitConverter.Convert(1, 'mg/mL', 'mol/L'); end,
    EArgumentException);
  Assert.IsFalse(ParseSIInput('1 mg/mL', 'mol/L', Value));
  Assert.AreEqual<Double>(1, TUnitConverter.Convert(1, 'mg/mL', 'g/L'));
  Assert.AreEqual<Double>(1000, TUnitConverter.Convert(1, 'mg/mL', 'mg/L'));
  Assert.AreEqual<Double>(1000, TUnitConverter.Convert(1, 'mol/L', 'mmol/L'));
end;

procedure TScientificIntegrityTests.FailedPackageLeavesNoTrackedImports;
var
  Importer: TELNPackageImporter;
  Outcome: TELNPackageImportResult;
  Existing: TItem;
  Path: string;
  RolledBackId: Integer;
  Observer: TObjectManager;
begin
  Existing := NewItem;
  RolledBackId := Existing.Id + 1;
  Existing.Description := 'Unsaved host draft';
  Path := TPath.Combine(FRoot, 'test.elnpkg');
  Importer := TELNPackageImporter.Create(FNotebook.Manager);
  try
    System.IOUtils.TFile.WriteAllText(Path,
      '{"items":[{"title":"First import","level":1,"type":0},42]}', TEncoding.UTF8);
    Outcome := Importer.ImportPackage(Path, FProjectId, 0, FNotebook.Principal.Id);
    Assert.IsFalse(Outcome.Success);
    Assert.IsNull(FNotebook.Manager.Find<TItem>(RolledBackId), 'No ghost from rolled-back first item');
    Assert.AreEqual('Unsaved host draft', Existing.Description);
    Observer := TObjectManager.Create(FNotebook.Connection);
    try
      Assert.AreEqual('', Observer.Find<TItem>(Existing.Id).Description);
    finally
      Observer.Free;
    end;
    System.IOUtils.TFile.WriteAllText(Path,
      '{"items":[{"title":"Successful retry","level":1,"type":0}]}', TEncoding.UTF8);
    Outcome := Importer.ImportPackage(Path, FProjectId, 0, FNotebook.Principal.Id);
    Assert.IsTrue(Outcome.Success, Outcome.ErrorMessage);
    Assert.AreEqual('Successful retry', FNotebook.Manager.Find<TItem>(RolledBackId).Title);
  finally
    Importer.Free;
  end;
end;

procedure TScientificIntegrityTests.FolderTemplateUpdatesLoadedHostFolders;
var
  Templates: TExperimentTemplateModel;
  Template: TExperimentTemplate;
  Project: TProject;
  Created: TItem;
begin
  Templates := TExperimentTemplateModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Template := Templates.AddTemplate('Visible folders', '', '',
      '{"folder":{"title":"Wiki","children":[{"folder":{"title":"Goals",'+
      '"children":[{"item":{"title":"Readme"}}]}}]}}', FNotebook.Principal.Id);
    Project := FNotebook.Manager.Find<TProject>(FProjectId);
    Assert.AreEqual(0, Project.Folders.Count, 'Preload the collection used by the tree');
    Created := Templates.ApplyTemplate(Template.Id, FProjectId, 0, FNotebook.Principal.Id);
    Assert.AreEqual(2, Project.Folders.Count,
      'The already-loaded host project must expose committed template folders');
    Assert.IsNotNull(Project.GetFolder(Created.FolderID));
    Assert.AreEqual('Goals', Project.GetFolder(Created.FolderID).Title);
  finally
    Templates.Free;
  end;
end;

procedure TScientificIntegrityTests.FolderTemplateKeepsHostDraftsWhileUpdatingFolders;
var
  Templates: TExperimentTemplateModel;
  Projects: TProjectsModel;
  Template: TExperimentTemplate;
  Project: TProject;
  ExistingFolder: TFolder;
  DraftItem: TItem;
  Observer: TObjectManager;
begin
  Templates := TExperimentTemplateModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Projects.AddFolder('Existing folder', '', FProjectId, 0);
    Template := Templates.AddTemplate('Visible folders', '', '',
      '{"folder":{"title":"Wiki","children":[{"item":{"title":"Readme"}}]}}',
      FNotebook.Principal.Id);
    DraftItem := NewItem;
    Project := FNotebook.Manager.Find<TProject>(FProjectId);
    Assert.AreEqual(1, Project.Folders.Count);
    ExistingFolder := Project.Folders[0];
    Project.Description := 'Unflushed project draft';
    ExistingFolder.Description := 'Unflushed folder draft';
    DraftItem.Description := 'Unflushed item draft';
    Templates.ApplyTemplate(Template.Id, FProjectId, 0, FNotebook.Principal.Id);
    Assert.AreEqual(2, Project.Folders.Count);
    Assert.AreEqual('Unflushed project draft', Project.Description);
    Assert.AreEqual('Unflushed folder draft', ExistingFolder.Description);
    Assert.AreEqual('Unflushed item draft', DraftItem.Description);
    Observer := TObjectManager.Create(FNotebook.Connection);
    try
      Assert.AreEqual(Project.Version, Observer.Find<TProject>(FProjectId).Version,
        'Host version must follow the committed folder insertion');
      Assert.AreEqual('', Observer.Find<TProject>(FProjectId).Description);
      Assert.AreEqual('', Observer.Find<TFolder>(ExistingFolder.Id).Description);
      Assert.AreEqual('', Observer.Find<TItem>(DraftItem.Id).Description);
      FNotebook.Manager.Flush;
      Observer.Refresh(Observer.Find<TProject>(FProjectId));
      Observer.Refresh(Observer.Find<TFolder>(ExistingFolder.Id));
      Observer.Refresh(Observer.Find<TItem>(DraftItem.Id));
      Assert.AreEqual('Unflushed project draft', Observer.Find<TProject>(FProjectId).Description);
      Assert.AreEqual('Unflushed folder draft', Observer.Find<TFolder>(ExistingFolder.Id).Description);
      Assert.AreEqual('Unflushed item draft', Observer.Find<TItem>(DraftItem.Id).Description);
    finally
      Observer.Free;
    end;
  finally
    Projects.Free;
    Templates.Free;
  end;
end;

procedure TScientificIntegrityTests.CheckAtomicApplication(const Structure: string);
var
  Templates: TExperimentTemplateModel;
  Template: TExperimentTemplate;
  Statement: IDBStatement;
  Observer: TObjectManager;
  Items: TList<TItem>;
  Folders: TList<TFolder>;
  Audits: TList<TAuditLog>;
  AuditCount: Integer;
begin
  Templates := TExperimentTemplateModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Template := Templates.AddTemplate('Atomic tree', '', '', Structure, FNotebook.Principal.Id);
    Audits := FNotebook.Manager.Find<TAuditLog>.List;
    try AuditCount := Audits.Count; finally Audits.Free; end;
    Statement := FNotebook.Connection.CreateStatement;
    Statement.SetSQLCommand('CREATE TRIGGER FailSecondChild BEFORE INSERT ON Items ' +
      'WHEN NEW.Title = ''Reject child'' BEGIN SELECT RAISE(ABORT, ''synthetic child failure''); END');
    Statement.Execute;
    try
      Assert.WillRaise(procedure begin
        Templates.ApplyTemplate(Template.Id, FProjectId, 0, FNotebook.Principal.Id);
      end);
    finally
      Statement := FNotebook.Connection.CreateStatement;
      Statement.SetSQLCommand('DROP TRIGGER FailSecondChild');
      Statement.Execute;
      Statement := nil;
    end;
    Observer := TObjectManager.Create(FNotebook.Connection);
    try
      Items := Observer.Find<TItem>.List;
      try Assert.AreEqual(0, Items.Count); finally Items.Free; end;
      Folders := Observer.Find<TFolder>.List;
      try Assert.AreEqual(0, Folders.Count); finally Folders.Free; end;
      Audits := Observer.Find<TAuditLog>.List;
      try Assert.AreEqual(AuditCount, Audits.Count); finally Audits.Free; end;
    finally
      Observer.Free;
    end;
    Assert.IsNotNull(Templates.ApplyTemplate(Template.Id, FProjectId, 0,
      FNotebook.Principal.Id), 'Same-session retry succeeds without ghost identities');
  finally
    Templates.Free;
  end;
end;

procedure TScientificIntegrityTests.FailedItemTemplateRollsBackTreeAndAudit;
begin
  CheckAtomicApplication('{"proc":{"title":"Root","children":[' +
    '{"item":{"title":"First child"}},{"item":{"title":"Reject child"}}]}}');
end;

procedure TScientificIntegrityTests.FailedFolderTemplateRollsBackTreeAndAudit;
begin
  CheckAtomicApplication('{"folder":{"title":"Folder root","children":[' +
    '{"item":{"title":"First child"}},{"item":{"title":"Reject child"}}]}}');
end;

procedure TScientificIntegrityTests.WrappedActionTypesRoundTripByName;
var
  Templates: TExperimentTemplateModel;
  Template, Imported: TExperimentTemplate;
  Action, Replacement: TActionType;
  Path, Warnings: string;
  Applied: TItem;
  Children: TList<TItem>;
begin
  Action := TActionType.Create;
  Action.Title := 'Portable action';
  FNotebook.Manager.Save(Action);
  FNotebook.Manager.Flush;
  Templates := TExperimentTemplateModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Template := Templates.AddTemplate('Wrapped tree', '', '',
      '{"folder":{"title":"Portable folder","children":[{"proc":{"title":"Wrapped proc",' +
      '"actionTypeId":' + IntToStr(Action.Id) + ',"children":[{"item":{"title":"Wrapped item",' +
      '"actionTypeId":' + IntToStr(Action.Id) + ',"children":[{"title":"Bare child",' +
      '"actionTypeId":' + IntToStr(Action.Id) + '}]}}]}},' +
      '{"folder":{"title":"Nested folder","children":[{"item":{"title":"Nested item",' +
      '"actionTypeId":' + IntToStr(Action.Id) + '}}]}}]}}', FNotebook.Principal.Id);
    Path := TPath.Combine(FRoot, 'portable.elntemplate');
    Templates.ExportTemplateToFile(Template.Id, Path);
    Action.Title := 'Unrelated source ID';
    Replacement := TActionType.Create;
    Replacement.Title := 'Portable action';
    FNotebook.Manager.Save(Replacement);
    FNotebook.Manager.Flush;
    Imported := Templates.ImportTemplateFromFile(Path, FNotebook.Principal.Id, Warnings);
    Assert.AreEqual('', Warnings);
    Applied := Templates.ApplyTemplate(Imported.Id, FProjectId, 0, FNotebook.Principal.Id);
    Assert.IsNotNull(Applied);
    Children := FNotebook.Manager.Find<TItem>.List;
    try
      Assert.AreEqual(4, Children.Count);
      for Applied in Children do
      begin
        Assert.IsNotNull(Applied.ActionType);
        Assert.AreEqual(Replacement.Id, Applied.ActionType.Id, 'Resolve all wrappers by local name');
      end;
    finally
      Children.Free;
    end;
    Replacement.Title := 'No longer matches exported action';
    FNotebook.Manager.Flush;
    Templates.ImportTemplateFromFile(Path, FNotebook.Principal.Id, Warnings);
    Assert.IsTrue(Warnings.Contains('Portable action'),
      'Unresolved names below wrappers must be reported to the importing user');
  finally
    Templates.Free;
  end;
end;

procedure TScientificIntegrityTests.RootSignatureCacheIncludesLegacyAndCanonicalRows;
var
  LegacyRoot, CanonicalRoot, Nested, Deleted: TItem;
  Signatures: TSignatureModel;
  Ids: TList<Integer>;
  RootContext: Integer;

  procedure AddLegacySignature(Item: TItem);
  var
    Signature: TSignature;
  begin
    Signature := TSignature.Create;
    Signature.ItemId := Item.Id;
    Signature.UserId := FNotebook.Principal.Id;
    Signature.UserName := 'Historical scientist';
    Signature.SignedDate := Now;
    Signature.Meaning := 'Authorship';
    Signature.ContentHash := StringOfChar('a', 64);
    FNotebook.Manager.Save(Signature);
  end;

begin
  LegacyRoot := NewItem;
  LegacyRoot.FolderID := -1;
  CanonicalRoot := NewItem;
  CanonicalRoot.FolderID := 0;
  Nested := NewItem;
  Nested.FolderID := 7;
  Deleted := NewItem;
  Deleted.FolderID := 0;
  Deleted.IsDeleted := True;
  AddLegacySignature(LegacyRoot);
  AddLegacySignature(CanonicalRoot);
  AddLegacySignature(Nested);
  AddLegacySignature(Deleted);
  FNotebook.Manager.Flush;
  Signatures := TSignatureModel.Create(FNotebook.Manager);
  try
    for RootContext := -1 to 0 do
    begin
      Ids := Signatures.GetSignedItemIds(FProjectId, RootContext);
      try
        Assert.AreEqual(2, Ids.Count);
        Assert.IsTrue(Ids.Contains(LegacyRoot.Id));
        Assert.IsTrue(Ids.Contains(CanonicalRoot.Id));
      finally
        Ids.Free;
      end;
    end;
    Ids := Signatures.GetSignedItemIds(FProjectId, 7);
    try
      Assert.AreEqual(1, Ids.Count);
      Assert.IsTrue(Ids.Contains(Nested.Id));
    finally
      Ids.Free;
    end;
    Assert.IsTrue(Signatures.IsSigned(LegacyRoot.Id));
    Assert.IsTrue(Signatures.GetIntegrityState(LegacyRoot.Id) = sisLegacyUnverifiable);
    Assert.AreEqual(-1, LegacyRoot.FolderID, 'Reading root signatures must not migrate rows');
  finally
    Signatures.Free;
  end;
end;

procedure TScientificIntegrityTests.TemplatesNormalizeNewRootsAndRecognizeLegacyFolders;
var
  Projects: TProjectsModel;
  Templates: TExperimentTemplateModel;
  FolderTemplate, ItemTemplate: TExperimentTemplate;
  Project: TProject;
  Existing: TFolder;
  Created: TItem;
  Children: TList<TItem>;
begin
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  Templates := TExperimentTemplateModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Projects.AddFolder('Wiki', '', FProjectId, 0);
    Project := FNotebook.Manager.Find<TProject>(FProjectId);
    Existing := Project.Folders[0];
    Existing.ParentFolderID := -1;
    FNotebook.Manager.Flush;
    FolderTemplate := Templates.AddTemplate('Wiki', '', '',
      '{"folder":{"title":"Wiki","children":[{"item":{"title":"Readme"}}]}}',
      FNotebook.Principal.Id);
    Assert.WillRaise(procedure begin
      Templates.ApplyTemplate(FolderTemplate.Id, FProjectId, 0, FNotebook.Principal.Id);
    end, EWikiFolderExists);
    Created := Templates.ApplyTemplate(FolderTemplate.Id, FProjectId, -1,
      FNotebook.Principal.Id, 'New Wiki');
    Assert.AreEqual(0, Project.GetFolder(Created.FolderID).ParentFolderID);
    Assert.AreEqual(-1, Existing.ParentFolderID, 'Legacy folders remain unchanged');
    ItemTemplate := Templates.AddTemplate('Root procedure', '', '',
      '{"proc":{"title":"Root procedure","children":[{"item":{"title":"Child"}}]}}',
      FNotebook.Principal.Id);
    Created := Templates.ApplyTemplate(ItemTemplate.Id, FProjectId, -1, FNotebook.Principal.Id);
    Assert.AreEqual(0, Created.FolderID);
    Children := FNotebook.Manager.Find<TItem>.Where(Linq['ParentID'] = Created.Id).List;
    try
      Assert.AreEqual(1, Children.Count);
      Assert.AreEqual(0, Children[0].FolderID);
    finally
      Children.Free;
    end;
  finally
    Templates.Free;
    Projects.Free;
  end;
end;

procedure TScientificIntegrityTests.PackageImportNormalizesNegativeRoot;
var
  Importer: TELNPackageImporter;
  Outcome: TELNPackageImportResult;
  Path: string;
  Items: TList<TItem>;
begin
  Path := TPath.Combine(FRoot, 'root.elnpkg');
  System.IOUtils.TFile.WriteAllText(Path,
    '{"items":[{"title":"Imported at root","level":1,"type":0}]}', TEncoding.UTF8);
  Importer := TELNPackageImporter.Create(FNotebook.Manager);
  try
    Outcome := Importer.ImportPackage(Path, FProjectId, -1, FNotebook.Principal.Id);
    Assert.IsTrue(Outcome.Success, Outcome.ErrorMessage);
    Items := FNotebook.Manager.Find<TItem>.List;
    try
      Assert.AreEqual(1, Items.Count);
      Assert.AreEqual(0, Items[0].FolderID);
    finally
      Items.Free;
    end;
  finally
    Importer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TScientificIntegrityTests);

end.
