unit frm_CommunityPreferences;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Types,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.Dialogs, unit_NotebookSettings, unit_TreeAppearance;

type
  TdlgCommunityPreferences = class(TForm)
    pcPreferences: TPageControl;
    tsGeneral: TTabSheet;
    tsPaths: TTabSheet;
    tsTree: TTabSheet;
    lblTheme: TLabel;
    cmbTheme: TComboBox;
    chkDashboard: TCheckBox;
    lblDashboardScale: TLabel;
    cmbDashboardScale: TComboBox;
    chkDarkCharts: TCheckBox;
    lblPreviewScope: TLabel;
    cmbPreviewScope: TComboBox;
    chkItemIDs: TCheckBox;
    lblStorage: TLabel;
    edtStorage: TEdit;
    lblStorageNote: TLabel;
    lblTemplates: TLabel;
    edtTemplates: TEdit;
    btnTemplates: TButton;
    lblPlugins: TLabel;
    edtPlugins: TEdit;
    btnPlugins: TButton;
    lblLogo: TLabel;
    edtLogo: TEdit;
    btnLogo: TButton;
    lblPathsNote: TLabel;
    lblTreeScale: TLabel;
    cmbTreeScale: TComboBox;
    lblTreeSpacing: TLabel;
    cmbTreeSpacing: TComboBox;
    lblTreeTint: TLabel;
    cmbTreeTint: TComboBox;
    lblColors: TLabel;
    lstColors: TListBox;
    btnColor: TButton;
    btnResetColor: TButton;
    btnResetColors: TButton;
    btnOK: TButton;
    btnCancel: TButton;
    dlgFolder: TFileOpenDialog;
    dlgLogo: TOpenDialog;
    dlgColor: TColorDialog;
    procedure BrowseFolderClick(Sender: TObject);
    procedure BrowseLogoClick(Sender: TObject);
    procedure ColorClick(Sender: TObject);
    procedure ResetColorClick(Sender: TObject);
    procedure ResetColorsClick(Sender: TObject);
    procedure ColorsClick(Sender: TObject);
    procedure ColorsDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
  private
    FDraftAppearance: TTreeAppearance;
    procedure LoadPreferences(Settings: TNotebookSettings);
    procedure SavePreferences(Settings: TNotebookSettings);
  public
    destructor Destroy; override;
    class function Execute(Settings: TNotebookSettings): Boolean; static;
  end;

implementation

uses
  Vcl.Themes;

{$R *.dfm}

class function TdlgCommunityPreferences.Execute(
  Settings: TNotebookSettings): Boolean;
var
  Dialog: TdlgCommunityPreferences;
begin
  if not Assigned(Settings) then
    raise EArgumentException.Create('Notebook settings are required.');
  Dialog := TdlgCommunityPreferences.Create(nil);
  try
    Dialog.LoadPreferences(Settings);
    Result := Dialog.ShowModal = mrOk;
    if Result then
      Dialog.SavePreferences(Settings);
  finally
    Dialog.Free;
  end;
end;

destructor TdlgCommunityPreferences.Destroy;
begin
  FDraftAppearance.Free;
  inherited Destroy;
end;

procedure TdlgCommunityPreferences.LoadPreferences(Settings: TNotebookSettings);
var
  Name: string;
  Scope: TPreviewScope;
  Spacing: TTreeSpacing;
  Tint: TTreeTint;
  I: Integer;
begin
  FDraftAppearance := TTreeAppearance.Create;
  FDraftAppearance.Load(Settings);
  for Name in TStyleManager.StyleNames do
    cmbTheme.Items.Add(Name);
  Name := Settings.VCLTheme;
  if Name = '' then
    Name := TStyleManager.ActiveStyle.Name;
  I := cmbTheme.Items.IndexOf(Name);
  if I < 0 then
    I := cmbTheme.Items.IndexOf(TStyleManager.ActiveStyle.Name);
  cmbTheme.ItemIndex := I;
  chkDashboard.Checked := Settings.ShowDashboard;
  Name := IntToStr(Settings.DashboardScale) + '%';
  I := cmbDashboardScale.Items.IndexOf(Name);
  if I < 0 then
    I := cmbDashboardScale.Items.Add(Name);
  cmbDashboardScale.ItemIndex := I;
  chkDarkCharts.Checked := Settings.DarkCharts;
  for Scope := Low(TPreviewScope) to High(TPreviewScope) do
    cmbPreviewScope.Items.Add(PreviewScopeNames[Scope]);
  cmbPreviewScope.ItemIndex := Ord(Settings.PreviewScope);
  chkItemIDs.Checked := Settings.ShowItemIDs;
  edtStorage.Text := Settings.StorageRoot;
  edtTemplates.Text := Settings.TemplatesDir;
  edtPlugins.Text := Settings.PluginsDir;
  edtLogo.Text := Settings.ReportLogoPath;
  for I := Low(TREE_SCALES) to High(TREE_SCALES) do
  begin
    cmbTreeScale.Items.Add(IntToStr(TREE_SCALES[I]) + '%');
    if TREE_SCALES[I] = FDraftAppearance.Scale then
      cmbTreeScale.ItemIndex := I;
  end;
  for Spacing := Low(TTreeSpacing) to High(TTreeSpacing) do
    cmbTreeSpacing.Items.Add(TREE_SPACING_NAMES[Spacing]);
  cmbTreeSpacing.ItemIndex := Ord(FDraftAppearance.Spacing);
  for Tint := Low(TTreeTint) to High(TTreeTint) do
    cmbTreeTint.Items.Add(TREE_TINT_NAMES[Tint]);
  cmbTreeTint.ItemIndex := Ord(FDraftAppearance.Tint);
  for I := 0 to TREE_COLOR_COUNT - 1 do
    lstColors.Items.Add(TREE_COLOR_GROUP_NAMES[TREE_COLORS[I].Group] +
      ' / ' + TREE_COLORS[I].Caption);
  if lstColors.Items.Count > 0 then
    lstColors.ItemIndex := 0;
  ColorsClick(nil);
