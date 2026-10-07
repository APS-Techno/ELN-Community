unit frame_Dashboard;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Math, System.Generics.Collections, System.DateUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  RzPanel, RzLabel,
  unit_Item, unit_Protocol, unit_AuditLog, unit_Project, unit_User,
  unit_ProjectModel, RzButton, unit_NotebookSettings,
  unit_HypothesisModel, unit_HypothesesVM;

const
  // Section accent colors (Delphi BGR)
  clAccentRecentItems = $00B0803A;  // Steel blue
  clAccentProtocols   = $000080D0;  // Amber
  clAccentProjects    = $00809040;  // Teal
  clAccentActivity    = $00996070;  // Purple/slate
  clAccentApprovals   = $00A05090;  // Plum

  // Activity dots
  clDotCreate         = $0040B040;  // Green
  clDotUpdate         = $00C08020;  // Blue-ish
  clDotDelete         = $002020D0;  // Red

  // Protocol status dots
  clStatusDraft       = $000080D0;  // Amber
  clStatusInReview    = $00C07020;  // Blue

  // Recent items age dots
  clDotToday          = $0040B040;  // Green
  clDotThisWeek       = $00B0803A;  // Steel blue
  clDotOlder          = $00A0A0A0;  // Gray

  // Project squares palette
  clProjectColors: array[0..5] of TColor = (
    $00B0803A, $00809040, $000080D0, $00996070, $00C07020, $002F4F4F
  );

function BlendColor(C1, C2: TColor; Ratio: Byte): TColor;

type
  TNavigateItemEvent = procedure(Sender: TObject; ProjectId, FolderId, ItemId: Integer) of object;

  TframeDashboard = class(TFrame)
    pnlWelcome: TRzPanel;
    pbAvatar: TPaintBox;
    lblGreeting: TRzLabel;
    lblRoleDate: TRzLabel;
    lblQuickStats: TRzLabel;
    Splitter2: TSplitter;
    RzPanel1: TRzPanel;
    pnlBottom: TPanel;
    Splitter3: TSplitter;
    pnlProjects: TPanel;
    pbHeaderProjects: TPaintBox;
    lbProjects: TListBox;
    pnlActivity: TPanel;
    pbHeaderActivity: TPaintBox;
    lbActivity: TListBox;
    pnlTop: TPanel;
    Splitter1: TSplitter;
    pnlRecentItems: TPanel;
    pbHeaderRecent: TPaintBox;
    lbRecentItems: TListBox;
    pnlProtocols: TPanel;
    pbHeaderProtocols: TPaintBox;
    lbProtocols: TListBox;
    btnRefresh: TRzBitBtn;
    cbScale: TComboBox;
    lblScale: TRzLabel;
    pnlFilters: TRzPanel;
    lblFilterUser: TRzLabel;
    cbFilterUser: TComboBox;
    lblFilterTimeRange: TRzLabel;
    cbFilterTimeRange: TComboBox;
    Splitter4: TSplitter;
    pnlApprovals: TPanel;
    pbHeaderApprovals: TPaintBox;
    lbApprovals: TListBox;
    procedure btnRefreshClick(Sender: TObject);
    procedure cbScaleChange(Sender: TObject);
    procedure lbRecentItemsDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure lbProtocolsDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure lbProjectsDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure lbActivityDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure lbRecentItemsClick(Sender: TObject);
    procedure lbProtocolsClick(Sender: TObject);
    procedure pbAvatarPaint(Sender: TObject);
    procedure pbHeaderRecentPaint(Sender: TObject);
    procedure pbHeaderProtocolsPaint(Sender: TObject);
    procedure pbHeaderProjectsPaint(Sender: TObject);
    procedure pbHeaderActivityPaint(Sender: TObject);
    procedure pbHeaderApprovalsPaint(Sender: TObject);
    procedure lbApprovalsDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure lbApprovalsClick(Sender: TObject);
    procedure lbActivityClick(Sender: TObject);
    procedure FrameResize(Sender: TObject);
    procedure FilterChanged(Sender: TObject);
  private
    FRecentItems: TItems;
    FProtocols: TObjectList<TProtocol>;
    FAuditLogs: TAuditLogs;
    FProjectStats: TProjectStatsList;
    FApprovals: TArray<THypothesisSummary>;
    FOnNavigateItem: TNavigateItemEvent;
    FOnOpenHypothesis: TOpenHypothesisEvent;
    FUserRole: TDBRole;
    FInitials: string;
    FAvatarColor: TColor;
    FUserNameCache: TDictionary<Integer, string>;
    FProjectNameCache: TDictionary<Integer, string>;
    FScalePct: Integer;  // combined DPI + user scale percentage
    // Supervisor filter state
    FFilterUserId: Integer;
    FFilterDateFrom: TDateTime;
    FFilterUserIds: TList<Integer>;
    function GetDateFromForRange(Index: Integer): TDateTime;
    function S(V: Integer): Integer;
    procedure ApplyScale;
    procedure WelcomeResize(Sender: TObject);
    procedure ClearData;
    procedure LoadRecentItems;
    procedure LoadProtocols;
    procedure LoadApprovals;
    procedure LoadProjectStats;
    procedure LoadActivityFeed;
    procedure UpdateWelcome;
    procedure UpdateListCounts;
    function MaxVisibleItems(AListBox: TListBox): Integer;
    procedure BuildProjectNameCache;
    procedure BuildUserNameCache;
    // Drawing helpers
    procedure DrawSectionHeader(ACanvas: TCanvas; ARect: TRect;
      const ATitle: string; AAccentColor: TColor; ACount: Integer);
    procedure DrawRowBackground(ACanvas: TCanvas; ARect: TRect;
      Index: Integer; State: TOwnerDrawState);
    procedure DrawItemSeparator(ACanvas: TCanvas; ARect: TRect);
    procedure DrawColorDot(ACanvas: TCanvas; X, Y, Radius: Integer; AColor: TColor);
    procedure DrawColorSquare(ACanvas: TCanvas; X, Y, Size: Integer; AColor: TColor);
    procedure DrawEmptyState(AListBox: TListBox; const AMessage: string);
    function RelativeTimeStr(ADate: TDateTime): string;
    function GetProjectName(ProjectID: Integer): string;
    function GetUserName(UserID: Integer): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadData(UserRole: TDBRole);
    /// <summary>Reloads the "Waiting for You" list only (cheap), without
    /// touching the rest of the dashboard - called after a gate, Submit, a
    /// proposal or Abandon (frm_Main.HypothesisDecisionsChanged).</summary>
    procedure RefreshApprovals;
    /// <summary>Logout: call before Model is freed. Drops every list that
    /// points at manager-owned entities and empties the list boxes, so a
    /// repaint during the modal re-login never reaches a freed object.
    /// </summary>
    procedure ClearEntities;
    property OnNavigateItem: TNavigateItemEvent read FOnNavigateItem write FOnNavigateItem;
    property OnOpenHypothesis: TOpenHypothesisEvent read FOnOpenHypothesis write FOnOpenHypothesis;
  end;

