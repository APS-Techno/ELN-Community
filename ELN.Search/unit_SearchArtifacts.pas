unit unit_SearchArtifacts;

interface

uses
  System.SysUtils;

type
  ESearchArtifactError = class(Exception);

  TArtifactFile = record
    RelativePath: string;
    Size: Int64;
    Sha256: string;
  end;

  TArtifactArchiveKind = (akZip, akTarGz);

  TArtifactModelRole = (mrEmbedder, mrReranker);

  TArtifactModel = record
    Name, License, DataTerms, Revision, BaseUrl, Folder: string;
    Role: TArtifactModelRole;
    Optional: Boolean;
    Files: TArray<TArtifactFile>;
  end;

  TArtifactArchive = record
    Name, Url, Folder, License: string;
    Size: Int64;
    Sha256: string;
    Kind: TArtifactArchiveKind;
    Optional: Boolean;
    Files: TArray<TArtifactFile>;
  end;

  TArtifactPart = record
    Name, License, DataTerms: string;
    Optional: Boolean;
    Size: Int64;
    Files: TArray<TArtifactFile>;
  end;

  TSearchArtifactManifest = record
    Models: TArray<TArtifactModel>;
    Archives: TArray<TArtifactArchive>;
    TotalDownloadBytes: Int64;
    class function LoadFromFile(const Path: string): TSearchArtifactManifest; static;
    class function DefaultPath: string; static;
    function PdfiumLibraryPath(const Root: string): string;
    function FindModel(Role: TArtifactModelRole; out Model: TArtifactModel): Boolean;
    function Parts: TArray<TArtifactPart>;
  end;

  TArtifactState = (asReady, asMissing, asWrongSize, asWrongHash);

  TArtifactCheck = record
    State: TArtifactState;
    FirstProblem: string;
  end;

  TArtifactReadiness = (arNotReady, arReadyOptionalMissing, arReady);

  TArtifactReport = record
    Parts: TArray<TArtifactPart>;
    Checks: TArray<TArtifactCheck>;
    Required: TArtifactCheck;
    Readiness: TArtifactReadiness;
  end;

const
  SearchArtifactManifestName = {$IFDEF MSWINDOWS}'search-artifacts.json'{$ELSE}'search-artifacts-linux.json'{$ENDIF};

function CheckSearchArtifacts(const Manifest: TSearchArtifactManifest; const Root: string;
  VerifyHashes: Boolean; RequiredOnly: Boolean = False): TArtifactCheck;

function CheckArtifactPart(const Part: TArtifactPart; const Root: string; VerifyHashes: Boolean): TArtifactCheck;

function CheckArtifactReport(const Manifest: TSearchArtifactManifest; const Root: string;
  VerifyHashes: Boolean): TArtifactReport;

function OptionalPartReady(const Manifest: TSearchArtifactManifest; const Root, Name: string): Boolean;

function ArtifactFileMatches(const Path: string; Size: Int64; const Sha256: string): Boolean;

function SearchArtifactRoot: string;

function SearchPdfiumLibraryPath: string;

function SearchArtifactsReady: Boolean;

function SearchArtifactsReadyAt(const ManifestPath, Root: string): Boolean;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.JSON, System.Hash, unit_TextEmbedder;

const
  SupportedManifestVersion = 3;
  PdfiumLibraryRelativePath = {$IFDEF MSWINDOWS}'pdfium\bin\pdfium.dll'{$ELSE}'pdfium/lib/libpdfium.so'{$ENDIF};
  HashBufferSize = 1024 * 1024;

function RequireValue(Obj: TJSONObject; const Key: string): TJSONValue;
begin
  Result := Obj.GetValue(Key);
  if Result = nil then
    raise ESearchArtifactError.CreateFmt('Search artifact manifest: "%s" is missing', [Key]);
end;

