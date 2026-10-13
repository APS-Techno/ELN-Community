unit unit_SearchModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  unit_Item,
  unit_Tag,
  unit_User,
  unit_ProjectAccessPolicy,
  unit_ELNDB_Dictionary;

type
  TSearchResultKind = (srkItem, srkEntry, srkFile, srkValue, srkTag);

  TSearchResult = record
    Kind: TSearchResultKind;
    ItemId: Integer;
    ProjectId: Integer;
    FolderId: Integer;
    ItemTitle: string;
    FileId: Int64;
    FullName: string;
    Extension: string;
    EntityName: string;
    MatchedField: string;
    ProjectPath: string;
  end;

  TSearchResults = TList<TSearchResult>;

  TSearchModel = class
  private
    FManager: TObjectManager;
    FItemDic: TItemDictionary;
    FTagDic: TTagDictionary;
    FItemTagDic: TItemTagDictionary;
    FFileDic: TFileDictionary;
    FLabEntryDic: TLabEntryDictionary;
    FValueDic: TValueDictionary;

    FUser: TUser;
    FAccess: IProjectAccessPolicy;

    function MakeKey(const R: TSearchResult): string;
    // A nil set means the injected policy permits unrestricted visibility.
    function BuildAccessibleProjectIds: TDictionary<Integer, Boolean>;
    procedure ApplyAccessFilter(Results: TSearchResults;
      const Allowed: TDictionary<Integer, Boolean>);
    procedure SearchItems(const Pattern: string; Results: TSearchResults;
      Seen: TDictionary<string, Boolean>);
    procedure SearchEntries(const Pattern: string; Results: TSearchResults;
      Seen: TDictionary<string, Boolean>);
    procedure SearchFiles(const Pattern: string; Results: TSearchResults;
      Seen: TDictionary<string, Boolean>);
    procedure SearchValues(const Pattern: string; Results: TSearchResults;
      Seen: TDictionary<string, Boolean>);
    procedure SearchTags(const Pattern: string; Results: TSearchResults;
      Seen: TDictionary<string, Boolean>);
    function BuildProjectPath(ProjectId, FolderId: Integer): string;
  public
    constructor Create(Manager: TObjectManager; const Access: IProjectAccessPolicy);
    destructor Destroy; override;
    procedure AssignUser(AUser: TUser);
    function Search(const Term: string): TSearchResults;
  end;

implementation

uses
  Aurelius.Criteria.Base,
  unit_Project,
  unit_LabEntry,
  unit_FilePaths;


constructor TSearchModel.Create(Manager: TObjectManager;
  const Access: IProjectAccessPolicy);
begin
  inherited Create;
  if Access = nil then
    raise EArgumentNilException.Create('Access');
  FManager := Manager;
  FAccess := Access;
  FItemDic := TItemDictionary.Create;
  FTagDic := TTagDictionary.Create;
  FItemTagDic := TItemTagDictionary.Create;
  FFileDic := TFileDictionary.Create;
  FLabEntryDic := TLabEntryDictionary.Create;
  FValueDic := TValueDictionary.Create;
end;

destructor TSearchModel.Destroy;
begin
  FValueDic.Free;
  FLabEntryDic.Free;
  FFileDic.Free;
  FItemTagDic.Free;
  FTagDic.Free;
  FItemDic.Free;
  inherited;
end;

function EscapeLikeTerm(const S: string): string;
begin
  // Escape LIKE metacharacters so a user-supplied term cannot match every row
  // via a bare `%` or expand unexpectedly via `_`. The backslash escape itself
  // is escaped first; both SQLite and MySQL honour the default `\` escape.
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '%', '\%', [rfReplaceAll]);
  Result := StringReplace(Result, '_', '\_', [rfReplaceAll]);
end;

