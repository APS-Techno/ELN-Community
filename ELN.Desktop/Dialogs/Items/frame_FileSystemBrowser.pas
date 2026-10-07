unit frame_FileSystemBrowser;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.ComCtrls,
  RzCommon, RzPanel, RzButton, RzEdit, RzLabel, RzTreeVw, RzListVw, RzSplit,
  unit_FileBrowserState;

type
  IFileBrowserRequest = interface
    ['{1E8A8BB6-58B5-4AB0-A6A4-6C3FB5B28DA6}']
    procedure Start;
    procedure Cancel;
  end;

  TframeFileSystemBrowser = class(TFrame)
    pnlNavigation: TRzPanel;
    btnBack: TRzButton;
    btnForward: TRzButton;
    btnUp: TRzButton;
    btnRefresh: TRzButton;
    edPath: TRzEdit;
    tvFolders: TRzTreeView;
    splFolders: TRzSplitter;
    lvFiles: TRzListView;
    lblStatus: TRzLabel;
    procedure btnBackClick(Sender: TObject);
    procedure btnForwardClick(Sender: TObject);
    procedure btnUpClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure edPathKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure tvFoldersExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    procedure tvFoldersChange(Sender: TObject; Node: TTreeNode);
    procedure tvFoldersDeletion(Sender: TObject; Node: TTreeNode);
    procedure lvFilesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvFilesDblClick(Sender: TObject);
    procedure lvFilesColumnClick(Sender: TObject; Column: TListColumn);
    procedure lvFilesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FState: TFileBrowserState;
    FRequests: TList<IFileBrowserRequest>;
    FListRequest: IFileBrowserRequest;
    FEntries: TBrowserEntries;
    FMasks, FStatusText, FLastError: string;
    FRequestedDirectory: string;
    FNavigationKind: TBrowserNavigation;
    FSortColumn: Integer;
    FDescending, FRendering, FSelectingTree, FClosing, FLoading: Boolean;
    FCurrentNode: TTreeNode;
    FOnDirectoryChanged, FOnSelectionChanged, FOnStatusChanged: TNotifyEvent;
    procedure StartNavigation(const APath: string; AKind: TBrowserNavigation);
    procedure RenderEntries;
    procedure UpdateNavigation;
    procedure UpdateSelection;
    procedure SetStatus(const AText: string);
    procedure InitializeTree;
    procedure AddFolderNode(AParent: TTreeNode; const ACaption, APath: string);
    procedure ShowTreeLocation;
    function GetCurrentDirectory: string;
    function GetSelectedPaths: TArray<string>;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Navigate(const APath: string);
    procedure Refresh;
    procedure SetFilter(const AMasks: string);
    property CurrentDirectory: string read GetCurrentDirectory;
    property SelectedPaths: TArray<string> read GetSelectedPaths;
    property StatusText: string read FStatusText;
    property Loading: Boolean read FLoading;
    property LastError: string read FLastError;
    property OnDirectoryChanged: TNotifyEvent read FOnDirectoryChanged write FOnDirectoryChanged;
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;
    property OnStatusChanged: TNotifyEvent read FOnStatusChanged write FOnStatusChanged;
  end;

function BrowserKnownFolder(const AFolder: TGUID): string;

implementation

uses
  Winapi.Windows, Winapi.ShlObj, Winapi.KnownFolders, Winapi.ActiveX,
  System.SyncObjs, System.Generics.Defaults;

{$R *.dfm}

type
  TDirectoryComplete = reference to procedure(const ARequest: IFileBrowserRequest;
    const AEntries: TBrowserEntries; const AError: string);

  TDirectoryRequest = class(TInterfacedObject, IFileBrowserRequest)
  private
    FLock: TCriticalSection;
    FCancelled, FDirectoriesOnly, FDescending: Boolean;
    FPath, FMasks: string;
    FSortColumn: Integer;
    FOnComplete: TDirectoryComplete;
    function IsCancelled: Boolean;
    procedure Execute;
  public
    constructor Create(const APath, AMasks: string; ADirectoriesOnly: Boolean;
      AColumn: Integer; ADescending: Boolean; const AComplete: TDirectoryComplete);
    destructor Destroy; override;
    procedure Start;
    procedure Cancel;
  end;

  TFolderNodeData = class
  public
    Path: string;
    Loaded: Boolean;
    Request: IFileBrowserRequest;
    destructor Destroy; override;
  end;

