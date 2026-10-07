unit unit_FileBrowserState;

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TBrowserEntry = record
    Name, FullPath: string;
    IsDirectory: Boolean;
    Size: Int64;
    Modified: TDateTime;
  end;
  TBrowserEntries = TArray<TBrowserEntry>;
  TBrowserNavigation = (bnNew, bnBack, bnForward, bnRefresh);

  TFileBrowserState = class
  private
    FHistory: TList<string>;
    FHistoryIndex: Integer;
    FCurrentDirectory, FRequestedPath: string;
    FRequestedKind: TBrowserNavigation;
    FRequest: UInt64;
    FPending: Boolean;
    FSelectedPaths: TArray<string>;
    function GetBackPath: string;
    function GetForwardPath: string;
    function GetSelectedPaths: TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function BeginRequest(const APath: string; AKind: TBrowserNavigation): UInt64;
    function CompleteRequest(ARequest: UInt64; ASucceeded: Boolean): Boolean;
    procedure SetSelectedPaths(const APaths: TArray<string>);
    procedure ReconcileSelection(const AVisibleFiles: TArray<string>);
    property CurrentDirectory: string read FCurrentDirectory;
    property SelectedPaths: TArray<string> read GetSelectedPaths;
    property BackPath: string read GetBackPath;
    property ForwardPath: string read GetForwardPath;
  end;

function NormalizeBrowserPath(const APath: string): string;
function BrowserParentDirectory(const APath: string): string;
function EnumerateBrowserDirectory(const APath: string): TBrowserEntries;
function BrowserEntryMatches(const AEntry: TBrowserEntry; const AMasks: string): Boolean;
function CompareBrowserEntries(const ALeft, ARight: TBrowserEntry;
  AColumn: Integer; ADescending: Boolean): Integer;

implementation

uses
  Winapi.Windows, Winapi.Shlwapi, System.IOUtils, System.Classes;

function NormalizeBrowserPath(const APath: string): string;
var
  Root: string;
begin
  Result := ExpandFileName(Trim(APath));
  Root := TPath.GetPathRoot(Result);
  if SameText(IncludeTrailingPathDelimiter(Result), IncludeTrailingPathDelimiter(Root)) then
    Result := IncludeTrailingPathDelimiter(Root)
  else
    Result := ExcludeTrailingPathDelimiter(Result);
end;

function BrowserParentDirectory(const APath: string): string;
var
  Path, Root: string;
begin
  Result := '';
  if APath = '' then Exit;
  Path := NormalizeBrowserPath(APath);
  Root := TPath.GetPathRoot(Path);
  if SameText(IncludeTrailingPathDelimiter(Path), IncludeTrailingPathDelimiter(Root)) then
    Exit;
  Result := NormalizeBrowserPath(ExtractFileDir(ExcludeTrailingPathDelimiter(Path)));
end;

function EnumerateBrowserDirectory(const APath: string): TBrowserEntries;
var
  Items: TList<TBrowserEntry>;
  Search: TSearchRec;
  Entry: TBrowserEntry;
  Path: string;
  Attr: DWORD;
  Code: Integer;
begin
  Path := NormalizeBrowserPath(APath);
  Attr := GetFileAttributes(PChar(Path));
  if Attr = INVALID_FILE_ATTRIBUTES then
    raise EOSError.CreateFmt('%s: %s', [Path, SysErrorMessage(GetLastError)]);
  if Attr and FILE_ATTRIBUTE_DIRECTORY = 0 then
    raise EOSError.CreateFmt('Not a folder: %s', [Path]);
  Items := TList<TBrowserEntry>.Create;
  try
    Code := FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faAnyFile, Search);
    if Code = 0 then
    try
      repeat
        if (Search.Name <> '.') and (Search.Name <> '..') then
        begin
          Entry.Name := Search.Name;
          Entry.FullPath := IncludeTrailingPathDelimiter(Path) + Search.Name;
          Entry.IsDirectory := Search.Attr and faDirectory <> 0;
          Entry.Size := Search.Size;
          Entry.Modified := Search.TimeStamp;
          Items.Add(Entry);
        end;
        Code := FindNext(Search);
      until Code <> 0;
      if Code <> ERROR_NO_MORE_FILES then
        raise EOSError.CreateFmt('%s: %s', [Path, SysErrorMessage(Code)]);
    finally
      System.SysUtils.FindClose(Search);
    end
    else if (Code <> ERROR_FILE_NOT_FOUND) and (Code <> ERROR_NO_MORE_FILES) then
      raise EOSError.CreateFmt('%s: %s', [Path, SysErrorMessage(Code)]);
    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

