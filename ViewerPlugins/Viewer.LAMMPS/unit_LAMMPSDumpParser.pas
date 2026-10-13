unit unit_LAMMPSDumpParser;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TMassRecord = record
    AtomType: Integer;
    Mass: Double;
  end;

  TAtomRecord = record
    ID: Integer;
    AtomType: Integer;
    X, Y, Z: Double;
  end;

  TBoxBounds = record
    XLo, XHi: Double;
    YLo, YHi: Double;
    ZLo, ZHi: Double;
    XY, XZ, YZ: Double; // restricted triclinic tilt factors
  end;

  TLAMMPSDumpFile = class
  private
    FAtomCount: Integer;
    FHeaderAtomCount: Integer;
    FAtomTypeCount: Integer;
    FBox: TBoxBounds;
    FMasses: TArray<TMassRecord>;
    FAtoms: TArray<TAtomRecord>;
    FHasVelocities: Boolean;
    FFileName: string;
    FAtomStyle: string;
    FIsDumpFormat: Boolean;
    FIsBinaryRestart: Boolean;
    FTimestep: Int64;
    FFrameCount: Integer;
    FDumpColumns: string;

    procedure ParseLines(Lines: TStringList);
    procedure ParseDumpLines(Lines: TStringList);
    function LooksLikeDump(Lines: TStringList): Boolean;
    function ParseHeaderInt(const Line, Suffix: string; out Value: Integer): Boolean;
    function ParseBoxLine(const Line: string; out Lo, Hi: Double): Boolean;
    function TypeColumnValid(ARows: TList<TArray<string>>;
      ATypeCol: Integer): Boolean;
    function ColumnsValid(ARows: TList<TArray<string>>;
      ATypeCol, AXCol: Integer): Boolean;
    procedure ResolveAtomColumns(ARows: TList<TArray<string>>;
      const AStyleComment: string; out ATypeCol, AXCol: Integer);
  public
    procedure Clear;
    procedure ParseFromFile(const AFileName: string);

    function GetSummaryText: string;
    function AtomTypeColor(AType: Integer): Integer;

    property AtomCount: Integer read FAtomCount;
    property HeaderAtomCount: Integer read FHeaderAtomCount;
    property AtomTypeCount: Integer read FAtomTypeCount;
    property AtomStyle: string read FAtomStyle;
    property Box: TBoxBounds read FBox;
    property Masses: TArray<TMassRecord> read FMasses;
    property Atoms: TArray<TAtomRecord> read FAtoms;
    property HasVelocities: Boolean read FHasVelocities;
    property FileName: string read FFileName;

    // Dump-format extras. IsDumpFormat is False for read_data text files, and
    // then Timestep/FrameCount/DumpColumns carry no meaning.
    // True for a binary "write_restart" file. Nothing else is populated: the
    // format is LAMMPS-build-specific binary and is not read here.
    property IsBinaryRestart: Boolean read FIsBinaryRestart;
    property IsDumpFormat: Boolean read FIsDumpFormat;
    property Timestep: Int64 read FTimestep;
    property FrameCount: Integer read FFrameCount;
    property DumpColumns: string read FDumpColumns;
  end;

implementation

uses
  System.Math;

type
  // Column map for one LAMMPS atom_style, as documented for read_data.
  // TypeCol/XCol are 0-based indices into the whitespace-split Atoms line;
  // Y and Z always follow X immediately.
  TAtomStyleColumns = record
    Style: string;
    TypeCol: Integer;
    XCol: Integer;
  end;