function BrowserKnownFolder(const AFolder: TGUID): string;
var
  Path: PWideChar;
begin
  Result := '';
  Path := nil;
  if Succeeded(SHGetKnownFolderPath(AFolder, KF_FLAG_DONT_VERIFY, 0, Path)) then
  try
    Result := Path;
  finally
    CoTaskMemFree(Path);
  end;
end;

constructor TDirectoryRequest.Create(const APath, AMasks: string;
  ADirectoriesOnly: Boolean; AColumn: Integer; ADescending: Boolean;
  const AComplete: TDirectoryComplete);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FPath := APath;
  FMasks := AMasks;
  FDirectoriesOnly := ADirectoriesOnly;
  FSortColumn := AColumn;
  FDescending := ADescending;
  FOnComplete := AComplete;
end;

destructor TDirectoryRequest.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TDirectoryRequest.Cancel;
begin
  FLock.Enter;
  try
    FCancelled := True;
    FOnComplete := nil;
  finally
    FLock.Leave;
  end;
end;

function TDirectoryRequest.IsCancelled: Boolean;
begin
  FLock.Enter;
  try
    Result := FCancelled;
  finally
    FLock.Leave;
  end;
end;

procedure TDirectoryRequest.Start;
var
  Hold: IFileBrowserRequest;
begin
  Hold := Self;
  TThread.CreateAnonymousThread(
    procedure
    var
      KeepAlive: IFileBrowserRequest;
    begin
      KeepAlive := Hold;
      Execute;
    end).Start;
end;

procedure TDirectoryRequest.Execute;
var
  Raw, Entries: TBrowserEntries;
  Entry: TBrowserEntry;
  Items: TList<TBrowserEntry>;
  Error: string;
  Hold: IFileBrowserRequest;
begin
  if IsCancelled then Exit;
  Error := '';
  Entries := nil;
  try
    Raw := EnumerateBrowserDirectory(FPath);
    if IsCancelled then Exit;
    Items := TList<TBrowserEntry>.Create;
    try
      for Entry in Raw do
        if (not FDirectoriesOnly or Entry.IsDirectory) and
          BrowserEntryMatches(Entry, FMasks) then
          Items.Add(Entry);
      Entries := Items.ToArray;
    finally
      Items.Free;
    end;
    TArray.Sort<TBrowserEntry>(Entries, TComparer<TBrowserEntry>.Construct(
      function(const Left, Right: TBrowserEntry): Integer
      begin
        Result := CompareBrowserEntries(Left, Right, FSortColumn, FDescending);
      end));
  except
    on E: Exception do
      Error := E.Message;
  end;
  if IsCancelled then Exit;
  Hold := Self;
  TThread.Queue(nil,
    procedure
    var
      KeepAlive: IFileBrowserRequest;
      Complete: TDirectoryComplete;
    begin
      KeepAlive := Hold;
      FLock.Enter;
      try
        if FCancelled then Exit;
        Complete := FOnComplete;
      finally
        FLock.Leave;
      end;
      if Assigned(Complete) then
        Complete(KeepAlive, Entries, Error);
    end);
end;

destructor TFolderNodeData.Destroy;
begin
  if Assigned(Request) then Request.Cancel;
  inherited;
end;

constructor TframeFileSystemBrowser.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FState := TFileBrowserState.Create;
  FRequests := TList<IFileBrowserRequest>.Create;
  FMasks := '*.*';
  InitializeTree;
  UpdateNavigation;
end;

destructor TframeFileSystemBrowser.Destroy;
var
  Request: IFileBrowserRequest;
begin
  FClosing := True;
  if Assigned(FRequests) then
    for Request in FRequests do
      Request.Cancel;
  FListRequest := nil;
  FreeAndNil(FRequests);
  FState.Free;
  inherited;
end;