implementation

{$R *.dfm}

uses
  System.StrUtils,
  Vcl.Dialogs,
  Aurelius.Engine.ObjectManager,
  Winapi.GDIPAPI, Winapi.GDIPOBJ,
  Vcl.Themes,
  unit_DataModel, unit_ItemTypes, unit_AuthorModel,
  unit_TimeHelper,
  unit_Hypothesis, unit_HypothesisQueries, unit_Signature;

function StyledColor(AColor: TColor): TColor;
begin
  if TStyleManager.IsCustomStyleActive then
    Result := StyleServices.GetSystemColor(AColor)
  else
    Result := AColor;
end;

function BlendColor(C1, C2: TColor; Ratio: Byte): TColor;
var
  R1, G1, B1, R2, G2, B2: Byte;
begin
  C1 := ColorToRGB(C1);
  C2 := ColorToRGB(C2);
  R1 := GetRValue(C1); G1 := GetGValue(C1); B1 := GetBValue(C1);
  R2 := GetRValue(C2); G2 := GetGValue(C2); B2 := GetBValue(C2);
  Result := RGB(
    R1 + MulDiv(R2 - R1, Ratio, 255),
    G1 + MulDiv(G2 - G1, Ratio, 255),
    B1 + MulDiv(B2 - B1, Ratio, 255));
end;

{ TframeDashboard }

constructor TframeDashboard.Create(AOwner: TComponent);
var
  BgColor: TColor;
  Settings: TNotebookSettings;
  UserPct, Idx: Integer;
begin
  inherited;
  FUserNameCache := TDictionary<Integer, string>.Create;
  FProjectNameCache := TDictionary<Integer, string>.Create;
  FAvatarColor := $002F4F4F;
  OnResize := FrameResize;
  pnlWelcome.OnResize := WelcomeResize;

  // Load user scale preference
  Settings := TNotebookSettings.Create;
  try
    UserPct := Settings.DashboardScale;
  finally
    Settings.Free;
  end;

  // Combined scale: DPI normalization * user preference
  // Drawing code uses 96-PPI baseline values; scale up for actual DPI
  FScalePct := MulDiv(UserPct, Screen.PixelsPerInch, 96);

  // Set combo to match saved value
  Idx := cbScale.Items.IndexOf(IntToStr(UserPct) + '%');
  if Idx >= 0 then
    cbScale.ItemIndex := Idx
  else
    cbScale.ItemIndex := 1; // 100%

  ApplyScale;

  // Apply themed panel color to listboxes
  BgColor := StyledColor(clBtnFace);
  lbRecentItems.Color := BgColor;
  lbProtocols.Color := BgColor;
  lbProjects.Color := BgColor;
  lbActivity.Color := BgColor;
  lbApprovals.Color := BgColor;
end;

destructor TframeDashboard.Destroy;
begin
  ClearData;
  FreeAndNil(FFilterUserIds);
  FUserNameCache.Free;
  FProjectNameCache.Free;
  inherited;
end;

function TframeDashboard.S(V: Integer): Integer;
begin
  Result := MulDiv(V, FScalePct, 100);
end;

procedure TframeDashboard.ApplyScale;
begin
  // Section header paintbox heights
  pbHeaderRecent.Height    := S(32);
  pbHeaderProtocols.Height := S(32);
  pbHeaderProjects.Height  := S(32);
  pbHeaderActivity.Height  := S(32);
  pbHeaderApprovals.Height := S(32);

  // Listbox item heights
  lbRecentItems.ItemHeight := S(52);
  lbProtocols.ItemHeight   := S(52);
  lbProjects.ItemHeight    := S(48);
  lbActivity.ItemHeight    := S(40);
  lbApprovals.ItemHeight   := S(52);
end;

procedure TframeDashboard.cbScaleChange(Sender: TObject);
var
  Settings: TNotebookSettings;
  UserPct: Integer;
  Txt: string;
begin
  Txt := cbScale.Text;
  UserPct := StrToIntDef(Copy(Txt, 1, Length(Txt) - 1), 100);
  FScalePct := MulDiv(UserPct, Screen.PixelsPerInch, 96);

  Settings := TNotebookSettings.Create;
  try
    Settings.DashboardScale := UserPct;
  finally
    Settings.Free;
  end;

  ApplyScale;
  UpdateListCounts;

  pbHeaderRecent.Invalidate;
  pbHeaderProtocols.Invalidate;
  pbHeaderProjects.Invalidate;
  pbHeaderActivity.Invalidate;
  pbHeaderApprovals.Invalidate;
  pbAvatar.Invalidate;

  lbRecentItems.Invalidate;
  lbProtocols.Invalidate;
  lbProjects.Invalidate;
  lbActivity.Invalidate;
  lbApprovals.Invalidate;
end;

procedure TframeDashboard.ClearData;
begin
  FreeAndNil(FRecentItems);
  FreeAndNil(FProtocols);
  FreeAndNil(FAuditLogs);
  FreeAndNil(FProjectStats);
  FApprovals := nil;
  FUserNameCache.Clear;
  FProjectNameCache.Clear;
end;

procedure TframeDashboard.ClearEntities;
begin
  ClearData;
  // Invalidate as UpdateListCounts does: a virtual list box may not repaint
  // on a Count change alone and would keep the old rows on screen.
  lbRecentItems.Count := 0;
  lbRecentItems.Invalidate;
  lbProtocols.Count := 0;
  lbProtocols.Invalidate;
  lbProjects.Count := 0;
  lbProjects.Invalidate;
  lbActivity.Count := 0;
  lbActivity.Invalidate;
  UpdateListCounts;   // Approvals keeps its one "Nothing waits for you." row