const
  ATOM_COLORS: array[0..19] of Integer = (
    $004B19E6,
    $004BB43C,
    $00D86343,
    $003182F5,
    $00B41E91,
    $00F0F046,
    $00E632F0,
    $000CF6BC,
    $008515C7,
    $00808000,
    $002F6B55,
    $0024639A,
    $00008080,
    $00000080,
    $0020A5DA,
    $00750000,
    $00808080,
    $00616FFF,
    $0082004B,
    $000B86B8
  );

  // Hints only - every entry is re-validated against the actual columns.
  ATOM_STYLE_COLUMNS: array[0..15] of TAtomStyleColumns = (
    (Style: 'atomic';    TypeCol: 1; XCol: 2),  // id type x y z
    (Style: 'charge';    TypeCol: 1; XCol: 3),  // id type q x y z
    (Style: 'dipole';    TypeCol: 1; XCol: 3),  // id type q x y z mux muy muz
    (Style: 'dpd';       TypeCol: 1; XCol: 3),  // id type theta x y z
    (Style: 'sphere';    TypeCol: 1; XCol: 4),  // id type diameter density x y z
    (Style: 'ellipsoid'; TypeCol: 1; XCol: 4),  // id type flag density x y z
    (Style: 'peri';      TypeCol: 1; XCol: 4),  // id type volume density x y z
    (Style: 'body';      TypeCol: 1; XCol: 4),  // id type bodyflag mass x y z
    (Style: 'sph';       TypeCol: 1; XCol: 5),  // id type rho esph cv x y z
    (Style: 'molecular'; TypeCol: 2; XCol: 3),  // id mol type x y z
    (Style: 'bond';      TypeCol: 2; XCol: 3),  // id mol type x y z
    (Style: 'angle';     TypeCol: 2; XCol: 3),  // id mol type x y z
    (Style: 'full';      TypeCol: 2; XCol: 4),  // id mol type q x y z
    (Style: 'line';      TypeCol: 2; XCol: 5),  // id mol type flag density x y z
    (Style: 'tri';       TypeCol: 2; XCol: 5),  // id mol type flag density x y z
    (Style: 'template';  TypeCol: 4; XCol: 5)   // id mol t-index t-atom type x y z
  );

  TYPE_COL_CANDIDATES: array[0..2] of Integer = (1, 2, 4);

function SectionComment(const ALine: string): string;
var
  P: Integer;
begin
  P := Pos('#', ALine);
  if P > 0 then
    Result := LowerCase(Trim(Copy(ALine, P + 1, MaxInt)))
  else
    Result := '';
end;


{ Every LAMMPS binary restart opens with this magic string. }

function FileIsBinaryRestart(const AFileName: string): Boolean;
const
  MAGIC: AnsiString = 'LammpS Restart';
var
  FS: TFileStream;
  Buf: TBytes;
  I: Integer;
begin
  Result := False;
  SetLength(Buf, Length(MAGIC));
  try
    FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
    try
      if FS.Read(Buf[0], Length(Buf)) <> Length(Buf) then
        Exit;
    finally
      FS.Free;
    end;
  except
    Exit;
  end;

  for I := 1 to Length(MAGIC) do
    if Buf[I - 1] <> Byte(MAGIC[I]) then
      Exit;
  Result := True;
end;