procedure TframeFileSystemBrowser.SetStatus(const AText: string);
begin
  FStatusText := AText;
  lblStatus.Caption := AText;
  lblStatus.Hint := AText;
  if Assigned(FOnStatusChanged) then FOnStatusChanged(Self);
end;

procedure TframeFileSystemBrowser.AddFolderNode(AParent: TTreeNode;
  const ACaption, APath: string);
var
  Node: TTreeNode;
  Data: TFolderNodeData;
begin
  if APath = '' then Exit;
  Data := TFolderNodeData.Create;
  try
    Data.Path := NormalizeBrowserPath(APath);
    Node := tvFolders.Items.AddChildObject(AParent, ACaption, Data);
  except
    Data.Free;
    raise;
  end;
  tvFolders.Items.AddChild(Node, '');
end;

procedure TframeFileSystemBrowser.InitializeTree;
var
  Drives: DWORD;
  I: Integer;
  Root: string;
begin
  AddFolderNode(nil, 'Desktop', BrowserKnownFolder(FOLDERID_Desktop));
  AddFolderNode(nil, 'Documents', BrowserKnownFolder(FOLDERID_Documents));
  AddFolderNode(nil, 'Downloads', BrowserKnownFolder(FOLDERID_Downloads));
  Drives := GetLogicalDrives;
  for I := 0 to 25 do
    if Drives and (DWORD(1) shl I) <> 0 then
    begin
      Root := Char(Ord('A') + I) + ':\';
      AddFolderNode(nil, Root, Root);
    end;
end;

procedure TframeFileSystemBrowser.ShowTreeLocation;
var
  Node: TTreeNode;
  Data: TFolderNodeData;
begin
  FSelectingTree := True;
  try
    Node := tvFolders.Items.GetFirstNode;
    while Assigned(Node) do
    begin
      Data := TFolderNodeData(Node.Data);
      if Assigned(Data) and SameText(Data.Path, CurrentDirectory) then
      begin
        tvFolders.Selected := Node;
        Exit;
      end;
      Node := Node.GetNext;
    end;
    if Assigned(FCurrentNode) then
    begin
      FCurrentNode.Delete;
      FCurrentNode := nil;
    end;
    AddFolderNode(nil, CurrentDirectory, CurrentDirectory);
    FCurrentNode := tvFolders.Items[tvFolders.Items.Count - 2];
    tvFolders.Selected := FCurrentNode;
  finally
    FSelectingTree := False;
  end;
end;

procedure TframeFileSystemBrowser.StartNavigation(const APath: string;
  AKind: TBrowserNavigation);
var
  Token: UInt64;
  Path: string;
  Request: IFileBrowserRequest;
begin
  if FClosing or (Trim(APath) = '') then Exit;
  Path := NormalizeBrowserPath(APath);
  if Assigned(FListRequest) then
  begin
    FListRequest.Cancel;
    FRequests.Remove(FListRequest);
    FListRequest := nil;
  end;
  Token := FState.BeginRequest(Path, AKind);
  FRequestedDirectory := Path;
  FNavigationKind := AKind;
  FLoading := True;
  lvFiles.Enabled := False;
  FLastError := '';
  edPath.Text := Path;
  SetStatus('Loading ' + Path);
  Request := TDirectoryRequest.Create(Path, FMasks, False, FSortColumn,
    FDescending,
    procedure(const Completed: IFileBrowserRequest;
      const Entries: TBrowserEntries; const Error: string)
    var
      OldPath: string;
    begin
      FRequests.Remove(Completed);
      FListRequest := nil;
      OldPath := CurrentDirectory;
      if not FState.CompleteRequest(Token, Error = '') then Exit;
      FLoading := False;
      lvFiles.Enabled := True;
      FLastError := Error;
      if Error = '' then
      begin
        FEntries := Entries;
        RenderEntries;
        edPath.Text := CurrentDirectory;
        ShowTreeLocation;
        UpdateNavigation;
        if not SameText(OldPath, CurrentDirectory) and Assigned(FOnDirectoryChanged) then
          FOnDirectoryChanged(Self);
      end
      else
      begin
        if CurrentDirectory <> '' then edPath.Text := CurrentDirectory;
        UpdateNavigation;
        SetStatus(Error);
      end;
      Completed.Cancel;
    end);
  FListRequest := Request;
  FRequests.Add(Request);
  Request.Start;
