unit frame_LAMMPSViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl,
  System.SysUtils, System.Variants, System.Classes,
  System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.ComCtrls,
  SynEditHighlighter, SynEdit,
  VclTee.TeeGDIPlus, VCLTee.TeCanvas, VCLTee.TeEngine, VCLTee.Series, VCLTee.TeeProcs, VCLTee.Chart,
  RzPanel, RzLabel, RzButton,
  unit_ELNPluginCore, unit_ELNPluginTypes, unit_LAMMPSDumpParser;

type


  TPageControl = class(Vcl.ComCtrls.TPageControl)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;


  TSynLAMMPSSyn = class(TSynCustomHighlighter)
  private
    FTokenPos: Integer;
    FTokenLen: Integer;
    FLine: string;
    FLineLen: Integer;
    FRun: Integer;
    FTokenID: Integer;

    FCommentAttr: TSynHighlighterAttributes;
    FKeywordAttr: TSynHighlighterAttributes;
    FVariableAttr: TSynHighlighterAttributes;
    FNumberAttr: TSynHighlighterAttributes;
    FStringAttr: TSynHighlighterAttributes;
    FIdentAttr: TSynHighlighterAttributes;
    FSpaceAttr: TSynHighlighterAttributes;

    FKeywords: TDictionary<string, Boolean>;

    procedure InitKeywords;
    function IsLAMMPSKeyword(const S: string): Boolean;
  protected
    function GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure SetLine(const NewValue: string; LineNumber: Integer); override;
    procedure Next; override;
    function GetTokenAttribute: TSynHighlighterAttributes; override;
    function GetToken: string; override;
    function GetTokenPos: Integer; override;
    function GetTokenKind: Integer; override;
    function GetEol: Boolean; override;

    class function GetLanguageName: string; override;
    class function GetFriendlyLanguageName: string; override;
  end;


  TframeLAMMPSViewer = class(TFrame)
    RzPanel1: TRzPanel;
    lblTitle: TRzLabel;
    Pages: TPageControl;
    tabLmpin: TTabSheet;
    tabDump: TTabSheet;
    Editor: TSynEdit;
    pnlInfo: TPanel;
    lblInfo: TLabel;
    Chart: TChart;
    Status: TRzStatusBar;
    pnlCrossSection: TPanel;
    chkCrossSection: TCheckBox;
    trkSlab: TTrackBar;
    lblSlab: TLabel;
  private
    FSyn: TSynLAMMPSSyn;
    FDumpFile: TLAMMPSDumpFile;
    FStatusBase: string;
    FBtnCopy: TRzBitBtn;

    procedure BuildChart;
    procedure BtnCopyClick(Sender: TObject);
    procedure ChartMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ChartDblClick(Sender: TObject);
    procedure CrossSectionChanged(Sender: TObject);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadFromFile(const AFileName: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
    function SaveState: string;
    procedure RestoreState(const AState: string);
  end;

implementation

uses
  ClipBrd, System.JSON, unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}


procedure TPageControl.WndProc(var Message: TMessage);
begin
  if Message.Msg = TCM_ADJUSTRECT then
    Message.Result := 0
  else
    inherited;
end;

function LightenColor(AColor: TColor; Amount: Byte): TColor;
var
  R, G, B: Byte;
begin
  R := GetRValue(AColor);
  G := GetGValue(AColor);
  B := GetBValue(AColor);
  R := R + (255 - R) * Amount div 255;
  G := G + (255 - G) * Amount div 255;
  B := B + (255 - B) * Amount div 255;
  Result := RGB(R, G, B);
end;

const
  TK_COMMENT  = 1;
  TK_KEYWORD  = 2;
  TK_VARIABLE = 3;
  TK_NUMBER   = 4;
  TK_STRING   = 5;
  TK_IDENT    = 6;
  TK_SPACE    = 7;