end;

{ --- Welcome Bar --- }

procedure TframeDashboard.UpdateWelcome;
var
  User: TUser;
  S: string;
  p: Integer;
begin
  User := unit_DataModel.Model.User;
  if not Assigned(User) then Exit;

  // Greeting
  lblGreeting.Caption := 'Welcome back, ' + User.DisplayName;

  // Role + date
  lblRoleDate.Caption := User.RoleString +
    ' '#183' ' + FormatDateTime('dddd, mmmm d, yyyy', Now);

  // Avatar initials
  S := User.DisplayName;
  FInitials := '';
  if Length(S) > 0 then
  begin
    FInitials := UpperCase(S[1]);
    p := Pos(' ', S);
    if (p > 0) and (p < Length(S)) then
      FInitials := FInitials + UpperCase(S[p + 1]);
  end;

  // Avatar color based on role
  case User.Role of
    dbAdmin: FAvatarColor := $001E96C8;
    dbSuper: FAvatarColor := $00996633;
  else
    FAvatarColor := $002F4F4F;
  end;

  lblQuickStats.Caption := '';

  pbAvatar.Invalidate;
end;

procedure TframeDashboard.pbAvatarPaint(Sender: TObject);
var
  G: TGPGraphics;
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
  GFont: TGPFont;
  SF: TGPStringFormat;
  R: TGPRectF;
  C: TColor;
  Radius, W, H: Integer;
begin
  C := ColorToRGB(FAvatarColor);
  G := TGPGraphics.Create(pbAvatar.Canvas.Handle);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    G.SetTextRenderingHint(TextRenderingHintAntiAlias);

    // Rounded rectangle background
    Brush := TGPSolidBrush.Create(MakeColor(255, GetRValue(C), GetGValue(C), GetBValue(C)));
    try
      Path := TGPGraphicsPath.Create;
      try
        Radius := 10;
        W := pbAvatar.Width - 1;
        H := pbAvatar.Height - 1;
        Path.AddArc(0, 0, Radius, Radius, 180, 90);
        Path.AddArc(W - Radius, 0, Radius, Radius, 270, 90);
        Path.AddArc(W - Radius, H - Radius, Radius, Radius, 0, 90);
        Path.AddArc(0, H - Radius, Radius, Radius, 90, 90);
        Path.CloseFigure;
        G.FillPath(Brush, Path);
      finally
        Path.Free;
      end;
    finally
      Brush.Free;
    end;

    // Initials text
    if FInitials <> '' then
    begin
      GFont := TGPFont.Create('Segoe UI', S(15), FontStyleBold);
      SF := TGPStringFormat.Create;
      Brush := TGPSolidBrush.Create(MakeColor(255, 245, 245, 245));
      try
        SF.SetAlignment(StringAlignmentCenter);
        SF.SetLineAlignment(StringAlignmentCenter);
        R := MakeRect(0.0, 0.0, Single(pbAvatar.Width), Single(pbAvatar.Height));
        G.DrawString(FInitials, Length(FInitials), GFont, R, SF, Brush);
      finally
        Brush.Free;
        SF.Free;
        GFont.Free;
      end;
    end;
  finally
    G.Free;
  end;
end;

{ --- List Count Limiting (no scrollbars) --- }

function TframeDashboard.MaxVisibleItems(AListBox: TListBox): Integer;
begin
  if AListBox.ItemHeight > 0 then
    Result := AListBox.ClientHeight div AListBox.ItemHeight
  else
    Result := 0;
  if Result < 0 then
    Result := 0;
end;

procedure TframeDashboard.UpdateListCounts;
var
  N: Integer;
begin
  // Recent Items
  if Assigned(FRecentItems) then
  begin
    N := Min(FRecentItems.Count, MaxVisibleItems(lbRecentItems));
    if lbRecentItems.Count <> N then
    begin
      lbRecentItems.Count := N;
      lbRecentItems.Invalidate;
    end;
  end;

  // Protocols
  if Assigned(FProtocols) then
  begin
    N := Min(FProtocols.Count, MaxVisibleItems(lbProtocols));
    if lbProtocols.Count <> N then
    begin
      lbProtocols.Count := N;
      lbProtocols.Invalidate;
    end;
  end;

  // Projects
  if Assigned(FProjectStats) then
  begin
    N := Min(FProjectStats.Count, MaxVisibleItems(lbProjects));
    if lbProjects.Count <> N then
    begin
      lbProjects.Count := N;
      lbProjects.Invalidate;
    end;
  end;

  // Activity
  if Assigned(FAuditLogs) then
  begin
    N := Min(Min(FAuditLogs.Count, 50), MaxVisibleItems(lbActivity));
    if lbActivity.Count <> N then
    begin
      lbActivity.Count := N;
      lbActivity.Invalidate;
    end;
  end;

  // Approvals: unlike the other lists here, clamp to a minimum Count of 1
  // when empty, so index 0 is still drawn and lbApprovalsDrawItem's "Nothing
  // waits for you." branch actually paints (the other lists' owner-draw
  // empty-state branches are currently unreachable at Count = 0 - not fixed
  // here, out of this task's scope).
  N := Max(1, Min(Length(FApprovals), MaxVisibleItems(lbApprovals)));
  if lbApprovals.Count <> N then
    lbApprovals.Count := N;
  lbApprovals.Invalidate;
end;

procedure TframeDashboard.WelcomeResize(Sender: TObject);
begin
  // The aligned refresh button, not the streamed anchors, defines the right edge.
  cbScale.Left := btnRefresh.Left - btnRefresh.Margins.Left - cbScale.Width;
  lblScale.Left := cbScale.Left - btnRefresh.Margins.Left - lblScale.Width;
end;

procedure TframeDashboard.FrameResize(Sender: TObject);
begin
  UpdateListCounts;
end;

{ --- Section Headers --- }

procedure TframeDashboard.DrawSectionHeader(ACanvas: TCanvas; ARect: TRect;
  const ATitle: string; AAccentColor: TColor; ACount: Integer);
var
  AccentRect: TRect;
  CountStr: string;
  CountWidth: Integer;