end;

procedure TdlgCommunityPreferences.SavePreferences(Settings: TNotebookSettings);
var
  ScaleText: string;
begin
  FDraftAppearance.Scale := TREE_SCALES[cmbTreeScale.ItemIndex];
  FDraftAppearance.Spacing := TTreeSpacing(cmbTreeSpacing.ItemIndex);
  FDraftAppearance.Tint := TTreeTint(cmbTreeTint.ItemIndex);
  Settings.VCLTheme := cmbTheme.Text;
  Settings.ShowDashboard := chkDashboard.Checked;
  ScaleText := cmbDashboardScale.Text;
  Settings.DashboardScale := StrToInt(Copy(ScaleText, 1, Length(ScaleText) - 1));
  Settings.DarkCharts := chkDarkCharts.Checked;
  Settings.PreviewScope := TPreviewScope(cmbPreviewScope.ItemIndex);
  Settings.ShowItemIDs := chkItemIDs.Checked;
  Settings.TemplatesDir := Trim(edtTemplates.Text);
  Settings.PluginsDir := Trim(edtPlugins.Text);
  Settings.ReportLogoPath := Trim(edtLogo.Text);
  FDraftAppearance.Save(Settings);
  Appearance.Assign(FDraftAppearance);
end;

procedure TdlgCommunityPreferences.BrowseFolderClick(Sender: TObject);
var
  Target: TEdit;
begin
  if Sender = btnTemplates then
  begin
    Target := edtTemplates;
    dlgFolder.Title := 'Select templates directory';
  end
  else
  begin
    Target := edtPlugins;
    dlgFolder.Title := 'Select plugins directory';
  end;
  dlgFolder.FileName := '';
  dlgFolder.DefaultFolder := Target.Text;
  if dlgFolder.Execute(Handle) then
    Target.Text := dlgFolder.FileName;
end;

procedure TdlgCommunityPreferences.BrowseLogoClick(Sender: TObject);
begin
  dlgLogo.FileName := edtLogo.Text;
  if dlgLogo.Execute then
    edtLogo.Text := dlgLogo.FileName;
end;

procedure TdlgCommunityPreferences.ColorsClick(Sender: TObject);
begin
  btnColor.Enabled := lstColors.ItemIndex >= 0;
  btnResetColor.Enabled := (lstColors.ItemIndex >= 0) and
    Assigned(FDraftAppearance);
end;

procedure TdlgCommunityPreferences.ColorClick(Sender: TObject);
var
  I: Integer;
begin
  I := lstColors.ItemIndex;
  if I < 0 then
    Exit;
  dlgColor.Color := FDraftAppearance.Color(I);
  if dlgColor.Execute then
  begin
    FDraftAppearance.SetColor(I, dlgColor.Color);
    lstColors.Invalidate;
  end;
end;

procedure TdlgCommunityPreferences.ResetColorClick(Sender: TObject);
begin
  if lstColors.ItemIndex < 0 then
    Exit;
  FDraftAppearance.ResetColor(lstColors.ItemIndex);
  lstColors.Invalidate;
end;

procedure TdlgCommunityPreferences.ResetColorsClick(Sender: TObject);
begin
  FDraftAppearance.ResetAllColors;
  lstColors.Invalidate;
end;

procedure TdlgCommunityPreferences.ColorsDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  Swatch: TRect;
  Text: string;
  Gap, Size: Integer;
begin
  if not Assigned(FDraftAppearance) or (Index < 0) or
    (Index >= TREE_COLOR_COUNT) then
    Exit;
  with lstColors.Canvas do
  begin
    FillRect(Rect);
    Gap := MulDiv(6, CurrentPPI, 96);
    Size := Rect.Bottom - Rect.Top - 2 * Gap;
    Swatch := System.Types.Rect(Rect.Left + Gap, Rect.Top + Gap,
      Rect.Left + Gap + Size, Rect.Bottom - Gap);
    Brush.Color := FDraftAppearance.Color(Index);
    FillRect(Swatch);
    Brush.Color := Font.Color;
    FrameRect(Swatch);
    Brush.Style := bsClear;
    try
      Text := lstColors.Items[Index];
      if FDraftAppearance.IsCustom(Index) then
        Text := Text + ' (custom)';
      TextOut(Swatch.Right + Gap, Rect.Top +
        (Rect.Bottom - Rect.Top - TextHeight(Text)) div 2, Text);
    finally
      Brush.Style := bsSolid;
    end;
  end;
end;

end.
