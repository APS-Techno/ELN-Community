unit unit_MitFileParser;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

const
  MIT_MAGIC = $11011972;
  MIT_STRIDE = 14;  // 14 Single-precision floats per data row

  COL_FORCE = 0;
  COL_DISPLACEMENT = 1;
  COL_TEMPERATURE = 7;
  COL_FORCESETPOINT = 12;
  COL_TIME = 13;

  // Typical penetration depth per unit force for Berkovich indentation
  // on medium-hard materials (nm per mN). Used as fallback when HcNm
  // is not stored in post-data (version <20 files).
  DEFAULT_DEPTH_PER_FORCE = 60;  // nm/mN, gives ~30 nm at 0.5 mN

type
  TMitDataRow = array[0..MIT_STRIDE - 1] of Single;

  TMitCurvePoint = record
    DepthNm: Double;
    ForceMN: Double;
  end;

  TMitRecord = record
    Description: string;
    IndenterType: string;
    Material: string;
    DataPointCount: Integer;
    DataPoints: TArray<TMitDataRow>;
    ContactRow: Integer;
    FrameCompliance: Double;
    Curve: TArray<TMitCurvePoint>;
    PeakIndex: Integer;

    HcNm: Double;
    FmaxRefN: Double;
    EstimatedDepth: Boolean;

    // BSpline area function calibration (from indenter section)
    AreaHc: TArray<Double>;  // Control point hc values (nm)
    AreaAp: TArray<Double>;  // Control point Ap values (nm^2)
    Beta: Double;            // Berkovich correction factor (1.034)

    FmaxMN: Double;
    HmaxNm: Double;
    HfNm: Double;       // Fitting depth in nm (hf from power law unloading fit)
    HrNm: Double;
    MExp: Double;        // Power law exponent m for unloading fit
    Epsilon: Double;    // Geometric factor epsilon
    H_GPa: Double;      // Hardness
    Er_GPa: Double;     // Reduced modulus
    S_mNnm: Double;     // Stiffness (dF/dh at hmax)
    A_nm2: Double;      // Projected contact area

    FitPhysical: Boolean;
    InstrumentValid: Boolean;
    HInstGPa: Double;
    EInstGPa: Double;
    SInstMNnm: Double;

    procedure CalcOliverPharr;
    procedure BuildCurve;
    function HasCurve: Boolean;
    function SampleCount: Integer;
    function ReducedModulusFromStiffness(SmNnm: Double): Double;
    function CalcArea(hcNm: Double): Double;
    function Time(Row: Integer): Single;
    function Temperature(Row: Integer): Single;
    function ForceSetpoint(Row: Integer): Single;
  end;

  TMitSource = (msComputed, msInstrument);

  TMitIndent = record
    Usable: Boolean;
    H_GPa: Double;
    E_GPa: Double;
    HasE: Boolean;
    Er_GPa: Double;
  end;

  TMitFile = class
  private
    FRecords: TList<TMitRecord>;
    FIndents: TArray<TMitIndent>;
    FSource: TMitSource;
    FFileName: string;
    FVersion: Byte;  // Format version from global header (byte 45); 0 = old format

    function ReadLenString(Stream: TStream): string;
    procedure ParseRecord(Stream: TStream; EndPos: Int64; out Rec: TMitRecord);
    function FindBytes(Stream: TStream; const Pattern: TBytes;
      MaxSearch: Integer): Int64;
    function FindDataBlock(Stream: TStream; EndPos: Int64;
      out Count: Integer): Boolean;
    function FindFrameCompliance(Stream: TStream; EndPos: Int64): Double;
    procedure ParsePostData(Stream: TStream; EndPos: Int64;
      var Rec: TMitRecord);
    procedure EstimateHmaxFromRawData(var Rec: TMitRecord);
    procedure Classify;
  public
    constructor Create;
    destructor Destroy; override;

    procedure ParseFromFile(const AFileName: string);
    procedure ParseFromStream(Stream: TStream);

    function RecordCount: Integer;
    function GetRecord(Index: Integer): TMitRecord;
    function Indent(Index: Integer): TMitIndent;
    function UsableCount: Integer;
    function ExcludedCount: Integer;

    property FileName: string read FFileName;
    property Version: Byte read FVersion;
    property Source: TMitSource read FSource;
  end;