begin
  // Background
  ACanvas.Brush.Color := StyledColor(clBtnFace);
  ACanvas.FillRect(ARect);

  // Left accent strip
  AccentRect := Rect(ARect.Left, ARect.Top + S(4), ARect.Left + S(4), ARect.Bottom - S(4));
  ACanvas.Brush.Color := AAccentColor;
  ACanvas.FillRect(AccentRect);

  // Title text
  ACanvas.Font.Name := 'Segoe UI';
  ACanvas.Font.Height := -S(13);
  ACanvas.Font.Style := [fsBold];
  ACanvas.Font.Color := StyledColor(clWindowText);
  ACanvas.Brush.Style := bsClear;
  ACanvas.TextOut(ARect.Left + S(12), ARect.Top + S(7), ATitle);

  // Count badge (right-aligned)
  if ACount >= 0 then
  begin
    CountStr := IntToStr(ACount) + IfThen(ACount = 1, ' item', ' items');
    ACanvas.Font.Height := -S(11);
    ACanvas.Font.Style := [];
    ACanvas.Font.Color := clGray;
    CountWidth := ACanvas.TextWidth(CountStr);
    ACanvas.TextOut(ARect.Right - CountWidth - S(8), ARect.Top + S(9), CountStr);
  end;

  ACanvas.Brush.Style := bsSolid;

  // Bottom border line
  ACanvas.Pen.Color := BlendColor(StyledColor(clBtnFace), StyledColor(clBtnShadow), 40);
  ACanvas.MoveTo(ARect.Left, ARect.Bottom - 1);
  ACanvas.LineTo(ARect.Right, ARect.Bottom - 1);
end;

procedure TframeDashboard.pbHeaderRecentPaint(Sender: TObject);
var
  Count: Integer;
begin
  if Assigned(FRecentItems) then Count := FRecentItems.Count
  else Count := 0;
  DrawSectionHeader(pbHeaderRecent.Canvas,
    Rect(0, 0, pbHeaderRecent.Width, pbHeaderRecent.Height),
    'Recent Items', clAccentRecentItems, Count);
end;

procedure TframeDashboard.pbHeaderProtocolsPaint(Sender: TObject);
var
  Count: Integer;
begin
  if Assigned(FProtocols) then Count := FProtocols.Count
  else Count := 0;
  DrawSectionHeader(pbHeaderProtocols.Canvas,
    Rect(0, 0, pbHeaderProtocols.Width, pbHeaderProtocols.Height),
    'Protocols Awaiting Review', clAccentProtocols, Count);
end;

procedure TframeDashboard.pbHeaderProjectsPaint(Sender: TObject);
var
  Count: Integer;
begin
  if Assigned(FProjectStats) then Count := FProjectStats.Count
  else Count := 0;
  DrawSectionHeader(pbHeaderProjects.Canvas,
    Rect(0, 0, pbHeaderProjects.Width, pbHeaderProjects.Height),
    'Project Statistics', clAccentProjects, Count);
end;

procedure TframeDashboard.pbHeaderActivityPaint(Sender: TObject);
var
  Count: Integer;
begin
  if Assigned(FAuditLogs) then Count := Min(FAuditLogs.Count, 50)
  else Count := 0;
  DrawSectionHeader(pbHeaderActivity.Canvas,
    Rect(0, 0, pbHeaderActivity.Width, pbHeaderActivity.Height),
    'Activity Feed', clAccentActivity, Count);
end;

procedure TframeDashboard.pbHeaderApprovalsPaint(Sender: TObject);
begin
  // Pre-flight C9 dashboard wording.
  DrawSectionHeader(pbHeaderApprovals.Canvas,
    Rect(0, 0, pbHeaderApprovals.Width, pbHeaderApprovals.Height),
    'Waiting for You', clAccentApprovals, Length(FApprovals));
end;

{ --- Drawing Helpers --- }

procedure TframeDashboard.DrawRowBackground(ACanvas: TCanvas; ARect: TRect;
  Index: Integer; State: TOwnerDrawState);
var
  BgColor: TColor;
begin
  BgColor := StyledColor(clBtnFace);
  if odSelected in State then
    ACanvas.Brush.Color := BlendColor(BgColor, StyledColor(clHighlight), 60)
  else if Odd(Index) then
    ACanvas.Brush.Color := BlendColor(BgColor, StyledColor(clBtnShadow), 20)
  else
    ACanvas.Brush.Color := BgColor;
  ACanvas.Font.Color := StyledColor(clWindowText);
  ACanvas.FillRect(ARect);
end;

procedure TframeDashboard.DrawItemSeparator(ACanvas: TCanvas; ARect: TRect);
begin
  ACanvas.Pen.Color := BlendColor(StyledColor(clBtnFace), StyledColor(clBtnShadow), 40);
  ACanvas.MoveTo(ARect.Left + S(12), ARect.Bottom - 1);
  ACanvas.LineTo(ARect.Right - S(8), ARect.Bottom - 1);
end;

procedure TframeDashboard.DrawColorDot(ACanvas: TCanvas; X, Y, Radius: Integer;
  AColor: TColor);
begin
  ACanvas.Brush.Color := AColor;
  ACanvas.Pen.Color := AColor;
  ACanvas.Ellipse(X - Radius, Y - Radius, X + Radius, Y + Radius);
end;

procedure TframeDashboard.DrawColorSquare(ACanvas: TCanvas; X, Y, Size: Integer;
  AColor: TColor);
begin
  ACanvas.Brush.Color := AColor;
  ACanvas.Pen.Color := AColor;
  ACanvas.FillRect(Rect(X, Y, X + Size, Y + Size));
end;

procedure TframeDashboard.DrawEmptyState(AListBox: TListBox; const AMessage: string);
var
  R: TRect;
  Flags: Cardinal;
begin
  R := AListBox.ClientRect;
  AListBox.Canvas.Brush.Color := StyledColor(clBtnFace);
  AListBox.Canvas.FillRect(R);
  AListBox.Canvas.Font.Name := 'Segoe UI';
  AListBox.Canvas.Font.Height := -S(12);
  AListBox.Canvas.Font.Style := [fsItalic];
  AListBox.Canvas.Font.Color := clGray;
  Flags := DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;
  DrawText(AListBox.Canvas.Handle, PChar(AMessage), Length(AMessage), R, Flags);
end;

function TframeDashboard.RelativeTimeStr(ADate: TDateTime): string;
var
  Diff: Double;
  Mins, Hrs, Days: Integer;