end;

procedure TframeFileSystemBrowser.Navigate(const APath: string);
begin
  StartNavigation(APath, bnNew);
end;

procedure TframeFileSystemBrowser.Refresh;
begin
  if CurrentDirectory <> '' then
    StartNavigation(CurrentDirectory, bnRefresh);
end;

procedure TframeFileSystemBrowser.SetFilter(const AMasks: string);
begin
  if FMasks = AMasks then Exit;
  FMasks := AMasks;
  FState.SetSelectedPaths(nil);
  FRendering := True;
  try
    lvFiles.ClearSelection;
  finally
    FRendering := False;
  end;
  if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
  if FLoading then
    StartNavigation(FRequestedDirectory, FNavigationKind)
  else
    Refresh;
end;

procedure TframeFileSystemBrowser.RenderEntries;
var
  Entry: TBrowserEntry;
  Visible: TList<string>;
  Selection: TStringList;
  Item: TListItem;
  Path: string;
  I: Integer;
begin
  Visible := TList<string>.Create;
  Selection := TStringList.Create;
  try
    for Entry in FEntries do
      if not Entry.IsDirectory then Visible.Add(Entry.FullPath);
    FState.ReconcileSelection(Visible.ToArray);
    Selection.CaseSensitive := False;
    Selection.Sorted := True;
    for Path in FState.SelectedPaths do Selection.Add(Path);
    FRendering := True;
    lvFiles.Items.BeginUpdate;
    try
      lvFiles.Items.Clear;
      for I := 0 to High(FEntries) do
      begin
        Entry := FEntries[I];
        Item := lvFiles.Items.Add;
        Item.Data := Pointer(NativeInt(I + 1));
        Item.Caption := Entry.Name;
        if Entry.IsDirectory then
        begin
          Item.SubItems.Add('Folder');
          Item.SubItems.Add('');
        end
        else
        begin
          Item.SubItems.Add(ExtractFileExt(Entry.Name));
          Item.SubItems.Add(FormatFloat('#,##0', Entry.Size) + ' B');
        end;
        Item.SubItems.Add(FormatDateTime('yyyy-mm-dd hh:nn', Entry.Modified));
        Item.Selected := not Entry.IsDirectory and (Selection.IndexOf(Entry.FullPath) >= 0);
      end;
    finally
      lvFiles.Items.EndUpdate;
      FRendering := False;
    end;
    UpdateSelection;
  finally
    Selection.Free;
    Visible.Free;
  end;
end;

procedure TframeFileSystemBrowser.UpdateSelection;
var
  Paths: TList<string>;
  Item: TListItem;
  Index: Integer;
begin
  if FRendering or FClosing then Exit;
  Paths := TList<string>.Create;
  try
    Item := lvFiles.Selected;
    while Assigned(Item) do
    begin
      Index := NativeInt(Item.Data) - 1;
      if (Index >= 0) and (Index < Length(FEntries)) and
        not FEntries[Index].IsDirectory then
        Paths.Add(FEntries[Index].FullPath);
      Item := lvFiles.GetNextItem(Item, sdAll, [isSelected]);
    end;
    FState.SetSelectedPaths(Paths.ToArray);
    SetStatus(Format('%d file(s) selected', [Paths.Count]));
  finally
    Paths.Free;
  end;
  if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
end;

procedure TframeFileSystemBrowser.UpdateNavigation;
begin
  btnBack.Enabled := FState.BackPath <> '';
  btnForward.Enabled := FState.ForwardPath <> '';
  btnUp.Enabled := BrowserParentDirectory(CurrentDirectory) <> '';
  btnRefresh.Enabled := CurrentDirectory <> '';
end;

function TframeFileSystemBrowser.GetCurrentDirectory: string;
begin
  Result := FState.CurrentDirectory;
end;

function TframeFileSystemBrowser.GetSelectedPaths: TArray<string>;
begin
  Result := FState.SelectedPaths;
end;

procedure TframeFileSystemBrowser.btnBackClick(Sender: TObject);
begin
  StartNavigation(FState.BackPath, bnBack);
end;

