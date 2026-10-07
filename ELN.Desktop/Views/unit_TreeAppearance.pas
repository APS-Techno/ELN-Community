unit unit_TreeAppearance;

{
  How the desktop trees look for this user (item tree, projects panel,
  hypotheses): scale, row spacing, tint strength and row colours.

  The row colours live here, in one catalogue, so the trees, the item info
  panel and the Settings page share them. Only colours the user changed are
  stored (TNotebookSettings.TreeColors, "Key=#RRGGBB;..."), so a default changed here
  still reaches everyone who never touched it.

  Appearance is the one live instance: frmMain loads it at startup, the
  Settings page edits it, and TTreeLook reads it whenever it applies.
}

interface

uses
  System.SysUtils, Vcl.Graphics,
  unit_ItemTypes, unit_Hypothesis, unit_NotebookSettings;

type
  TTreeSpacing = (tspCompact, tspNormal, tspComfortable);
  TTreeTint = (ttnOff, ttnLight, ttnNormal, ttnStrong);
  TProjectRowKind = (prkUser, prkGroup, prkProject, prkFolder, prkFavorites,
    prkArchived);
  TTreeColorGroup = (tcgItems, tcgProjects, tcgHypotheses);

  TTreeColorEntry = record
    Key: string;
    Group: TTreeColorGroup;
    Caption: string;
    Default: TColor;
  end;

const
  TREE_SCALES: array[0..4] of Integer = (90, 100, 110, 125, 150);
  TREE_SPACING_NAMES: array[TTreeSpacing] of string =
    ('Compact', 'Normal', 'Comfortable');
  TREE_TINT_NAMES: array[TTreeTint] of string =
    ('Off', 'Light', 'Normal', 'Strong');
  TREE_COLOR_GROUP_NAMES: array[TTreeColorGroup] of string =
    ('Items', 'Projects', 'Hypotheses');

  // Catalogue layout: item types at Ord(TItemType), then the rest. A new
  // TItemType or THypothesisStatus changes TREE_COLOR_COUNT, and the
  // TREE_COLORS literal below stops compiling until it gets its colour.
  TC_PROTOCOL = Ord(High(TItemType)) + 1;
  TC_NOTE = TC_PROTOCOL + 1;
  TC_FILE = TC_NOTE + 1;
  TC_PROJECT_FIRST = TC_FILE + 1;
  TC_HYP_FIRST = TC_PROJECT_FIRST + Ord(High(TProjectRowKind)) + 1;
  TREE_COLOR_COUNT = TC_HYP_FIRST + Ord(High(THypothesisStatus)) + 1;

  // Defaults ($00BBGGRR) are the colours the trees always had.
  TREE_COLORS: array[0..TREE_COLOR_COUNT - 1] of TTreeColorEntry = (
    (Key: 'Item.Synthesis';        Group: tcgItems; Caption: 'Synthesis';        Default: $003C8E38),
    (Key: 'Item.Treatment';        Group: tcgItems; Caption: 'Treatment';        Default: $000051E6),
    (Key: 'Item.Measurement';      Group: tcgItems; Caption: 'Measurement';      Default: $00C06515),
    (Key: 'Item.Testing';          Group: tcgItems; Caption: 'Testing';          Default: $002828C6),
    (Key: 'Item.Characterization'; Group: tcgItems; Caption: 'Characterization'; Default: $009A1B6A),
    (Key: 'Item.Computing';        Group: tcgItems; Caption: 'Computing';        Default: $007A6E54),
    (Key: 'Item.Specimen';         Group: tcgItems; Caption: 'Specimen';         Default: $002E344E),
    (Key: 'Item.Model';            Group: tcgItems; Caption: 'Model';            Default: $00006FFF),
    (Key: 'Item.Other';            Group: tcgItems; Caption: 'Other';            Default: $00645A45),
    (Key: 'Item.Wiki';             Group: tcgItems; Caption: 'Wiki';             Default: $00899968),
    (Key: 'Item.Protocol';         Group: tcgItems; Caption: 'Protocol';         Default: $008F8300),
    (Key: 'Item.Note';             Group: tcgItems; Caption: 'Note';             Default: $000DA8F9),
    (Key: 'Item.File';             Group: tcgItems; Caption: 'File';             Default: $00757575),
    (Key: 'Project.User';      Group: tcgProjects; Caption: 'User';             Default: $007C6B5B),
    (Key: 'Project.Group';     Group: tcgProjects; Caption: 'Group';            Default: $00955B6B),
    (Key: 'Project.Project';   Group: tcgProjects; Caption: 'Project';          Default: $00C06515),
    (Key: 'Project.Folder';    Group: tcgProjects; Caption: 'Folder';           Default: $00757575),
    (Key: 'Project.Favorites'; Group: tcgProjects; Caption: 'Favorites';        Default: $00008FFF),
    (Key: 'Project.Archived';  Group: tcgProjects; Caption: 'Archived project'; Default: $009E9E9E),
    (Key: 'Hyp.Proposed';  Group: tcgHypotheses; Caption: 'Proposed';  Default: $00A34F8E),
    (Key: 'Hyp.Approved';  Group: tcgHypotheses; Caption: 'Approved';  Default: $00C06515),
    (Key: 'Hyp.Rejected';  Group: tcgHypotheses; Caption: 'Rejected';  Default: $002828C6),
    (Key: 'Hyp.InReview';  Group: tcgHypotheses; Caption: 'In review'; Default: $008D8B0F),
    (Key: 'Hyp.Accepted';  Group: tcgHypotheses; Caption: 'Accepted';  Default: $003C8E38),
    (Key: 'Hyp.Abandoned'; Group: tcgHypotheses; Caption: 'Abandoned'; Default: $00757575)
  );