begin
  Diff := UTCNow - ADate;
  Mins := Trunc(Diff * 24 * 60);
  Hrs := Trunc(Diff * 24);
  Days := Trunc(Diff);

  if Mins < 1 then
    Result := 'just now'
  else if Mins < 60 then
    Result := IntToStr(Mins) + 'm ago'
  else if Hrs < 24 then
    Result := IntToStr(Hrs) + 'h ago'
  else if Days = 1 then
    Result := 'yesterday'
  else if Days < 7 then
    Result := IntToStr(Days) + 'd ago'
  else if Days < 30 then
    Result := IntToStr(Days div 7) + 'w ago'
  else
    Result := FormatDateTime('mmm d', ADate);
end;

function TframeDashboard.GetProjectName(ProjectID: Integer): string;
var
  Proj: TProject;
begin
  if FProjectNameCache.TryGetValue(ProjectID, Result) then
    Exit;
  Result := 'Project #' + IntToStr(ProjectID);
  Proj := unit_DataModel.Model.Projects.GetProject(ProjectID);
  if Assigned(Proj) then
    Result := Proj.Title;
  FProjectNameCache.AddOrSetValue(ProjectID, Result);
end;

function TframeDashboard.GetUserName(UserID: Integer): string;
var
  U: TUser;
begin
  if FUserNameCache.TryGetValue(UserID, Result) then
    Exit;
  Result := 'User #' + IntToStr(UserID);
  U := unit_DataModel.Model.Authors.GetUser(UserID);
  if Assigned(U) then
    Result := U.DisplayName;
  FUserNameCache.AddOrSetValue(UserID, Result);
end;

{ --- Supervisor Filter Bar --- }

function TframeDashboard.GetDateFromForRange(Index: Integer): TDateTime;
begin
  case Index of
    0: Result := UTCNow - 7;       // 1 Week
    1: Result := UTCNow - 30;      // 1 Month
    2: Result := UTCNow - 90;      // 3 Months
    3: Result := UTCNow - 180;     // 6 Months
    4: Result := UTCNow - 365;     // 1 Year
  else
    Result := 0;                // All Time
  end;
end;

procedure TframeDashboard.FilterChanged(Sender: TObject);
begin
  // Update filter user ID
  if cbFilterUser.ItemIndex <= 0 then
    FFilterUserId := -1
  else if Assigned(FFilterUserIds) and (cbFilterUser.ItemIndex - 1 < FFilterUserIds.Count) then
    FFilterUserId := FFilterUserIds[cbFilterUser.ItemIndex - 1];

  // Update date filter
  FFilterDateFrom := GetDateFromForRange(cbFilterTimeRange.ItemIndex);

  // Reload all data with new filters
  ClearData;
  LoadRecentItems;
  if FUserRole <> dbGuest then
    LoadProtocols;
  if FUserRole <> dbGuest then
    LoadApprovals;
  LoadProjectStats;
  if FUserRole <> dbGuest then
    LoadActivityFeed;

  BuildProjectNameCache;
  if FUserRole <> dbGuest then
    BuildUserNameCache;

  UpdateWelcome;
  UpdateListCounts;

  pbHeaderRecent.Invalidate;
  pbHeaderProtocols.Invalidate;
  pbHeaderProjects.Invalidate;
  pbHeaderActivity.Invalidate;
  pbHeaderApprovals.Invalidate;
end;

{ --- Data Loading --- }

procedure TframeDashboard.LoadData(UserRole: TDBRole);
var
  U: TUser;
  UserList: TList<TUser>;
begin
  FUserRole := UserRole;
  // Guest: hide protocols, activity feed and approvals
  pnlProtocols.Visible := UserRole <> dbGuest;
  Splitter1.Visible := UserRole <> dbGuest;
  pnlActivity.Visible := UserRole <> dbGuest;
  Splitter3.Visible := UserRole <> dbGuest;
  pnlApprovals.Visible := UserRole <> dbGuest;
  Splitter4.Visible := UserRole <> dbGuest;

  // Supervisor/Admin filter bar
  if UserRole in [dbSuper, dbAdmin] then
  begin
    pnlFilters.Visible := True;

    // Populate user combo (exclude Supervisor/Admin)
    cbFilterUser.Items.Clear;
    cbFilterUser.Items.Add('All Users');
    if not Assigned(FFilterUserIds) then
      FFilterUserIds := TList<Integer>.Create
    else
      FFilterUserIds.Clear;
    UserList := unit_DataModel.Model.Authors.ActiveList;
    try
      for U in UserList do
        if not (U.Role in [dbSuper, dbAdmin]) then
        begin
          cbFilterUser.Items.Add(U.DisplayName);
          FFilterUserIds.Add(U.Id);
        end;
    finally
      UserList.Free;
    end;
    cbFilterUser.ItemIndex := 0;
    if cbFilterTimeRange.ItemIndex < 0 then
      cbFilterTimeRange.ItemIndex := 0;

    // Set defaults
    FFilterUserId := -1;
    FFilterDateFrom := GetDateFromForRange(cbFilterTimeRange.ItemIndex);
  end
  else
  begin
    pnlFilters.Visible := False;
    FFilterUserId := -1;
    FFilterDateFrom := UTCNow - 7;
  end;

  ClearData;
  LoadRecentItems;
  if UserRole <> dbGuest then
    LoadProtocols;
  if UserRole <> dbGuest then
    LoadApprovals;
  LoadProjectStats;
  if UserRole <> dbGuest then
    LoadActivityFeed;

  BuildProjectNameCache;
  if UserRole <> dbGuest then
    BuildUserNameCache;

  UpdateWelcome;
  UpdateListCounts;

  // Repaint section headers
  pbHeaderRecent.Invalidate;
  pbHeaderProtocols.Invalidate;
  pbHeaderProjects.Invalidate;
  pbHeaderActivity.Invalidate;
  pbHeaderApprovals.Invalidate;
end;

procedure TframeDashboard.LoadRecentItems;
begin
  if FUserRole in [dbSuper, dbAdmin] then
    FRecentItems := unit_DataModel.Model.Items.GetRecentItems(FFilterUserId, FFilterDateFrom)
  else
    FRecentItems := unit_DataModel.Model.Items.GetRecentItems(unit_DataModel.Model.User.Id);
end;

procedure TframeDashboard.LoadProtocols;
var
  DraftList, ReviewList: TList<TProtocol>;
  P: TProtocol;
  FilterUser: Integer;