constructor TSynLAMMPSSyn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FCommentAttr := TSynHighlighterAttributes.Create('Comment', 'Comment');
  FCommentAttr.Foreground := clGreen;
  FCommentAttr.Style := [fsItalic];
  AddAttribute(FCommentAttr);

  FKeywordAttr := TSynHighlighterAttributes.Create('Keyword', 'Keyword');
  FKeywordAttr.Foreground := clNavy;
  FKeywordAttr.Style := [fsBold];
  AddAttribute(FKeywordAttr);

  FVariableAttr := TSynHighlighterAttributes.Create('Variable', 'Variable');
  FVariableAttr.Foreground := clPurple;
  AddAttribute(FVariableAttr);

  FNumberAttr := TSynHighlighterAttributes.Create('Number', 'Number');
  FNumberAttr.Foreground := clMaroon;
  AddAttribute(FNumberAttr);

  FStringAttr := TSynHighlighterAttributes.Create('String', 'String');
  FStringAttr.Foreground := clTeal;
  AddAttribute(FStringAttr);

  FIdentAttr := TSynHighlighterAttributes.Create('Identifier', 'Identifier');
  FIdentAttr.Foreground := clBlack;
  AddAttribute(FIdentAttr);

  FSpaceAttr := TSynHighlighterAttributes.Create('Space', 'Space');
  AddAttribute(FSpaceAttr);

  FKeywords := TDictionary<string, Boolean>.Create;
  InitKeywords;

  SetAttributesOnChange(DefHighlightChange);
end;

destructor TSynLAMMPSSyn.Destroy;
begin
  FKeywords.Free;
  inherited;
end;

procedure TSynLAMMPSSyn.InitKeywords;
const
  WORDS: array[0..42] of string = (
    'units', 'dimension', 'boundary', 'timestep', 'region',
    'create_box', 'create_atoms', 'read_data', 'read_dump', 'mass',
    'pair_style', 'pair_coeff', 'compute', 'variable', 'dump',
    'fix', 'unfix', 'run', 'minimize', 'velocity',
    'thermo', 'thermo_style', 'neighbor', 'neigh_modify', 'group',
    'undump', 'reset_timestep', 'reset_atoms', 'min_style', 'atom_style',
    'lattice', 'set', 'print', 'write_data', 'write_restart',
    'atom_modify', 'bond_style', 'bond_coeff', 'angle_style', 'angle_coeff',
    'dihedral_style', 'special_bonds', 'read_restart'
  );
var
  W: string;
begin
  for W in WORDS do
    FKeywords.AddOrSetValue(W, True);
end;

function TSynLAMMPSSyn.IsLAMMPSKeyword(const S: string): Boolean;
begin
  Result := FKeywords.ContainsKey(LowerCase(S));
end;

procedure TSynLAMMPSSyn.SetLine(const NewValue: string; LineNumber: Integer);
begin
  FLine := NewValue;
  FLineLen := Length(FLine);
  FRun := 1;
  FTokenPos := 1;
  FTokenLen := 0;
  FTokenID := TK_SPACE;
  inherited;
end;

function TSynLAMMPSSyn.GetEol: Boolean;
begin
  Result := FRun > FLineLen + 1;
end;

procedure TSynLAMMPSSyn.Next;
var
  Start: Integer;
  C: Char;
  Word: string;
