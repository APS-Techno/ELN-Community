unit unit_ToolsWiki;

interface

uses
  unit_MCPTools;

procedure RegisterWikiTools(Registry: TToolRegistry);

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.JSON, System.StrUtils,
  System.IOUtils, System.Classes, System.Generics.Collections,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq, Aurelius.Drivers.Interfaces,
  unit_Project, unit_Item, unit_ItemTypes, unit_FileType,
  unit_ELNDB_Dictionary,
  unit_ConflictHandler, unit_AuditLog, unit_AuditHelper,
  unit_TimeHelper, unit_FilePaths,
  unit_SignatureModel,
  unit_ToolsWrite, unit_ToolScope, unit_ToolHelpers, unit_MCPDiag;


const
  VALID_WIKI_SECTIONS: array[0..4] of string =
    ('Goals', 'Ideas', 'Literature', 'Analysis', 'References');

function NormaliseSection(const ASection: string; out Canonical: string): Boolean;
var
  I: Integer;
begin
  for I := Low(VALID_WIKI_SECTIONS) to High(VALID_WIKI_SECTIONS) do
    if SameText(Trim(ASection), VALID_WIKI_SECTIONS[I]) then
    begin
      Canonical := VALID_WIKI_SECTIONS[I];
      Exit(True);
    end;
  Result := False;
end;

procedure RequireValidSection(const ASection: string; out Canonical: string);
begin
  if not NormaliseSection(ASection, Canonical) then
    raise Exception.CreateFmt(
      'Invalid section "%s". Valid sections: %s, %s, %s, %s, %s.',
      [ASection,
       VALID_WIKI_SECTIONS[0], VALID_WIKI_SECTIONS[1], VALID_WIKI_SECTIONS[2],
       VALID_WIKI_SECTIONS[3], VALID_WIKI_SECTIONS[4]]);
end;


// Case-insensitive title match: a pre-existing lower-case "wiki" folder is
// reused rather than duplicated. Section folders follow the same rule for
// consistency.
function FindOrCreateFolder(const Context: TToolContext;
  ProjectId: Integer; ParentFolderId: Integer; const Title: string): Integer;
var
  Project: TProject;
  Folder: TFolder;
begin
  Project := Context.Manager.Find<TProject>(ProjectId);
  if not Assigned(Project) then
    raise Exception.CreateFmt('Project not found: %d', [ProjectId]);

  for Folder in Project.Folders do
    if (Folder.ParentFolderID = ParentFolderId) and SameText(Folder.Title, Title) then
      Exit(Folder.Id);

  Folder := TFolder.Create;
  Folder.Title := Title;
  Folder.ParentFolderID := ParentFolderId;
  Folder.CreatedDate := UTCNow;
  Folder.CreatedBy := Context.User.Id;
  Folder.Expanded := True;
  Project.Folders.Add(Folder);
  Context.Manager.SaveOrUpdate(Project);
  TConflictHandler.SafeFlush(Context.Manager);
  RecordAudit(Context.Manager, aetFolder, Folder.Id, aoCreate,
    Context.User.Id,
    Format('MCP: Wiki - created folder "%s" in project "%s"',
      [Title, Project.Title]));
  Result := Folder.Id;
end;


function SlugifyTitle(const Title: string): string;
var
  I: Integer;
  Ch: Char;
  LastDash: Boolean;
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    LastDash := True;  // suppresses leading dash
    for I := 1 to Length(Title) do
    begin
      Ch := Title[I];
      if CharInSet(Ch, ['A'..'Z']) then
        Ch := Chr(Ord(Ch) + 32);
      if CharInSet(Ch, ['a'..'z', '0'..'9']) then
      begin
        Sb.Append(Ch);
        LastDash := False;
      end
      else if not LastDash then
      begin
        Sb.Append('-');
        LastDash := True;
      end;
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
  while (Length(Result) > 0) and (Result[Length(Result)] = '-') do
    SetLength(Result, Length(Result) - 1);
  if Length(Result) > 80 then
    SetLength(Result, 80);
  if Result = '' then
    Result := 'page';