implementation

uses
  System.Math;


function TMitRecord.CalcArea(hcNm: Double): Double;
var
  I, N: Integer;
  Frac: Double;
begin
  N := Length(AreaHc);
  if (N < 2) or (hcNm <= 0) then
  begin
    Result := 24.5 * hcNm * hcNm;
    Exit;
  end;

  if hcNm <= AreaHc[0] then
    Result := AreaAp[0]
  else if hcNm >= AreaHc[N - 1] then
    // Extrapolate using ideal Berkovich beyond calibration range
    Result := 24.5 * hcNm * hcNm
  else
  begin
    Result := 24.5 * hcNm * hcNm;
    for I := 0 to N - 2 do
      if (hcNm >= AreaHc[I]) and (hcNm <= AreaHc[I + 1]) then
      begin
        if (AreaHc[I + 1] - AreaHc[I]) > 0 then
        begin
          Frac := (hcNm - AreaHc[I]) / (AreaHc[I + 1] - AreaHc[I]);
          Result := AreaAp[I] + Frac * (AreaAp[I + 1] - AreaAp[I]);
        end
        else
          Result := AreaAp[I];
        Break;
      end;
  end;
end;

procedure TMitRecord.CalcOliverPharr;
begin
  FitPhysical := False;
  if FmaxRefN > 0 then
    FmaxMN := FmaxRefN * 1000
  else if DataPointCount > 0 then
    FmaxMN := ForceSetpoint(0) * 1000
  else
    FmaxMN := 0.5;

  if Beta <= 0 then
    Beta := 1.034;

  if (not EstimatedDepth) and (HmaxNm > 0) and (HcNm > 0) then
  begin
    if MExp <= 0 then
      MExp := 1.5;
    if Epsilon <= 0 then
      Epsilon := 0.75;

    FitPhysical := (HfNm > 0) and (HmaxNm > HfNm) and (MExp > 0.5) and (MExp < 15);
    if FitPhysical then
      S_mNnm := FmaxMN * MExp / (HmaxNm - HfNm)
    else
      S_mNnm := 0;

    A_nm2 := CalcArea(HcNm);

    if A_nm2 > 0 then
      H_GPa := (FmaxMN / A_nm2) * 1e6
    else
      H_GPa := 0;

    Er_GPa := ReducedModulusFromStiffness(S_mNnm);

    Exit;
  end;

  EstimatedDepth := True;
  if HcNm > 0 then
    HmaxNm := HcNm * 1.1  // hmax ~ 1.1 * hc for Berkovich
  else
    HmaxNm := 34;

  MExp := 1.5;
  Epsilon := 0.75;
  HfNm := HmaxNm * 0.7;
  HrNm := HfNm;

  A_nm2 := CalcArea(HcNm);

  if A_nm2 > 0 then
    H_GPa := (FmaxMN / A_nm2) * 1e6
  else
    H_GPa := 0;

  if (HmaxNm - HfNm) > 0 then
    S_mNnm := MExp * FmaxMN / (HmaxNm - HfNm)
  else
    S_mNnm := 0;

  if A_nm2 > 0 then
    Er_GPa := (Sqrt(Pi) / (2 * Beta)) * (S_mNnm / Sqrt(A_nm2)) * 1e6
  else
    Er_GPa := 0;
end;

function TMitRecord.ReducedModulusFromStiffness(SmNnm: Double): Double;
begin
  if (A_nm2 > 0) and (SmNnm > 0) then
    Result := (Sqrt(Pi) / (2 * Beta)) * (SmNnm / Sqrt(A_nm2)) * 1e6
  else
    Result := 0;
end;

procedure TMitRecord.BuildCurve;
var
  Trailer: Single;
  Index, I, N: Integer;
  Z0, F0, DF: Double;
  Point: TMitCurvePoint;
