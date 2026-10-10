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
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  unit_Project, unit_Item, unit_ItemTypes, unit_FileType,
  unit_ELNDB_Dictionary,
  unit_ConflictHandler, unit_AuditLog, unit_AuditHelper,
  unit_TimeHelper, unit_FilePaths,
  unit_SignatureModel,
  unit_ToolsWrite, unit_ToolScope;


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

// Callers must pass permission and signed-item checks before attaching files.
procedure AppendAttachments(const Context: TToolContext; Item: TItem;
  Attachments: TJSONArray; ResponseObj: TJSONObject);
var
  I: Integer;
  AttPath, AttTitle: string;
  AttType: TFileType;
  Info: TAttachedFileInfo;
  AttachedArr: TJSONArray;
  ExistingArr: TJSONValue;
  AttObj: TJSONObject;
begin
  ExistingArr := ResponseObj.FindValue('attachments');
  if ExistingArr is TJSONArray then
    AttachedArr := TJSONArray(ExistingArr)
  else
  begin
    AttachedArr := TJSONArray.Create;
    ResponseObj.AddPair('attachments', AttachedArr);
  end;

  for I := 0 to Attachments.Count - 1 do
  begin
    AttPath := (Attachments.Items[I] as TJSONString).Value;
    CheckUploadPathAllowed(Context, AttPath);
    if not FileExists(AttPath) then
      raise Exception.CreateFmt('Attachment not found: %s', [AttPath]);
    AttType := ResolveFileTypeByExt(Context, AttPath);
    AttTitle := TPath.GetFileNameWithoutExtension(AttPath);
    Info := AttachFileToItem(Context, Item.Id, AttPath, AttType.Id, AttTitle);

    AttObj := TJSONObject.Create;
    AttObj.AddPair('id',        TJSONNumber.Create(Info.Id));
    AttObj.AddPair('title',     Info.Title);
    AttObj.AddPair('full_name', Info.FullName);
    AttachedArr.AddElement(AttObj);
  end;
end;