procedure TframeFileSystemBrowser.btnForwardClick(Sender: TObject);
begin
  StartNavigation(FState.ForwardPath, bnForward);
end;

procedure TframeFileSystemBrowser.btnUpClick(Sender: TObject);
begin
  Navigate(BrowserParentDirectory(CurrentDirectory));
end;

procedure TframeFileSystemBrowser.btnRefreshClick(Sender: TObject);
begin
  Refresh;
end;

procedure TframeFileSystemBrowser.edPathKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    Navigate(edPath.Text);
  end;
end;

procedure TframeFileSystemBrowser.tvFoldersExpanding(Sender: TObject;
  Node: TTreeNode; var AllowExpansion: Boolean);
var
  Data: TFolderNodeData;
  Request: IFileBrowserRequest;
begin
  Data := TFolderNodeData(Node.Data);
  if not Assigned(Data) or Data.Loaded then Exit;
  AllowExpansion := False;
  if Assigned(Data.Request) then Exit;
  Request := TDirectoryRequest.Create(Data.Path, '*.*', True, 0, False,
    procedure(const Completed: IFileBrowserRequest;
      const Entries: TBrowserEntries; const Error: string)
    var
      Entry: TBrowserEntry;
    begin
      FRequests.Remove(Completed);
      Data.Request := nil;
      if Error = '' then
      begin
        Node.DeleteChildren;
        for Entry in Entries do AddFolderNode(Node, Entry.Name, Entry.FullPath);
        Data.Loaded := True;
        Node.Expand(False);
      end
      else
        SetStatus(Error);
      Completed.Cancel;
    end);
  Data.Request := Request;
  FRequests.Add(Request);
  Request.Start;
end;

procedure TframeFileSystemBrowser.tvFoldersChange(Sender: TObject; Node: TTreeNode);
var
  Data: TFolderNodeData;
begin
  if FSelectingTree or FClosing or not Assigned(Node) then Exit;
  Data := TFolderNodeData(Node.Data);
  if Assigned(Data) then Navigate(Data.Path);
end;

procedure TframeFileSystemBrowser.tvFoldersDeletion(Sender: TObject; Node: TTreeNode);
var
  Data: TFolderNodeData;
begin
  if Node = FCurrentNode then FCurrentNode := nil;
  Data := TFolderNodeData(Node.Data);
  if Assigned(Data) then
  begin
    if Assigned(FRequests) and Assigned(Data.Request) then
      FRequests.Remove(Data.Request);
    Data.Free;
  end;
end;

procedure TframeFileSystemBrowser.lvFilesSelectItem(Sender: TObject;
  Item: TListItem; Selected: Boolean);
begin
  UpdateSelection;
end;

procedure TframeFileSystemBrowser.lvFilesDblClick(Sender: TObject);
var
  Index: Integer;
begin
  if not Assigned(lvFiles.Selected) then Exit;
  Index := NativeInt(lvFiles.Selected.Data) - 1;
  if (Index >= 0) and (Index < Length(FEntries)) and FEntries[Index].IsDirectory then
    Navigate(FEntries[Index].FullPath);
end;

procedure TframeFileSystemBrowser.lvFilesColumnClick(Sender: TObject;
  Column: TListColumn);
begin
  if FLoading then Exit;
  if FSortColumn = Column.Index then FDescending := not FDescending
  else
  begin
    FSortColumn := Column.Index;
    FDescending := False;
  end;
  TArray.Sort<TBrowserEntry>(FEntries, TComparer<TBrowserEntry>.Construct(
    function(const Left, Right: TBrowserEntry): Integer
    begin
      Result := CompareBrowserEntries(Left, Right, FSortColumn, FDescending);
    end));
  RenderEntries;
end;

procedure TframeFileSystemBrowser.lvFilesKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
var
  Index: Integer;
begin
  if (Key <> VK_RETURN) or not Assigned(lvFiles.Selected) then Exit;
  Index := NativeInt(lvFiles.Selected.Data) - 1;
  if (Index >= 0) and (Index < Length(FEntries)) and FEntries[Index].IsDirectory then
  begin
    Navigate(FEntries[Index].FullPath);
    Key := 0;
  end;
end;

end.