begin
  FTokenPos := FRun;

  if FRun > FLineLen then
  begin
    Inc(FRun);
    FTokenLen := 0;
    FTokenID := TK_SPACE;
    Exit;
  end;

  C := FLine[FRun];

  if C = '#' then
  begin
    FTokenID := TK_COMMENT;
    FTokenLen := FLineLen - FRun + 1;
    FRun := FLineLen + 1;
    Exit;
  end;

  if CharInSet(C, [' ', #9]) then
  begin
    FTokenID := TK_SPACE;
    Start := FRun;
    while (FRun <= FLineLen) and CharInSet(FLine[FRun], [' ', #9]) do
      Inc(FRun);
    FTokenLen := FRun - Start;
    Exit;
  end;

  if C = '"' then
  begin
    FTokenID := TK_STRING;
    Start := FRun;
    Inc(FRun);
    while (FRun <= FLineLen) and (FLine[FRun] <> '"') do
      Inc(FRun);
    if FRun <= FLineLen then
      Inc(FRun);
    FTokenLen := FRun - Start;
    Exit;
  end;

  if C = '$' then
  begin
    FTokenID := TK_VARIABLE;
    Start := FRun;
    Inc(FRun);
    if (FRun <= FLineLen) and (FLine[FRun] = '{') then
    begin
      Inc(FRun);
      while (FRun <= FLineLen) and (FLine[FRun] <> '}') do
        Inc(FRun);
      if FRun <= FLineLen then
        Inc(FRun);
    end
    else
    begin
      while (FRun <= FLineLen) and (CharInSet(FLine[FRun], ['a'..'z','A'..'Z','0'..'9','_'])) do
        Inc(FRun);
    end;
    FTokenLen := FRun - Start;
    Exit;
  end;

  if CharInSet(C, ['0'..'9']) or
     ((C = '-') and (FRun + 1 <= FLineLen) and CharInSet(FLine[FRun + 1], ['0'..'9','.'])) then
  begin
    FTokenID := TK_NUMBER;
    Start := FRun;
    if C = '-' then
      Inc(FRun);
    while (FRun <= FLineLen) and CharInSet(FLine[FRun], ['0'..'9']) do
      Inc(FRun);
    if (FRun <= FLineLen) and (FLine[FRun] = '.') then
    begin
      Inc(FRun);
      while (FRun <= FLineLen) and CharInSet(FLine[FRun], ['0'..'9']) do
        Inc(FRun);
    end;
    if (FRun <= FLineLen) and CharInSet(FLine[FRun], ['e','E']) then
    begin
      Inc(FRun);
      if (FRun <= FLineLen) and CharInSet(FLine[FRun], ['+','-']) then
        Inc(FRun);
      while (FRun <= FLineLen) and CharInSet(FLine[FRun], ['0'..'9']) do
        Inc(FRun);
    end;
    FTokenLen := FRun - Start;
    Exit;
  end;

  if CharInSet(C, ['a'..'z','A'..'Z','_']) then
  begin
    Start := FRun;
    while (FRun <= FLineLen) and CharInSet(FLine[FRun], ['a'..'z','A'..'Z','0'..'9','_']) do
      Inc(FRun);
    FTokenLen := FRun - Start;
    Word := Copy(FLine, Start, FTokenLen);
    if IsLAMMPSKeyword(Word) then
      FTokenID := TK_KEYWORD
    else
      FTokenID := TK_IDENT;
    Exit;
  end;

  FTokenID := TK_IDENT;
  Inc(FRun);
  FTokenLen := 1;
end;

function TSynLAMMPSSyn.GetToken: string;
begin
  Result := Copy(FLine, FTokenPos, FTokenLen);
end;

function TSynLAMMPSSyn.GetTokenPos: Integer;
begin
  Result := FTokenPos - 1; // SynEdit expects 0-based
end;

function TSynLAMMPSSyn.GetTokenKind: Integer;
begin
  Result := FTokenID;
end;

function TSynLAMMPSSyn.GetTokenAttribute: TSynHighlighterAttributes;
begin
  case FTokenID of
    TK_COMMENT:  Result := FCommentAttr;
    TK_KEYWORD:  Result := FKeywordAttr;
    TK_VARIABLE: Result := FVariableAttr;
    TK_NUMBER:   Result := FNumberAttr;
    TK_STRING:   Result := FStringAttr;
    TK_IDENT:    Result := FIdentAttr;
    TK_SPACE:    Result := FSpaceAttr;
  else
    Result := FIdentAttr;
  end;
end;

function TSynLAMMPSSyn.GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_COMMENT:    Result := FCommentAttr;
    SYN_ATTR_KEYWORD:    Result := FKeywordAttr;
    SYN_ATTR_STRING:     Result := FStringAttr;
    SYN_ATTR_WHITESPACE: Result := FSpaceAttr;
    SYN_ATTR_IDENTIFIER: Result := FIdentAttr;
  else
    Result := nil;
  end;
end;

class function TSynLAMMPSSyn.GetLanguageName: string;
begin
  Result := 'LAMMPS';
end;

class function TSynLAMMPSSyn.GetFriendlyLanguageName: string;
begin
  Result := 'LAMMPS Input Script';
end;


procedure TframeLAMMPSViewer.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // The native page control requests a handle during DFM streaming, before
  // callers can set Parent. Use their real host, not an application window
  // that is absent in a console host.
  if Parent = nil then
    if ParentWindow <> 0 then
      Params.WndParent := ParentWindow
    else if Owner is TWinControl then
      Params.WndParent := TWinControl(Owner).Handle;
end;

constructor TframeLAMMPSViewer.Create(AOwner: TComponent);
begin
  inherited;
  FDumpFile := TLAMMPSDumpFile.Create;

  FSyn := TSynLAMMPSSyn.Create(Self);
  Editor.Highlighter := FSyn;

  Pages.ActivePage := tabLmpin;

  FBtnCopy := TRzBitBtn.Create(Self);
  FBtnCopy.Parent := RzPanel1;
  FBtnCopy.Align := alRight;
  FBtnCopy.AlignWithMargins := True;
  FBtnCopy.Width := MulDiv(80, CurrentPPI, 96);
  FBtnCopy.Caption := 'Copy';
  FBtnCopy.OnClick := BtnCopyClick;

  Chart.OnMouseWheel := ChartMouseWheel;
  Chart.OnMouseMove := ChartMouseMove;
  Chart.OnDblClick := ChartDblClick;

  chkCrossSection.OnClick := CrossSectionChanged;
  trkSlab.OnChange := CrossSectionChanged;
  trkSlab.Enabled := False;
  lblSlab.Enabled := False;
end;

destructor TframeLAMMPSViewer.Destroy;
begin
  FDumpFile.Free;
  inherited;
end;

procedure TframeLAMMPSViewer.LoadFromFile(const AFileName: string);
var
  Ext: string;
begin
  lblTitle.Caption := ExtractFileName(AFileName);
  Ext := LowerCase(ExtractFileExt(AFileName));

  if Ext = '.lmpin' then
  begin
    // An input deck has no atoms to parse. Drop the previous file's parse or
    // this deck would report that file's atoms, box and masses as its own.
    FDumpFile.Clear;
    Pages.ActivePage := tabLmpin;
    Editor.Lines.LoadFromFile(AFileName);
    FStatusBase := Format('%s  |  %d lines', [
      ExtractFileName(AFileName), Editor.Lines.Count]);
  end
  else if (Ext = '.dump') or (Ext = '.data') or (Ext = '.lammps') then
  begin
    Pages.ActivePage := tabDump;
    FDumpFile.ParseFromFile(AFileName);
    lblInfo.Caption := FDumpFile.GetSummaryText;
    BuildChart;
    FStatusBase := Format('%s  |  %d atoms  |  %d types', [
      ExtractFileName(AFileName), FDumpFile.AtomCount, FDumpFile.AtomTypeCount]);
    // The resolved atom_style decides which column was read as the type, so
    // surface it - a file parsed as 'atomic' when it is 'full' looks normal
    // otherwise. Empty when the file carried no Atoms section.
    if FDumpFile.AtomStyle <> '' then
      FStatusBase := FStatusBase + Format('  |  style: %s', [FDumpFile.AtomStyle]);
  end;

  Status.SimpleCaption := FStatusBase;
end;

procedure TframeLAMMPSViewer.BuildChart;
var
  SeriesMap: TDictionary<Integer, TPointSeries>;
  Ser: TPointSeries;
  I, AType, VisCount: Integer;
  Atom: TAtomRecord;
  UseSlab: Boolean;
  YMid, YRange, SlabHalf: Double;
begin
  Chart.AutoRepaint := False;
  try
    Chart.FreeAllSeries;

    YMid := 0;
    SlabHalf := 0;
    UseSlab := chkCrossSection.Checked;
    if UseSlab then
    begin
      // Atom.Y is Cartesian. Recover the Cartesian envelope from the true
      // cell bounds so the XZ slab remains centered for either sign of yz.
      YMid := (FDumpFile.Box.YLo + FDumpFile.Box.YHi + FDumpFile.Box.YZ) / 2;
      YRange := FDumpFile.Box.YHi - FDumpFile.Box.YLo + Abs(FDumpFile.Box.YZ);
      SlabHalf := YRange * (trkSlab.Position / 100) / 2;
    end;

    VisCount := 0;
    SeriesMap := TDictionary<Integer, TPointSeries>.Create;
    try
      for I := 0 to High(FDumpFile.Atoms) do
      begin
        Atom := FDumpFile.Atoms[I];

        if UseSlab and (Abs(Atom.Y - YMid) > SlabHalf) then
          Continue;

        Inc(VisCount);
        AType := Atom.AtomType;

        if not SeriesMap.TryGetValue(AType, Ser) then
        begin
          Ser := TPointSeries.Create(Chart);
          Ser.Title := Format('Type %d', [AType]);
          Ser.Pointer.Style := psCircle;
          Ser.Pointer.Size := 8;
          Ser.Pointer.Color := FDumpFile.AtomTypeColor(AType);
          Ser.Pointer.Pen.Visible := True;
          Ser.Pointer.Pen.Color := FDumpFile.AtomTypeColor(AType);
          Ser.Pointer.Pen.Width := 1;
          Ser.Pointer.Draw3D := False;
          Ser.Pointer.Gradient.Visible := True;
          Ser.Pointer.Gradient.Direction := gdRadial;
          Ser.Pointer.Gradient.StartColor := LightenColor(FDumpFile.AtomTypeColor(AType), 128);
          Ser.Pointer.Gradient.EndColor := FDumpFile.AtomTypeColor(AType);
          Ser.XValues.Order := loNone;
          Ser.YValues.Order := loNone;
          Chart.AddSeries(Ser);
          SeriesMap.Add(AType, Ser);
        end;

        Ser.AddXY(Atom.X, Atom.Z);
      end;
    finally
      SeriesMap.Free;
    end;
    Chart.BottomAxis.AutomaticMinimum := False;
    Chart.BottomAxis.Minimum := 0;
    Chart.LeftAxis.AutomaticMinimum := False;
    Chart.LeftAxis.Minimum := 0;

    if UseSlab then
      Status.SimpleCaption := Format('%s  |  slab %d%% — %d / %d atoms',
        [FStatusBase, trkSlab.Position, VisCount, FDumpFile.AtomCount])
    else
      Status.SimpleCaption := FStatusBase;

    ApplyChartTheme(Chart);
  finally
    Chart.AutoRepaint := True;
    Chart.Repaint;
  end;
end;

procedure TframeLAMMPSViewer.CrossSectionChanged(Sender: TObject);
begin
  trkSlab.Enabled := chkCrossSection.Checked;
  lblSlab.Enabled := chkCrossSection.Checked;
  lblSlab.Caption := Format('Slab: %d%%', [trkSlab.Position]);
  if FDumpFile.AtomCount > 0 then
    BuildChart;
end;

procedure TframeLAMMPSViewer.BtnCopyClick(Sender: TObject);
begin
  if Pages.ActivePage = tabLmpin then
    Clipboard.AsText := Editor.Text;
end;


procedure TframeLAMMPSViewer.ChartMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  Factor, RangeX, RangeY, CenterX, CenterY: Double;
begin
  if WheelDelta > 0 then
    Factor := 0.8
  else
    Factor := 1.25;

  RangeX := Chart.BottomAxis.Maximum - Chart.BottomAxis.Minimum;
  RangeY := Chart.LeftAxis.Maximum - Chart.LeftAxis.Minimum;
  CenterX := (Chart.BottomAxis.Maximum + Chart.BottomAxis.Minimum) / 2;
  CenterY := (Chart.LeftAxis.Maximum + Chart.LeftAxis.Minimum) / 2;

  Chart.BottomAxis.SetMinMax(
    CenterX - RangeX * Factor / 2,
    CenterX + RangeX * Factor / 2);
  Chart.LeftAxis.SetMinMax(
    CenterY - RangeY * Factor / 2,
    CenterY + RangeY * Factor / 2);

  Handled := True;
end;

procedure TframeLAMMPSViewer.ChartMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  XVal, YVal: Double;
begin
  XVal := Chart.BottomAxis.CalcPosPoint(X);
  YVal := Chart.LeftAxis.CalcPosPoint(Y);
  Status.SimpleCaption := Format('%s  |  Cursor: %.2f, %.2f',
    [FStatusBase, XVal, YVal]);
end;

procedure TframeLAMMPSViewer.ChartDblClick(Sender: TObject);
begin
  Chart.BottomAxis.Automatic := True;
  Chart.LeftAxis.Automatic := True;
end;


function TframeLAMMPSViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
  I, Y, LineH, MaxLines: Integer;
  Info: TStringList;
begin
  Result := nil;

  Large := TBitmap.Create;
  try
    Large.PixelFormat := pf32bit;
    Large.SetSize(800, 600);
    Large.Canvas.Brush.Color := ThemePanelColor;
    Large.Canvas.FillRect(Rect(0, 0, 800, 600));

    // NOTE: never Free Large before an Exit here. Exit still runs the finally
    // below, so freeing it early is a double free (EInvalidPointer).

    if Pages.ActivePage = tabLmpin then
    begin
      if Editor.Lines.Count = 0 then
        Exit;

      Large.Canvas.Font.Name := Editor.Font.Name;
      Large.Canvas.Font.Size := Editor.Font.Size;
      Large.Canvas.Font.Color := ThemeTextColor;

      LineH := Large.Canvas.TextHeight('Wg') + 2;
      MaxLines := 600 div LineH;
      if MaxLines > Editor.Lines.Count then
        MaxLines := Editor.Lines.Count;

      Y := 4;
      for I := 0 to MaxLines - 1 do
      begin
        Large.Canvas.TextOut(4, Y, Editor.Lines[I]);
        Y := Y + LineH;
      end;
    end
    else if Pages.ActivePage = tabDump then
    begin
      if Chart.SeriesCount > 0 then
        Chart.Draw(Large.Canvas, Rect(0, 0, 800, 600))
      else
      begin
        Info := TStringList.Create;
        try
          Info.Text := lblInfo.Caption;
          if Trim(Info.Text) = '' then
            Exit;

          Large.Canvas.Font.Name := lblInfo.Font.Name;
          Large.Canvas.Font.Size := lblInfo.Font.Size;
          Large.Canvas.Font.Color := ThemeTextColor;

          LineH := Large.Canvas.TextHeight('Wg') + 2;
          MaxLines := 600 div LineH;
          if MaxLines > Info.Count then
            MaxLines := Info.Count;

          Y := 4;
          for I := 0 to MaxLines - 1 do
          begin
            Large.Canvas.TextOut(4, Y, Info[I]);
            Y := Y + LineH;
          end;
        finally
          Info.Free;
        end;
      end;
    end
    else
      Exit;

    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

function TframeLAMMPSViewer.GetKeyValues: TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  KV: TPluginKeyValue;
  B: TBoxBounds;

  procedure Add(const AName: string; AValue: Double; const AUnits: string;
    ARecType: TPluginRecType; AIsKey: Boolean = False);
  begin
    KV.Name := AName;
    KV.Value := AValue;
    KV.Units := AUnits;
    KV.RecType := ARecType;
    KV.IsKey := AIsKey;
    List.Add(KV);
  end;

begin
  Result := nil;
  if FDumpFile.AtomCount = 0 then
    Exit;

  B := FDumpFile.Box;
  List := TList<TPluginKeyValue>.Create;
  try
    Add('Atom Count', FDumpFile.AtomCount, '', prResult, True);
    Add('Atom Types', FDumpFile.AtomTypeCount, '', prResult, True);
    Add('Box X', B.XHi - B.XLo, 'A', prCondition, True);
    Add('Box Y', B.YHi - B.YLo, 'A', prCondition);
    Add('Box Z', B.ZHi - B.ZLo, 'A', prCondition);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TframeLAMMPSViewer.GetDetailedInfo: string;
var
  J, JBox, JMass: TJSONObject;
  JMassArr: TJSONArray;
  B: TBoxBounds;
  I: Integer;
begin
  Result := '';

  if FDumpFile.IsBinaryRestart then
  begin
    J := TJSONObject.Create;
    try
      J.AddPair('fileName', ExtractFileName(FDumpFile.FileName));
      J.AddPair('format', 'binary-restart');
      J.AddPair('note', 'LAMMPS binary restart file (write_restart). Its layout ' +
        'is specific to the LAMMPS build that wrote it and is not parsed. Use ' +
        'read_restart + write_data in LAMMPS to obtain a readable data file.');
      Result := J.ToJSON;
    finally
      J.Free;
    end;
    Exit;
  end;

  if FDumpFile.AtomCount = 0 then
    Exit;

  B := FDumpFile.Box;
  J := TJSONObject.Create;
  try
    J.AddPair('fileName', ExtractFileName(FDumpFile.FileName));
    J.AddPair('atomCount', TJSONNumber.Create(FDumpFile.AtomCount));
    J.AddPair('atomTypeCount', TJSONNumber.Create(FDumpFile.AtomTypeCount));
    if FDumpFile.AtomStyle <> '' then
      J.AddPair('atomStyle', FDumpFile.AtomStyle);
    if FDumpFile.HeaderAtomCount > 0 then
      J.AddPair('headerAtomCount', TJSONNumber.Create(FDumpFile.HeaderAtomCount));
    // Dump frames carry a timestep and named columns; read_data files do not.
    if FDumpFile.IsDumpFormat then
    begin
      J.AddPair('format', 'dump');
      J.AddPair('timestep', TJSONNumber.Create(FDumpFile.Timestep));
      J.AddPair('frameCount', TJSONNumber.Create(FDumpFile.FrameCount));
      if FDumpFile.DumpColumns <> '' then
        J.AddPair('dumpColumns', FDumpFile.DumpColumns);
    end;
    J.AddPair('hasVelocities', TJSONBool.Create(FDumpFile.HasVelocities));

    JBox := TJSONObject.Create;
    JBox.AddPair('xLo', JNum(B.XLo));
    JBox.AddPair('xHi', JNum(B.XHi));
    JBox.AddPair('yLo', JNum(B.YLo));
    JBox.AddPair('yHi', JNum(B.YHi));
    JBox.AddPair('zLo', JNum(B.ZLo));
    JBox.AddPair('zHi', JNum(B.ZHi));
    J.AddPair('box', JBox);

    if Length(FDumpFile.Masses) > 0 then
    begin
      JMassArr := TJSONArray.Create;
      for I := 0 to High(FDumpFile.Masses) do
      begin
        JMass := TJSONObject.Create;
        JMass.AddPair('atomType', TJSONNumber.Create(FDumpFile.Masses[I].AtomType));
        JMass.AddPair('mass', JNum(FDumpFile.Masses[I].Mass));
        JMassArr.AddElement(JMass);
      end;
      J.AddPair('masses', JMassArr);
    end;

    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

function TframeLAMMPSViewer.SaveState: string;
var
  JObj: TJSONObject;
begin
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('v', TJSONNumber.Create(1));
    JObj.AddPair('tab', TJSONNumber.Create(Pages.ActivePageIndex));
    JObj.AddPair('crossSection', TJSONBool.Create(chkCrossSection.Checked));
    JObj.AddPair('slab', TJSONNumber.Create(trkSlab.Position));
    Result := JObj.ToJSON;
  finally
    JObj.Free;
  end;
end;

procedure TframeLAMMPSViewer.RestoreState(const AState: string);
var
  JObj: TJSONObject;
  JVal: TJSONValue;
  Idx: Integer;
begin
  try
    JObj := TJSONObject.ParseJSONValue(AState) as TJSONObject;
  except
    Exit;
  end;
  if not Assigned(JObj) then Exit;

  try
    Idx := JObj.GetValue<Integer>('tab', 0);
    if (Idx >= 0) and (Idx < Pages.PageCount) then
      Pages.ActivePageIndex := Idx;

    JVal := JObj.GetValue('crossSection');
    if Assigned(JVal) and (JVal is TJSONBool) then
      chkCrossSection.Checked := (JVal as TJSONBool).AsBoolean;

    trkSlab.Position := JObj.GetValue<Integer>('slab', trkSlab.Position);

    if Pages.ActivePage = tabDump then
      CrossSectionChanged(nil);
  finally
    JObj.Free;
  end;
end;

end.