begin
  ContactRow := -1;
  Curve := nil;
  PeakIndex := -1;
  if DataPointCount < 2 then
    Exit;
  // The last row is not a sample: its time field holds the Int32 index of
  // the contact row, the zero of depth and force in the Anton Paar software.
  Trailer := DataPoints[DataPointCount - 1][COL_TIME];
  Move(Trailer, Index, SizeOf(Index));
  if (Index < 0) or (Index >= DataPointCount - 1) then
    Exit;
  Z0 := DataPoints[Index][COL_DISPLACEMENT];
  F0 := DataPoints[Index][COL_FORCE];
  N := DataPointCount - 1 - Index;
  SetLength(Curve, N);
  PeakIndex := 0;
  for I := 0 to N - 1 do
  begin
    DF := DataPoints[Index + I][COL_FORCE] - F0;
    Point.DepthNm := (DataPoints[Index + I][COL_DISPLACEMENT] - Z0 -
      FrameCompliance * DF) * 1e9;
    Point.ForceMN := DF * 1e3;
    if IsNan(Point.DepthNm) or IsInfinite(Point.DepthNm) or
       IsNan(Point.ForceMN) or IsInfinite(Point.ForceMN) then
    begin
      Curve := nil;
      PeakIndex := -1;
      Exit;
    end;
    Curve[I] := Point;
    if Point.ForceMN > Curve[PeakIndex].ForceMN then
      PeakIndex := I;
  end;
  ContactRow := Index;
end;

function TMitRecord.HasCurve: Boolean;
begin
  Result := Length(Curve) > 1;
end;

function TMitRecord.SampleCount: Integer;
begin
  Result := Max(DataPointCount - 1, 0);
end;

function TMitRecord.Time(Row: Integer): Single;
begin
  Result := DataPoints[Row][COL_TIME];
end;

function TMitRecord.Temperature(Row: Integer): Single;
begin
  Result := DataPoints[Row][COL_TEMPERATURE];
end;

function TMitRecord.ForceSetpoint(Row: Integer): Single;
begin
  Result := DataPoints[Row][COL_FORCESETPOINT];
end;


constructor TMitFile.Create;
begin
  inherited Create;
  FRecords := TList<TMitRecord>.Create;
end;

destructor TMitFile.Destroy;
begin
  FRecords.Free;
  inherited;
end;

function TMitFile.RecordCount: Integer;
begin
  Result := FRecords.Count;
end;

function TMitFile.GetRecord(Index: Integer): TMitRecord;
begin
  Result := FRecords[Index];
end;

function TMitFile.Indent(Index: Integer): TMitIndent;
begin
  Result := FIndents[Index];
end;

function TMitFile.UsableCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FIndents) do
    if FIndents[I].Usable then
      Inc(Result);
end;

function TMitFile.ExcludedCount: Integer;
begin
  Result := Length(FIndents) - UsableCount;
end;

procedure TMitFile.Classify;
var
  I, Measured: Integer;
  AllInstrument: Boolean;
  Rec: TMitRecord;
  Item: TMitIndent;
begin
  Measured := 0;
  AllInstrument := True;
  for I := 0 to FRecords.Count - 1 do
  begin
    Rec := FRecords[I];
    if Rec.EstimatedDepth then
      Continue;
    Inc(Measured);
    if not Rec.InstrumentValid then
      AllInstrument := False;
  end;
  if (Measured > 0) and AllInstrument then
    FSource := msInstrument
  else
    FSource := msComputed;

  SetLength(FIndents, FRecords.Count);
  for I := 0 to FRecords.Count - 1 do
  begin
    Rec := FRecords[I];
    Item := Default(TMitIndent);
    if (not Rec.EstimatedDepth) and (Rec.A_nm2 > 0) then
      if FSource = msInstrument then
      begin
        Item.Usable := True;
        Item.H_GPa := Rec.HInstGPa;
        Item.E_GPa := Rec.EInstGPa;
        Item.HasE := True;
        Item.Er_GPa := Rec.ReducedModulusFromStiffness(Rec.SInstMNnm);
      end
      else if Rec.FitPhysical and (Rec.H_GPa > 0) and (Rec.Er_GPa > 0) then
      begin
        Item.Usable := True;
        Item.H_GPa := Rec.H_GPa;
        Item.Er_GPa := Rec.Er_GPa;
      end;
    FIndents[I] := Item;
  end;
end;