function RequireObject(Obj: TJSONObject; const Key: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := RequireValue(Obj, Key);
  if not (V is TJSONObject) then
    raise ESearchArtifactError.CreateFmt('Search artifact manifest: "%s" must be an object', [Key]);
  Result := TJSONObject(V);
end;

function RequireText(Obj: TJSONObject; const Key: string): string;
var
  V: TJSONValue;
begin
  V := RequireValue(Obj, Key);
  if not (V is TJSONString) or (TJSONString(V).Value = '') then
    raise ESearchArtifactError.CreateFmt('Search artifact manifest: "%s" must be a non-empty string', [Key]);
  Result := TJSONString(V).Value;
end;

function RequireSize(Obj: TJSONObject; const Key: string): Int64;
var
  V: TJSONValue;
begin
  V := RequireValue(Obj, Key);
  if not (V is TJSONNumber) then
    raise ESearchArtifactError.CreateFmt('Search artifact manifest: "%s" must be a number', [Key]);
  Result := TJSONNumber(V).AsInt64;
  if Result < 0 then
    raise ESearchArtifactError.CreateFmt('Search artifact manifest: "%s" must not be negative', [Key]);
end;

function RequireSha(Obj: TJSONObject; const Key: string): string;
var
  C: Char;
begin
  Result := UpperCase(RequireText(Obj, Key));
  if Length(Result) <> 64 then
    raise ESearchArtifactError.CreateFmt('Search artifact manifest: "%s" must be 64 hex digits', [Key]);
  for C in Result do
    if not CharInSet(C, ['0'..'9', 'A'..'F']) then
      raise ESearchArtifactError.CreateFmt('Search artifact manifest: "%s" must be 64 hex digits', [Key]);
end;

function ReadFiles(Section: TJSONObject; const Folder: string): TArray<TArtifactFile>;
var
  V: TJSONValue;
  Items: TJSONArray;
  I: Integer;
  Item: TJSONObject;
begin
  V := RequireValue(Section, 'Files');
  if not (V is TJSONArray) or (TJSONArray(V).Count = 0) then
    raise ESearchArtifactError.Create('Search artifact manifest: "Files" must be a non-empty array');
  Items := TJSONArray(V);
  SetLength(Result, Items.Count);
  for I := 0 to Items.Count - 1 do
  begin
    if not (Items.Items[I] is TJSONObject) then
      raise ESearchArtifactError.Create('Search artifact manifest: "Files" entries must be objects');
    Item := TJSONObject(Items.Items[I]);
    Result[I].RelativePath := TPath.Combine(Folder,
      RequireText(Item, 'Name').Replace('\', '/').Replace('/', PathDelim));
    Result[I].Size := RequireSize(Item, 'Size');
    Result[I].Sha256 := RequireSha(Item, 'Sha256');
  end;
end;

function ReadOptional(Item: TJSONObject): Boolean;
var
  V: TJSONValue;
begin
  Result := False;
  V := Item.GetValue('Optional');
  if V = nil then
    Exit;
  if not (V is TJSONBool) then
    raise ESearchArtifactError.Create('Search artifact manifest: "Optional" must be a boolean');
  Result := TJSONBool(V).AsBoolean;
end;

function ReadModels(Obj: TJSONObject): TArray<TArtifactModel>;
var
  V: TJSONValue;
  Items: TJSONArray;
  I, Embedders, Rerankers: Integer;
  Item: TJSONObject;
  Role: string;
begin
  V := RequireValue(Obj, 'Models');
  if not (V is TJSONArray) or (TJSONArray(V).Count = 0) then
    raise ESearchArtifactError.Create('Search artifact manifest: "Models" must be a non-empty array');
  Items := TJSONArray(V);
  SetLength(Result, Items.Count);
  Embedders := 0;
  Rerankers := 0;
  for I := 0 to Items.Count - 1 do
  begin
    if not (Items.Items[I] is TJSONObject) then
      raise ESearchArtifactError.Create('Search artifact manifest: "Models" entries must be objects');
    Item := TJSONObject(Items.Items[I]);
    Result[I].Name := RequireText(Item, 'Name');
    Result[I].License := RequireText(Item, 'License');
    Result[I].Revision := RequireText(Item, 'Revision');
    Result[I].BaseUrl := RequireText(Item, 'BaseUrl');
    Result[I].Folder := RequireText(Item, 'Folder');
    V := Item.GetValue('DataTerms');
    if V <> nil then
    begin
      if not (V is TJSONString) or (TJSONString(V).Value = '') then
        raise ESearchArtifactError.Create('Search artifact manifest: "DataTerms" must be a non-empty string');
      Result[I].DataTerms := TJSONString(V).Value;
    end;
    Result[I].Optional := ReadOptional(Item);
    Result[I].Files := ReadFiles(Item, Result[I].Folder);
    Role := RequireText(Item, 'Role');
    if Role = 'embedder' then
    begin
      if Result[I].Optional then
        raise ESearchArtifactError.Create('Search artifact manifest: the embedder model must not be optional');
      Result[I].Role := mrEmbedder;
      Inc(Embedders);
    end
    else if Role = 'reranker' then
    begin
      Result[I].Role := mrReranker;
      Inc(Rerankers);
    end
    else
      raise ESearchArtifactError.CreateFmt('Search artifact manifest: model role "%s" is not supported', [Role]);
  end;
  if Embedders <> 1 then
    raise ESearchArtifactError.Create('Search artifact manifest: "Models" must have exactly one embedder');
  if Rerankers > 1 then
    raise ESearchArtifactError.Create('Search artifact manifest: "Models" must have at most one reranker');
end;

function ReadArchives(Obj: TJSONObject): TArray<TArtifactArchive>;
var
  V: TJSONValue;
  Items: TJSONArray;
  I: Integer;
  Item: TJSONObject;
  Kind: string;
begin
  V := RequireValue(Obj, 'Archives');
  if not (V is TJSONArray) or (TJSONArray(V).Count = 0) then
    raise ESearchArtifactError.Create('Search artifact manifest: "Archives" must be a non-empty array');
  Items := TJSONArray(V);
  SetLength(Result, Items.Count);
  for I := 0 to Items.Count - 1 do
  begin
    if not (Items.Items[I] is TJSONObject) then
      raise ESearchArtifactError.Create('Search artifact manifest: "Archives" entries must be objects');
    Item := TJSONObject(Items.Items[I]);
    Result[I].Name := RequireText(Item, 'Name');
    Result[I].Url := RequireText(Item, 'Url');
    Result[I].Folder := RequireText(Item, 'Folder');
    Result[I].License := RequireText(Item, 'License');
    Result[I].Size := RequireSize(Item, 'Size');
    Result[I].Sha256 := RequireSha(Item, 'Sha256');
    Kind := RequireText(Item, 'Kind');
    if Kind = 'zip' then
      Result[I].Kind := akZip
    else if Kind = 'tar.gz' then
      Result[I].Kind := akTarGz
    else
      raise ESearchArtifactError.CreateFmt('Search artifact manifest: archive kind "%s" is not supported', [Kind]);
    Result[I].Files := ReadFiles(Item, Result[I].Folder);
    Result[I].Optional := ReadOptional(Item);
  end;
end;

{ TSearchArtifactManifest }

class function TSearchArtifactManifest.DefaultPath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + SearchArtifactManifestName;
end;

function TSearchArtifactManifest.PdfiumLibraryPath(const Root: string): string;
begin
  Result := TPath.Combine(Root, PdfiumLibraryRelativePath);
end;

class function TSearchArtifactManifest.LoadFromFile(const Path: string): TSearchArtifactManifest;
var
  Root: TJSONValue;
  Obj: TJSONObject;
  Version: Int64;
  Part, Other: Integer;
  Parts: TArray<TArtifactPart>;
begin
  Result := Default(TSearchArtifactManifest);
  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllBytes(Path), 0, True);
  except
    on E: EInOutError do
      raise ESearchArtifactError.CreateFmt('Search artifact manifest cannot be read: %s', [Path]);
  end;
  if Root = nil then
    raise ESearchArtifactError.CreateFmt('Search artifact manifest is not valid JSON: %s', [Path]);
  try
    if not (Root is TJSONObject) then
      raise ESearchArtifactError.Create('Search artifact manifest: the root must be an object');
    Obj := TJSONObject(Root);
    Version := RequireSize(Obj, 'ManifestVersion');
    if Version <> SupportedManifestVersion then
      raise ESearchArtifactError.CreateFmt(
        'Search artifact manifest version %d is not supported. This program needs version %d. ' +
        'Use the search-artifacts.json that belongs to this program version.',
        [Version, SupportedManifestVersion]);
    Result.Models := ReadModels(Obj);
    Result.Archives := ReadArchives(Obj);
    Parts := Result.Parts;
    for Part := 0 to High(Parts) do
    begin
      Inc(Result.TotalDownloadBytes, Parts[Part].Size);
      for Other := 0 to Part - 1 do
        if SameText(Parts[Other].Name, Parts[Part].Name) then
          raise ESearchArtifactError.CreateFmt('Search artifact manifest: the name "%s" is used twice',
            [Parts[Part].Name]);
    end;
  finally
    Root.Free;
  end;
end;

function TSearchArtifactManifest.FindModel(Role: TArtifactModelRole; out Model: TArtifactModel): Boolean;
var
  M: TArtifactModel;
begin
  for M in Models do
    if M.Role = Role then
    begin
      Model := M;
      Exit(True);
    end;
  Model := Default(TArtifactModel);
  Result := False;
end;

function TSearchArtifactManifest.Parts: TArray<TArtifactPart>;
var
  N: Integer;
  M: TArtifactModel;
  A: TArtifactArchive;
  F: TArtifactFile;
begin
  SetLength(Result, Length(Models) + Length(Archives));
  N := 0;
  for M in Models do
  begin
    Result[N].Name := M.Name;
    Result[N].License := M.License;
    Result[N].DataTerms := M.DataTerms;
    Result[N].Optional := M.Optional;
    Result[N].Files := M.Files;
    for F in M.Files do
      Inc(Result[N].Size, F.Size);
    Inc(N);
  end;
  for A in Archives do
  begin
    Result[N].Name := A.Name;
    Result[N].License := A.License;
    Result[N].Optional := A.Optional;
    Result[N].Files := A.Files;
    Result[N].Size := A.Size;
    Inc(N);
  end;
end;

function Problem(State: TArtifactState; const Text: string): TArtifactCheck;
begin
  Result.State := State;
  Result.FirstProblem := Text;
end;

function StreamSha256(Stream: TStream): string;
var
  Hasher: THashSHA2;
  Buffer: TBytes;
  Count: Integer;
begin
  Hasher := THashSHA2.Create(SHA256);
  SetLength(Buffer, HashBufferSize);
  Stream.Position := 0;
  repeat
    Count := Stream.Read(Buffer, Length(Buffer));
    if Count > 0 then
      Hasher.Update(Buffer, Count);
  until Count = 0;
  Result := Hasher.HashAsString;
end;

function CheckFile(const Root: string; const F: TArtifactFile; VerifyHashes: Boolean): TArtifactCheck;
var
  Stream: TFileStream;
  Path: string;
begin
  Path := TPath.Combine(Root, F.RelativePath);
  if not TFile.Exists(Path) then
    Exit(Problem(asMissing, 'Missing: ' + F.RelativePath));
  try
    Stream := TBufferedFileStream.Create(Path, fmOpenRead or fmShareDenyWrite, HashBufferSize);
  except
    on E: EFOpenError do
      Exit(Problem(asMissing, 'Cannot open: ' + F.RelativePath));
  end;
  try
    if Stream.Size <> F.Size then
      Exit(Problem(asWrongSize, Format('Wrong size (%d, expected %d): %s', [Stream.Size, F.Size, F.RelativePath])));
    if VerifyHashes and not SameText(StreamSha256(Stream), F.Sha256) then
      Exit(Problem(asWrongHash, 'Wrong SHA-256: ' + F.RelativePath));
  finally
    Stream.Free;
  end;
  Result := Problem(asReady, '');
end;

function CheckArtifactPart(const Part: TArtifactPart; const Root: string; VerifyHashes: Boolean): TArtifactCheck;
var
  F: TArtifactFile;
begin
  for F in Part.Files do
  begin
    Result := CheckFile(Root, F, VerifyHashes);
    if Result.State <> asReady then
      Exit;
  end;
  Result := Problem(asReady, '');
end;

function CheckSearchArtifacts(const Manifest: TSearchArtifactManifest; const Root: string;
  VerifyHashes: Boolean; RequiredOnly: Boolean): TArtifactCheck;
var
  Part: TArtifactPart;
begin
  for Part in Manifest.Parts do
    if not (RequiredOnly and Part.Optional) then
    begin
      Result := CheckArtifactPart(Part, Root, VerifyHashes);
      if Result.State <> asReady then
        Exit;
    end;
  Result := Problem(asReady, '');
end;

function CheckArtifactReport(const Manifest: TSearchArtifactManifest; const Root: string;
  VerifyHashes: Boolean): TArtifactReport;
var
  I: Integer;
  OptionalMissing: Boolean;
begin
  Result := Default(TArtifactReport);
  Result.Parts := Manifest.Parts;
  SetLength(Result.Checks, Length(Result.Parts));
  Result.Required := Problem(asReady, '');
  OptionalMissing := False;
  for I := 0 to High(Result.Parts) do
  begin
    Result.Checks[I] := CheckArtifactPart(Result.Parts[I], Root, VerifyHashes);
    if Result.Checks[I].State = asReady then
      Continue;
    if Result.Parts[I].Optional then
      OptionalMissing := True
    else if Result.Required.State = asReady then
      Result.Required := Result.Checks[I];
  end;
  if Result.Required.State <> asReady then
    Result.Readiness := arNotReady
  else if OptionalMissing then
    Result.Readiness := arReadyOptionalMissing
  else
    Result.Readiness := arReady;
end;

function OptionalPartReady(const Manifest: TSearchArtifactManifest; const Root, Name: string): Boolean;
var
  Part: TArtifactPart;
begin
  for Part in Manifest.Parts do
    if Part.Optional and SameText(Part.Name, Name) then
      Exit(CheckArtifactPart(Part, Root, False).State = asReady);
  Result := False;
end;

function ArtifactFileMatches(const Path: string; Size: Int64; const Sha256: string): Boolean;
var
  F: TArtifactFile;
begin
  F.RelativePath := Path;
  F.Size := Size;
  F.Sha256 := Sha256;
  Result := CheckFile('', F, True).State = asReady;
end;

function SearchArtifactRoot: string;
begin
  Result := TE5EmbedderConfig.DefaultArtifactRoot;
end;

function SearchPdfiumLibraryPath: string;
begin
  Result := TPath.Combine(SearchArtifactRoot, PdfiumLibraryRelativePath);
end;

function SearchArtifactsReadyAt(const ManifestPath, Root: string): Boolean;
var
  Manifest: TSearchArtifactManifest;
begin
  Result := False;
  if not FileExists(ManifestPath) then
    Exit;
  try
    Manifest := TSearchArtifactManifest.LoadFromFile(ManifestPath);
    Result := CheckSearchArtifacts(Manifest, Root, False, True).State = asReady;
  except
    on Exception do
      Result := False;
  end;
end;

function SearchArtifactsReady: Boolean;
begin
  Result := SearchArtifactsReadyAt(TSearchArtifactManifest.DefaultPath, SearchArtifactRoot);
end;

end.