function HandleWikiCreatePage(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId: Integer;
  Section, Title, BodyMd, CanonicalSection: string;
  Project: TProject;
  WikiFolderId, SectionFolderId: Integer;
  Existing: TItem;
  Item: TItem;
  MdFileType: TFileType;
  Slug, TempPath, RemotePath, Hash: string;
  F: unit_Item.TFile;
  Attachments: TJSONArray;
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

  WikiFolderId    := FindOrCreateFolder(Context, ProjectId, 0,            'Wiki');
  SectionFolderId := FindOrCreateFolder(Context, ProjectId, WikiFolderId, CanonicalSection);

  Existing := FindExistingPageItem(Context, ProjectId, SectionFolderId, Title);
  if Assigned(Existing) then
    raise Exception.CreateFmt(
      'A wiki page titled "%s" already exists in section "%s" ' +
      '(item id %d). To edit it, call wiki_update_page(item_id=%d, ...).',
      [Title, CanonicalSection, Existing.Id, Existing.Id]);

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
  Context.Manager.Save(Item);
  TConflictHandler.SafeFlush(Context.Manager);
  RecordAudit(Context.Manager, aetItem, Item.Id, aoCreate, Context.User.Id,
    Format('MCP: Wiki - created page "%s" in Wiki/%s',
      [Title, CanonicalSection]));

  MdFileType := ResolveMarkdownFileType(Context);
  Slug := SlugifyTitle(Title);
  TempPath := TPath.Combine(TPath.GetTempPath,
    Format('eln-wiki-%d-%s.md', [GetCurrentThreadId, Slug]));
  // Write UTF-8 bytes WITHOUT a BOM. TFile.WriteAllText with TEncoding.UTF8
  // emits a BOM via GetPreamble, which then surfaces as a literal U+FEFF at
  // the head of every wiki body when read back.
  System.IOUtils.TFile.WriteAllBytes(TempPath, TEncoding.UTF8.GetBytes(BodyMd));
  try
    Hash := ComputeFileMD5(TempPath);

    F := unit_Item.TFile.Create;
    F.FileType    := MdFileType;
    F.Title       := Slug;
    F.Hash        := Hash;
    F.CreatedDate := UTCNow;
    F.CreatedBy   := Context.User.Id;
    F.Item        := Item;
    Item.Files.Add(F);
    Context.Manager.Update(Item);
    TConflictHandler.SafeFlush(Context.Manager);

    RemotePath := Format('Projects/%s/%s/%s', [
      CleanFileName(Project.FileFolder),
      CleanFileName(Item.FolderName),
      F.FullName]);
    Context.Storage.CopyIn(TempPath, RemotePath);

    RecordAudit(Context.Manager, aetFile, F.Id, aoCreate, Context.User.Id,
      Format('MCP: Wiki - wrote body to "%s"', [F.FullName]));
  finally
    if System.IOUtils.TFile.Exists(TempPath) then
      System.IOUtils.TFile.Delete(TempPath);
  end;

  Result := TJSONObject.Create;
  try
  Result.AddPair('item_id',           TJSONNumber.Create(Item.Id));
  Result.AddPair('project_id',        TJSONNumber.Create(ProjectId));
  Result.AddPair('wiki_folder_id',    TJSONNumber.Create(WikiFolderId));
  Result.AddPair('section_folder_id', TJSONNumber.Create(SectionFolderId));
  Result.AddPair('section',           CanonicalSection);
  Result.AddPair('title',             Title);
  Result.AddPair('md_file_id',        TJSONNumber.Create(F.Id));
  Result.AddPair('md_file_name',      F.FullName);

  Attachments := nil;
  if (Params <> nil) and (Params.FindValue('attachments') is TJSONArray) then
    Attachments := TJSONArray(Params.FindValue('attachments'));
  if (Attachments <> nil) and (Attachments.Count > 0) then
    AppendAttachments(Context, Item, Attachments, Result);
  except
    Result.Free;
    raise;
  end;
end;

function HandleWikiUpdatePage(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  BodyMd: string;
  HasBody, HasAttachments: Boolean;
  Attachments: TJSONArray;
  Item: TItem;
  Project: TProject;
  MdFile: TFile;
  F: TFile;
  TempPath, RemotePath, Hash: string;
begin
  ItemId := GetReqInt(Params, 'item_id');
  HasBody := GetOptStr(Params, 'body_md', BodyMd);
  HasAttachments := (Params <> nil) and
    (Params.FindValue('attachments') is TJSONArray) and
    (TJSONArray(Params.FindValue('attachments')).Count > 0);
  if not (HasBody or HasAttachments) then
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

  Result := TJSONObject.Create;
  try
  Result.AddPair('item_id', TJSONNumber.Create(Item.Id));

  if HasBody then
  begin
    MdFile := nil;
    for F in Item.Files do
      if Assigned(F.FileType) and SameText(F.FileType.Ext, '.md') then
      begin
        MdFile := F;
        Break;
      end;
    if not Assigned(MdFile) then
      raise Exception.Create(
        'Item has no .md file — this does not look like a wiki page created by ' +
        'wiki_create_page. Aborting to avoid creating a second markdown file.');

    // Name the temp file from safe data only. MdFile.Title comes from the DB
    // (settable via upload_file/rename), so a title containing '\..\' could
    // escape %TEMP% (arbitrary local write) and '*?"<>|' would raise. Use the
    // numeric file Id instead.
    TempPath := TPath.Combine(TPath.GetTempPath,
      Format('eln-wiki-update-%d-%d.md', [GetCurrentThreadId, MdFile.Id]));
    // Write UTF-8 bytes WITHOUT a BOM (see HandleWikiCreatePage for rationale).
    System.IOUtils.TFile.WriteAllBytes(TempPath, TEncoding.UTF8.GetBytes(BodyMd));
    try
      Hash := ComputeFileMD5(TempPath);
      RemotePath := Format('Projects/%s/%s/%s', [
        CleanFileName(Project.FileFolder),
        CleanFileName(Item.FolderName),
        MdFile.FullName]);
      Context.Storage.CopyIn(TempPath, RemotePath);

      MdFile.Hash         := Hash;
      MdFile.ModifiedDate := UTCNow;
      MdFile.ModifiedBy   := Context.User.Id;
      TConflictHandler.SafeFlush(Context.Manager);
      RecordAudit(Context.Manager, aetFile, MdFile.Id, aoUpdate,
        Context.User.Id,
        Format('MCP: Wiki - updated body of "%s"', [MdFile.FullName]));

      Result.AddPair('md_file_id',   TJSONNumber.Create(MdFile.Id));
      Result.AddPair('md_file_name', MdFile.FullName);
    finally
      if System.IOUtils.TFile.Exists(TempPath) then
        System.IOUtils.TFile.Delete(TempPath);
    end;
  end;

  if HasAttachments then
  begin
    Attachments := TJSONArray(Params.FindValue('attachments'));
    AppendAttachments(Context, Item, Attachments, Result);
  end;
  except
    Result.Free;
    raise;
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

  MdFile := nil;
  for F in Item.Files do
    if Assigned(F.FileType) and SameText(F.FileType.Ext, '.md') then
    begin
      MdFile := F;
      Break;
    end;
  if not Assigned(MdFile) then
    raise Exception.CreateFmt(
      'Item %d has no .md file — not a wiki page. Use list_files(%d) to ' +
      'inspect attachments.', [ItemId, ItemId]);

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
    MakeWikiCreatePageSchema, HandleWikiCreatePage, tscProjectScoped);

  Registry.Register('wiki_update_page',
    'Update an existing wiki page: replace its body_md and/or append attachments. ' +
    'Body replacement rewrites the page''s .md file in place (same filename). ' +
    'Attachments are added; existing files are never removed.',
    MakeWikiUpdatePageSchema, HandleWikiUpdatePage, tscProjectScoped);

  Registry.Register('wiki_get_page',
    'Read a wiki page: downloads the attached .md from WebDAV and returns its ' +
    'body inline as body_md (UTF-8), plus item/project/folder metadata and any ' +
    'non-.md attachments. Works for any item whose first .md file is its body.',
    MakeWikiGetPageSchema, HandleWikiGetPage, tscProjectScoped);
end;

end.