function TMitFile.ReadLenString(Stream: TStream): string;
var
  Len: UInt32;
  Buf: TBytes;
begin
  Stream.ReadData(Len);
  if Len > 10000 then
    raise Exception.Create('Invalid string length in MIT file');
  SetLength(Buf, Len);
  if Len > 0 then
    Stream.ReadBuffer(Buf[0], Len);
  Result := TEncoding.ASCII.GetString(Buf);
end;

function TMitFile.FindBytes(Stream: TStream; const Pattern: TBytes;
  MaxSearch: Integer): Int64;
var
  Buf: TBytes;
  I, PatLen, BufLen: Integer;
  StartPos: Int64;
begin
  Result := -1;
  PatLen := Length(Pattern);
  if PatLen = 0 then
    Exit;

  BufLen := MaxSearch;
  StartPos := Stream.Position;
  SetLength(Buf, BufLen);
  BufLen := Stream.Read(Buf[0], BufLen);

  for I := 0 to BufLen - PatLen do
  begin
    if CompareMem(@Buf[I], @Pattern[0], PatLen) then
    begin
      Result := StartPos + I;
      Stream.Position := Result;
      Exit;
    end;
  end;

  Stream.Position := StartPos;
end;

function TMitFile.FindDataBlock(Stream: TStream; EndPos: Int64;
  out Count: Integer): Boolean;
var
  Buf: TBytes;
  BufLen, I: Integer;
  StartPos: Int64;
  Val: UInt32;
  FirstFloat, TimeFloat: Single;
begin
  Result := False;
  Count := 0;
  StartPos := Stream.Position;

  BufLen := Integer(EndPos - StartPos);
  if BufLen < 64 then
    Exit;

  SetLength(Buf, BufLen);
  BufLen := Stream.Read(Buf[0], BufLen);

  // Scan byte-by-byte for: uint32 count + 4 bytes + valid float data
  // Old MIT files have a float (time step) instead of zero after the count,
  // so we validate by checking that the data block fits and row content is valid.
  I := 0;
  while I <= BufLen - (8 + MIT_STRIDE * SizeOf(Single)) do
  begin
    Move(Buf[I], Val, 4);
    if (Val > 500) and (Val < 50000000) then
    begin
      if Int64(I) + 8 + Int64(Val) * MIT_STRIDE * SizeOf(Single) > BufLen then
      begin
        Inc(I);
        Continue;
      end;

      Move(Buf[I + 8], FirstFloat, 4);
      if (Abs(FirstFloat) < 1.0) and (Abs(FirstFloat) > 0) then
      begin
        Move(Buf[I + 8 + COL_TIME * 4], TimeFloat, 4);
        if (TimeFloat > 0.01) and (TimeFloat < 1.0) then
        begin
          Count := Val;
          Stream.Position := StartPos + I + 8;
          Result := True;
          Exit;
        end;
      end;
    end;
    Inc(I);
  end;

  Stream.Position := StartPos;
end;

function TMitFile.FindFrameCompliance(Stream: TStream; EndPos: Int64): Double;
var
  Buf: TBytes;
  StartPos: Int64;
  BufLen, I, J, Len, Dots, Tail: Integer;
  Valid: Boolean;
  Value: Single;
begin
  // Software 7.x and later store, after a length-prefixed version string
  // such as "9.0.19": one byte, an enabled flag byte, the frame compliance
  // (Single, m/N) and the UInt32 5. Older files have no such section.
  Result := 0;
  StartPos := Stream.Position;
  BufLen := Integer(Min(EndPos - StartPos, Int64(MaxInt)));
  if BufLen < 32 then
    Exit;
  SetLength(Buf, BufLen);
  BufLen := Stream.Read(Buf[0], BufLen);
  Stream.Position := StartPos;
  for I := 0 to BufLen - 4 do
  begin
    Len := PInteger(@Buf[I])^;
    if (Len < 5) or (Len > 11) or (I + 4 + Len + 10 > BufLen) then
      Continue;
    Dots := 0;
    Valid := CharInSet(Char(Buf[I + 4]), ['0'..'9']) and
      CharInSet(Char(Buf[I + 3 + Len]), ['0'..'9']);
    for J := I + 4 to I + 3 + Len do
      if Buf[J] = Ord('.') then
        Inc(Dots)
      else if not CharInSet(Char(Buf[J]), ['0'..'9']) then
        Valid := False;
    J := I + 4 + Len;
    Tail := PInteger(@Buf[J + 6])^;
    if not Valid or (Dots <> 2) or (Buf[J + 1] > 1) or (Tail <> 5) then
      Continue;
    Value := PSingle(@Buf[J + 2])^;
    if (Buf[J + 1] = 1) and not IsNan(Value) and not IsInfinite(Value) and
       (Value > 0) and (Value < 1e-5) then
      Result := Value;
    Exit;
  end;