end;


function MakeWikiCreatePageSchema: TJSONObject;
var
  Props, P, ItemsSchema: TJSONObject;
  Req, Sections: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Project ID that will host the wiki page');
  Props.AddPair('project_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'Wiki section (Goals | Ideas | Literature | Analysis | References). Case-insensitive on input.');
  Sections := TJSONArray.Create;
  for I := Low(VALID_WIKI_SECTIONS) to High(VALID_WIKI_SECTIONS) do
    Sections.Add(VALID_WIKI_SECTIONS[I]);
  P.AddPair('enum', Sections);
  Props.AddPair('section', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Page title (also the ELN item title)');
  Props.AddPair('title', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'Markdown body (CommonMark + GFM). Stored as {slug(title)}.md attached to the item.');
  Props.AddPair('body_md', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'array');
  P.AddPair('description',
    'Optional attachment paths (figures, PDFs). Each must be under the MCP upload root.');
  ItemsSchema := TJSONObject.Create;
  ItemsSchema.AddPair('type', 'string');
  ItemsSchema.AddPair('description', 'Absolute path to a file under the MCP upload root');
  P.AddPair('items', ItemsSchema);
  Props.AddPair('attachments', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('project_id');
  Req.Add('section');
  Req.Add('title');
  Req.Add('body_md');
  Result.AddPair('required', Req);
end;

function MakeWikiUpdatePageSchema: TJSONObject;
var
  Props, P, ItemsSchema: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'ID of the wiki page item to update');
  Props.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'New markdown body. Replaces the existing .md file in place (same filename). ' +
    'Optional, but at least one of body_md or attachments must be provided.');
  Props.AddPair('body_md', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'array');
  P.AddPair('description',
    'Optional attachment paths to add. Existing attachments are never removed.');
  ItemsSchema := TJSONObject.Create;
  ItemsSchema.AddPair('type', 'string');
  ItemsSchema.AddPair('description', 'Absolute path to a file under the MCP upload root');
  P.AddPair('items', ItemsSchema);
  Props.AddPair('attachments', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Result.AddPair('required', Req);
end;


function FindExistingPageItem(const Context: TToolContext;
  ProjectId, FolderId: Integer; const Title: string): TItem;
var
  ItemDic: TItemDictionary;
  Items: TList<TItem>;
  I: TItem;
begin
  Result := nil;
  ItemDic := TItemDictionary.Create;
  try
    Items := Context.Manager.Find<TItem>
      .Where((ItemDic.ProjectID = ProjectId)
         and (ItemDic.FolderID  = FolderId)
         and (ItemDic.IsDeleted = False))
      .List;
    try
      for I in Items do
        if SameText(I.Title, Title) then
          Exit(I);
    finally
      Items.Free;
    end;
  finally
    ItemDic.Free;
  end;
end;

function ResolveFileTypeByExt(const Context: TToolContext;
  const Path: string): TFileType;
var
  Ext: string;
  Dic: TFileTypeDictionary;
  Types: TList<TFileType>;
begin
  Ext := LowerCase(ExtractFileExt(Path));
  if Ext = '' then
    raise Exception.CreateFmt('Attachment has no extension: %s', [Path]);
  Dic := TFileTypeDictionary.Create;
  try
    Types := Context.Manager.Find<TFileType>.Where(Dic.Ext = Ext).Take(1).List;
    try
      if Types.Count = 0 then
        raise Exception.CreateFmt(
          'No FileTypes row for extension "%s". Add it via the ELN admin ' +
          'UI or by inserting into the FileTypes table.', [Ext]);
      Result := Types[0];
    finally
      Types.Free;
    end;
  finally
    Dic.Free;
  end;
end;

function ResolveMarkdownFileType(const Context: TToolContext): TFileType;
var
  Dic: TFileTypeDictionary;
  Types: TList<TFileType>;
begin
  Dic := TFileTypeDictionary.Create;
  try
    Types := Context.Manager.Find<TFileType>
      .Where(Dic.Ext = '.md')
      .Take(1)
      .List;
    try
      if Types.Count = 0 then
        raise Exception.Create(
          'No FileTypes row for ".md". Insert one and restart the MCP server.');
      Result := Types[0];
    finally
      Types.Free;
    end;
  finally
    Dic.Free;
  end;
end;

type
  TWikiAttachment = record
    Path, Title: string;
    FileTypeId: Integer;
  end;

function ResolveAttachments(const Context: TToolContext;
  const Params: TJSONObject): TArray<TWikiAttachment>;
var
  Value: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := nil;
  if Params = nil then
    Exit;
  Value := Params.FindValue('attachments');
  if not (Value is TJSONArray) then
    Exit;
  Arr := TJSONArray(Value);
  SetLength(Result, Arr.Count);
  for I := 0 to Arr.Count - 1 do
  begin
    Result[I].Path := (Arr.Items[I] as TJSONString).Value;
    CheckUploadPathAllowed(Context, Result[I].Path);
    if not FileExists(Result[I].Path) then
      raise Exception.CreateFmt('Attachment not found: %s', [Result[I].Path]);
    Result[I].FileTypeId := ResolveFileTypeByExt(Context, Result[I].Path).Id;
    Result[I].Title := TPath.GetFileNameWithoutExtension(Result[I].Path);
  end;
end;

// Adds the file row inside the caller's open transaction, then stores the
// bytes and records their path in Written so a rollback can delete them.
function StageFileOnItem(const Context: TToolContext; Manager: TObjectManager;
  Item: TItem; const SourcePath: string; FileType: TFileType;
  const Title: string; Written: TStrings): TFile;
var
  Project: TProject;
  Path: string;
begin
  Result := TFile.Create;
  Result.FileType := FileType;
  Result.Title := Title;
  Result.Hash := ComputeFileMD5(SourcePath);
  Result.CreatedDate := UTCNow;
  Result.CreatedBy := Context.User.Id;
  Result.Item := Item;
  Item.Files.Add(Result);
  Manager.Update(Item);
  if not TConflictHandler.SafeFlush(Manager) then
    raise Exception.Create('The file record could not be saved.');
  Project := Manager.Find<TProject>(Item.ProjectID);
  Path := AttachmentRelativePath(Project.FileFolder, Item.FolderName, Result.FullName);
  Context.Storage.CopyIn(SourcePath, Path);
  Written.Add(Path);
end;

procedure StageAttachments(const Context: TToolContext; Manager: TObjectManager;
  Item: TItem; const Attachments: TArray<TWikiAttachment>; Written: TStrings;
  Response: TJSONObject);
var
  Attachment: TWikiAttachment;
  F: TFile;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  if Length(Attachments) = 0 then
    Exit;
  Arr := TJSONArray.Create;
  Response.AddPair('attachments', Arr);
  for Attachment in Attachments do
  begin
    F := StageFileOnItem(Context, Manager, Item, Attachment.Path,
      Manager.Find<TFileType>(Attachment.FileTypeId), Attachment.Title, Written);
    RecordAudit(Manager, aetFile, F.Id, aoCreate, Context.User.Id,
      'MCP: Added file "' + Attachment.Title + '" to item "' + Item.Title + '"');
    Obj := TJSONObject.Create;
    Obj.AddPair('id',        TJSONNumber.Create(F.Id));
    Obj.AddPair('title',     F.Title);
    Obj.AddPair('full_name', F.FullName);
    Arr.AddElement(Obj);
  end;
end;

procedure DeleteWrittenPaths(const Context: TToolContext; Written: TStrings;
  var Errors: string);
var
  Path: string;
begin
  for Path in Written do
    try
      Context.Storage.DeleteFile(Path);
    except
      on E: Exception do
        Errors := Errors + Format('; could not delete stored bytes %s: %s',
          [Path, E.Message]);
    end;
end;

function WikiTempPath(const Kind: string; Id: Int64): string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    Format('eln-wiki-%s-%d-%d.md', [Kind, GetCurrentThreadId, Id]));
end;

procedure DeleteTempFile(const Path: string);
begin
  if (Path <> '') and System.IOUtils.TFile.Exists(Path) then
    System.IOUtils.TFile.Delete(Path);
end;

// The transport forwards a message verbatim only for the exact Exception
// class; rewrapping any other class would expose driver or storage text.
function CleanupFailure(E: Exception; const Errors: string): Exception;
begin
  MCPLog(Format('wiki write failed: %s: %s%s', [E.ClassName, E.Message, Errors]));
  if E.ClassType = Exception then
    Result := Exception.Create(E.Message + Errors)
  else
    Result := Exception.Create('The wiki page was not saved and its cleanup ' +
      'was incomplete. See the MCP server log.');
end;


function HandleWikiCreatePage(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId, WikiFolderId, SectionFolderId, MdFileTypeId, ItemId: Integer;
  Section, Title, BodyMd, CanonicalSection, Slug, TempPath, Errors: string;
  Project: TProject;
  Existing, Item: TItem;
  MdFile: TFile;
  Attachments: TArray<TWikiAttachment>;
  Operation: TObjectManager;
  Transaction: IDBTransaction;
  Committed: Boolean;
  Written: TStringList;
begin
  ProjectId := GetReqInt(Params, 'project_id');
  Section   := GetReqStr(Params, 'section');
  Title     := GetReqStr(Params, 'title');
  BodyMd    := GetReqStr(Params, 'body_md');
  if Trim(Title) = '' then
    raise Exception.Create('title must not be empty');
  RequireValidSection(Section, CanonicalSection);

  // Check scope first so write-path errors cannot reveal foreign projects.
  RequireProjectRead(Context, ProjectId);
  CheckProjectWriteAccess(Context, ProjectId);

  Project := Context.Manager.Find<TProject>(ProjectId);
  if not Assigned(Project) then
    raise Exception.CreateFmt('Project not found: %d', [ProjectId]);

  MdFileTypeId := ResolveMarkdownFileType(Context).Id;
  Attachments := ResolveAttachments(Context, Params);

  WikiFolderId    := FindOrCreateFolder(Context, ProjectId, 0,            'Wiki');
  SectionFolderId := FindOrCreateFolder(Context, ProjectId, WikiFolderId, CanonicalSection);

  Existing := FindExistingPageItem(Context, ProjectId, SectionFolderId, Title);
  if Assigned(Existing) then
    raise Exception.CreateFmt(
      'A wiki page titled "%s" already exists in section "%s" ' +
      '(item id %d). To edit it, call wiki_update_page(item_id=%d, ...).',
      [Title, CanonicalSection, Existing.Id, Existing.Id]);

  Slug := SlugifyTitle(Title);
  TempPath := WikiTempPath('create', ProjectId);
  // Write UTF-8 bytes WITHOUT a BOM. TFile.WriteAllText with TEncoding.UTF8
  // emits a BOM via GetPreamble, which then surfaces as a literal U+FEFF at
  // the head of every wiki body when read back.
  System.IOUtils.TFile.WriteAllBytes(TempPath, TEncoding.UTF8.GetBytes(BodyMd));

  Result := TJSONObject.Create;
  Written := TStringList.Create;
  Operation := TObjectManager.Create(Context.Manager.Connection);
  try
    try
      Transaction := TConflictHandler.BeginOperationTransaction(Context.Manager);
      Committed := False;
      try
        Item := TItem.Create;
        Item.Title       := Title;
        Item.Level       := TItemLevel.Item;
        Item.Type_       := TItemType.Wiki;
        Item.ProjectID   := ProjectId;
        Item.FolderID    := SectionFolderId;
        Item.Parent      := 0;
        Item.CreatedDate := UTCNow;
        Item.CreatedBy   := Context.User.Id;
        Item.Expanded    := True;
        Operation.Save(Item);
        if not TConflictHandler.SafeFlush(Operation) then
          raise Exception.Create('The page item could not be saved.');
        ItemId := Item.Id;
        Operation.Evict(Item);
        Item.Free;
        Item := Operation.Find<TItem>(ItemId);
        RecordAudit(Operation, aetItem, ItemId, aoCreate, Context.User.Id,
          Format('MCP: Wiki - created page "%s" in Wiki/%s',
            [Title, CanonicalSection]));

        MdFile := StageFileOnItem(Context, Operation, Item, TempPath,
          Operation.Find<TFileType>(MdFileTypeId), Slug, Written);
        RecordAudit(Operation, aetFile, MdFile.Id, aoCreate, Context.User.Id,
          Format('MCP: Wiki - wrote body to "%s"', [MdFile.FullName]));

        Result.AddPair('item_id',           TJSONNumber.Create(ItemId));
        Result.AddPair('project_id',        TJSONNumber.Create(ProjectId));
        Result.AddPair('wiki_folder_id',    TJSONNumber.Create(WikiFolderId));
        Result.AddPair('section_folder_id', TJSONNumber.Create(SectionFolderId));
        Result.AddPair('section',           CanonicalSection);
        Result.AddPair('title',             Title);
        Result.AddPair('md_file_id',        TJSONNumber.Create(MdFile.Id));
        Result.AddPair('md_file_name',      MdFile.FullName);
        StageAttachments(Context, Operation, Item, Attachments, Written, Result);

        Transaction.Commit;
        Committed := True;
      finally
        if not Committed then
          Transaction.Rollback;
      end;
    except
      on E: Exception do
      begin
        Errors := '';
        DeleteWrittenPaths(Context, Written, Errors);
        Result.Free;
        if Errors = '' then
          raise;
        raise CleanupFailure(E, Errors);
      end;
    end;
  finally
    TConflictHandler.FreeOperationManager(Operation);
    Written.Free;
    DeleteTempFile(TempPath);
  end;
end;

function FindWikiMarkdown(const Context: TToolContext; Item: TItem): TFile;
var
  F, FirstCandidate: TFile;
  Project: TProject;
begin
  Project := Context.Manager.Find<TProject>(Item.ProjectID);
  FirstCandidate := nil;
  for F in Item.Files do
    if Assigned(F.FileType) and SameText(F.FileType.Ext, '.md') then
    begin
      if Context.Storage.Exists(AttachmentRelativePath(Project.FileFolder,
        Item.FolderName, F.FullName)) then
        Exit(F);
      if FirstCandidate = nil then
        FirstCandidate := F;
    end;
  if Assigned(FirstCandidate) then
    raise Exception.CreateFmt('Item %d has .md file %d, but its bytes are ' +
      'missing from storage. Run check_storage or repair_files.',
      [Item.Id, FirstCandidate.Id]);
  raise Exception.CreateFmt(
    'Item %d has no .md file — not a wiki page. Use list_files(%d) to ' +
    'inspect attachments.', [Item.Id, Item.Id]);
end;

function HandleWikiUpdatePage(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  MdFileId: Int64;
  BodyMd, MdPath, TempPath, BackupPath, Errors: string;
  HasBody, BodyReplaced, Committed: Boolean;
  Attachments: TArray<TWikiAttachment>;
  Item: TItem;
  Project: TProject;
  MdFile, Cached: TFile;
  Operation: TObjectManager;
  Transaction: IDBTransaction;
  Written: TStringList;
begin
  ItemId := GetReqInt(Params, 'item_id');
  HasBody := GetOptStr(Params, 'body_md', BodyMd);
  if not HasBody and not ((Params <> nil) and
    (Params.FindValue('attachments') is TJSONArray) and
    (TJSONArray(Params.FindValue('attachments')).Count > 0)) then
    raise Exception.Create('Provide at least one of body_md or attachments.');

  RequireItemRead(Context, ItemId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);
  if Item.IsDeleted then
    raise Exception.CreateFmt('Item %d is deleted.', [ItemId]);

  CheckProjectWriteAccess(Context, Item.ProjectID);
  if IsItemSignedCheck(Context.Manager, ItemId) then
    raise Exception.Create('Item is signed and cannot be modified.');

  Project := Context.Manager.Find<TProject>(Item.ProjectID);
  Attachments := ResolveAttachments(Context, Params);

  MdFileId := 0;
  TempPath := '';
  BackupPath := '';
  if HasBody then
  begin
    MdFile := FindWikiMarkdown(Context, Item);
    MdFileId := MdFile.Id;
    MdPath := AttachmentRelativePath(Project.FileFolder, Item.FolderName, MdFile.FullName);
    // Name temp files from the numeric file Id only: the title comes from the
    // DB and could escape %TEMP% or contain characters Windows rejects.
    TempPath := WikiTempPath('update', MdFileId);
    BackupPath := WikiTempPath('backup', MdFileId);
  end;

  Result := TJSONObject.Create;
  Written := TStringList.Create;
  Operation := TObjectManager.Create(Context.Manager.Connection);
  BodyReplaced := False;
  try
    try
      if HasBody then
      begin
        // Write UTF-8 bytes WITHOUT a BOM (see HandleWikiCreatePage).
        System.IOUtils.TFile.WriteAllBytes(TempPath, TEncoding.UTF8.GetBytes(BodyMd));
        Context.Storage.CopyOut(MdPath, BackupPath);
      end;
      Transaction := TConflictHandler.BeginOperationTransaction(Context.Manager);
      Committed := False;
      try
        Result.AddPair('item_id', TJSONNumber.Create(ItemId));
        if HasBody then
        begin
          MdFile := Operation.Find<TFile>(MdFileId);
          Context.Storage.CopyIn(TempPath, MdPath);
          BodyReplaced := True;
          MdFile.Hash         := ComputeFileMD5(TempPath);
          MdFile.ModifiedDate := UTCNow;
          MdFile.ModifiedBy   := Context.User.Id;
          if not TConflictHandler.SafeFlush(Operation) then
            raise Exception.Create('The page body record could not be saved.');
          RecordAudit(Operation, aetFile, MdFileId, aoUpdate, Context.User.Id,
            Format('MCP: Wiki - updated body of "%s"', [MdFile.FullName]));
          Result.AddPair('md_file_id',   TJSONNumber.Create(MdFileId));
          Result.AddPair('md_file_name', MdFile.FullName);
        end;
        StageAttachments(Context, Operation, Operation.Find<TItem>(ItemId),
          Attachments, Written, Result);
        Transaction.Commit;
        Committed := True;
      finally
        if not Committed then
          Transaction.Rollback;
      end;
    except
      on E: Exception do
      begin
        Errors := '';
        if BodyReplaced then
          try
            Context.Storage.CopyIn(BackupPath, MdPath);
          except
            on R: Exception do
              Errors := Errors + Format('; could not restore the previous body %s: %s',
                [MdPath, R.Message]);
          end;
        DeleteWrittenPaths(Context, Written, Errors);
        Result.Free;
        if Errors = '' then
          raise;
        raise CleanupFailure(E, Errors);
      end;
    end;
  finally
    TConflictHandler.FreeOperationManager(Operation);
    Written.Free;
    DeleteTempFile(TempPath);
    DeleteTempFile(BackupPath);
  end;

  try
    RefreshCachedItem(Context, ItemId);
    if MdFileId <> 0 then
    begin
      Cached := Context.Manager.FindCached<TFile>(MdFileId);
      if Assigned(Cached) and not Context.Manager.HasChanges(Cached) then
        Context.Manager.Refresh(Cached);
    end;
  except
    on E: Exception do
      MCPLog(Format('wiki_update_page: item %d is saved, but the session cache ' +
        'refresh failed: %s: %s', [ItemId, E.ClassName, E.Message]));
  end;
end;


function HandleWikiGetPage(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  Item: TItem;
  Project: TProject;
  Folder: TFolder;
  MdFile, F: TFile;
  RemotePath, BodyMd: string;
  Bytes: TBytes;
  AttachmentsArr: TJSONArray;
  AttObj: TJSONObject;
begin
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);
  if Item.IsDeleted then
    raise Exception.CreateFmt('Item %d is deleted.', [ItemId]);

  Project := Context.Manager.Find<TProject>(Item.ProjectID);
  if not Assigned(Project) then
    raise Exception.CreateFmt('Project %d not found for item %d.',
      [Item.ProjectID, ItemId]);

  MdFile := FindWikiMarkdown(Context, Item);

  RemotePath := Format('Projects/%s/%s/%s', [
    CleanFileName(Project.FileFolder),
    CleanFileName(Item.FolderName),
    MdFile.FullName]);
  Bytes := Context.Storage.ReadBytes(RemotePath);
  BodyMd := TEncoding.UTF8.GetString(Bytes);
  // Strip a leading UTF-8 BOM (U+FEFF) if present — some legacy pages were
  // written by an earlier code path that emitted one, and clients should
  // not see it as content.
  if (Length(BodyMd) > 0) and (BodyMd[1] = #$FEFF) then
    Delete(BodyMd, 1, 1);

  Result := TJSONObject.Create;
  Result.AddPair('item_id',      TJSONNumber.Create(Item.Id));
  Result.AddPair('title',        Item.Title);
  Result.AddPair('project_id',   TJSONNumber.Create(Item.ProjectID));
  Result.AddPair('folder_id',    TJSONNumber.Create(Item.FolderID));

  Folder := Project.GetFolder(Item.FolderID);
  if Assigned(Folder) then
    Result.AddPair('folder_title', Folder.Title)
  else
    Result.AddPair('folder_title', '');

  Result.AddPair('md_file_id',   TJSONNumber.Create(MdFile.Id));
  Result.AddPair('md_file_name', MdFile.FullName);
  Result.AddPair('body_md',      BodyMd);

  AttachmentsArr := TJSONArray.Create;
  for F in Item.Files do
  begin
    if F = MdFile then Continue;
    AttObj := TJSONObject.Create;
    AttObj.AddPair('id',        TJSONNumber.Create(F.Id));
    AttObj.AddPair('title',     F.Title);
    AttObj.AddPair('full_name', F.FullName);
    if Assigned(F.FileType) then
      AttObj.AddPair('ext', F.FileType.Ext)
    else
      AttObj.AddPair('ext', '');
    AttObj.AddPair('hash',      F.Hash);
    AttachmentsArr.AddElement(AttObj);
  end;
  Result.AddPair('attachments', AttachmentsArr);
end;

function MakeWikiGetPageSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'ID of the wiki page item (or any item that has a .md file attached).');
  Props.AddPair('item_id', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Result.AddPair('required', Req);
end;


procedure RegisterWikiTools(Registry: TToolRegistry);
begin
  Registry.Register('wiki_create_page',
    'Create a wiki page under a project, enforcing the five-section convention ' +
    '(Goals/Ideas/Literature/Analysis/References). Idempotently creates Wiki/ ' +
    'and Wiki/{section}/ folders if missing, creates the page item, writes body_md ' +
    'as a .md file, and uploads any attachments. Returns the created item id.',
    MakeWikiCreatePageSchema, HandleWikiCreatePage, tscProjectScoped, taWrite);

  Registry.Register('wiki_update_page',
    'Update an existing wiki page: replace its body_md and/or append attachments. ' +
    'Body replacement rewrites the page''s .md file in place (same filename). ' +
    'Attachments are added; existing files are never removed.',
    MakeWikiUpdatePageSchema, HandleWikiUpdatePage, tscProjectScoped, taWrite);

  Registry.Register('wiki_get_page',
    'Read a wiki page: downloads the attached .md from WebDAV and returns its ' +
    'body inline as body_md (UTF-8), plus item/project/folder metadata and any ' +
    'non-.md attachments. Works for any item whose first .md file is its body.',
    MakeWikiGetPageSchema, HandleWikiGetPage, tscProjectScoped, taRead);
end;

end.