{ The frame reuses one instance across files, and the plugin host reuses one
  frame across requests. Anything not reset here is reported against the NEXT
  file - a file with no box lines would inherit the previous file's bounds, and
  a file that is never parsed at all (an .lmpin input deck) would otherwise
  report the previous file's atoms as its own. }

procedure TLAMMPSDumpFile.Clear;
begin
  FFileName := '';
  FAtomCount := 0;
  FHeaderAtomCount := 0;
  FAtomTypeCount := 0;
  FAtomStyle := '';
  FHasVelocities := False;
  FBox := Default(TBoxBounds);
  SetLength(FMasses, 0);
  SetLength(FAtoms, 0);
  FIsDumpFormat := False;
  FIsBinaryRestart := False;
  FTimestep := 0;
  FFrameCount := 0;
  FDumpColumns := '';
end;

procedure TLAMMPSDumpFile.ParseFromFile(const AFileName: string);
var
  Lines: TStringList;
begin
  Clear;
  FFileName := AFileName;

  // write_restart output is binary and carries no text at all. Detect it up
  // front: loading an 11 MB binary into a TStringList only to parse nothing
  // out of it looks to the caller exactly like an empty file.
  if FileIsBinaryRestart(AFileName) then
  begin
    FIsBinaryRestart := True;
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(AFileName);
    if LooksLikeDump(Lines) then
      ParseDumpLines(Lines)
    else
      ParseLines(Lines);
  finally
    Lines.Free;
  end;
end;

{ A dump frame always opens with "ITEM: TIMESTEP". Scan a few lines rather than
  only the first so a leading comment or blank line does not hide it. }

function TLAMMPSDumpFile.LooksLikeDump(Lines: TStringList): Boolean;
var
  I, Last: Integer;
begin
  Result := False;
  Last := Min(Lines.Count - 1, 20);
  for I := 0 to Last do
    if Trim(Lines[I]).StartsWith('ITEM:', True) then
      Exit(True);
end;

function TryLAMMPSFloat(const Text: string; out Value: Double): Boolean;
begin
  Result := TryStrToFloat(Text, Value, TFormatSettings.Invariant) and
    not IsNan(Value) and not IsInfinite(Value);
end;

function ParseDumpBoxLine(const Line: string; Triclinic: Boolean;
  out Lo, Hi, Tilt: Double): Boolean;
var
  Parts: TArray<string>;
begin
  Tilt := 0;
  Parts := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  Result := (Length(Parts) = 2 + Ord(Triclinic)) and
    TryLAMMPSFloat(Parts[0], Lo) and TryLAMMPSFloat(Parts[1], Hi);
  if Result and Triclinic then
    Result := TryLAMMPSFloat(Parts[2], Tilt);
end;

{ LAMMPS dump format:

    ITEM: TIMESTEP
    <step>
    ITEM: NUMBER OF ATOMS
    <n>
    ITEM: BOX BOUNDS <flags>
    <lo> <hi>   x3
    ITEM: ATOMS <col> <col> ...
    <n rows>

  A file may hold many frames. The viewer wants the final state, so each frame
  overwrites the previous one and only the last survives.

  Unlike read_data there is no column guessing: the ITEM: ATOMS line names the
  columns. Coordinates come as x/y/z (real), xs/ys/zs (box fractions) or
  xu/yu/zu (unwrapped); scaled ones are mapped back onto the box. }

procedure TLAMMPSDumpFile.ParseDumpLines(Lines: TStringList);
var
  I, N, BoxAxis, Cnt: Integer;
  IdCol, TypeCol, XCol, YCol, ZCol: Integer;
  Scaled, Triclinic: Boolean;
  Line, Head, Rest: string;
  Cols, Parts: TArray<string>;
  Lo, Hi, Tilt: Double;
  Atom: TAtomRecord;
  InAtoms: Boolean;

  procedure ResetFrameColumns;
  begin
    IdCol := -1; TypeCol := -1; XCol := -1; YCol := -1; ZCol := -1;
    Scaled := False;
  end;

  function ColValue(const AParts: TArray<string>; ACol: Integer;
    out V: Double): Boolean;
  begin
    Result := (ACol >= 0) and (ACol < Length(AParts)) and
      TryLAMMPSFloat(AParts[ACol], V);
  end;

  function Column(const Name: string): Integer;
  var
    K: Integer;
  begin
    for K := 0 to High(Cols) do
      if Cols[K] = Name then
        Exit(K);
    Result := -1;
  end;

  function CoordinateColumns(const XName, YName, ZName: string): Boolean;
  begin
    XCol := Column(XName);
    YCol := Column(YName);
    ZCol := Column(ZName);
    Result := (XCol >= 0) and (YCol >= 0) and (ZCol >= 0);
  end;

begin
  FIsDumpFormat := True;
  ResetFrameColumns;
  InAtoms := False;
  BoxAxis := 3;
  Triclinic := False;
  Cnt := 0;

  I := 0;
  while I < Lines.Count do
  begin
    Line := Trim(Lines[I]);

    if Line.StartsWith('ITEM:', True) then
    begin
      InAtoms := False;
      Rest := Trim(Copy(Line, 6, MaxInt));
      Head := UpperCase(Rest);

      if Head = 'TIMESTEP' then
      begin
        Inc(FFrameCount);
        SetLength(FAtoms, 0);
        Cnt := 0;
        FAtomCount := 0;
        FHeaderAtomCount := 0;
        FAtomTypeCount := 0;
        FBox := Default(TBoxBounds);
        BoxAxis := 3;
        Triclinic := False;
        ResetFrameColumns;
        if (I + 1 < Lines.Count) then
          TryStrToInt64(Trim(Lines[I + 1]), FTimestep);
        Inc(I);
      end
      else if Head = 'NUMBER OF ATOMS' then
      begin
        if (I + 1 < Lines.Count) and TryStrToInt(Trim(Lines[I + 1]), N) then
        begin
          if N < 0 then
            raise EConvertError.Create('Negative LAMMPS atom count');
          FHeaderAtomCount := N;
          SetLength(FAtoms, N);
        end;
        Inc(I);
      end
      else if Head.StartsWith('BOX BOUNDS') then
      begin
        if Head.Contains('ABC') or Head.Contains('ORIGIN') then
          raise EConvertError.Create('General triclinic LAMMPS boxes are not supported');
        Triclinic := Head.StartsWith('BOX BOUNDS XY XZ YZ');
        BoxAxis := 0;
      end
      else if Head.StartsWith('ATOMS') then
      begin
        FDumpColumns := Trim(Copy(Rest, 6, MaxInt));
        Cols := FDumpColumns.ToLower.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
        IdCol := Column('id');
        TypeCol := Column('type');
        Scaled := False;
        if not CoordinateColumns('x', 'y', 'z') and
           not CoordinateColumns('xu', 'yu', 'zu') then
        begin
          Scaled := True;
          if not CoordinateColumns('xs', 'ys', 'zs') and
             not CoordinateColumns('xsu', 'ysu', 'zsu') then
            raise EConvertError.Create('Unsupported or incomplete LAMMPS coordinate columns');
        end;
        if BoxAxis <> 3 then
          raise EConvertError.Create('Incomplete LAMMPS box bounds');
        InAtoms := True;
      end;
    end
    else if InAtoms and (Line <> '') then
    begin
      Parts := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      Atom := Default(TAtomRecord);

      if (IdCol >= 0) and (IdCol < Length(Parts)) then
        TryStrToInt(Parts[IdCol], Atom.ID)
      else
        Atom.ID := Cnt + 1;

      if (TypeCol >= 0) and (TypeCol < Length(Parts)) then
        TryStrToInt(Parts[TypeCol], Atom.AtomType);

      if not ColValue(Parts, XCol, Atom.X) or
         not ColValue(Parts, YCol, Atom.Y) or
         not ColValue(Parts, ZCol, Atom.Z) then
        raise EConvertError.Create('Invalid LAMMPS atom coordinates');

      if Scaled then
      begin
        Atom.X := FBox.XLo + Atom.X * (FBox.XHi - FBox.XLo) +
          Atom.Y * FBox.XY + Atom.Z * FBox.XZ;
        Atom.Y := FBox.YLo + Atom.Y * (FBox.YHi - FBox.YLo) + Atom.Z * FBox.YZ;
        Atom.Z := FBox.ZLo + Atom.Z * (FBox.ZHi - FBox.ZLo);
      end;

      if Cnt >= Length(FAtoms) then
        SetLength(FAtoms, Cnt + 1024);
      FAtoms[Cnt] := Atom;
      Inc(Cnt);

      // Dump frames carry no "N atom types" header. Type ids run 1..ntypes,
      // so the largest id seen is the best available estimate.
      if Atom.AtomType > FAtomTypeCount then
        FAtomTypeCount := Atom.AtomType;
    end
    else if (BoxAxis < 3) and (Line <> '') then
    begin
      if not ParseDumpBoxLine(Line, Triclinic, Lo, Hi, Tilt) then
        raise EConvertError.Create('Invalid LAMMPS box bounds');
      case BoxAxis of
        0: begin FBox.XLo := Lo; FBox.XHi := Hi; FBox.XY := Tilt; end;
        1: begin FBox.YLo := Lo; FBox.YHi := Hi; FBox.XZ := Tilt; end;
        2:
          begin
            FBox.ZLo := Lo;
            FBox.ZHi := Hi;
            FBox.YZ := Tilt;
            if Triclinic then
            begin
              FBox.XLo := FBox.XLo - Min(Min(0.0, FBox.XY), Min(FBox.XZ, FBox.XY + FBox.XZ));
              FBox.XHi := FBox.XHi - Max(Max(0.0, FBox.XY), Max(FBox.XZ, FBox.XY + FBox.XZ));
              FBox.YLo := FBox.YLo - Min(0.0, FBox.YZ);
              FBox.YHi := FBox.YHi - Max(0.0, FBox.YZ);
            end;
          end;
      end;
      Inc(BoxAxis);
    end;

    Inc(I);
  end;

  SetLength(FAtoms, Cnt);
  FAtomCount := Cnt;
end;

function TLAMMPSDumpFile.ParseHeaderInt(const Line, Suffix: string;
  out Value: Integer): Boolean;
var
  P: Integer;
  S: string;
begin
  Result := False;
  P := Pos(Suffix, LowerCase(Line));
  if P > 0 then
  begin
    S := Trim(Copy(Line, 1, P - 1));
    Result := TryStrToInt(S, Value);
  end;
end;

function TLAMMPSDumpFile.ParseBoxLine(const Line: string;
  out Lo, Hi: Double): Boolean;
var
  Parts: TArray<string>;
begin
  Result := False;
  Parts := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(Parts) >= 4 then
  begin
    Result := TryLAMMPSFloat(Parts[0], Lo) and TryLAMMPSFloat(Parts[1], Hi);
  end;
end;

function TLAMMPSDumpFile.TypeColumnValid(ARows: TList<TArray<string>>;
  ATypeCol: Integer): Boolean;
var
  Row: TArray<string>;
  V: Integer;
begin
  Result := False;
  if ATypeCol < 0 then
    Exit;
  for Row in ARows do
  begin
    if ATypeCol >= Length(Row) then
      Exit;
    if not TryStrToInt(Row[ATypeCol], V) then
      Exit;
    if (FAtomTypeCount > 0) and ((V < 1) or (V > FAtomTypeCount)) then
      Exit;
  end;
  Result := True;
end;

function TLAMMPSDumpFile.ColumnsValid(ARows: TList<TArray<string>>;
  ATypeCol, AXCol: Integer): Boolean;
var
  Row: TArray<string>;
begin
  Result := False;
  if (ATypeCol < 0) or (AXCol < 0) then
    Exit;
  for Row in ARows do
    if AXCol + 3 > Length(Row) then
      Exit;
  Result := TypeColumnValid(ARows, ATypeCol);
end;

{ Picks the type and x columns for the Atoms body. The "Atoms # <style>"
  comment is treated as a hint: if the mapped columns do not survive
  validation against the rows themselves, the layout is inferred instead. }
procedure TLAMMPSDumpFile.ResolveAtomColumns(ARows: TList<TArray<string>>;
  const AStyleComment: string; out ATypeCol, AXCol: Integer);
var
  I: Integer;
  ColCount: Integer;
  Found: Boolean;

  // Rows in a well-formed file are uniform; take the narrowest so every
  // index derived from it stays inside every row.
  function MinColumnCount: Integer;
  var
    R: TArray<string>;
  begin
    Result := 0;
    for R in ARows do
      if (Result = 0) or (Length(R) < Result) then
        Result := Length(R);
  end;

  function TrailingImageFlags(ACols: Integer): Boolean;
  var
    R: TArray<string>;
    K, V: Integer;
  begin
    Result := False;
    if ACols < 3 then
      Exit;
    for R in ARows do
      for K := ACols - 3 to ACols - 1 do
        if not TryStrToInt(R[K], V) then
          Exit;
    Result := True;
  end;

begin
  if AStyleComment <> '' then
    for I := Low(ATOM_STYLE_COLUMNS) to High(ATOM_STYLE_COLUMNS) do
      if ATOM_STYLE_COLUMNS[I].Style = AStyleComment then
      begin
        ATypeCol := ATOM_STYLE_COLUMNS[I].TypeCol;
        AXCol := ATOM_STYLE_COLUMNS[I].XCol;
        if ColumnsValid(ARows, ATypeCol, AXCol) then
        begin
          FAtomStyle := AStyleComment;
          Exit;
        end;
        Break;
      end;

  if AStyleComment <> '' then
    FAtomStyle := AStyleComment + ' (corrected)'
  else
    FAtomStyle := 'inferred';

  ATypeCol := 1;
  AXCol := 2;

  Found := False;
  for I := Low(TYPE_COL_CANDIDATES) to High(TYPE_COL_CANDIDATES) do
    if TypeColumnValid(ARows, TYPE_COL_CANDIDATES[I]) then
    begin
      ATypeCol := TYPE_COL_CANDIDATES[I];
      Found := True;
      Break;
    end;
  if not Found then
    Exit;

  // Coordinates are the last three columns unless image flags trail them.
  ColCount := MinColumnCount;
  if ColCount < ATypeCol + 4 then
    Exit;
  if (ColCount >= ATypeCol + 7) and TrailingImageFlags(ColCount) then
    AXCol := ColCount - 6
  else
    AXCol := ColCount - 3;
end;

procedure TLAMMPSDumpFile.ParseLines(Lines: TStringList);
var
  I: Integer;
  Line, Lower: string;
  Parts: TArray<string>;
  MassList: TList<TMassRecord>;
  RawAtoms: TList<TArray<string>>;
  MRec: TMassRecord;
  ARec: TAtomRecord;
  AtomsSeen: Boolean;
  StyleComment: string;
  TypeCol, XCol: Integer;

  procedure SkipBlanksAndComments;
  begin
    while I < Lines.Count do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or Line.StartsWith('#') then
        Inc(I)
      else
        Break;
    end;
  end;

begin
  MassList := TList<TMassRecord>.Create;
  RawAtoms := TList<TArray<string>>.Create;
  try
    I := 0;
    AtomsSeen := False;
    StyleComment := '';

    while I < Lines.Count do
    begin
      Line := Trim(Lines[I]);
      Inc(I);

      if (Line = '') or Line.StartsWith('#') then
        Continue;

      Lower := LowerCase(Line);

      if CharInSet(Line[1], ['A'..'Z', 'a'..'z']) then
      begin
        if Lower.StartsWith('masses') then
        begin
          SkipBlanksAndComments;
          while I < Lines.Count do
          begin
            Line := Trim(Lines[I]);
            if (Line = '') then
            begin
              Inc(I);
              Break;
            end;
            if not CharInSet(Line[1], ['0'..'9']) then
              Break;

            Parts := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
            if Length(Parts) >= 2 then
            begin
              MRec.AtomType := StrToIntDef(Parts[0], 0);
              if not TryLAMMPSFloat(Parts[1], MRec.Mass) then
                raise EConvertError.Create('Invalid LAMMPS mass');
              MassList.Add(MRec);
            end;
            Inc(I);
          end;
          Continue;
        end;

        if Lower.StartsWith('atoms') then
        begin
          // The column layout depends on the atom_style, which the section
          // header carries as a comment ("Atoms # full"). Collect the raw
          // columns first - validating the layout needs every row.
          AtomsSeen := True;
          StyleComment := SectionComment(Line);
          SkipBlanksAndComments;
          while I < Lines.Count do
          begin
            Line := Trim(Lines[I]);
            if (Line = '') then
            begin
              Inc(I);
              Break;
            end;
            if not CharInSet(Line[1], ['0'..'9']) then
              Break;

            Parts := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
            if Length(Parts) >= 5 then
              RawAtoms.Add(Parts);
            Inc(I);
          end;
          Continue;
        end;

        if Lower.StartsWith('velocities') then
        begin
          FHasVelocities := True;
          Break;
        end;

        if Lower.EndsWith('avec') or Lower.EndsWith('bvec') or
           Lower.EndsWith('cvec') or Lower.EndsWith('abc origin') then
          raise EConvertError.Create('General triclinic LAMMPS boxes are not supported');
        Continue;
      end;

      if Lower.Contains('atoms') and not Lower.Contains('atom types') then
      begin
        ParseHeaderInt(Line, ' atoms', FHeaderAtomCount);
        Continue;
      end;

      if Lower.Contains('atom types') then
      begin
        ParseHeaderInt(Line, ' atom types', FAtomTypeCount);
        Continue;
      end;

      if Lower.Contains('xlo xhi') then
      begin
        if not ParseBoxLine(Line, FBox.XLo, FBox.XHi) then
          raise EConvertError.Create('Invalid LAMMPS x bounds');
        Continue;
      end;

      if Lower.Contains('ylo yhi') then
      begin
        if not ParseBoxLine(Line, FBox.YLo, FBox.YHi) then
          raise EConvertError.Create('Invalid LAMMPS y bounds');
        Continue;
      end;

      if Lower.Contains('zlo zhi') then
      begin
        if not ParseBoxLine(Line, FBox.ZLo, FBox.ZHi) then
          raise EConvertError.Create('Invalid LAMMPS z bounds');
        Continue;
      end;
      if Lower.EndsWith('xy xz yz') then
      begin
        Parts := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
        if (Length(Parts) <> 6) or
           not TryLAMMPSFloat(Parts[0], FBox.XY) or
           not TryLAMMPSFloat(Parts[1], FBox.XZ) or
           not TryLAMMPSFloat(Parts[2], FBox.YZ) then
          raise EConvertError.Create('Invalid LAMMPS tilt factors');
      end;
      if Lower.EndsWith('avec') or Lower.EndsWith('bvec') or
         Lower.EndsWith('cvec') or Lower.EndsWith('abc origin') then
        raise EConvertError.Create('General triclinic LAMMPS boxes are not supported');
    end;

    FMasses := MassList.ToArray;

    TypeCol := 1;
    XCol := 2;
    if AtomsSeen then
      ResolveAtomColumns(RawAtoms, StyleComment, TypeCol, XCol);

    SetLength(FAtoms, RawAtoms.Count);
    for I := 0 to RawAtoms.Count - 1 do
    begin
      Parts := RawAtoms[I];
      ARec := Default(TAtomRecord);
      ARec.ID := StrToIntDef(Parts[0], 0);
      if TypeCol < Length(Parts) then
        ARec.AtomType := StrToIntDef(Parts[TypeCol], 0);
      if (XCol + 3 > Length(Parts)) or
         not TryLAMMPSFloat(Parts[XCol], ARec.X) or
         not TryLAMMPSFloat(Parts[XCol + 1], ARec.Y) or
         not TryLAMMPSFloat(Parts[XCol + 2], ARec.Z) then
        raise EConvertError.Create('Invalid LAMMPS atom coordinates');
      FAtoms[I] := ARec;
    end;

    FAtomCount := Length(FAtoms);
  finally
    MassList.Free;
    RawAtoms.Free;
  end;
end;

function TLAMMPSDumpFile.GetSummaryText: string;
var
  SB: TStringBuilder;
  I: Integer;
  XSize, YSize, ZSize: Double;
begin
  if FIsBinaryRestart then
    Exit('Binary LAMMPS restart file (write_restart).' + sLineBreak + sLineBreak +
      'Restart files are a binary snapshot whose layout depends on the LAMMPS' +
      sLineBreak +
      'build that wrote them, so their contents cannot be shown here.' +
      sLineBreak + sLineBreak +
      'To inspect this state, convert it to a text data file in LAMMPS:' +
      sLineBreak +
      '    read_restart <file>' + sLineBreak +
      '    write_data   <file>.data');

  SB := TStringBuilder.Create;
  try
    if FIsDumpFormat then
    begin
      SB.AppendLine(Format('Dump frame at timestep %d', [FTimestep]));
      if FFrameCount > 1 then
        SB.AppendLine(Format('(last of %d frames in file)', [FFrameCount]));
      if FDumpColumns <> '' then
        SB.AppendLine(Format('Columns: %s', [FDumpColumns]));
      SB.AppendLine('');
    end;

    SB.AppendLine(Format('Atoms: %d', [FAtomCount]));
    SB.AppendLine(Format('Atom types: %d', [FAtomTypeCount]));
    if FAtomStyle <> '' then
      SB.AppendLine(Format('Atom style: %s', [FAtomStyle]));
    if (FHeaderAtomCount > 0) and (FHeaderAtomCount <> FAtomCount) then
      SB.AppendLine(Format('WARNING: header declares %d atoms, parsed %d',
        [FHeaderAtomCount, FAtomCount]));
    SB.AppendLine('');

    XSize := FBox.XHi - FBox.XLo;
    YSize := FBox.YHi - FBox.YLo;
    ZSize := FBox.ZHi - FBox.ZLo;
    SB.AppendLine('Box bounds:');
    SB.AppendLine(Format('  X: %.2f .. %.2f', [FBox.XLo, FBox.XHi]));
    SB.AppendLine(Format('  Y: %.2f .. %.2f', [FBox.YLo, FBox.YHi]));
    SB.AppendLine(Format('  Z: %.2f .. %.2f', [FBox.ZLo, FBox.ZHi]));
    SB.AppendLine(Format('  Size: %.1f x %.1f x %.1f', [XSize, YSize, ZSize]));
    SB.AppendLine('');

    if Length(FMasses) > 0 then
    begin
      SB.AppendLine('Masses:');
      for I := 0 to High(FMasses) do
        SB.AppendLine(Format('  Type %d: %.1f', [FMasses[I].AtomType, FMasses[I].Mass]));
      SB.AppendLine('');
    end;

    if FHasVelocities then
      SB.AppendLine('Velocities: present');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TLAMMPSDumpFile.AtomTypeColor(AType: Integer): Integer;
begin
  if AType <= 0 then
    Result := ATOM_COLORS[0]
  else
    Result := ATOM_COLORS[(AType - 1) mod Length(ATOM_COLORS)];
end;

end.