end;

procedure TMitFile.ParseRecord(Stream: TStream; EndPos: Int64;
  out Rec: TMitRecord);
var
  Zero4: UInt32;
  PatternBytes: TBytes;
  FoundPos: Int64;
  I: Integer;
  MaxSearch: Int64;
  BetaSingle, PoissonSingle, YoungsSingle: Single;
  BSplineCount: UInt32;
  HcSingle, ApSingle: Single;
  CalibID: string;
begin
  Rec := Default(TMitRecord);
  // Skip 4 zero bytes after class name
  Stream.ReadData(Zero4);

  Rec.Description := ReadLenString(Stream);

  PatternBytes := TEncoding.ASCII.GetBytes('TIndentor');
  MaxSearch := EndPos - Stream.Position;
  if MaxSearch > MaxInt then
    MaxSearch := MaxInt;
  // Sinus records keep a cycle table before the indenter section, so the
  // indenter can lie far past the description and the data block follows it.
  FoundPos := FindBytes(Stream, PatternBytes, Integer(MaxSearch));

  Rec.Beta := 0;

  if FoundPos >= 0 then
  begin
    // Back up 4 bytes to read the uint32 length prefix
    Stream.Position := FoundPos - 4;
    Rec.IndenterType := ReadLenString(Stream);
    Rec.Material := ReadLenString(Stream);

    // Format: CalibID string, Beta(Single), Poisson(Single), Young's(Single),
    //         Zero(uint32), Count(uint32), Count pairs of Singles (hc_m, Ap_m2)
    try
      CalibID := ReadLenString(Stream);
      Stream.ReadBuffer(BetaSingle, SizeOf(Single));
      Stream.ReadBuffer(PoissonSingle, SizeOf(Single));
      Stream.ReadBuffer(YoungsSingle, SizeOf(Single));
      Stream.ReadData(Zero4);  // padding
      Stream.ReadData(BSplineCount);

      if (BetaSingle > 0.5) and (BetaSingle < 2.0) and
         (BSplineCount > 0) and (BSplineCount < 100) and
         (Stream.Position + BSplineCount * 8 <= EndPos) then
      begin
        Rec.Beta := BetaSingle;
        SetLength(Rec.AreaHc, BSplineCount);
        SetLength(Rec.AreaAp, BSplineCount);
        for I := 0 to Integer(BSplineCount) - 1 do
        begin
          Stream.ReadBuffer(HcSingle, SizeOf(Single));
          Stream.ReadBuffer(ApSingle, SizeOf(Single));
          Rec.AreaHc[I] := HcSingle * 1e9;   // meters -> nm
          Rec.AreaAp[I] := ApSingle * 1e18;   // m^2 -> nm^2
        end;
      end;
    except
      // Calibration section missing or malformed — continue without it
    end;
  end
  else
  begin
    Rec.IndenterType := '';
    Rec.Material := '';
  end;

  Rec.HcNm := 0;
  Rec.FmaxRefN := 0;

  if FindDataBlock(Stream, EndPos, Rec.DataPointCount) then
  begin
    SetLength(Rec.DataPoints, Rec.DataPointCount);
    for I := 0 to Rec.DataPointCount - 1 do
      Stream.ReadBuffer(Rec.DataPoints[I], SizeOf(TMitDataRow));
    Rec.FrameCompliance := FindFrameCompliance(Stream, EndPos);
    Rec.BuildCurve;

    //   New format (v>0): per-record Singles at +364..+400 (Fmax,hmax,hc,hr,hf,eps,m)
    //   Old format (v=0): Single FmaxRefN at +36, Double HcNm at +636
    ParsePostData(Stream, EndPos, Rec);
  end
  else
  begin
    Rec.DataPointCount := 0;
    SetLength(Rec.DataPoints, 0);
    Rec.BuildCurve;
  end;

  Rec.CalcOliverPharr;
