unit dlg_Search;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls,
  unit_SearchModel, unit_SemanticSearchApi;

type
  TNavigateProc = procedure(Sender: TObject; ProjectId, FolderId, ItemId: Integer) of object;

  TdlgSearch = class(TForm)
    pnlTop: TPanel;
    edSearch: TComboBox;
    btnSearch: TButton;
    lblCount: TLabel;
    ListView: TListView;
    pnlBottom: TPanel;
    chkMeaning: TCheckBox;
    chkRerank: TCheckBox;
    chkAutoComplete: TCheckBox;
    lblStatus: TLabel;
    lblDetail: TLabel;
    tmrStatus: TTimer;
    tmrNav: TTimer;
    pnlFilters: TPanel;
    cbProject: TComboBox;
    cbItemType: TComboBox;
    chkDateFrom: TCheckBox;
    dtpFrom: TDateTimePicker;
    chkDateTo: TCheckBox;
    dtpTo: TDateTimePicker;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnSearchClick(Sender: TObject);
    procedure edSearchKeyPress(Sender: TObject; var Key: Char);
    procedure ListViewDblClick(Sender: TObject);
    procedure ListViewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListViewSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure chkMeaningClick(Sender: TObject);
    procedure chkRerankClick(Sender: TObject);
    procedure chkAutoCompleteClick(Sender: TObject);
    procedure tmrStatusTimer(Sender: TObject);
    procedure tmrNavTimer(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure chkDateClick(Sender: TObject);
    procedure ListViewColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListViewCompare(Sender: TObject; Item1, Item2: TListItem;
      Data: Integer; var Compare: Integer);
  private
    class var FInstance: TdlgSearch;
    FResults: TSearchResults;
    FResultsByMeaning: Boolean;
    FOnNavigate: TNavigateProc;
    FSemantic: ISemanticSearch;
    FRunner: TSemanticSearchRunner;
    FVisibleProjectIds: TArray<Integer>;
    FFilterProjectIds: TArray<Integer>;
    FMaxPending: Integer;
    FSearchError: string;
    FUnavailableText: string;
    FBinding: Boolean;
    FBound: Boolean;
    FSearchSeq: Integer;
    FSearchPending: Boolean;
    FBusyCursor: Boolean;
    FDateNote: string;
    FSorted: Boolean;
    FSortColumn: Integer;
    FSortDescending: Boolean;
    function ColumnText(Item: TListItem; Column: Integer): string;
    procedure UpdateSortArrows;
    procedure SetBusyCursor(Busy: Boolean);
    procedure Bind(NavigateProc: TNavigateProc; const Semantic: ISemanticSearch;
      const VisibleProjectIds: TArray<Integer>; const UnavailableText: string = '');
    procedure LoadHistory;
    procedure FillProjectFilter(Reset: Boolean);
    procedure UpdateFilterState;
    procedure RememberQuery(const Query: string);
    procedure RestoreGeometry;
    procedure SaveGeometry;
    procedure RefreshList;
    procedure NavigateToSelected;
    procedure SearchKeyword(const Query: string);
    procedure StartSearchByMeaning(const Query: string);
    procedure ShowMeaningResults(const Outcome: TSemanticSearchResult; const Error: string);
    procedure UpdateStatus;
    procedure FitDetail;
    function KindToStr(Kind: TSearchResultKind): string;
  protected
    procedure FillRow(ListItem: TListItem; const R: TSearchResult); virtual;
  public
    class procedure Execute(NavigateProc: TNavigateProc;
      const Semantic: ISemanticSearch;
      const VisibleProjectIds: TArray<Integer>;
      const UnavailableText: string = '');
    class procedure ReleaseSemantic;
    class procedure CloseInstance;
  end;

implementation

uses
  Winapi.CommCtrl, System.Math, System.DateUtils, System.Generics.Collections,
  unit_DataModel, unit_Item, unit_Project, unit_NotebookSettings, unit_SearchPassages,
  unit_HybridSearch, unit_SearchStatusText;

{$R *.dfm}


const
  FieldNames: array[TPassageField] of string = ('Title', 'Description',
    'Properties', 'Tags', 'Entry title', 'Protocol form', 'Value description',
    'File name', 'File text');
  HistoryMax = 20;
  HistorySeparator = #9;
  NotInstalledText = 'Semantic search is not installed ' + #$2014 +
    ' Tools ' + #$2192 + ' Semantic Search Setup';

class procedure TdlgSearch.Execute(NavigateProc: TNavigateProc;
  const Semantic: ISemanticSearch;
  const VisibleProjectIds: TArray<Integer>;
  const UnavailableText: string);
begin
  if FInstance = nil then
  begin
    FInstance := Self.Create(Application);
    FInstance.PopupParent := Application.MainForm;
    FInstance.LoadHistory;
    FInstance.RestoreGeometry;
  end;
  FInstance.Bind(NavigateProc, Semantic, VisibleProjectIds, UnavailableText);
  FInstance.Show;
  SendMessage(ListView_GetToolTips(FInstance.ListView.Handle), TTM_ACTIVATE, 0, 0);
  if FInstance.WindowState = wsMinimized then
    FInstance.WindowState := wsNormal;
  FInstance.SetFocus;
  FInstance.edSearch.SetFocus;
  FInstance.edSearch.SelectAll;
end;

class procedure TdlgSearch.ReleaseSemantic;
begin
  if FInstance <> nil then
    FInstance.Bind(FInstance.FOnNavigate, nil, nil, FInstance.FUnavailableText);
end;

class procedure TdlgSearch.CloseInstance;
begin
  if FInstance = nil then
    Exit;
  FInstance.SaveGeometry;
  FInstance.Free;
end;

function SameProjectIds(const A, B: TArray<Integer>): Boolean;
var
  SortedA, SortedB: TArray<Integer>;
  I: Integer;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  SortedA := Copy(A);
  SortedB := Copy(B);
  TArray.Sort<Integer>(SortedA);
  TArray.Sort<Integer>(SortedB);
  for I := 0 to High(SortedA) do
    if SortedA[I] <> SortedB[I] then
      Exit(False);
  Result := True;
end;

procedure TdlgSearch.Bind(NavigateProc: TNavigateProc;
  const Semantic: ISemanticSearch; const VisibleProjectIds: TArray<Integer>;
  const UnavailableText: string);
var
  Settings: TNotebookSettings;
  First, Changed: Boolean;
begin
  First := not FBound;
  FBound := True;
  Changed := First or (Semantic <> FSemantic) or not SameProjectIds(VisibleProjectIds, FVisibleProjectIds);
  FOnNavigate := NavigateProc;
  if Changed then
  begin
    Inc(FSearchSeq);
    if FSearchPending then
    begin
      FSearchPending := False;
      SetBusyCursor(False);
      lblCount.Caption := '';
    end;
    FreeAndNil(FRunner);
    FSemantic := Semantic;
    if Semantic <> nil then
      FRunner := TSemanticSearchRunner.Create(Semantic);
    FVisibleProjectIds := VisibleProjectIds;
    FillProjectFilter(First);
  end;
  FSearchError := '';
  FUnavailableText := UnavailableText;
  FMaxPending := 0;
  FBinding := True;
  try
    chkMeaning.Enabled := Semantic <> nil;
    chkMeaning.Checked := False;
    chkRerank.Checked := False;
    if Semantic <> nil then
    begin
      Settings := TNotebookSettings.Create;
      try
        chkMeaning.Checked := Settings.LoadUIValue('Search', 'ByMeaning', 0) = 1;
        chkRerank.Checked := Semantic.RerankerAvailable and
          (Settings.LoadUIValue('Search', 'Rerank', 1) = 1);
      finally
        Settings.Free;
      end;
    end;
  finally
    FBinding := False;
  end;
  UpdateFilterState;
  tmrStatus.Enabled := Semantic <> nil;
  UpdateStatus;
end;

procedure TdlgSearch.FillProjectFilter(Reset: Boolean);
var
  Titles: TStringList;
  Project: TProject;
  Id, KeptId: Integer;
  I: Integer;
begin
  KeptId := 0;
  if cbProject.ItemIndex > 0 then
    KeptId := FFilterProjectIds[cbProject.ItemIndex - 1];
  cbProject.Items.BeginUpdate;
  try
    cbProject.Items.Clear;
    cbProject.Items.Add('All projects');
    FFilterProjectIds := nil;
    if Length(FVisibleProjectIds) > 0 then
    begin
      Titles := TStringList.Create;
      try
        Titles.CaseSensitive := False;
        for Id in FVisibleProjectIds do
        begin
          Project := Model.Manager.Find<TProject>(Id);
          if Project <> nil then
            Titles.AddObject(Project.Title, TObject(NativeInt(Id)));
        end;
        Titles.Sort;
        for I := 0 to Titles.Count - 1 do
        begin
          cbProject.Items.Add(Titles[I]);
          FFilterProjectIds := FFilterProjectIds + [Integer(NativeInt(Titles.Objects[I]))];
        end;
      finally
        Titles.Free;
      end;
    end;
  finally
    cbProject.Items.EndUpdate;
  end;
  cbProject.ItemIndex := 0;
  for I := 0 to High(FFilterProjectIds) do
    if FFilterProjectIds[I] = KeptId then
      cbProject.ItemIndex := I + 1;
  if Reset then
  begin
    cbItemType.ItemIndex := 0;
    chkDateFrom.Checked := False;
    chkDateTo.Checked := False;
  end;
end;

procedure TdlgSearch.UpdateFilterState;
var
  Active: Boolean;
begin
  Active := chkMeaning.Enabled and chkMeaning.Checked;
  cbProject.Enabled := Active;
  cbItemType.Enabled := Active;
  chkDateFrom.Enabled := Active;
  dtpFrom.Enabled := Active and chkDateFrom.Checked;
  chkDateTo.Enabled := Active;
  dtpTo.Enabled := Active and chkDateTo.Checked;
  chkRerank.Enabled := Active and (FSemantic <> nil) and FSemantic.RerankerAvailable;
end;

procedure TdlgSearch.LoadHistory;
var
  Settings: TNotebookSettings;
  Stored, Entry: string;
begin
  Settings := TNotebookSettings.Create;
  try
    Stored := Settings.LoadUIString('Search', 'History', '');
    chkAutoComplete.Checked := Settings.LoadUIValue('Search', 'AutoComplete', 1) = 1;
    edSearch.AutoComplete := chkAutoComplete.Checked;
  finally
    Settings.Free;
  end;
  edSearch.Items.BeginUpdate;
  try
    edSearch.Items.Clear;
    for Entry in Stored.Split([HistorySeparator]) do
      if (Entry <> '') and (edSearch.Items.Count < HistoryMax) then
        edSearch.Items.Add(Entry);
  finally
    edSearch.Items.EndUpdate;
  end;
end;

procedure TdlgSearch.RememberQuery(const Query: string);
var
  Settings: TNotebookSettings;
  Joined: string;
  I: Integer;
begin
  for I := edSearch.Items.Count - 1 downto 0 do
    if SameText(edSearch.Items[I], Query) then
      edSearch.Items.Delete(I);
  edSearch.Items.Insert(0, Query);
  while edSearch.Items.Count > HistoryMax do
    edSearch.Items.Delete(edSearch.Items.Count - 1);
  edSearch.Text := Query;

  Joined := '';
  for I := 0 to edSearch.Items.Count - 1 do
    Joined := Joined + edSearch.Items[I] + HistorySeparator;
  Settings := TNotebookSettings.Create;
  try
    Settings.SaveUIString('Search', 'History', Joined);
  finally
    Settings.Free;
  end;
end;

procedure TdlgSearch.RestoreGeometry;
var
  Settings: TNotebookSettings;
  L, T, W, H: Integer;
begin
  Settings := TNotebookSettings.Create;
  try
    W := Settings.LoadUIValue('Search', 'Width', 0);
    H := Settings.LoadUIValue('Search', 'Height', 0);
    L := Settings.LoadUIValue('Search', 'Left', 0);
    T := Settings.LoadUIValue('Search', 'Top', 0);
  finally
    Settings.Free;
  end;
  if (W < Constraints.MinWidth) or (H < Constraints.MinHeight) then
    Exit;
  if Screen.MonitorFromPoint(Point(L + W div 2, T + 10), mdNull) = nil then
    Exit;
  Position := poDesigned;
  SetBounds(L, T, W, H);
end;

procedure TdlgSearch.SaveGeometry;
var
  Settings: TNotebookSettings;
begin
  if WindowState <> wsNormal then
    Exit;
  Settings := TNotebookSettings.Create;
  try
    Settings.SaveUIValue('Search', 'Left', Left);
    Settings.SaveUIValue('Search', 'Top', Top);
    Settings.SaveUIValue('Search', 'Width', Width);
    Settings.SaveUIValue('Search', 'Height', Height);
  finally
    Settings.Free;
  end;
end;

procedure TdlgSearch.UpdateStatus;
var
  Status: TSemanticSearchStatus;
begin
  lblStatus.Hint := '';
  lblStatus.ShowHint := False;
  if FSemantic = nil then
  begin
    if FUnavailableText <> '' then
      lblStatus.Caption := FUnavailableText
    else
      lblStatus.Caption := NotInstalledText;
    Exit;
  end;
  if FSearchError <> '' then
  begin
    lblStatus.Caption := FSearchError;
    Exit;
  end;
  Status := FSemantic.Status;
  if (Status.State <> ssFailed) and Status.ServerDetail then
  begin
    lblStatus.Caption := ServerStatusText(Status,
      function(Value: TDateTime): TDateTime
      begin
        Result := TTimeZone.Local.ToLocalTime(Value);
      end, FormatSettings);
    lblStatus.Hint := lblStatus.Caption;
    lblStatus.ShowHint := True;
    Exit;
  end;
  case Status.State of
    ssSyncing:
      if Status.Phase = spExtracting then
        lblStatus.Caption := Format('Reading files' + #$2026 + ' %d/%d',
          [Status.FilesDone, Status.FilesTotal])
      else
      begin
        FMaxPending := Max(FMaxPending, Status.PendingPassages);
        if FMaxPending = 0 then
          lblStatus.Caption := 'Indexing' + #$2026
        else
          lblStatus.Caption := Format('Indexing' + #$2026 + ' %d %%',
            [(FMaxPending - Status.PendingPassages) * 100 div FMaxPending]);
      end;
    ssFailed:
      lblStatus.Caption := 'Indexing failed: ' + Status.LastError;
  else
    FMaxPending := 0;
    lblStatus.Caption := Format('Indexed %d passages', [Status.IndexedPassages]);
  end;
end;

procedure TdlgSearch.tmrStatusTimer(Sender: TObject);
begin
  UpdateFilterState;
  UpdateStatus;
end;

procedure TdlgSearch.chkMeaningClick(Sender: TObject);
var
  Settings: TNotebookSettings;
begin
  UpdateFilterState;
  if FBinding or (FSemantic = nil) then
    Exit;
  Settings := TNotebookSettings.Create;
  try
    Settings.SaveUIValue('Search', 'ByMeaning', Ord(chkMeaning.Checked));
  finally
    Settings.Free;
  end;
end;

procedure TdlgSearch.chkRerankClick(Sender: TObject);
var
  Settings: TNotebookSettings;
begin
  if FBinding or (FSemantic = nil) then
    Exit;
  Settings := TNotebookSettings.Create;
  try
    Settings.SaveUIValue('Search', 'Rerank', Ord(chkRerank.Checked));
  finally
    Settings.Free;
  end;
end;

procedure TdlgSearch.chkAutoCompleteClick(Sender: TObject);
var
  Settings: TNotebookSettings;
begin
  edSearch.AutoComplete := chkAutoComplete.Checked;
  Settings := TNotebookSettings.Create;
  try
    Settings.SaveUIValue('Search', 'AutoComplete', Ord(chkAutoComplete.Checked));
  finally
    Settings.Free;
  end;
end;

procedure TdlgSearch.chkDateClick(Sender: TObject);
begin
  UpdateFilterState;
end;

procedure TdlgSearch.SetBusyCursor(Busy: Boolean);
begin
  if Busy = FBusyCursor then
    Exit;
  FBusyCursor := Busy;
  if Busy then
    Screen.Cursor := crHourGlass
  else
    Screen.Cursor := crDefault;
end;

procedure TdlgSearch.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveGeometry;
  Action := caFree;
end;

procedure TdlgSearch.FormDestroy(Sender: TObject);
begin
  SetBusyCursor(False);
  FreeAndNil(FRunner);
  FSemantic := nil;
  if FInstance = Self then
    FInstance := nil;
  FreeAndNil(FResults);
end;

procedure TdlgSearch.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and not edSearch.DroppedDown then
  begin
    Key := 0;
    Close;
  end;
end;

function TdlgSearch.KindToStr(Kind: TSearchResultKind): string;
begin
  case Kind of
    srkItem:  Result := 'Item';
    srkEntry: Result := 'Protocol';
    srkFile:  Result := 'File';
    srkValue: Result := 'Value';
    srkTag:   Result := 'Tag';
  else
    Result := '';
  end;
end;

procedure TdlgSearch.edSearchKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    btnSearchClick(Sender);
  end;
end;

procedure TdlgSearch.btnSearchClick(Sender: TObject);
var
  Query: string;
begin
  Query := StringReplace(Trim(edSearch.Text), HistorySeparator, ' ', [rfReplaceAll]);
  if Length(Query) < 2 then
  begin
    lblCount.Caption := 'Min 2 characters';
    Exit;
  end;

  Inc(FSearchSeq);
  FSearchPending := False;
  SetBusyCursor(False);
  FSearchError := '';
  FreeAndNil(FResults);
  FSorted := False;
  UpdateSortArrows;
  if chkMeaning.Checked and (FSemantic <> nil) then
    StartSearchByMeaning(Query)
  else
  begin
    Screen.Cursor := crHourGlass;
    try
      SearchKeyword(Query);
      RefreshList;
      if FResults <> nil then
        lblCount.Caption := Format('%d result(s)', [FResults.Count]);
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  RememberQuery(Query);
end;

procedure TdlgSearch.SearchKeyword(const Query: string);
var
  Visible: TDictionary<Integer, Boolean>;
  Id, I: Integer;
begin
  FResultsByMeaning := False;
  FResults := Model.Search.Search(Query);
  Visible := TDictionary<Integer, Boolean>.Create;
  try
    for Id in FVisibleProjectIds do
      Visible.AddOrSetValue(Id, True);
    for I := FResults.Count - 1 downto 0 do
      if not Visible.ContainsKey(FResults[I].ProjectId) then
        FResults.Delete(I);
  finally
    Visible.Free;
  end;
end;

procedure TdlgSearch.StartSearchByMeaning(const Query: string);
var
  Request: TSemanticSearchRequest;
  Seq: Integer;
begin
  FResultsByMeaning := True;
  Request := Default(TSemanticSearchRequest);
  Request.Query := Query;
  Request.VisibleProjectIds := FVisibleProjectIds;
  if cbProject.ItemIndex > 0 then
    Request.VisibleProjectIds := [FFilterProjectIds[cbProject.ItemIndex - 1]];
  Request.TopK := 50;
  if cbItemType.ItemIndex > 0 then
    Request.Filter.ItemTypes := [cbItemType.Items[cbItemType.ItemIndex]];
  FDateNote := '';
  if chkDateFrom.Checked or chkDateTo.Checked then
    Request.Filter.DateField := sdfCreated;
  if chkDateFrom.Checked then
  begin
    Request.Filter.DateFrom := Int(dtpFrom.Date);
    FDateNote := ' from ' + DateToStr(Request.Filter.DateFrom);
  end;
  if chkDateTo.Checked then
  begin
    Request.Filter.DateTo := Int(dtpTo.Date);
    FDateNote := FDateNote + ' to ' + DateToStr(Request.Filter.DateTo);
  end;
  if FDateNote <> '' then
    FDateNote := ', created' + FDateNote;
  Request.Rerank := chkRerank.Enabled and chkRerank.Checked;
  lblCount.Caption := 'Searching' + #$2026;
  RefreshList;
  Seq := FSearchSeq;
  FSearchPending := True;
  SetBusyCursor(True);
  FRunner.Start(Request,
    procedure(const Outcome: TSemanticSearchResult; const Error: string)
    begin
      if Seq = FSearchSeq then
        ShowMeaningResults(Outcome, Error);
    end);
end;

procedure TdlgSearch.ShowMeaningResults(const Outcome: TSemanticSearchResult;
  const Error: string);
var
  Group: THybridGroup;
  Item: TItem;
  R: TSearchResult;
begin
  FSearchPending := False;
  SetBusyCursor(False);
  if Error <> '' then
  begin
    FSearchError := Error;
    lblStatus.Caption := FSearchError;
    lblCount.Caption := '';
    RefreshList;
    Exit;
  end;
  FreeAndNil(FResults);
  FResults := TSearchResults.Create;
  for Group in Outcome.Groups do
  begin
    Item := Model.Manager.Find<TItem>(Group.ItemId);
    if Item = nil then
      Continue;
    R := Default(TSearchResult);
    R.Kind := srkItem;
    R.ItemId := Item.Id;
    R.ProjectId := Item.ProjectID;
    R.FolderId := Item.FolderID;
    R.ItemTitle := Item.Title;
    R.EntityName := FieldNames[Group.Passages[0].Field];
    R.MatchedField := StringReplace(StringReplace(Group.Passages[0].Snippet, #13, ' ', [rfReplaceAll]),
      #10, ' ', [rfReplaceAll]);
    R.ProjectPath := Model.Search.BuildProjectPath(Item.ProjectID, Item.FolderID);
    FResults.Add(R);
  end;
  RefreshList;
  lblCount.Caption := Format('%d result(s)', [FResults.Count]) + FDateNote;
  if Outcome.Reranked then
    lblCount.Caption := lblCount.Caption + ', reranked';
end;

procedure TdlgSearch.RefreshList;
var
  I: Integer;
  ListItem: TListItem;
begin
  tmrNav.Enabled := False;
  lblDetail.Caption := '';
  FitDetail;
  ListView.Items.BeginUpdate;
  try
    ListView.Items.Clear;
    if not Assigned(FResults) then
      Exit;

    for I := 0 to FResults.Count - 1 do
    begin
      ListItem := ListView.Items.Add;
      FillRow(ListItem, FResults[I]);
      ListItem.Data := Pointer(I);
    end;
  finally
    ListView.Items.EndUpdate;
  end;
end;

procedure TdlgSearch.FillRow(ListItem: TListItem; const R: TSearchResult);
begin
  ListItem.Caption := IntToStr(R.ItemId);
  if FResultsByMeaning then
  begin
    ListItem.SubItems.Add(R.EntityName);
    ListItem.SubItems.Add(R.ItemTitle);
    ListItem.SubItems.Add(R.ProjectPath);
  end
  else
  begin
    ListItem.SubItems.Add(KindToStr(R.Kind));
    ListItem.SubItems.Add(R.EntityName);
    ListItem.SubItems.Add(R.ProjectPath + ' > ' + R.ItemTitle);
  end;
  ListItem.SubItems.Add(R.MatchedField);
end;

function TdlgSearch.ColumnText(Item: TListItem; Column: Integer): string;
begin
  if Column = 0 then
    Result := Item.Caption
  else if Column - 1 < Item.SubItems.Count then
    Result := Item.SubItems[Column - 1]
  else
    Result := '';
end;

procedure TdlgSearch.ListViewCompare(Sender: TObject; Item1, Item2: TListItem;
  Data: Integer; var Compare: Integer);
var
  A, B: string;
  NumA, NumB: Int64;
begin
  A := ColumnText(Item1, FSortColumn);
  B := ColumnText(Item2, FSortColumn);
  if TryStrToInt64(A, NumA) and TryStrToInt64(B, NumB) then
    Compare := CompareValue(NumA, NumB)
  else
    Compare := AnsiCompareText(A, B);
  if FSortDescending then
    Compare := -Compare;
  if Compare = 0 then
    Compare := CompareValue(NativeInt(Item1.Data), NativeInt(Item2.Data));
end;

procedure TdlgSearch.ListViewColumnClick(Sender: TObject; Column: TListColumn);
begin
  if FSorted and (FSortColumn = Column.Index) then
    FSortDescending := not FSortDescending
  else
  begin
    FSorted := True;
    FSortColumn := Column.Index;
    FSortDescending := False;
  end;
  ListView.AlphaSort;
  if ListView.Selected <> nil then
    ListView.Selected.MakeVisible(False);
  UpdateSortArrows;
end;

procedure TdlgSearch.UpdateSortArrows;
var
  Header: HWND;
  Item: THDItem;
  I: Integer;
begin
  if not ListView.HandleAllocated then
    Exit;
  Header := ListView_GetHeader(ListView.Handle);
  for I := 0 to ListView.Columns.Count - 1 do
  begin
    Item := Default(THDItem);
    Item.Mask := HDI_FORMAT;
    if not Header_GetItem(Header, I, Item) then
      Continue;
    Item.fmt := Item.fmt and not (HDF_SORTUP or HDF_SORTDOWN);
    if FSorted and (I = FSortColumn) then
      if FSortDescending then
        Item.fmt := Item.fmt or HDF_SORTDOWN
      else
        Item.fmt := Item.fmt or HDF_SORTUP;
    Header_SetItem(Header, I, Item);
  end;
end;

procedure TdlgSearch.NavigateToSelected;
var
  Idx: Integer;
  R: TSearchResult;
begin
  if ListView.Selected = nil then
    Exit;
  if not Assigned(FResults) then
    Exit;
  if not Assigned(FOnNavigate) then
    Exit;

  Idx := Integer(ListView.Selected.Data);
  if (Idx < 0) or (Idx >= FResults.Count) then
    Exit;

  R := FResults[Idx];
  FOnNavigate(Self, R.ProjectId, R.FolderId, R.ItemId);
end;

procedure TdlgSearch.ListViewDblClick(Sender: TObject);
begin
  tmrNav.Enabled := False;
  NavigateToSelected;
end;

procedure TdlgSearch.ListViewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    tmrNav.Enabled := False;
    NavigateToSelected;
  end;
end;

procedure TdlgSearch.ListViewSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not Selected then
    Exit;
  if (FResults <> nil) and (Integer(Item.Data) < FResults.Count) then
    lblDetail.Caption := FResults[Integer(Item.Data)].MatchedField;
  FitDetail;
  tmrNav.Enabled := False;
  tmrNav.Enabled := True;
end;

procedure TdlgSearch.FitDetail;
var
  R: TRect;
begin
  R := Rect(0, 0, lblDetail.Width, 0);
  lblDetail.Canvas.Font := lblDetail.Font;
  DrawText(lblDetail.Canvas.Handle, PChar(lblDetail.Caption), -1, R,
    DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
  pnlBottom.Height := Max(68, R.Height + lblDetail.Margins.Top + lblDetail.Margins.Bottom);
end;

procedure TdlgSearch.FormResize(Sender: TObject);
begin
  FitDetail;
end;

procedure TdlgSearch.tmrNavTimer(Sender: TObject);
begin
  tmrNav.Enabled := False;
  NavigateToSelected;
end;

end.