begin
  if FUserRole in [dbSuper, dbAdmin] then
    FilterUser := FFilterUserId
  else
    FilterUser := -1;

  FProtocols := TObjectList<TProtocol>.Create(False);
  DraftList := unit_DataModel.Model.ProtocolStatus.GetProtocolsByStatus(vsInReview, FilterUser);
  try
    for P in DraftList do
      FProtocols.Add(P);
  finally
    DraftList.Free;
  end;
  ReviewList := unit_DataModel.Model.ProtocolStatus.GetProtocolsByStatus(vsDraft, FilterUser);
  try
    for P in ReviewList do
      FProtocols.Add(P);
  finally
    ReviewList.Free;
  end;
end;

procedure TframeDashboard.LoadApprovals;
begin
  // Always the signed-in user's own decisions, not filtered by the
  // Supervisor/Admin filter bar (that bar scopes other users' data).
  FApprovals := NeedsMyApproval(unit_DataModel.Model.Manager,
    unit_DataModel.Model.User, unit_DataModel.Model.Access);
end;

procedure TframeDashboard.RefreshApprovals;
begin
  if FUserRole = dbGuest then
    Exit;
  LoadApprovals;
  UpdateListCounts;
  pbHeaderApprovals.Invalidate;
  lbApprovals.Invalidate;
end;

procedure TframeDashboard.LoadProjectStats;
begin
  if FUserRole in [dbSuper, dbAdmin] then
    FProjectStats := unit_DataModel.Model.Projects.GetProjectStats(FFilterUserId, FFilterDateFrom)
  else
    FProjectStats := unit_DataModel.Model.Projects.GetProjectStats;
end;

procedure TframeDashboard.LoadActivityFeed;
var
  DateFrom: TDateTime;
begin
  if FUserRole in [dbSuper, dbAdmin] then
    DateFrom := FFilterDateFrom
  else
    DateFrom := UTCNow - 7;

  if DateFrom <= 0 then
    DateFrom := EncodeDate(2000, 1, 1);  // "All Time" floor

  FAuditLogs := unit_DataModel.Model.AuditLog.GetLogs(DateFrom, UTCNow, -1, -1, FFilterUserId);
end;

procedure TframeDashboard.BuildProjectNameCache;
var
  S: TProjectStats;
begin
  if not Assigned(FProjectStats) then Exit;
  for S in FProjectStats do
    FProjectNameCache.AddOrSetValue(S.Project.Id, S.Project.Title);
end;

procedure TframeDashboard.BuildUserNameCache;
var
  Log: TAuditLog;
begin
  if not Assigned(FAuditLogs) then Exit;
  for Log in FAuditLogs do
    if not FUserNameCache.ContainsKey(Log.UserId) then
      GetUserName(Log.UserId);
end;

procedure TframeDashboard.btnRefreshClick(Sender: TObject);
begin
  LoadData(FUserRole);
end;

{ --- Owner-draw: Recent Items --- }

procedure TframeDashboard.lbRecentItemsDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  Canvas: TCanvas;
  Item: TItem;
  TimeStr, ProjName: string;
  TimeWidth: Integer;
  DotColor: TColor;
  DaysDiff: Integer;