end;

procedure TMitFile.ParsePostData(Stream: TStream; EndPos: Int64;
  var Rec: TMitRecord);
var
  PostBase: Int64;
  FmaxSingle: Single;
  FmaxN, HmaxM, HcM, HrM, HfM, EpsSingle, MExpSingle: Single;
  HInst, EInst, SInst: Single;
begin
  PostBase := Stream.Position;
  Rec.HcNm := 0;
  Rec.FmaxRefN := 0;
  Rec.EstimatedDepth := False;
  Rec.HmaxNm := 0;
  Rec.HfNm := 0;
  Rec.HrNm := 0;
  Rec.MExp := 0;
  Rec.Epsilon := 0;
  Rec.InstrumentValid := False;
  Rec.HInstGPa := 0;
  Rec.EInstGPa := 0;
  Rec.SInstMNnm := 0;

  if FVersion > 0 then
  begin
    // Per-record results stored as Singles at fixed offsets from post-data
    // start, in SI units (Pa, N, m, N/m).
    if PostBase + 408 <= EndPos then
    begin
      Stream.Position := PostBase + 352;
      Stream.ReadBuffer(HInst, SizeOf(Single));

      Stream.Position := PostBase + 360;
      Stream.ReadBuffer(EInst, SizeOf(Single));

      Stream.Position := PostBase + 364;
      Stream.ReadBuffer(FmaxN, SizeOf(Single));

      Stream.Position := PostBase + 368;
      Stream.ReadBuffer(HmaxM, SizeOf(Single));

      Stream.Position := PostBase + 376;
      Stream.ReadBuffer(SInst, SizeOf(Single));

      Stream.Position := PostBase + 380;
      Stream.ReadBuffer(HcM, SizeOf(Single));

      Stream.Position := PostBase + 384;
      Stream.ReadBuffer(HrM, SizeOf(Single));

      Stream.Position := PostBase + 388;
      Stream.ReadBuffer(HfM, SizeOf(Single));

      Stream.Position := PostBase + 392;
      Stream.ReadBuffer(EpsSingle, SizeOf(Single));

      Stream.Position := PostBase + 400;
      Stream.ReadBuffer(MExpSingle, SizeOf(Single));

      if (FmaxN > 1e-6) and (FmaxN < 0.1) and
         (HmaxM > 1e-9) and (HmaxM < 1e-5) and
         (HcM > 0) and (HcM <= HmaxM) and
         (MExpSingle > 0.5) and (MExpSingle < 15) then
      begin
        Rec.FmaxRefN := FmaxN;
        Rec.HmaxNm := HmaxM * 1e9;
        Rec.HcNm := HcM * 1e9;
        Rec.HrNm := HrM * 1e9;
        Rec.HfNm := HfM * 1e9;
        Rec.Epsilon := EpsSingle;
        Rec.MExp := MExpSingle;
        if (not IsNan(HInst)) and (not IsInfinite(HInst)) and (HInst > 0) and
           (not IsNan(EInst)) and (not IsInfinite(EInst)) and (EInst > 0) and
           (not IsNan(SInst)) and (not IsInfinite(SInst)) and (SInst > 0) then
        begin
          Rec.InstrumentValid := True;
          Rec.HInstGPa := HInst * 1e-9;
          Rec.EInstGPa := EInst * 1e-9;
          Rec.SInstMNnm := SInst * 1e-6;
        end;
        Exit;
      end;
    end;

    EstimateHmaxFromRawData(Rec);
    Exit;
  end;

  // Old format (60-byte header): Single FmaxRefN at +36, Double HcNm at +636
  if PostBase + 40 <= EndPos then
  begin
    Stream.Position := PostBase + 36;
    Stream.ReadBuffer(FmaxSingle, SizeOf(Single));
    if (FmaxSingle >= 1e-6) and (FmaxSingle <= 1) then
      Rec.FmaxRefN := FmaxSingle;
  end;

  if PostBase + 644 <= EndPos then
  begin
    Stream.Position := PostBase + 636;
    Stream.ReadBuffer(Rec.HcNm, SizeOf(Double));
    if (Rec.HcNm < 1) or (Rec.HcNm > 10000) then
      Rec.HcNm := 0;
  end;

  if Rec.HcNm = 0 then
    EstimateHmaxFromRawData(Rec);