type
  TTreeAppearance = class
  private
    FScale: Integer;
    FSpacing: TTreeSpacing;
    FTint: TTreeTint;
    FOverrides: array[0..TREE_COLOR_COUNT - 1] of TColor;   // clNone = default
    procedure SetScale(Value: Integer);
  public
    constructor Create;
    /// Copies everything, overrides included (a snapshot for Cancel).
    procedure Assign(Source: TTreeAppearance);
    /// Out-of-range stored values read as their defaults.
    procedure Load(S: TNotebookSettings);
    procedure Save(S: TNotebookSettings);
    /// Catalogue index -> the user's colour, or the default.
    function Color(Index: Integer): TColor;
    function IsCustom(Index: Integer): Boolean;
    /// Setting the default colour clears the override.
    procedure SetColor(Index: Integer; Value: TColor);
    procedure ResetColor(Index: Integer);
    procedure ResetAllColors;
    /// "Key=#RRGGBB;..." in catalogue order, overrides only.
    function OverridesText: string;
    /// Replaces all overrides; unknown keys and malformed entries are skipped.
    procedure SetOverridesText(const Text: string);
    /// Base (a font height or indent) times the scale.
    function Scaled(Base: Integer): Integer;
    /// A natural row height (already at the scaled font) times the spacing.
    function Spaced(Base: Integer): Integer;
    /// How much of the row colour is mixed into the tree background.
    function TintFactor(Dark: Boolean): Double;
    /// One of TREE_SCALES; anything else becomes 100.
    property Scale: Integer read FScale write SetScale;
    property Spacing: TTreeSpacing read FSpacing write FSpacing;
    property Tint: TTreeTint read FTint write FTint;
  end;

/// The live appearance of this session's trees.
function Appearance: TTreeAppearance;

function ItemTypeColor(T: TItemType): TColor;
function ItemProtocolColor: TColor;
function ItemNoteColor: TColor;
function ItemFileColor: TColor;
function ProjectKindColor(K: TProjectRowKind): TColor;
function HypStatusColor(S: THypothesisStatus): TColor;

implementation

const
  SPACING_FACTORS: array[TTreeSpacing] of Double = (0.8, 1.0, 1.25);
  // [Tint, Dark]
  TINT_FACTORS: array[TTreeTint, Boolean] of Double = (
    (0, 0), (0.06, 0.12), (0.12, 0.24), (0.20, 0.36));

var
  GAppearance: TTreeAppearance;

function Appearance: TTreeAppearance;
begin
  if not Assigned(GAppearance) then
    GAppearance := TTreeAppearance.Create;
  Result := GAppearance;
end;

function ItemTypeColor(T: TItemType): TColor;
begin
  Result := Appearance.Color(Ord(T));
end;

function ItemProtocolColor: TColor;
begin
  Result := Appearance.Color(TC_PROTOCOL);
end;

function ItemNoteColor: TColor;
begin
  Result := Appearance.Color(TC_NOTE);
end;

function ItemFileColor: TColor;
begin
  Result := Appearance.Color(TC_FILE);
end;

function ProjectKindColor(K: TProjectRowKind): TColor;
begin
  Result := Appearance.Color(TC_PROJECT_FIRST + Ord(K));
end;

function HypStatusColor(S: THypothesisStatus): TColor;
begin
  Result := Appearance.Color(TC_HYP_FIRST + Ord(S));
end;

function IndexOfKey(const Key: string): Integer;
var
  I: Integer;
begin
  for I := 0 to TREE_COLOR_COUNT - 1 do
    if SameText(TREE_COLORS[I].Key, Key) then
      Exit(I);
  Result := -1;
end;

// '#RRGGBB' -> TColor ($00BBGGRR).
function TryParseHexColor(const S: string; out C: TColor): Boolean;
var
  I, N: Integer;
begin
  Result := (Length(S) = 7) and (S[1] = '#');
  if not Result then Exit;
  for I := 2 to 7 do
    if not CharInSet(S[I], ['0'..'9', 'A'..'F', 'a'..'f']) then
      Exit(False);
  N := StrToInt('$' + Copy(S, 2, 6));
  C := TColor(((N and $FF) shl 16) or (N and $FF00) or ((N shr 16) and $FF));