begin
  Canvas := lbRecentItems.Canvas;

  // Empty state
  if not Assigned(FRecentItems) or (FRecentItems.Count = 0) then
  begin
    if Index = 0 then
      DrawEmptyState(lbRecentItems, 'No recent items '#8212' start by creating a new experiment');
    Exit;
  end;
  if Index >= FRecentItems.Count then Exit;

  Item := FRecentItems[Index];
  DrawRowBackground(Canvas, Rect, Index, State);

  // Age dot
  if Item.ModifiedDate.HasValue then
  begin
    DaysDiff := Trunc(UTCNow - Item.ModifiedDate.Value);
    if DaysDiff < 1 then DotColor := clDotToday
    else if DaysDiff < 7 then DotColor := clDotThisWeek
    else DotColor := clDotOlder;
  end
  else
    DotColor := clDotOlder;

  DrawColorDot(Canvas, Rect.Left + S(16), Rect.Top + S(18), S(4), DotColor);

  // Line 1: bold title + relative time (right)
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -S(12);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := StyledColor(clWindowText);
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(Rect.Left + S(28), Rect.Top + S(6), Item.Title);

  if Item.ModifiedDate.HasValue then
    TimeStr := RelativeTimeStr(Item.ModifiedDate.Value)
  else
    TimeStr := '';
  if TimeStr <> '' then
  begin
    Canvas.Font.Style := [];
    Canvas.Font.Color := clGray;
    TimeWidth := Canvas.TextWidth(TimeStr);
    Canvas.TextOut(Rect.Right - TimeWidth - S(8), Rect.Top + S(7), TimeStr);
  end;

  // Line 2: project name
  ProjName := GetProjectName(Item.ProjectID);
  Canvas.Font.Style := [];
  Canvas.Font.Height := -S(11);
  Canvas.Font.Color := clGray;
  Canvas.TextOut(Rect.Left + S(28), Rect.Top + S(28), ProjName);

  Canvas.Brush.Style := bsSolid;
  DrawItemSeparator(Canvas, Rect);
end;

{ --- Owner-draw: Protocols --- }

procedure TframeDashboard.lbProtocolsDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  Canvas: TCanvas;
  P: TProtocol;
  StatusStr: string;
  StatusColor: TColor;
begin
  Canvas := lbProtocols.Canvas;

  // Empty state
  if not Assigned(FProtocols) or (FProtocols.Count = 0) then
  begin
    if Index = 0 then
      DrawEmptyState(lbProtocols, 'All caught up! No protocols awaiting review');
    Exit;
  end;
  if Index >= FProtocols.Count then Exit;

  P := FProtocols[Index];
  DrawRowBackground(Canvas, Rect, Index, State);

  // Status dot
  case P.ValidationStatus of
    vsDraft:
    begin
      StatusStr := 'DRAFT';
      StatusColor := clStatusDraft;
    end;
    vsInReview:
    begin
      StatusStr := 'IN REVIEW';
      StatusColor := clStatusInReview;
    end;
  else
    StatusStr := '';
    StatusColor := clGray;
  end;

  DrawColorDot(Canvas, Rect.Left + S(16), Rect.Top + S(18), S(4), StatusColor);

  // Line 1: bold title
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -S(12);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := StyledColor(clWindowText);
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(Rect.Left + S(28), Rect.Top + S(6), P.Title);

  // Line 2: status badge + date
  Canvas.Font.Style := [];
  Canvas.Font.Height := -S(11);
  Canvas.Font.Color := StatusColor;
  Canvas.TextOut(Rect.Left + S(28), Rect.Top + S(28), StatusStr);

  if StatusStr <> '' then
  begin
    Canvas.Font.Color := clGray;
    Canvas.TextOut(Rect.Left + S(28) + Canvas.TextWidth(StatusStr + ' '), Rect.Top + S(28),
      ' '#183' ' + FormatDateTime('mmm d, yyyy', FromUTC(P.CreatedDate)));
  end;

  Canvas.Brush.Style := bsSolid;
  DrawItemSeparator(Canvas, Rect);
end;

{ --- Owner-draw: Projects --- }

procedure TframeDashboard.lbProjectsDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  Canvas: TCanvas;
  Stats: TProjectStats;
  SquareColor: TColor;
  ArchivedStr, SubLine: string;
  ArchivedWidth: Integer;
  BarWidth, FilledWidth: Integer;
  TotalItems: Integer;
begin
  Canvas := lbProjects.Canvas;

  // Empty state
  if not Assigned(FProjectStats) or (FProjectStats.Count = 0) then
  begin
    if Index = 0 then
      DrawEmptyState(lbProjects, 'No projects yet');
    Exit;
  end;
  if Index >= FProjectStats.Count then Exit;

  Stats := FProjectStats[Index];
  DrawRowBackground(Canvas, Rect, Index, State);

  // Colored square
  SquareColor := clProjectColors[Index mod Length(clProjectColors)];
  DrawColorSquare(Canvas, Rect.Left + S(12), Rect.Top + S(10), S(10), SquareColor);

  // Line 1: bold project name + optional [Archived] badge
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -S(12);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := StyledColor(clWindowText);
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(Rect.Left + S(30), Rect.Top + S(5), Stats.Project.Title);

  if Stats.Project.IsArchived then
  begin
    ArchivedStr := ' [Archived]';
    ArchivedWidth := Canvas.TextWidth(Stats.Project.Title);
    Canvas.Font.Style := [];
    Canvas.Font.Height := -S(10);
    Canvas.Font.Color := clGray;
    Canvas.TextOut(Rect.Left + S(30) + ArchivedWidth + S(4), Rect.Top + S(7), ArchivedStr);
  end;

  // Line 2: proc count + sub-item count
  SubLine := Format('%d procs '#183' %d sub-items', [Stats.ItemCount, Stats.FileCount]);
  Canvas.Font.Style := [];
  Canvas.Font.Height := -S(11);
  Canvas.Font.Color := clGray;
  Canvas.TextOut(Rect.Left + S(30), Rect.Top + S(26), SubLine);

  // Mini progress bar (thin colored line showing ratio)
  TotalItems := Stats.ItemCount + Stats.FileCount;
  if TotalItems > 0 then
  begin
    BarWidth := Min(Rect.Right - Rect.Left - S(50), S(120));
    FilledWidth := MulDiv(BarWidth, Stats.ItemCount, TotalItems);
    // Background bar
    Canvas.Brush.Color := BlendColor(StyledColor(clBtnFace), StyledColor(clBtnShadow), 40);
    Canvas.FillRect(Bounds(Rect.Right - BarWidth - S(10), Rect.Top + S(30), BarWidth, S(4)));
    // Filled portion
    if FilledWidth > 0 then
    begin
      Canvas.Brush.Color := SquareColor;
      Canvas.FillRect(Bounds(Rect.Right - BarWidth - S(10), Rect.Top + S(30), FilledWidth, S(4)));
    end;
  end;

  Canvas.Brush.Style := bsSolid;
  DrawItemSeparator(Canvas, Rect);
end;

{ --- Owner-draw: Activity --- }

// Repairs UTF-8 bytes that were stored through a non-UTF8 column and read
// back as garbled codepoints. Targets the two known patterns in legacy
// audit_log rows; safe no-op for clean strings.
function FixAuditMojibake(const S: string): string;
begin
  Result := S;
  // CP1252 round-trip: E2 80 94 -> U+00E2 U+20AC U+201D etc.
  Result := StringReplace(Result, #$00E2#$20AC#$201D, #$2014, [rfReplaceAll]);
  Result := StringReplace(Result, #$00E2#$20AC#$201C, #$2013, [rfReplaceAll]);
  Result := StringReplace(Result, #$00E2#$20AC#$2122, #$2019, [rfReplaceAll]);
  // Raw byte-to-codepoint mapping: bytes promoted as-is.
  Result := StringReplace(Result, #$00E2#$0080#$0094, #$2014, [rfReplaceAll]);
  Result := StringReplace(Result, #$00E2#$0080#$0093, #$2013, [rfReplaceAll]);
  Result := StringReplace(Result, #$00E2#$0080#$0099, #$2019, [rfReplaceAll]);
end;

procedure TframeDashboard.lbActivityDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  Canvas: TCanvas;
  Log: TAuditLog;
  DotColor: TColor;
  UserStr: string;
begin
  Canvas := lbActivity.Canvas;

  // Empty state
  if not Assigned(FAuditLogs) or (FAuditLogs.Count = 0) then
  begin
    if Index = 0 then
      DrawEmptyState(lbActivity, 'No recent activity');
    Exit;
  end;
  if Index >= Min(FAuditLogs.Count, 50) then Exit;

  Log := FAuditLogs[Index];
  DrawRowBackground(Canvas, Rect, Index, State);

  // Operation dot
  case Log.Operation of
    aoCreate: DotColor := clDotCreate;
    aoUpdate: DotColor := clDotUpdate;
    aoDelete: DotColor := clDotDelete;
  else
    DotColor := clGray;
  end;
  DrawColorDot(Canvas, Rect.Left + S(16), Rect.Top + S(13), S(4), DotColor);

  // Line 1: description
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -S(11);
  Canvas.Font.Style := [];
  Canvas.Font.Color := StyledColor(clWindowText);
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(Rect.Left + S(28), Rect.Top + S(3), FixAuditMojibake(Log.Description));

  // Line 2: user + relative time
  UserStr := GetUserName(Log.UserId) + ' '#183' ' + RelativeTimeStr(Log.Timestamp);
  Canvas.Font.Color := clGray;
  Canvas.Font.Height := -S(10);
  Canvas.TextOut(Rect.Left + S(28), Rect.Top + S(21), UserStr);

  Canvas.Brush.Style := bsSolid;
  DrawItemSeparator(Canvas, Rect);
end;

{ --- Owner-draw: Approvals ("Waiting for You", pre-flight C9) --- }

procedure TframeDashboard.lbApprovalsDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  Canvas: TCanvas;
  H: THypothesisSummary;   // not "S": S() is the frame's scaling method
  What, Line2: string;
  WhenUtc: TDateTime;
begin
  Canvas := lbApprovals.Canvas;

  // Empty state
  if Length(FApprovals) = 0 then
  begin
    if Index = 0 then
      DrawEmptyState(lbApprovals, 'Nothing waits for you.');
    Exit;
  end;
  if Index > High(FApprovals) then Exit;

  H := FApprovals[Index];
  DrawRowBackground(Canvas, Rect, Index, State);
  DrawColorDot(Canvas, Rect.Left + S(16), Rect.Top + S(18), S(4), clAccentApprovals);

  // Line 1: bold title
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -S(12);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := StyledColor(clWindowText);
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(Rect.Left + S(28), Rect.Top + S(6), H.Title);

  // Line 2: "Approve proposal / Accept conclusion . <project> . <author> . <age>"
  if H.Status = hsProposed then
    What := 'Approve proposal'
  else
    What := 'Accept conclusion';
  // Same "never modified" fallback as unit_HypothesisQueries.OldestFirst, so
  // the shown age matches the row's place in the (already sorted) list.
  WhenUtc := H.ModifiedDate;
  if WhenUtc = 0 then
    WhenUtc := H.CreatedDate;
  Line2 := What + ' '#183' ' + GetProjectName(H.ProjectId) + ' '#183' ' +
    GetUserName(H.CreatedBy) + ' '#183' ' + THypothesesVM.AgeText(WhenUtc, UTCNow);

  Canvas.Font.Style := [];
  Canvas.Font.Height := -S(11);
  Canvas.Font.Color := StyledColor(clGrayText);
  Canvas.TextOut(Rect.Left + S(28), Rect.Top + S(26), Line2);

  Canvas.Brush.Style := bsSolid;
  DrawItemSeparator(Canvas, Rect);
end;

{ --- Navigation handlers --- }

procedure TframeDashboard.lbRecentItemsClick(Sender: TObject);
var
  Idx: Integer;
  Item: TItem;
begin
  Idx := lbRecentItems.ItemIndex;
  if (Idx < 0) or not Assigned(FRecentItems) or (Idx >= FRecentItems.Count) then Exit;
  Item := FRecentItems[Idx];
  if Assigned(FOnNavigateItem) then
    FOnNavigateItem(Self, Item.ProjectID, Item.FolderID, Item.Id);
end;

procedure TframeDashboard.lbProtocolsClick(Sender: TObject);
var
  Idx: Integer;
  P: TProtocol;
  ParentItem: TItem;
begin
  Idx := lbProtocols.ItemIndex;
  if (Idx < 0) or not Assigned(FProtocols) or (Idx >= FProtocols.Count) then Exit;
  P := FProtocols[Idx];
  ParentItem := unit_DataModel.Model.Items.GetItemForEntry(P.Id);
  if Assigned(ParentItem) and Assigned(FOnNavigateItem) then
    FOnNavigateItem(Self, ParentItem.ProjectID, ParentItem.FolderID, ParentItem.Id);
end;

procedure TframeDashboard.lbActivityClick(Sender: TObject);
var
  Idx, ItemId: Integer;
  Log: TAuditLog;
  Mgr: TObjectManager;
  F: unit_Item.TFile;
  V: unit_Item.TValue;
  Sig: TSignature;
  Item: TItem;
  H: THypothesis;
begin
  Idx := lbActivity.ItemIndex;
  if (Idx < 0) or not Assigned(FAuditLogs) or (Idx >= Min(FAuditLogs.Count, 50)) then Exit;
  Log := FAuditLogs[Idx];
  Mgr := unit_DataModel.Model.Manager;
  ItemId := 0;
  case Log.EntityType of
    aetItem:
      ItemId := Log.EntityId;
    aetFile:
      begin
        F := Mgr.Find<unit_Item.TFile>(Log.EntityId);
        if Assigned(F) and Assigned(F.Item) then
          ItemId := F.Item.Id;
      end;
    aetProtocol, aetNote:
      begin
        Item := unit_DataModel.Model.Items.GetItemForEntry(Log.EntityId);
        if Assigned(Item) then
          ItemId := Item.Id;
      end;
    aetValue:
      begin
        V := Mgr.Find<unit_Item.TValue>(Log.EntityId);
        if Assigned(V) and Assigned(V.Item) then
          ItemId := V.Item.Id;
      end;
    aetSignature:
      begin
        Sig := Mgr.Find<TSignature>(Log.EntityId);
        if Assigned(Sig) then
          ItemId := Sig.ItemId;
      end;
    aetHypothesis:
      begin
        H := Mgr.Find<THypothesis>(Log.EntityId);
        if Assigned(H) and Assigned(FOnOpenHypothesis) then
          FOnOpenHypothesis(Self, H.ProjectId, H.Id)
        else
          MessageDlg('This hypothesis is no longer available.', mtInformation, [mbOK], 0);
        Exit;
      end;
  else
    Exit;  // project/folder/group/setting rows: nothing item-shaped to open
  end;

  Item := nil;
  if ItemId > 0 then
    Item := Mgr.Find<TItem>(ItemId);
  if (Item = nil) or Item.IsDeleted then
  begin
    MessageDlg('This item is no longer available.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if Assigned(FOnNavigateItem) then
    FOnNavigateItem(Self, Item.ProjectID, Item.FolderID, Item.Id);
end;

procedure TframeDashboard.lbApprovalsClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := lbApprovals.ItemIndex;
  if (Idx < 0) or (Idx > High(FApprovals)) then Exit;
  if Assigned(FOnOpenHypothesis) then
    FOnOpenHypothesis(Self, FApprovals[Idx].ProjectId, FApprovals[Idx].Id);
end;

end.
