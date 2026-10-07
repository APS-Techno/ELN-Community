unit unit_AppearancePage;

{
  The Settings dialog's Appearance tab: tree scale, row spacing, row tint and
  row colours. Built at runtime onto a tab sheet, like the dialog's other
  runtime controls. Every edit goes straight to the live Appearance and calls
  OnChange, so the real trees change behind the dialog; Cancel puts back the
  snapshot taken when the page was made. Saving is the caller's (on OK).
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Types,
  Vcl.Graphics, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs, unit_TreeAppearance;

type
  TAppearancePage = class(TComponent)
  private
    FTab: TTabSheet;
    FSnapshot: TTreeAppearance;
    FOnChange: TProc;
    FScale, FSpacing, FTint: TComboBox;
    FColors: TListBox;
    FColorDlg: TColorDialog;
    function S(V: Integer): Integer;
    function AddCombo(const ACaption: string; ATop: Integer;
      const AItems: array of string; AIndex: Integer): TComboBox;
    function AddButton(AParent: TWinControl; const ACaption: string;
      ATop: Integer): TButton;
    procedure FillColors;
    /// Catalogue index of a list row, or GROUP_ROW for a heading.
    function ColorAt(Row: Integer): Integer;
    function SelectedColor: Integer;
    procedure Changed;
    procedure ScaleChange(Sender: TObject);
    procedure SpacingChange(Sender: TObject);
    procedure TintChange(Sender: TObject);
    procedure ColorsDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure ChangeClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure ResetAllClick(Sender: TObject);
  public
    /// Builds the page on ATab. AOnChange runs after every edit (may be nil).
    constructor Create(AOwner: TComponent; ATab: TTabSheet;
      const AOnChange: TProc); reintroduce;
    destructor Destroy; override;
    /// Puts back the appearance from when the page was made, and applies it.
    procedure Cancel;
  end;

implementation

const
  GROUP_ROW = -1;   // ColorAt's answer for a group heading

// A row's item data is its catalogue index + 1, and 0 for a heading: never
// -1, which is LB_ERR, and reading it back would raise EListError.

constructor TAppearancePage.Create(AOwner: TComponent; ATab: TTabSheet;
  const AOnChange: TProc);
var
  Scales: array of string;
  I, ScaleIndex: Integer;
  Lbl: TLabel;
  Area, Side: TPanel;
  Btn: TButton;
begin
  inherited Create(AOwner);
  FTab := ATab;
  FOnChange := AOnChange;
  FSnapshot := TTreeAppearance.Create;
  FSnapshot.Assign(Appearance);

  SetLength(Scales, Length(TREE_SCALES));
  ScaleIndex := 1;
  for I := 0 to High(TREE_SCALES) do
  begin
    Scales[I] := IntToStr(TREE_SCALES[I]) + '%';
    if TREE_SCALES[I] = Appearance.Scale then
      ScaleIndex := I;
  end;
  FScale := AddCombo('Tree scale:', 16, Scales, ScaleIndex);
  FScale.OnChange := ScaleChange;
  FSpacing := AddCombo('Row spacing:', 48, TREE_SPACING_NAMES, Ord(Appearance.Spacing));
  FSpacing.OnChange := SpacingChange;
  FTint := AddCombo('Row tint:', 80, TREE_TINT_NAMES, Ord(Appearance.Tint));
  FTint.OnChange := TintChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := FTab;
  Lbl.Left := S(16);
  Lbl.Top := S(120);
  Lbl.Caption := 'Row colours (double-click to change):';

  // The list fills the rest of the tab, buttons on its right. Aligned, not
  // positioned: the tab has no size yet while the dialog is being built.
  Area := TPanel.Create(Self);
  Area.Parent := FTab;
  Area.BevelOuter := bvNone;
  Area.AlignWithMargins := True;
  Area.Margins.SetBounds(S(16), S(140), S(16), S(12));
  Area.Align := alClient;

  Side := TPanel.Create(Self);
  Side.Parent := Area;
  Side.BevelOuter := bvNone;
  Side.AlignWithMargins := True;
  Side.Align := alRight;
  Side.Width := S(112);

  FColors := TListBox.Create(Self);
  FColors.Parent := Area;
  FColors.AlignWithMargins := True;
  FColors.Align := alClient;
  FColors.Style := lbOwnerDrawFixed;
  FColors.ItemHeight := S(22);
  FColors.OnDrawItem := ColorsDrawItem;
  FColors.OnDblClick := ChangeClick;
  FillColors;

  Btn := AddButton(Side, 'Change...', 0);
  Btn.OnClick := ChangeClick;
  Btn := AddButton(Side, 'Reset', 32);
  Btn.OnClick := ResetClick;
  Btn := AddButton(Side, 'Reset all', 64);
  Btn.OnClick := ResetAllClick;

  FColorDlg := TColorDialog.Create(Self);
  FColorDlg.Options := [cdFullOpen, cdAnyColor];
end;

destructor TAppearancePage.Destroy;
begin
  FSnapshot.Free;
  inherited;
end;

function TAppearancePage.S(V: Integer): Integer;
begin
  Result := MulDiv(V, FTab.CurrentPPI, 96);
end;

function TAppearancePage.AddCombo(const ACaption: string; ATop: Integer;
  const AItems: array of string; AIndex: Integer): TComboBox;
var
  Lbl: TLabel;
  Item: string;
begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := FTab;
  Lbl.Left := S(16);
  Lbl.Top := S(ATop + 3);
  Lbl.Caption := ACaption;
  Result := TComboBox.Create(Self);
  Result.Parent := FTab;
  Result.Style := csDropDownList;
  Result.SetBounds(S(140), S(ATop), S(160), Result.Height);
  for Item in AItems do
    Result.Items.Add(Item);
  Result.ItemIndex := AIndex;
end;

function TAppearancePage.AddButton(AParent: TWinControl; const ACaption: string;
  ATop: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.SetBounds(S(12), S(ATop), S(100), S(25));
end;

procedure TAppearancePage.FillColors;
var
  G: TTreeColorGroup;
  I: Integer;
begin
  FColors.Items.BeginUpdate;
  try
    FColors.Items.Clear;
    for G := Low(TTreeColorGroup) to High(TTreeColorGroup) do
    begin
      FColors.Items.AddObject(TREE_COLOR_GROUP_NAMES[G], TObject(0));
      for I := 0 to TREE_COLOR_COUNT - 1 do
        if TREE_COLORS[I].Group = G then
          FColors.Items.AddObject(TREE_COLORS[I].Caption, TObject(NativeInt(I + 1)));
    end;
  finally
    FColors.Items.EndUpdate;
  end;
end;

function TAppearancePage.ColorAt(Row: Integer): Integer;
begin
  Result := Integer(NativeInt(FColors.Items.Objects[Row])) - 1;
end;

function TAppearancePage.SelectedColor: Integer;
begin
  Result := GROUP_ROW;
  if FColors.ItemIndex >= 0 then
    Result := ColorAt(FColors.ItemIndex);
end;

procedure TAppearancePage.Changed;
begin
  FColors.Invalidate;
  if Assigned(FOnChange) then
    FOnChange();
end;

procedure TAppearancePage.ScaleChange(Sender: TObject);
begin
  Appearance.Scale := TREE_SCALES[FScale.ItemIndex];
  Changed;
end;

procedure TAppearancePage.SpacingChange(Sender: TObject);
begin
  Appearance.Spacing := TTreeSpacing(FSpacing.ItemIndex);
  Changed;
end;

procedure TAppearancePage.TintChange(Sender: TObject);
begin
  Appearance.Tint := TTreeTint(FTint.ItemIndex);
  Changed;
end;

procedure TAppearancePage.ColorsDrawItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  C: TCanvas;
  I, Y: Integer;
  Swatch: TRect;
  Text: string;
begin
  C := FColors.Canvas;
  C.FillRect(Rect);
  I := ColorAt(Index);
  Y := Rect.Top + (Rect.Height - C.TextHeight('Wg')) div 2;
  if I = GROUP_ROW then
  begin
    C.Font.Style := [fsBold];
    C.TextOut(Rect.Left + S(4), Y, FColors.Items[Index]);
    Exit;
  end;
  C.Font.Style := [];
  Swatch := System.Types.Rect(Rect.Left + S(16), Rect.Top + S(3),
    Rect.Left + S(16 + 32), Rect.Bottom - S(3));
  C.Brush.Color := Appearance.Color(I);
  C.Pen.Color := clGray;
  C.Rectangle(Swatch);
  C.Brush.Style := bsClear;
  Text := TREE_COLORS[I].Caption;
  if Appearance.IsCustom(I) then
    Text := Text + '   (custom)';
  C.TextOut(Swatch.Right + S(8), Y, Text);
end;

procedure TAppearancePage.ChangeClick(Sender: TObject);
var
  I: Integer;
begin
  I := SelectedColor;
  if I = GROUP_ROW then Exit;
  FColorDlg.Color := Appearance.Color(I);
  if FColorDlg.Execute then
  begin
    Appearance.SetColor(I, FColorDlg.Color);
    Changed;
  end;
end;

procedure TAppearancePage.ResetClick(Sender: TObject);
var
  I: Integer;
begin
  I := SelectedColor;
  if I = GROUP_ROW then Exit;
  Appearance.ResetColor(I);
  Changed;
end;

procedure TAppearancePage.ResetAllClick(Sender: TObject);
begin
  Appearance.ResetAllColors;
  Changed;
end;

procedure TAppearancePage.Cancel;
begin
  Appearance.Assign(FSnapshot);
  if Assigned(FOnChange) then
    FOnChange();
end;

end.