end;

procedure TMitFile.EstimateHmaxFromRawData(var Rec: TMitRecord);
var
  FmaxMN, HmaxNm: Double;
begin
  // Estimate hmax from force using a typical depth-per-force ratio.
  // Approximate; exact values require Anton Paar software.
  if Rec.FmaxRefN > 0 then
    FmaxMN := Rec.FmaxRefN * 1000
  else if (Rec.DataPointCount > 0) then
    FmaxMN := Rec.DataPoints[0][COL_FORCESETPOINT] * 1000
  else
    FmaxMN := 0.5;

  HmaxNm := FmaxMN * DEFAULT_DEPTH_PER_FORCE;
  Rec.HcNm := HmaxNm / 1.1;
  Rec.HmaxNm := 0;
  Rec.MExp := 0;
  Rec.Epsilon := 0;
  Rec.EstimatedDepth := True;

  if Rec.FmaxRefN <= 0 then
    Rec.FmaxRefN := FmaxMN / 1000;
end;

procedure TMitFile.ParseFromFile(const AFileName: string);
var
  FS: TFileStream;
begin
  FFileName := AFileName;
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    ParseFromStream(FS);
  finally
    FS.Free;
  end;
end;

procedure TMitFile.ParseFromStream(Stream: TStream);
const
  RecordClasses: array[0..2] of string = ('TSimpleIndentation',
    'TStandardIndentation', 'TSinusIndentation');
var
  Magic: UInt32;
  FileType: string;
  Buf, Marker: TBytes;
  MarkerPositions: TList<Int64>;
  EndPos: Int64;
  I, BufLen: Integer;
  RecordClass: string;
  Rec: TMitRecord;
  VersionByte: Byte;
begin
  FRecords.Clear;
  FIndents := nil;
  FSource := msComputed;
  FVersion := 0;

  Stream.ReadData(Magic);
  if Magic <> MIT_MAGIC then
    raise Exception.CreateFmt('Invalid MIT file: bad magic 0x%x (expected 0x%x)',
      [Magic, MIT_MAGIC]);

  FileType := ReadLenString(Stream);

  // Read format version from global header byte 45 (new format only).
  // Old format has 60-byte header, new format has 93 bytes.
  // Byte 45 = version: 20 (0x14) stores HcNm in post-data,
  // versions 18-19 do not.
  if Stream.Size > 45 then
  begin
    Stream.Position := 45;
    Stream.ReadBuffer(VersionByte, 1);
    FVersion := VersionByte;
  end;

  MarkerPositions := TList<Int64>.Create;
  try
    BufLen := Integer(Min(Stream.Size, Int64(MaxInt)));
    SetLength(Buf, BufLen);
    Stream.Position := 0;
    BufLen := Stream.Read(Buf[0], BufLen);
    for RecordClass in RecordClasses do
    begin
      Marker := TEncoding.ASCII.GetBytes(RecordClass);
      for I := 4 to BufLen - Length(Marker) do
        if (PInteger(@Buf[I - 4])^ = Length(Marker)) and
           CompareMem(@Buf[I], @Marker[0], Length(Marker)) then
          MarkerPositions.Add(I - 4);
    end;
    Buf := nil;
    MarkerPositions.Sort;

    for I := 0 to MarkerPositions.Count - 1 do
    begin
      Stream.Position := MarkerPositions[I];
      // Skip the uint32 length prefix + class name string
      ReadLenString(Stream);

      if I < MarkerPositions.Count - 1 then
        EndPos := MarkerPositions[I + 1]
      else
        EndPos := Stream.Size;

      ParseRecord(Stream, EndPos, Rec);
      FRecords.Add(Rec);
    end;
    Classify;
  finally
    MarkerPositions.Free;
  end;
end;

end.