function UnescapeLikePattern(const Pattern: string): string;
begin
  // Post-filters use Contains, not LIKE; restore escaped metacharacters too.
  Result := Pattern;
  if Result.StartsWith('%') then
    Delete(Result, 1, 1);
  if Result.EndsWith('%') then
    SetLength(Result, Length(Result) - 1);
  Result := StringReplace(Result, '\_', '_', [rfReplaceAll]);
  Result := StringReplace(Result, '\%', '%', [rfReplaceAll]);
  Result := StringReplace(Result, '\\', '\', [rfReplaceAll]);
end;

procedure TSearchModel.AssignUser(AUser: TUser);
begin
  FUser := AUser;
end;

function TSearchModel.BuildAccessibleProjectIds: TDictionary<Integer, Boolean>;
begin
  Result := FAccess.VisibleProjectIds(FManager, FUser);
end;

procedure TSearchModel.ApplyAccessFilter(Results: TSearchResults;
  const Allowed: TDictionary<Integer, Boolean>);
var
  I: Integer;
begin
  if Allowed = nil then
    Exit;
  for I := Results.Count - 1 downto 0 do
    if not Allowed.ContainsKey(Results[I].ProjectId) then
      Results.Delete(I);
end;

function TSearchModel.MakeKey(const R: TSearchResult): string;
begin
  if R.Kind = srkFile then
    Result := Format('%d|%d|%d', [R.ItemId, Ord(R.Kind), R.FileId])
  else
    Result := Format('%d|%d|%s', [R.ItemId, Ord(R.Kind), R.EntityName]);
end;

function TSearchModel.BuildProjectPath(ProjectId, FolderId: Integer): string;
var
  Proj: TProject;
  Folder: TFolder;
begin
  Result := '';
  Proj := FManager.Find<TProject>(ProjectId);
  if Assigned(Proj) then
  begin
    Result := Proj.Title;
    if FolderId > 0 then
    begin
      Folder := FManager.Find<TFolder>(FolderId);
      if Assigned(Folder) then
        Result := Result + ' > ' + Folder.Title;
    end;
  end;
end;

procedure TSearchModel.SearchItems(const Pattern: string;
  Results: TSearchResults; Seen: TDictionary<string, Boolean>);
var
  Items: TList<TItem>;
  Item: TItem;
  R: TSearchResult;
  Key: string;
  MatchField: string;
begin
  R := Default(TSearchResult);
  Items := FManager.Find<TItem>
    .Where(
      (FItemDic.IsDeleted = False) and
      (FItemDic.Title.Like(Pattern) or
       FItemDic.Description.Like(Pattern) or
       Linq['Properties'].Like(Pattern)))
    .List;
  try
    for Item in Items do
    begin
      if Item.Title.ToLower.Contains(UnescapeLikePattern(Pattern).ToLower) then
        MatchField := 'Title'
      else if Item.Description.ToLower.Contains(UnescapeLikePattern(Pattern).ToLower) then
        MatchField := 'Description'
      else
        MatchField := 'Properties';

      R.Kind := srkItem;
      R.ItemId := Item.Id;
      R.ProjectId := Item.ProjectID;
      R.FolderId := Item.FolderID;
      R.ItemTitle := Item.Title;
      R.EntityName := Item.Title;
      R.MatchedField := MatchField;
      R.ProjectPath := BuildProjectPath(Item.ProjectID, Item.FolderID);

      Key := MakeKey(R);
      if not Seen.ContainsKey(Key) then
      begin
        Seen.Add(Key, True);
        Results.Add(R);
      end;
    end;
  finally
    Items.Free;
  end;
end;

procedure TSearchModel.SearchEntries(const Pattern: string;
  Results: TSearchResults; Seen: TDictionary<string, Boolean>);
var
  Items: TList<TItem>;
  Item: TItem;
  Entry: TLabEntry;
  R: TSearchResult;
  Key: string;
begin
  R := Default(TSearchResult);
  Items := FManager.Find<TItem>
    .CreateAlias('FEntries', 'e')
    .Where(
      (FItemDic.IsDeleted = False) and
      Linq['e.Title'].Like(Pattern))
    .List;
  try
    for Item in Items do
    begin
      for Entry in Item.Entries do
      begin
        if Entry.Title.ToLower.Contains(UnescapeLikePattern(Pattern).ToLower) then
        begin
          R.Kind := srkEntry;
          R.ItemId := Item.Id;
          R.ProjectId := Item.ProjectID;
          R.FolderId := Item.FolderID;
          R.ItemTitle := Item.Title;
          R.EntityName := Entry.Title;
          R.MatchedField := 'Protocol Title';
          R.ProjectPath := BuildProjectPath(Item.ProjectID, Item.FolderID);

          Key := MakeKey(R);
          if not Seen.ContainsKey(Key) then
          begin
            Seen.Add(Key, True);
            Results.Add(R);
          end;
        end;
      end;
    end;
  finally
    Items.Free;
  end;
end;

procedure TSearchModel.SearchFiles(const Pattern: string;
  Results: TSearchResults; Seen: TDictionary<string, Boolean>);
var
  Files: TList<TFile>;
  Item: TItem;
  F: TFile;
  R: TSearchResult;
  Key, NameTerm, LowerTerm, ASCIITerm: string;
  FileId: Int64;
  CloseBracket: Integer;
  Criterion: TLinqExpression;
begin
  R := Default(TSearchResult);
  NameTerm := UnescapeLikePattern(Pattern);
  LowerTerm := NameTerm.ToLower;
  Criterion := Linq['Title'].Concat(Linq['ft.Ext']).Lower.Position(LowerTerm) > 0;
  // SQLite lower() folds ASCII only; other dialects also fold Unicode.
  ASCIITerm := System.SysUtils.LowerCase(NameTerm);
  if ASCIITerm <> LowerTerm then
    Criterion := Criterion or
      (Linq['Title'].Concat(Linq['ft.Ext']).Lower.Position(ASCIITerm) > 0);
  CloseBracket := Pos(']', NameTerm);
  if NameTerm.StartsWith('[') and (CloseBracket > 2) and
    TryStrToInt64(Copy(NameTerm, 2, CloseBracket - 2), FileId) then
    Criterion := Criterion or (Linq['Id'] = FileId);
  Files := FManager.Find<TFile>
    .CreateAlias('FItem', 'i')
    .CreateAlias('FFileType', 'ft')
    .Where((Linq['i.IsDeleted'] = False) and Criterion)
    .List;
  try
    for F in Files do
    begin
      R.FullName := F.FullName;
      if not R.FullName.ToLower.Contains(LowerTerm) then
        Continue;
      Item := F.Item;
      R.Kind := srkFile;
      R.ItemId := Item.Id;
      R.FileId := F.Id;
      Key := MakeKey(R);
      if Seen.ContainsKey(Key) then
        Continue;
      R.ProjectId := Item.ProjectID;
      R.FolderId := Item.FolderID;
      R.ItemTitle := Item.Title;
      R.EntityName := F.Title;
      R.Extension := FileFormatExtension(R.FullName, F.FileType.Ext);
      R.MatchedField := 'File Name';
      R.ProjectPath := BuildProjectPath(Item.ProjectID, Item.FolderID);
      Seen.Add(Key, True);
      Results.Add(R);
    end;
  finally
    Files.Free;
  end;
end;

procedure TSearchModel.SearchValues(const Pattern: string;
  Results: TSearchResults; Seen: TDictionary<string, Boolean>);
var
  Items: TList<TItem>;
  Item: TItem;
  V: TValue;
  R: TSearchResult;
  Key: string;
begin
  R := Default(TSearchResult);
  Items := FManager.Find<TItem>
    .CreateAlias('FValues', 'v')
    .Where(
      (FItemDic.IsDeleted = False) and
      Linq['v.Description'].Like(Pattern))
    .List;
  try
    for Item in Items do
    begin
      for V in Item.Values do
      begin
        if V.Description.ToLower.Contains(UnescapeLikePattern(Pattern).ToLower) then
        begin
          R.Kind := srkValue;
          R.ItemId := Item.Id;
          R.ProjectId := Item.ProjectID;
          R.FolderId := Item.FolderID;
          R.ItemTitle := Item.Title;
          R.EntityName := V.Description;
          R.MatchedField := 'Value Description';
          R.ProjectPath := BuildProjectPath(Item.ProjectID, Item.FolderID);

          Key := MakeKey(R);
          if not Seen.ContainsKey(Key) then
          begin
            Seen.Add(Key, True);
            Results.Add(R);
          end;
        end;
      end;
    end;
  finally
    Items.Free;
  end;
end;

procedure TSearchModel.SearchTags(const Pattern: string;
  Results: TSearchResults; Seen: TDictionary<string, Boolean>);
var
  Tags: TTags;
  Tag: TTag;
  Links: TItemTags;
  Link: TItemTag;
  Item: TItem;
  R: TSearchResult;
  Key: string;
begin
  R := Default(TSearchResult);
  Tags := FManager.Find<TTag>
    .Where(FTagDic.Name.Like(Pattern))
    .List;
  try
    for Tag in Tags do
    begin
      Links := FManager.Find<TItemTag>
        .Where(FItemTagDic.TagId = Tag.Id)
        .List;
      try
        for Link in Links do
        begin
          Item := FManager.Find<TItem>(Link.ItemId);
          if Assigned(Item) and not Item.IsDeleted then
          begin
            R.Kind := srkTag;
            R.ItemId := Item.Id;
            R.ProjectId := Item.ProjectID;
            R.FolderId := Item.FolderID;
            R.ItemTitle := Item.Title;
            R.EntityName := Tag.Name;
            R.MatchedField := 'Tag';
            R.ProjectPath := BuildProjectPath(Item.ProjectID, Item.FolderID);

            Key := MakeKey(R);
            if not Seen.ContainsKey(Key) then
            begin
              Seen.Add(Key, True);
              Results.Add(R);
            end;
          end;
        end;
      finally
        Links.Free;
      end;
    end;
  finally
    Tags.Free;
  end;
end;

function TSearchModel.Search(const Term: string): TSearchResults;
var
  Tokens, LowerTokens: TArray<string>;
  Token, Pattern, Existing, LowerName, LowerTitle: string;
  Seen: TDictionary<string, Boolean>;
  TokenResults: TObjectList<TSearchResults>;
  TokenRes: TSearchResults;
  ItemIdCounts: TDictionary<Integer, Integer>;
  ItemFields: TDictionary<Integer, string>;
  TokenIds: TDictionary<Integer, Boolean>;
  IdArr: TArray<Integer>;
  I, J, K, Count: Integer;
  R, R2: TSearchResult;
  Allowed: TDictionary<Integer, Boolean>;
  SeenFiles: TDictionary<Int64, Boolean>;
  AllTokensMatch: Boolean;
begin
  Result := TSearchResults.Create;
  if Length(Term) < 2 then
    Exit;

  Allowed := BuildAccessibleProjectIds;
  try
  Pattern := '%' + EscapeLikeTerm(Term) + '%';
  Seen := TDictionary<string, Boolean>.Create;
  try
    SearchItems(Pattern, Result, Seen);
    SearchEntries(Pattern, Result, Seen);
    SearchFiles(Pattern, Result, Seen);
    SearchValues(Pattern, Result, Seen);
    SearchTags(Pattern, Result, Seen);
  finally
    Seen.Free;
  end;

  // Drop matches from projects the user cannot access before deciding whether
  // the phrase search already satisfied the query.
  ApplyAccessFilter(Result, Allowed);

  Tokens := Term.Split([' '], TStringSplitOptions.ExcludeEmpty);
  if (Result.Count > 0) or (Length(Tokens) <= 1) then
    Exit;

  SetLength(LowerTokens, Length(Tokens));
  for I := 0 to High(Tokens) do
    LowerTokens[I] := Tokens[I].ToLower;

  TokenResults := TObjectList<TSearchResults>.Create(True);
  try
    for Token in Tokens do
    begin
      if Length(Token) < 2 then
        Continue;
      Pattern := '%' + EscapeLikeTerm(Token) + '%';
      TokenRes := TSearchResults.Create;
      Seen := TDictionary<string, Boolean>.Create;
      try
        SearchItems(Pattern, TokenRes, Seen);
        SearchEntries(Pattern, TokenRes, Seen);
        SearchFiles(Pattern, TokenRes, Seen);
        SearchValues(Pattern, TokenRes, Seen);
        SearchTags(Pattern, TokenRes, Seen);
      finally
        Seen.Free;
      end;
      TokenResults.Add(TokenRes);
    end;

    if TokenResults.Count = 0 then
      Exit;

    ItemIdCounts := TDictionary<Integer, Integer>.Create;
    try
      for I := 0 to TokenResults.Count - 1 do
      begin
        TokenIds := TDictionary<Integer, Boolean>.Create;
        try
          for J := 0 to TokenResults[I].Count - 1 do
            if not TokenIds.ContainsKey(TokenResults[I][J].ItemId) then
              TokenIds.Add(TokenResults[I][J].ItemId, True);

          IdArr := TokenIds.Keys.ToArray;
          for J := 0 to High(IdArr) do
          begin
            if ItemIdCounts.TryGetValue(IdArr[J], Count) then
              ItemIdCounts[IdArr[J]] := Count + 1
            else
              ItemIdCounts.Add(IdArr[J], 1);
          end;
        finally
          TokenIds.Free;
        end;
      end;

      ItemFields := TDictionary<Integer, string>.Create;
      try
        for I := 0 to TokenResults.Count - 1 do
        begin
          for J := 0 to TokenResults[I].Count - 1 do
          begin
            R := TokenResults[I][J];
            if ItemIdCounts.TryGetValue(R.ItemId, Count) and
               (Count = TokenResults.Count) then
            begin
              if not ItemFields.ContainsKey(R.ItemId) then
              begin
                R.Kind := srkItem;
                R.EntityName := R.ItemTitle;
                R.FileId := 0;
                R.FullName := '';
                R.Extension := '';
                ItemFields.Add(R.ItemId, R.MatchedField);
                Result.Add(R);
              end
              else
              begin
                Existing := ItemFields[R.ItemId];
                if not Existing.Contains(R.MatchedField) then
                begin
                  Existing := Existing + ', ' + R.MatchedField;
                  ItemFields[R.ItemId] := Existing;
                  for K := 0 to Result.Count - 1 do
                  begin
                    R2 := Result[K];
                    if R2.ItemId = R.ItemId then
                    begin
                      R2.MatchedField := Existing;
                      Result[K] := R2;
                      Break;
                    end;
                  end;
                end;
              end;
            end;
          end;
        end;
      finally
        ItemFields.Free;
      end;

      SeenFiles := TDictionary<Int64, Boolean>.Create;
      try
        for TokenRes in TokenResults do
          for R in TokenRes do
            if (R.Kind = srkFile) and not SeenFiles.ContainsKey(R.FileId) and
              ItemIdCounts.TryGetValue(R.ItemId, Count) and
              (Count = TokenResults.Count) then
            begin
              SeenFiles.Add(R.FileId, True);
              LowerName := R.FullName.ToLower;
              LowerTitle := R.ItemTitle.ToLower;
              AllTokensMatch := True;
              for Token in LowerTokens do
                if (Length(Token) >= 2) and
                  not LowerName.Contains(Token) and not LowerTitle.Contains(Token) then
                begin
                  AllTokensMatch := False;
                  Break;
                end;
              if AllTokensMatch then
                Result.Add(R);
            end;
      finally
        SeenFiles.Free;
      end;
    finally
      ItemIdCounts.Free;
    end;
  finally
    TokenResults.Free;
  end;

  ApplyAccessFilter(Result, Allowed);
  finally
    Allowed.Free;
  end;
end;

end.