function BrowserEntryMatches(const AEntry: TBrowserEntry; const AMasks: string): Boolean;
begin
  Result := AEntry.IsDirectory or (AMasks = '') or
    PathMatchSpec(PChar(AEntry.Name), PChar(AMasks));
end;

function CompareBrowserEntries(const ALeft, ARight: TBrowserEntry;
  AColumn: Integer; ADescending: Boolean): Integer;
begin
  if ALeft.IsDirectory <> ARight.IsDirectory then
  begin
    if ALeft.IsDirectory then Result := -1 else Result := 1;
    Exit;
  end;
  Result := 0;
  case AColumn of
    0: Result := CompareText(ALeft.Name, ARight.Name);
    1: Result := CompareText(ExtractFileExt(ALeft.Name), ExtractFileExt(ARight.Name));
    2: if ALeft.Size < ARight.Size then Result := -1
       else if ALeft.Size > ARight.Size then Result := 1;
    3: if ALeft.Modified < ARight.Modified then Result := -1
       else if ALeft.Modified > ARight.Modified then Result := 1;
  end;
  if Result = 0 then
    Result := CompareText(ALeft.Name, ARight.Name);
  if Result = 0 then
    Result := CompareStr(ALeft.Name, ARight.Name);
  if ADescending then
    Result := -Result;
end;

constructor TFileBrowserState.Create;
begin
  inherited Create;
  FHistory := TList<string>.Create;
  FHistoryIndex := -1;
end;

destructor TFileBrowserState.Destroy;
begin
  FHistory.Free;
  inherited;
end;

function TFileBrowserState.BeginRequest(const APath: string;
  AKind: TBrowserNavigation): UInt64;
begin
  FRequestedPath := NormalizeBrowserPath(APath);
  FRequestedKind := AKind;
  Inc(FRequest);
  FPending := True;
  Result := FRequest;
end;

function TFileBrowserState.CompleteRequest(ARequest: UInt64;
  ASucceeded: Boolean): Boolean;
var
  Changed: Boolean;
begin
  Result := FPending and (ARequest = FRequest);
  if not Result then Exit;
  FPending := False;
  if not ASucceeded then Exit;
  Changed := not SameText(FCurrentDirectory, FRequestedPath);
  case FRequestedKind of
    bnBack: if FHistoryIndex > 0 then Dec(FHistoryIndex);
    bnForward: if FHistoryIndex < FHistory.Count - 1 then Inc(FHistoryIndex);
    bnNew:
      if Changed then
      begin
        while FHistory.Count > FHistoryIndex + 1 do
          FHistory.Delete(FHistory.Count - 1);
        FHistory.Add(FRequestedPath);
        FHistoryIndex := FHistory.Count - 1;
      end;
  end;
  FCurrentDirectory := FRequestedPath;
  if Changed then
    FSelectedPaths := nil;
end;

function TFileBrowserState.GetBackPath: string;
begin
  Result := '';
  if FHistoryIndex > 0 then
    Result := FHistory[FHistoryIndex - 1];
end;

function TFileBrowserState.GetForwardPath: string;
begin
  Result := '';
  if FHistoryIndex < FHistory.Count - 1 then
    Result := FHistory[FHistoryIndex + 1];
end;

function TFileBrowserState.GetSelectedPaths: TArray<string>;
begin
  Result := Copy(FSelectedPaths);
end;

procedure TFileBrowserState.SetSelectedPaths(const APaths: TArray<string>);
begin
  FSelectedPaths := Copy(APaths);
end;

procedure TFileBrowserState.ReconcileSelection(const AVisibleFiles: TArray<string>);
var
  Selected, Visible: string;
  VisibleSet: TStringList;
  Kept: TArray<string>;
  Count: Integer;
begin
  if Length(FSelectedPaths) = 0 then Exit;
  VisibleSet := TStringList.Create;
  try
    VisibleSet.CaseSensitive := False;
    for Visible in AVisibleFiles do VisibleSet.Add(Visible);
    VisibleSet.Sorted := True;
    SetLength(Kept, Length(FSelectedPaths));
    Count := 0;
    for Selected in FSelectedPaths do
      if VisibleSet.IndexOf(Selected) >= 0 then
      begin
        Kept[Count] := Selected;
        Inc(Count);
      end;
    SetLength(Kept, Count);
    FSelectedPaths := Kept;
  finally
    VisibleSet.Free;
  end;
end;

end.