end;

function HexColor(C: TColor): string;
begin
  Result := Format('#%.2X%.2X%.2X', [C and $FF, (C shr 8) and $FF, (C shr 16) and $FF]);
end;

{ TTreeAppearance }

constructor TTreeAppearance.Create;
begin
  inherited Create;
  FScale := 100;
  FSpacing := tspNormal;
  FTint := ttnNormal;
  ResetAllColors;
end;

procedure TTreeAppearance.Assign(Source: TTreeAppearance);
begin
  FScale := Source.FScale;
  FSpacing := Source.FSpacing;
  FTint := Source.FTint;
  FOverrides := Source.FOverrides;   // static array: copied by value
end;

// Each read on its own: a value of the wrong registry type (hand-edited)
// raises in TRegistry, and must cost only that value, not the app's start.
function ReadOr(const Read: TFunc<Integer>; Default: Integer): Integer; overload;
begin
  try
    Result := Read();
  except
    Result := Default;
  end;
end;

function ReadOr(const Read: TFunc<string>; const Default: string): string; overload;
begin
  try
    Result := Read();
  except
    Result := Default;
  end;
end;

procedure TTreeAppearance.Load(S: TNotebookSettings);
var
  V: Integer;
begin
  Scale := ReadOr(function: Integer begin Result := S.TreeScale end, 100);
  V := ReadOr(function: Integer begin Result := S.TreeSpacing end, Ord(tspNormal));
  if (V >= Ord(Low(TTreeSpacing))) and (V <= Ord(High(TTreeSpacing))) then
    FSpacing := TTreeSpacing(V)
  else
    FSpacing := tspNormal;
  V := ReadOr(function: Integer begin Result := S.TreeTint end, Ord(ttnNormal));
  if (V >= Ord(Low(TTreeTint))) and (V <= Ord(High(TTreeTint))) then
    FTint := TTreeTint(V)
  else
    FTint := ttnNormal;
  SetOverridesText(ReadOr(function: string begin Result := S.TreeColors end, ''));
end;

procedure TTreeAppearance.Save(S: TNotebookSettings);
begin
  S.TreeScale := FScale;
  S.TreeSpacing := Ord(FSpacing);
  S.TreeTint := Ord(FTint);
  S.TreeColors := OverridesText;
end;

procedure TTreeAppearance.SetScale(Value: Integer);
var
  Allowed: Integer;
begin
  FScale := 100;
  for Allowed in TREE_SCALES do
    if Value = Allowed then
      FScale := Value;
end;

function TTreeAppearance.Color(Index: Integer): TColor;
begin
  Result := FOverrides[Index];
  if Result = clNone then
    Result := TREE_COLORS[Index].Default;
end;

function TTreeAppearance.IsCustom(Index: Integer): Boolean;
begin
  Result := FOverrides[Index] <> clNone;
end;

procedure TTreeAppearance.SetColor(Index: Integer; Value: TColor);
begin
  if Value = TREE_COLORS[Index].Default then
    FOverrides[Index] := clNone
  else
    FOverrides[Index] := Value;
end;

procedure TTreeAppearance.ResetColor(Index: Integer);
begin
  FOverrides[Index] := clNone;
end;

procedure TTreeAppearance.ResetAllColors;
var
  I: Integer;
begin
  for I := 0 to TREE_COLOR_COUNT - 1 do
    FOverrides[I] := clNone;
end;

function TTreeAppearance.OverridesText: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to TREE_COLOR_COUNT - 1 do
    if IsCustom(I) then
    begin
      if Result <> '' then
        Result := Result + ';';
      Result := Result + TREE_COLORS[I].Key + '=' + HexColor(FOverrides[I]);
    end;
end;

procedure TTreeAppearance.SetOverridesText(const Text: string);
var
  Part: string;
  P, Index: Integer;
  C: TColor;
begin
  ResetAllColors;
  for Part in Text.Split([';']) do
  begin
    P := Pos('=', Part);
    if P = 0 then Continue;
    Index := IndexOfKey(Trim(Copy(Part, 1, P - 1)));
    if (Index >= 0) and TryParseHexColor(Trim(Copy(Part, P + 1, MaxInt)), C) then
      SetColor(Index, C);
  end;
end;

function TTreeAppearance.Scaled(Base: Integer): Integer;
begin
  Result := Round(Base * FScale / 100);
end;

function TTreeAppearance.Spaced(Base: Integer): Integer;
begin
  Result := Round(Base * SPACING_FACTORS[FSpacing]);
end;

function TTreeAppearance.TintFactor(Dark: Boolean): Double;
begin
  Result := TINT_FACTORS[FTint, Dark];
end;

initialization

finalization
  FreeAndNil(GAppearance);

end.
