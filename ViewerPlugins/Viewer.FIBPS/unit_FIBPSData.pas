unit unit_FIBPSData;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math, System.Generics.Collections;

type
  TFIBPSRecipe = record
    BackscanMicrons: string;
    ScanLengthMicrons: string;
    ScanSpeedPct: string;
    ScanAverages: string;
    ObjectiveType: string;
    AnalysisMethod: string;
    MeasPurpose: string;
    AuthorName: string;
    function TryGetMagnification(out Value: Double): Boolean;
  end;
  TFIBPSStepResult = record
    RectA: TRect;
    RectB: TRect;
    MeanA: Double;
    MeanB: Double;
    CountA: Integer;
    CountB: Integer;
    PlaneA: Double;
    PlaneB: Double;
    PlaneC: Double;
    StepHeight: Double;
    StepHeightStd: Double;
    LowConfidence: Boolean;
  end;

  TFIBPSWearResult = record
    Edge1Start: TPoint;
    Edge1End: TPoint;
    Edge2Start: TPoint;
    Edge2End: TPoint;
    PlaneA: Double;
    PlaneB: Double;
    PlaneC: Double;
    SpikeLimit: Double;
    WearArea: Double;
    WearAreaStd: Double;
    RowCount: Integer;
    Edge1X: Double;
    Edge2X: Double;
    ProfileX: TArray<Double>;
    ProfileMean: TArray<Double>;
    ProfileStd: TArray<Double>;
    ProfileMeasured: TArray<Integer>;
  end;

  TFIBPSStepOutcome = (fsoNone, fsoLowConfidence, fsoNoStepFound);

  TFIBPSData = class
  private
    FFileName: string;
    FRecipe: TFIBPSRecipe;
    procedure ParseRecipeXml(const XmlStr: string);
  public
    PixW, PixH: Cardinal;
    PhysW, PhysH: Single;
    MinH, MaxH: Single;
    Heights: array of Single;  // row-major float32

    procedure ParseFromFile(const AFileName: string);
    function HeightAt(X, Y: Integer): Single;
    function PhysXAt(X: Integer): Single;
    function PhysYAt(Y: Integer): Single;
    function TryCalcWearTrackEx(out Res: TFIBPSWearResult): Boolean;
    function TryCalcWearTrack(out WearArea, WearAreaStd: Double): Boolean;
    function TryCalcStepHeightEx(out Res: TFIBPSStepResult): Boolean;
    function TryCalcStepHeight(out StepHeight, StepHeightStd: Double): Boolean;
    function CalcStepFromRects(const ARectA, ARectB: TRect; out Res: TFIBPSStepResult): Boolean;
    function CalcGlobalPlane(out PlaneA, PlaneB, PlaneC: Double): Boolean;
    property FileName: string read FFileName;
    property Recipe: TFIBPSRecipe read FRecipe;
  end;

function FIBPSStepOutcome(StepExtracted, StepAvailable, Automatic, LowConfidence,
  HasWear, Loaded: Boolean): TFIBPSStepOutcome;

implementation

function FIBPSStepOutcome(StepExtracted, StepAvailable, Automatic, LowConfidence,
  HasWear, Loaded: Boolean): TFIBPSStepOutcome;
begin
  Result := fsoNone;
  if StepExtracted then
  begin
    if Automatic and LowConfidence then
      Result := fsoLowConfidence;
  end
  else if Loaded and Automatic and not StepAvailable and not HasWear then
    Result := fsoNoStepFound;
end;

function TFIBPSRecipe.TryGetMagnification(out Value: Double): Boolean;
const
  Magnifications: array[0..6] of Double = (1, 2.5, 5, 10, 20, 50, 100);
var
  Code: Integer;
begin
  Result := TryStrToInt(ObjectiveType, Code) and
    (Code >= Low(Magnifications)) and (Code <= High(Magnifications));
  if Result then
    Value := Magnifications[Code]
  else
    Value := 0;
end;

procedure TFIBPSData.ParseRecipeXml(const XmlStr: string);

  function GetTag(const Tag: string): string;
  var
    P1, P2: Integer;
    OpenTag, CloseTag: string;
  begin
    Result := '';
    OpenTag := '<' + Tag + '>';
    CloseTag := '</' + Tag + '>';
    P1 := Pos(OpenTag, XmlStr);
    if P1 = 0 then Exit;
    P1 := P1 + Length(OpenTag);
    P2 := Pos(CloseTag, XmlStr);
    if P2 > P1 then
      Result := Trim(Copy(XmlStr, P1, P2 - P1));
  end;

begin
  FRecipe := Default(TFIBPSRecipe);
  FRecipe.BackscanMicrons := GetTag('BackscanMicrons');
  FRecipe.ScanLengthMicrons := GetTag('ScanLengthMicrons');
  FRecipe.ScanSpeedPct := GetTag('UserSpecifiedScanSpeedPercentage');
  FRecipe.ScanAverages := GetTag('ScanAverages');
  FRecipe.ObjectiveType := GetTag('ObjectiveType');
  FRecipe.AnalysisMethod := GetTag('VSIAnalysisMethod');
  FRecipe.MeasPurpose := GetTag('MeasPurpose');
  FRecipe.AuthorName := GetTag('AuthorName');
end;

procedure TFIBPSData.ParseFromFile(const AFileName: string);
var
  FS: TFileStream;
  Data: TBytes;
  XmlEndTag: AnsiString;
  XmlEndPos, SearchStart, GuidStart, GuidEnd, Off, AfterH, I: Integer;
  XmlStart: Integer;
  OpInfoEndPos: UInt64;
  Val, PixelSizeUm: Single;
begin
  FFileName := AFileName;

  PixW := 0;
  PixH := 0;
  PhysW := 0;
  PhysH := 0;
  MinH := 0;
  MaxH := 0;
  SetLength(Heights, 0);
  FRecipe := Default(TFIBPSRecipe);

  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    // FIBPS files are XML-wrapped recipe data — a few MB at most in practice.
    // Cap well above that so a malformed file cannot exhaust process memory
    // before any structural validation runs.
    if FS.Size > 512 * 1024 * 1024 then
      raise Exception.CreateFmt(
        'FIBPS file too large (%.1f MB); refusing to load.',
        [FS.Size / (1024 * 1024)]);
    SetLength(Data, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Data[0], FS.Size);
  finally
    FS.Free;
  end;

  XmlEndTag := '</PFRecipes>';
  XmlEndPos := -1;
  for I := 0 to Length(Data) - Length(XmlEndTag) do
  begin
    if CompareMem(@Data[I], @XmlEndTag[1], Length(XmlEndTag)) then
    begin
      XmlEndPos := I + Length(XmlEndTag);
      Break;
    end;
  end;

  if XmlEndPos < 0 then
    raise Exception.Create('Invalid FIBPS file: XML recipe block not found');

  // Extract and parse XML recipe metadata — search for '<?xml' to skip binary header
  XmlStart := -1;
  for I := 0 to XmlEndPos - 6 do
    if (Data[I] = Ord('<')) and (Data[I+1] = Ord('?')) and
       (Data[I+2] = Ord('x')) and (Data[I+3] = Ord('m')) and
       (Data[I+4] = Ord('l')) then
    begin
      XmlStart := I;
      Break;
    end;
  if XmlStart < 0 then
    XmlStart := 0;
  ParseRecipeXml(TEncoding.UTF8.GetString(Data, XmlStart, XmlEndPos - XmlStart));

  GuidStart := -1;
  GuidEnd := -1;
  SearchStart := XmlEndPos;
  for I := SearchStart to Min(SearchStart + 300, Length(Data) - 37) do
  begin
    if (Data[I] = $24) and
       (I + 37 <= Length(Data)) and
       (Data[I + 9] = Ord('-')) and
       (Data[I + 14] = Ord('-')) and
       (Data[I + 19] = Ord('-')) and
       (Data[I + 24] = Ord('-')) then
    begin
      GuidStart := I + 1;
      GuidEnd := GuidStart + 36;
      Break;
    end;
  end;

  if GuidStart < 0 then
    raise Exception.Create('Invalid FIBPS file: GUID marker not found');

  Off := GuidEnd;
  Move(Data[Off + 8], PixW, 4);
  Move(Data[Off + 12], PixH, 4);

  if (PixW = 0) or (PixH = 0) or (PixW > 10000) or (PixH > 10000) then
    raise Exception.CreateFmt('Invalid FIBPS dimensions: %d x %d', [PixW, PixH]);

  Off := Off + 17; // skip 16 bytes (dims) + 1 byte separator

  // Read height data (layer 0)
  SetLength(Heights, PixW * PixH);
  if Off + Integer(PixW * PixH * 4) > Length(Data) then
    raise Exception.Create('Invalid FIBPS file: insufficient height data');

  Move(Data[Off], Heights[0], PixW * PixH * 4);


  AfterH := Off + Integer(PixW * PixH * 4);
  if AfterH + 32 <= Length(Data) then
  begin
    Move(Data[AfterH + 12], OpInfoEndPos, SizeOf(OpInfoEndPos));
    if (OpInfoEndPos >= UInt64(AfterH + 20)) and
       (OpInfoEndPos <= UInt64(Length(Data) - 4)) then
      Move(Data[Integer(OpInfoEndPos)], PixelSizeUm, 4)
    else
      Move(Data[AfterH + 28], PixelSizeUm, 4);
    if (not IsNan(PixelSizeUm)) and (PixelSizeUm > 0) and (PixelSizeUm < 1000) then
    begin
      if PixW > 1 then
        PhysW := (PixW - 1) * PixelSizeUm
      else
        PhysW := 0;
      if PixH > 1 then
        PhysH := (PixH - 1) * PixelSizeUm
      else
        PhysH := 0;
    end;
  end;
  MinH := MaxSingle;
  MaxH := -MaxSingle;
  for I := 0 to Length(Heights) - 1 do
  begin
    Val := Heights[I];
    if not IsNan(Val) then
    begin
      if Val < MinH then MinH := Val;
      if Val > MaxH then MaxH := Val;
    end;
  end;
end;

function TFIBPSData.HeightAt(X, Y: Integer): Single;
begin
  if (X >= 0) and (X < Integer(PixW)) and (Y >= 0) and (Y < Integer(PixH)) then
    Result := Heights[Y * Integer(PixW) + X]
  else
    Result := NaN;
end;

function TFIBPSData.PhysXAt(X: Integer): Single;
begin
  if PixW > 1 then
    Result := PhysW * X / (PixW - 1)
  else
    Result := 0;
end;

function TFIBPSData.PhysYAt(Y: Integer): Single;
begin
  if PixH > 1 then
    Result := PhysH * Y / (PixH - 1)
  else
    Result := 0;
end;

function MedianOfSlice(const Values: TArray<Double>; Count: Integer): Double;
var
  CopyArr: TArray<Double>;
  I: Integer;
begin
  if Count <= 0 then
    Exit(0.0);
  SetLength(CopyArr, Count);
  for I := 0 to Count - 1 do
    CopyArr[I] := Values[I];
  TArray.Sort<Double>(CopyArr);
  if Odd(Count) then
    Result := CopyArr[Count div 2]
  else
    Result := 0.5 * (CopyArr[(Count div 2) - 1] + CopyArr[Count div 2]);
end;

procedure FitPlane3x3(SumX, SumY, SumZ, SumXX, SumXY, SumYY, SumXZ, SumYZ: Double;
  N: Integer; out A, B, C: Double);
var
  M00, M01, M02, M11, M12, M22: Double;
  C00, C01, C02, C11, C12, C22, Det: Double;
begin
  if N < 3 then
  begin
    A := 0;
    B := 0;
    if N > 0 then
      C := SumZ / N
    else
      C := 0;
    Exit;
  end;
  M00 := SumXX;
  M01 := SumXY;
  M02 := SumX;
  M11 := SumYY;
  M12 := SumY;
  M22 := N;
  C00 := M11 * M22 - M12 * M12;
  C01 := -(M01 * M22 - M12 * M02);
  C02 := M01 * M12 - M11 * M02;
  C11 := M00 * M22 - M02 * M02;
  C12 := -(M00 * M12 - M01 * M02);
  C22 := M00 * M11 - M01 * M01;
  Det := M00 * C00 + M01 * C01 + M02 * C02;
  if Abs(Det) < 1E-12 then
  begin
    A := 0;
    B := 0;
    C := SumZ / N;
    Exit;
  end;
  A := (C00 * SumXZ + C01 * SumYZ + C02 * SumZ) / Det;
  B := (C01 * SumXZ + C11 * SumYZ + C12 * SumZ) / Det;
  C := (C02 * SumXZ + C12 * SumYZ + C22 * SumZ) / Det;
end;

procedure FitLine2x2(const Xs, Ys: TArray<Double>; Count: Integer; out M, B: Double);
var
  I: Integer;
  SX, SY, SXX, SXY, Denom: Double;
begin
  if Count <= 0 then
  begin
    M := 0;
    B := 0;
    Exit;
  end;
  SX := 0;
  SY := 0;
  SXX := 0;
  SXY := 0;
  for I := 0 to Count - 1 do
  begin
    SX := SX + Xs[I];
    SY := SY + Ys[I];
    SXX := SXX + Xs[I] * Xs[I];
    SXY := SXY + Xs[I] * Ys[I];
  end;
  Denom := Count * SXX - SX * SX;
  if Abs(Denom) < 1E-12 then
  begin
    M := 0;
    B := SY / Count;
  end
  else
  begin
    M := (Count * SXY - SX * SY) / Denom;
    B := (SY - M * SX) / Count;
  end;
end;

procedure InterpolateRowNaNs(var Row: TArray<Double>; W: Integer);
var
  FirstValid, LastValid, Prev, Next, X, K: Integer;
begin
  FirstValid := -1;
  LastValid := -1;
  for X := 0 to W - 1 do
    if not IsNan(Row[X]) then
    begin
      if FirstValid < 0 then
        FirstValid := X;
      LastValid := X;
    end;
  if (FirstValid < 0) or (FirstValid = LastValid) then
    Exit;
  for X := 0 to FirstValid - 1 do
    Row[X] := Row[FirstValid];
  for X := LastValid + 1 to W - 1 do
    Row[X] := Row[LastValid];
  Prev := FirstValid;
  X := FirstValid + 1;
  while X <= LastValid do
  begin
    if IsNan(Row[X]) then
    begin
      Next := X + 1;
      while (Next <= LastValid) and IsNan(Row[Next]) do
        Inc(Next);
      for K := Prev + 1 to Next - 1 do
        Row[K] := Row[Prev] + (Row[Next] - Row[Prev]) * (K - Prev) / (Next - Prev);
      Prev := Next;
      X := Next + 1;
    end
    else
    begin
      Prev := X;
      Inc(X);
    end;
  end;
end;

function TFIBPSData.TryCalcWearTrackEx(out Res: TFIBPSWearResult): Boolean;
var
  W, H, ValidTotal, I, Orient, GW, GH, EdgeW, R, X, K: Integer;
  LeftCnt, RightCnt, InCnt, ResCnt, ColCnt, ValidRows, AreaCnt: Integer;
  RX, RY, XLo, XHi, MinW, FirstX, LastX, PadU, XS, XE, Cnt, KeptRows, MCnt: Integer;
  PxX, PxY, DX, Z, A, B, C, AU, BU, CU: Double;
  SX, SY, SZ, SXX, SXY, SYY, SXZ, SYZ: Double;
  MedR, MadR, MeanRes, SumSq, Sigma, Spk, MinDip, MaxBump, ThrG: Double;
  RowSum, MeanA, StdA, BestDip, Med1, Med2, Tol1, Tol2, ColMean: Double;
  M1, B1, M2, B2, MLeft, BLeft, MRight, BRight, X1Lim, X2Lim: Double;
  ResBuf, ColBuf, ColMed, BandX, BandY, VR, VX1, VX2, Areas, Dev: TArray<Double>;
  KR, K1, K2: TArray<Double>;
  Clean, Tmp, Sm: TArray<TArray<Double>>;

  function SurfVal(RowIdx, ColIdx: Integer): Single;
  begin
    if Orient = 0 then
      Result := Heights[RowIdx * W + ColIdx]
    else
      Result := Heights[ColIdx * W + RowIdx];
  end;

begin
  Res := Default(TFIBPSWearResult);
  Result := False;
  W := Integer(PixW);
  H := Integer(PixH);
  if (W < 16) or (H < 16) or (PhysW <= 0) or (PhysH <= 0) then
    Exit;
  ValidTotal := 0;
  for I := 0 to Length(Heights) - 1 do
    if not IsNan(Heights[I]) then
      Inc(ValidTotal);
  if ValidTotal * 2 < W * H then
    Exit;

  PxX := PhysW / (W - 1);
  PxY := PhysH / (H - 1);
  BestDip := -1;

  for Orient := 0 to 1 do
  begin
    if Orient = 0 then
    begin
      GW := W;
      GH := H;
      DX := PxX;
    end
    else
    begin
      GW := H;
      GH := W;
      DX := PxY;
    end;

    EdgeW := Max(4, Trunc(0.20 * GW));
    LeftCnt := 0;
    RightCnt := 0;
    SX := 0; SY := 0; SZ := 0; SXX := 0; SXY := 0; SYY := 0; SXZ := 0; SYZ := 0;
    for R := 0 to GH - 1 do
      for X := 0 to GW - 1 do
        if (X < EdgeW) or (X >= GW - EdgeW) then
        begin
          Z := SurfVal(R, X);
          if not IsNan(Z) then
          begin
            if X < EdgeW then
              Inc(LeftCnt)
            else
              Inc(RightCnt);
            SX := SX + X;
            SY := SY + R;
            SZ := SZ + Z;
            SXX := SXX + Double(X) * X;
            SXY := SXY + Double(X) * R;
            SYY := SYY + Double(R) * R;
            SXZ := SXZ + X * Z;
            SYZ := SYZ + R * Z;
          end;
        end;
    if (LeftCnt < 20) or (RightCnt < 20) then
      Continue;

    FitPlane3x3(SX, SY, SZ, SXX, SXY, SYY, SXZ, SYZ, LeftCnt + RightCnt, A, B, C);
    SetLength(ResBuf, LeftCnt + RightCnt);
    ResCnt := 0;
    for R := 0 to GH - 1 do
      for X := 0 to GW - 1 do
        if (X < EdgeW) or (X >= GW - EdgeW) then
        begin
          Z := SurfVal(R, X);
          if not IsNan(Z) then
          begin
            ResBuf[ResCnt] := Z - (A * X + B * R + C);
            Inc(ResCnt);
          end;
        end;
    MedR := MedianOfSlice(ResBuf, ResCnt);
    for I := 0 to ResCnt - 1 do
      ResBuf[I] := Abs(ResBuf[I] - MedR);
    MadR := MedianOfSlice(ResBuf, ResCnt) + 1E-6;

    InCnt := 0;
    SX := 0; SY := 0; SZ := 0; SXX := 0; SXY := 0; SYY := 0; SXZ := 0; SYZ := 0;
    for R := 0 to GH - 1 do
      for X := 0 to GW - 1 do
        if (X < EdgeW) or (X >= GW - EdgeW) then
        begin
          Z := SurfVal(R, X);
          if (not IsNan(Z)) and (Abs(Z - (A * X + B * R + C) - MedR) < 4.0 * MadR) then
          begin
            Inc(InCnt);
            SX := SX + X;
            SY := SY + R;
            SZ := SZ + Z;
            SXX := SXX + Double(X) * X;
            SXY := SXY + Double(X) * R;
            SYY := SYY + Double(R) * R;
            SXZ := SXZ + X * Z;
            SYZ := SYZ + R * Z;
          end;
        end;
    if InCnt < 40 then
      Continue;

    FitPlane3x3(SX, SY, SZ, SXX, SXY, SYY, SXZ, SYZ, InCnt, A, B, C);
    MeanRes := 0;
    ResCnt := 0;
    for R := 0 to GH - 1 do
      for X := 0 to GW - 1 do
        if (X < EdgeW) or (X >= GW - EdgeW) then
        begin
          Z := SurfVal(R, X);
          if (not IsNan(Z)) and (Abs(Z - (A * X + B * R + C) - MedR) < 4.0 * MadR) then
          begin
            ResBuf[ResCnt] := Z - (A * X + B * R + C);
            MeanRes := MeanRes + ResBuf[ResCnt];
            Inc(ResCnt);
          end;
        end;
    MeanRes := MeanRes / ResCnt;
    SumSq := 0;
    for I := 0 to ResCnt - 1 do
      SumSq := SumSq + Sqr(ResBuf[I] - MeanRes);
    Sigma := Sqrt(SumSq / ResCnt);
    if Sigma < 1E-5 then
      Sigma := 1E-4;
    Spk := Max(12.0 * Sigma, 0.25);

    SetLength(Clean, GH, GW);
    for R := 0 to GH - 1 do
    begin
      for X := 0 to GW - 1 do
      begin
        Z := SurfVal(R, X);
        if IsNan(Z) then
          Clean[R][X] := NaN
        else
        begin
          Z := Z - (A * X + B * R + C);
          if Z > Spk then
            Clean[R][X] := NaN
          else
            Clean[R][X] := Z;
        end;
      end;
      InterpolateRowNaNs(Clean[R], GW);
    end;

    SetLength(ColMed, GW);
    SetLength(ColBuf, GH);
    for X := 0 to GW - 1 do
    begin
      ColCnt := 0;
      for R := 0 to GH - 1 do
        if not IsNan(Clean[R][X]) then
        begin
          ColBuf[ColCnt] := Clean[R][X];
          Inc(ColCnt);
        end;
      if ColCnt > 0 then
        ColMed[X] := MedianOfSlice(ColBuf, ColCnt)
      else
        ColMed[X] := NaN;
    end;

    MinDip := MaxDouble;
    MaxBump := -MaxDouble;
    for X := EdgeW to GW - EdgeW - 1 do
      if not IsNan(ColMed[X]) then
      begin
        if ColMed[X] < MinDip then MinDip := ColMed[X];
        if ColMed[X] > MaxBump then MaxBump := ColMed[X];
      end;
    if (MinDip = MaxDouble) or
       not ((MinDip < -Max(5.0 * Sigma, 0.03)) and
            (Abs(MinDip) > 2.5 * Max(0.0, MaxBump))) then
      Continue;

    SetLength(BandX, EdgeW);
    SetLength(BandY, EdgeW);
    Cnt := 0;
    for X := 0 to EdgeW - 1 do
      if not IsNan(ColMed[X]) then
      begin
        BandX[Cnt] := X;
        BandY[Cnt] := ColMed[X];
        Inc(Cnt);
      end;
    if Cnt < 3 then
      Continue;
    FitLine2x2(BandX, BandY, Cnt, MLeft, BLeft);

    Cnt := 0;
    for X := GW - EdgeW to GW - 1 do
      if not IsNan(ColMed[X]) then
      begin
        BandX[Cnt] := X;
        BandY[Cnt] := ColMed[X];
        Inc(Cnt);
      end;
    if Cnt < 3 then
      Continue;
    FitLine2x2(BandX, BandY, Cnt, MRight, BRight);
    if Abs(0.5 * (MLeft + MRight)) * (GW - EdgeW) >= 0.5 * Abs(MinDip) then
      Continue;

    RX := Min(5, Max(1, GW div 40));
    RY := Min(12, Max(1, GH div 20));
    SetLength(Tmp, GH, GW);
    SetLength(Sm, GH, GW);
    for R := 0 to GH - 1 do
      for X := 0 to GW - 1 do
      begin
        RowSum := 0;
        Cnt := 0;
        for K := Max(0, X - RX) to Min(GW - 1, X + RX) do
        begin
          if not IsNan(Clean[R][K]) then
            RowSum := RowSum + Clean[R][K];
          Inc(Cnt);
        end;
        Tmp[R][X] := RowSum / Cnt;
      end;
    for X := 0 to GW - 1 do
      for R := 0 to GH - 1 do
      begin
        RowSum := 0;
        Cnt := 0;
        for K := Max(0, R - RY) to Min(GH - 1, R + RY) do
        begin
          RowSum := RowSum + Tmp[K][X];
          Inc(Cnt);
        end;
        Sm[R][X] := RowSum / Cnt;
      end;

    ThrG := -Max(3.0 * Sigma, 0.015);
    XLo := Trunc(0.10 * GW);
    XHi := Trunc(0.90 * GW);
    MinW := Max(3, GW div 50);
    SetLength(VR, GH);
    SetLength(VX1, GH);
    SetLength(VX2, GH);
    ValidRows := 0;
    for R := 0 to GH - 1 do
    begin
      FirstX := -1;
      LastX := -1;
      Cnt := 0;
      for X := XLo to XHi - 1 do
        if Sm[R][X] < ThrG then
        begin
          if FirstX < 0 then
            FirstX := X;
          LastX := X;
          Inc(Cnt);
        end;
      if Cnt >= MinW then
      begin
        VR[ValidRows] := R;
        VX1[ValidRows] := FirstX;
        VX2[ValidRows] := LastX;
        Inc(ValidRows);
      end;
    end;
    if ValidRows < Trunc(0.75 * GH) then
      Continue;

    SetLength(Dev, ValidRows);
    Med1 := MedianOfSlice(VX1, ValidRows);
    Med2 := MedianOfSlice(VX2, ValidRows);
    for I := 0 to ValidRows - 1 do
      Dev[I] := Abs(VX1[I] - Med1);
    Tol1 := Max(Max(3.0, GW / 100), 4.45 * MedianOfSlice(Dev, ValidRows));
    for I := 0 to ValidRows - 1 do
      Dev[I] := Abs(VX2[I] - Med2);
    Tol2 := Max(Max(3.0, GW / 100), 4.45 * MedianOfSlice(Dev, ValidRows));
    SetLength(KR, ValidRows);
    SetLength(K1, ValidRows);
    SetLength(K2, ValidRows);
    KeptRows := 0;
    for I := 0 to ValidRows - 1 do
      if (Abs(VX1[I] - Med1) <= Tol1) and (Abs(VX2[I] - Med2) <= Tol2) then
      begin
        KR[KeptRows] := VR[I];
        K1[KeptRows] := VX1[I];
        K2[KeptRows] := VX2[I];
        Inc(KeptRows);
      end;
    if KeptRows < Trunc(0.5 * GH) then
      Continue;
    FitLine2x2(KR, K1, KeptRows, M1, B1);
    FitLine2x2(KR, K2, KeptRows, M2, B2);
    PadU := Max(5, GW div 35);
    InCnt := 0;
    SX := 0; SY := 0; SZ := 0; SXX := 0; SXY := 0; SYY := 0; SXZ := 0; SYZ := 0;
    for R := 0 to GH - 1 do
    begin
      X1Lim := (M1 * R + B1) - PadU;
      X2Lim := (M2 * R + B2) + PadU;
      for X := 0 to GW - 1 do
        if (X < X1Lim) or (X > X2Lim) then
        begin
          Z := SurfVal(R, X);
          if (not IsNan(Z)) and (Abs(Z - (A * X + B * R + C)) < 4.0 * Sigma) then
          begin
            Inc(InCnt);
            SX := SX + X;
            SY := SY + R;
            SZ := SZ + Z;
            SXX := SXX + Double(X) * X;
            SXY := SXY + Double(X) * R;
            SYY := SYY + Double(R) * R;
            SXZ := SXZ + X * Z;
            SYZ := SYZ + R * Z;
          end;
        end;
    end;
    if InCnt < 40 then
      Continue;
    FitPlane3x3(SX, SY, SZ, SXX, SXY, SYY, SXZ, SYZ, InCnt, AU, BU, CU);

    for R := 0 to GH - 1 do
    begin
      for X := 0 to GW - 1 do
      begin
        Z := SurfVal(R, X);
        if IsNan(Z) then
          Clean[R][X] := NaN
        else
        begin
          Z := Z - (AU * X + BU * R + CU);
          if Z > Spk then
            Clean[R][X] := NaN
          else
            Clean[R][X] := Z;
        end;
      end;
      InterpolateRowNaNs(Clean[R], GW);
    end;

    SetLength(Areas, GH);
    AreaCnt := 0;
    MeanA := 0;
    for R := 0 to GH - 1 do
    begin
      XS := EnsureRange(Round(M1 * R + B1), 0, GW - 1);
      XE := EnsureRange(Round(M2 * R + B2), 0, GW - 1);
      if XE > XS then
      begin
        RowSum := 0;
        for X := XS to XE do
          if not IsNan(Clean[R][X]) then
            RowSum := RowSum - Clean[R][X];
        Areas[AreaCnt] := RowSum * DX;
        MeanA := MeanA + Areas[AreaCnt];
        Inc(AreaCnt);
      end;
    end;
    if AreaCnt = 0 then
      Continue;
    MeanA := MeanA / AreaCnt;
    SumSq := 0;
    for I := 0 to AreaCnt - 1 do
      SumSq := SumSq + Sqr(Areas[I] - MeanA);
    StdA := Sqrt(SumSq / AreaCnt);
    if (MeanA > 0) and (Abs(MinDip) > BestDip) then
    begin
      BestDip := Abs(MinDip);
      Res.WearArea := MeanA;
      Res.WearAreaStd := StdA;
      Res.RowCount := AreaCnt;
      Res.SpikeLimit := Spk;
      Res.Edge1X := (M1 * 0.5 * (GH - 1) + B1) * DX;
      Res.Edge2X := (M2 * 0.5 * (GH - 1) + B2) * DX;
      SetLength(Res.ProfileX, GW);
      SetLength(Res.ProfileMean, GW);
      SetLength(Res.ProfileStd, GW);
      SetLength(Res.ProfileMeasured, GW);
      for X := 0 to GW - 1 do
      begin
        ColMean := 0;
        Cnt := 0;
        MCnt := 0;
        for R := 0 to GH - 1 do
        begin
          if not IsNan(Clean[R][X]) then
          begin
            ColMean := ColMean + Clean[R][X];
            Inc(Cnt);
          end;
          Z := SurfVal(R, X);
          if (not IsNan(Z)) and (Z - (AU * X + BU * R + CU) <= Spk) then
            Inc(MCnt);
        end;
        Res.ProfileX[X] := X * DX;
        Res.ProfileMeasured[X] := MCnt;
        if Cnt = 0 then
        begin
          Res.ProfileMean[X] := NaN;
          Res.ProfileStd[X] := NaN;
          Continue;
        end;
        ColMean := ColMean / Cnt;
        SumSq := 0;
        for R := 0 to GH - 1 do
          if not IsNan(Clean[R][X]) then
            SumSq := SumSq + Sqr(Clean[R][X] - ColMean);
        Res.ProfileMean[X] := ColMean;
        Res.ProfileStd[X] := Sqrt(SumSq / Cnt);
      end;
      if Orient = 0 then
      begin
        Res.PlaneA := AU;
        Res.PlaneB := BU;
        Res.PlaneC := CU;
        Res.Edge1Start := Point(EnsureRange(Round(B1), 0, W - 1), 0);
        Res.Edge1End := Point(EnsureRange(Round(M1 * (H - 1) + B1), 0, W - 1), H - 1);
        Res.Edge2Start := Point(EnsureRange(Round(B2), 0, W - 1), 0);
        Res.Edge2End := Point(EnsureRange(Round(M2 * (H - 1) + B2), 0, W - 1), H - 1);
      end
      else
      begin
        Res.PlaneA := BU;
        Res.PlaneB := AU;
        Res.PlaneC := CU;
        Res.Edge1Start := Point(0, EnsureRange(Round(B1), 0, H - 1));
        Res.Edge1End := Point(W - 1, EnsureRange(Round(M1 * (W - 1) + B1), 0, H - 1));
        Res.Edge2Start := Point(0, EnsureRange(Round(B2), 0, H - 1));
        Res.Edge2End := Point(W - 1, EnsureRange(Round(M2 * (W - 1) + B2), 0, H - 1));
      end;
      Result := True;
    end;
  end;
end;

function TFIBPSData.TryCalcWearTrack(out WearArea, WearAreaStd: Double): Boolean;
var
  Res: TFIBPSWearResult;
begin
  Result := TryCalcWearTrackEx(Res);
  WearArea := Res.WearArea;
  WearAreaStd := Res.WearAreaStd;
end;

type
  TMat4 = array[0..3, 0..3] of Double;
  TVec4 = array[0..3] of Double;
  TStepFit = record
    A, B, C, D: Double;
    CountA, CountB: Integer;
    MeanA, MeanB, VarA, VarB: Double;
  end;

const
  StepMarginDivisors: array[0..3] of Integer = (20, 12, 8, 6);
  StepSpanDivisor = 6;
  StepRobustPasses = 3;
  StepRejectSigmas = 3.5;
  StepMinSigmaUm = 0.0005;
  StepMinSamples = 20;
  StepMinSnr = 2.5;
  StepLowConfidenceSnr = 6.0;
  StepSecondJumpRatio = 0.4;

function WindowJump(const D: TArray<Double>; X, W: Integer): Double;
var
  K: Integer;
  After, Before: Double;
begin
  After := 0;
  Before := 0;
  for K := 1 to W do
  begin
    After := After + D[X + K];
    Before := Before + D[X - K + 1];
  end;
  Result := Abs(After - Before) / W;
end;

function SolveLinear4(var M: TMat4; var V: TVec4): Boolean;
var
  I, J, K, Piv: Integer;
  F, T: Double;
begin
  Result := False;
  for I := 0 to 3 do
  begin
    Piv := I;
    for J := I + 1 to 3 do
      if Abs(M[J, I]) > Abs(M[Piv, I]) then
        Piv := J;
    if Abs(M[Piv, I]) < 1E-12 then
      Exit;
    if Piv <> I then
    begin
      for K := 0 to 3 do
      begin
        T := M[I, K];
        M[I, K] := M[Piv, K];
        M[Piv, K] := T;
      end;
      T := V[I];
      V[I] := V[Piv];
      V[Piv] := T;
    end;
    for J := I + 1 to 3 do
    begin
      F := M[J, I] / M[I, I];
      for K := I to 3 do
        M[J, K] := M[J, K] - F * M[I, K];
      V[J] := V[J] - F * V[I];
    end;
  end;
  for I := 3 downto 0 do
  begin
    T := V[I];
    for K := I + 1 to 3 do
      T := T - M[I, K] * V[K];
    V[I] := T / M[I, I];
  end;
  Result := True;
end;

function FitStepModel(const Xs, Ys, Zs: TArray<Double>; const Side: TArray<Byte>;
  Count: Integer; out Fit: TStepFit): Boolean;
var
  Keep: TArray<Boolean>;
  Res, Buf: TArray<Double>;
  M: TMat4;
  V, Row: TVec4;
  Pass, I, J, K, N, CntA, CntB: Integer;
  Med, Sigma, SumA, SumB, R: Double;
begin
  Fit := Default(TStepFit);
  Result := False;
  SetLength(Keep, Count);
  SetLength(Res, Count);
  SetLength(Buf, Count);
  for I := 0 to Count - 1 do
    Keep[I] := True;
  for Pass := 0 to StepRobustPasses do
  begin
    M := Default(TMat4);
    V := Default(TVec4);
    CntA := 0;
    CntB := 0;
    for I := 0 to Count - 1 do
      if Keep[I] then
      begin
        Row[0] := Xs[I];
        Row[1] := Ys[I];
        Row[2] := 1;
        Row[3] := Side[I];
        for J := 0 to 3 do
        begin
          V[J] := V[J] + Row[J] * Zs[I];
          for K := 0 to 3 do
            M[J, K] := M[J, K] + Row[J] * Row[K];
        end;
        if Side[I] = 0 then
          Inc(CntA)
        else
          Inc(CntB);
      end;
    if (CntA < StepMinSamples) or (CntB < StepMinSamples) then
      Exit;
    if not SolveLinear4(M, V) then
      Exit;
    if Pass = StepRobustPasses then
      Break;
    N := 0;
    for I := 0 to Count - 1 do
    begin
      Res[I] := Zs[I] - (V[0] * Xs[I] + V[1] * Ys[I] + V[2] + V[3] * Side[I]);
      if Keep[I] then
      begin
        Buf[N] := Res[I];
        Inc(N);
      end;
    end;
    Med := MedianOfSlice(Buf, N);
    for I := 0 to N - 1 do
      Buf[I] := Abs(Buf[I] - Med);
    Sigma := Max(1.4826 * MedianOfSlice(Buf, N), StepMinSigmaUm);
    for I := 0 to Count - 1 do
      Keep[I] := Abs(Res[I] - Med) < StepRejectSigmas * Sigma;
  end;
  Fit.A := V[0];
  Fit.B := V[1];
  Fit.C := V[2];
  Fit.D := V[3];
  Fit.CountA := CntA;
  Fit.CountB := CntB;
  SumA := 0;
  SumB := 0;
  for I := 0 to Count - 1 do
    if Keep[I] then
    begin
      R := Zs[I] - (V[0] * Xs[I] + V[1] * Ys[I] + V[2]);
      if Side[I] = 0 then
        SumA := SumA + R
      else
        SumB := SumB + R;
    end;
  Fit.MeanA := SumA / CntA;
  Fit.MeanB := SumB / CntB;
  for I := 0 to Count - 1 do
    if Keep[I] then
    begin
      R := Zs[I] - (V[0] * Xs[I] + V[1] * Ys[I] + V[2]);
      if Side[I] = 0 then
        Fit.VarA := Fit.VarA + Sqr(R - Fit.MeanA)
      else
        Fit.VarB := Fit.VarB + Sqr(R - Fit.MeanB);
    end;
  Fit.VarA := Fit.VarA / CntA;
  Fit.VarB := Fit.VarB / CntB;
  Result := True;
end;

function TFIBPSData.TryCalcStepHeightEx(out Res: TFIBPSStepResult): Boolean;
var
  W, H, ValidTotal, I, Orient, SW, SH, R, X, K, ColCnt, Rad, Cnt: Integer;
  XStep, SLo, SHi, Y1, Y2, AX1, AX2, BX1, BX2, Margin, Span, MI, SampCnt: Integer;
  WTrans, NX1, NX2, NearCnt1, NearCnt2: Integer;
  ColInvalid: Boolean;
  Z, MedG, BestGrad, MainJump, SecondJump, AS0, BS0, CS0, YMid: Double;
  StepUm, StdUm, NearJump, SNR, BestSNR: Double;
  Fit: TStepFit;
  ColMed, ColBuf, SmCol, Grad, Detr, NearBuf1, NearBuf2, SampX, SampY, SampZ: TArray<Double>;
  SampSide: TArray<Byte>;

  function SurfVal(RowIdx, ColIdx: Integer): Single;
  begin
    if Orient = 0 then
      Result := Heights[RowIdx * W + ColIdx]
    else
      Result := Heights[ColIdx * W + RowIdx];
  end;

begin
  Res := Default(TFIBPSStepResult);
  Result := False;
  W := Integer(PixW);
  H := Integer(PixH);
  if (W < 16) or (H < 16) then
    Exit;
  ValidTotal := 0;
  for I := 0 to Length(Heights) - 1 do
    if not IsNan(Heights[I]) then
      Inc(ValidTotal);
  if ValidTotal * 2 < W * H then
    Exit;

  BestSNR := -1;
  for Orient := 0 to 1 do
  begin
    if Orient = 0 then
    begin
      SW := W;
      SH := H;
    end
    else
    begin
      SW := H;
      SH := W;
    end;

    SetLength(ColMed, SW);
    SetLength(ColBuf, SH);
    ColInvalid := False;
    for X := 0 to SW - 1 do
    begin
      ColCnt := 0;
      for R := 0 to SH - 1 do
      begin
        Z := SurfVal(R, X);
        if not IsNan(Z) then
        begin
          ColBuf[ColCnt] := Z;
          Inc(ColCnt);
        end;
      end;
      if ColCnt = 0 then
      begin
        ColInvalid := True;
        Break;
      end;
      ColMed[X] := MedianOfSlice(ColBuf, ColCnt);
    end;
    if ColInvalid then
      Continue;

    Rad := Min(4, Max(1, SW div 40));
    SetLength(SmCol, SW);
    for X := 0 to SW - 1 do
    begin
      Z := 0;
      Cnt := 0;
      for K := Max(0, X - Rad) to Min(SW - 1, X + Rad) do
      begin
        Z := Z + ColMed[K];
        Inc(Cnt);
      end;
      SmCol[X] := Z / Cnt;
    end;

    SetLength(Grad, SW - 1);
    for X := 0 to SW - 2 do
      Grad[X] := SmCol[X + 1] - SmCol[X];
    MedG := MedianOfSlice(Grad, SW - 1);
    SLo := Trunc(0.20 * SW);
    SHi := Trunc(0.80 * SW);
    if SHi <= SLo + 4 then
      Continue;
    XStep := SLo;
    BestGrad := -1;
    for X := SLo to SHi - 1 do
      if Abs(Grad[X] - MedG) > BestGrad then
      begin
        BestGrad := Abs(Grad[X] - MedG);
        XStep := X;
      end;

    Y1 := Trunc(0.10 * SH);
    Y2 := Trunc(0.90 * SH);
    if Y2 <= Y1 + 2 then
      Continue;
    YMid := 0.5 * (Y1 + Y2);
    Span := Max(8, SW div StepSpanDivisor);
    WTrans := Max(4, SW div 10);
    NX1 := Max(0, XStep - WTrans);
    NX2 := Min(SW - 1, XStep + WTrans);
    SetLength(Detr, SW);
    for X := 0 to SW - 1 do
      Detr[X] := SmCol[X] - MedG * X;
    MainJump := WindowJump(Detr, XStep, WTrans);
    SecondJump := 0;
    for X := WTrans - 1 to SW - WTrans - 1 do
      if (X < XStep - WTrans) or (X > XStep + WTrans) then
        SecondJump := Max(SecondJump, WindowJump(Detr, X, WTrans));
    if SecondJump >= StepSecondJumpRatio * MainJump then
      Continue;

    for MI := Low(StepMarginDivisors) to High(StepMarginDivisors) do
    begin
      Margin := Max(2, SW div StepMarginDivisors[MI]);
      AX1 := Max(0, XStep - Margin - Span);
      AX2 := XStep - Margin;
      BX1 := XStep + Margin + 1;
      BX2 := Min(SW - 1, XStep + Margin + Span);
      if (AX2 <= AX1 + 2) or (BX2 <= BX1 + 2) then
        Continue;

      SetLength(SampX, (Y2 - Y1 + 1) * (AX2 - AX1 + BX2 - BX1 + 2));
      SetLength(SampY, Length(SampX));
      SetLength(SampZ, Length(SampX));
      SetLength(SampSide, Length(SampX));
      SampCnt := 0;
      for R := Y1 to Y2 do
      begin
        for X := AX1 to AX2 do
        begin
          Z := SurfVal(R, X);
          if not IsNan(Z) then
          begin
            SampX[SampCnt] := X - XStep;
            SampY[SampCnt] := R - YMid;
            SampZ[SampCnt] := Z;
            SampSide[SampCnt] := 0;
            Inc(SampCnt);
          end;
        end;
        for X := BX1 to BX2 do
        begin
          Z := SurfVal(R, X);
          if not IsNan(Z) then
          begin
            SampX[SampCnt] := X - XStep;
            SampY[SampCnt] := R - YMid;
            SampZ[SampCnt] := Z;
            SampSide[SampCnt] := 1;
            Inc(SampCnt);
          end;
        end;
      end;
      if not FitStepModel(SampX, SampY, SampZ, SampSide, SampCnt, Fit) then
        Continue;

      StepUm := Abs(Fit.MeanA - Fit.MeanB);
      StdUm := Sqrt(Fit.VarA + Fit.VarB);
      AS0 := Fit.A;
      BS0 := Fit.B;
      CS0 := Fit.C - Fit.A * XStep - Fit.B * YMid;

      SetLength(NearBuf1, (Y2 - Y1 + 1) * (Max(NX1, XStep - 3) - NX1 + 1));
      SetLength(NearBuf2, (Y2 - Y1 + 1) * (NX2 - Min(SW - 1, XStep + 2) + 1));
      NearCnt1 := 0;
      NearCnt2 := 0;
      for R := Y1 to Y2 - 1 do
      begin
        for X := NX1 to Max(NX1, XStep - 3) do
        begin
          Z := SurfVal(R, X);
          if not IsNan(Z) then
          begin
            NearBuf1[NearCnt1] := Z - (AS0 * X + BS0 * R + CS0);
            Inc(NearCnt1);
          end;
        end;
        for X := Min(SW - 1, XStep + 2) to NX2 do
        begin
          Z := SurfVal(R, X);
          if not IsNan(Z) then
          begin
            NearBuf2[NearCnt2] := Z - (AS0 * X + BS0 * R + CS0);
            Inc(NearCnt2);
          end;
        end;
      end;
      if (NearCnt1 = 0) or (NearCnt2 = 0) then
        Continue;
      NearJump := Abs(MedianOfSlice(NearBuf1, NearCnt1) - MedianOfSlice(NearBuf2, NearCnt2));

      if (StepUm >= 0.010) and (StepUm >= StepMinSnr * StdUm) and (NearJump >= 0.5 * StepUm) then
      begin
        SNR := StepUm / Max(StdUm, 1E-6);
        if SNR > BestSNR then
        begin
          BestSNR := SNR;
          Res.MeanA := Fit.MeanA;
          Res.MeanB := Fit.MeanB;
          Res.CountA := Fit.CountA;
          Res.CountB := Fit.CountB;
          Res.StepHeight := StepUm;
          Res.StepHeightStd := StdUm;
          Res.LowConfidence := (MI > Low(StepMarginDivisors)) or (SNR < StepLowConfidenceSnr);
          if Orient = 0 then
          begin
            Res.RectA := Rect(AX1, Y1, AX2, Y2);
            Res.RectB := Rect(BX1, Y1, BX2, Y2);
            Res.PlaneA := AS0;
            Res.PlaneB := BS0;
            Res.PlaneC := CS0;
          end
          else
          begin
            Res.RectA := Rect(Y1, AX1, Y2, AX2);
            Res.RectB := Rect(Y1, BX1, Y2, BX2);
            Res.PlaneA := BS0;
            Res.PlaneB := AS0;
            Res.PlaneC := CS0;
          end;
          Result := True;
        end;
        Break;
      end;
    end;
  end;
end;

function TFIBPSData.TryCalcStepHeight(out StepHeight, StepHeightStd: Double): Boolean;
var
  Res: TFIBPSStepResult;
begin
  Result := TryCalcStepHeightEx(Res);
  StepHeight := Res.StepHeight;
  StepHeightStd := Res.StepHeightStd;
end;

function TFIBPSData.CalcGlobalPlane(out PlaneA, PlaneB, PlaneC: Double): Boolean;
var
  W, H, X, Y, Cnt: Integer;
  Z, SX, SY, SZ, SXX, SXY, SYY, SXZ, SYZ: Double;
begin
  PlaneA := 0;
  PlaneB := 0;
  PlaneC := 0;
  Result := False;
  W := Integer(PixW);
  H := Integer(PixH);
  if (W < 2) or (H < 2) then
    Exit;
  Cnt := 0;
  SX := 0; SY := 0; SZ := 0; SXX := 0; SXY := 0; SYY := 0; SXZ := 0; SYZ := 0;
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      Z := HeightAt(X, Y);
      if not IsNan(Z) then
      begin
        Inc(Cnt);
        SX := SX + X;
        SY := SY + Y;
        SZ := SZ + Z;
        SXX := SXX + Double(X) * X;
        SXY := SXY + Double(X) * Y;
        SYY := SYY + Double(Y) * Y;
        SXZ := SXZ + X * Z;
        SYZ := SYZ + Y * Z;
      end;
    end;
  if Cnt < 3 then
    Exit;
  FitPlane3x3(SX, SY, SZ, SXX, SXY, SYY, SXZ, SYZ, Cnt, PlaneA, PlaneB, PlaneC);
  Result := True;
end;

function TFIBPSData.CalcStepFromRects(const ARectA, ARectB: TRect;
  out Res: TFIBPSStepResult): Boolean;
var
  W, H, X, Y, SubCnt, CntA, CntB: Integer;
  RA, RB, RSub: TRect;
  GA, GB, GC, Z, MeanA0, MeanB0, MeanA, MeanB, VarA, VarB: Double;
  SX, SY, SZ, SXX, SXY, SYY, SXZ, SYZ: Double;
begin
  Res := Default(TFIBPSStepResult);
  Result := False;
  W := Integer(PixW);
  H := Integer(PixH);
  if (W < 2) or (H < 2) then
    Exit;
  RA.Left := EnsureRange(Min(ARectA.Left, ARectA.Right), 0, W - 1);
  RA.Right := EnsureRange(Max(ARectA.Left, ARectA.Right), 0, W - 1);
  RA.Top := EnsureRange(Min(ARectA.Top, ARectA.Bottom), 0, H - 1);
  RA.Bottom := EnsureRange(Max(ARectA.Top, ARectA.Bottom), 0, H - 1);
  RB.Left := EnsureRange(Min(ARectB.Left, ARectB.Right), 0, W - 1);
  RB.Right := EnsureRange(Max(ARectB.Left, ARectB.Right), 0, W - 1);
  RB.Top := EnsureRange(Min(ARectB.Top, ARectB.Bottom), 0, H - 1);
  RB.Bottom := EnsureRange(Max(ARectB.Top, ARectB.Bottom), 0, H - 1);
  if (RA.Right <= RA.Left) or (RA.Bottom <= RA.Top) or
     (RB.Right <= RB.Left) or (RB.Bottom <= RB.Top) then
    Exit;

  CalcGlobalPlane(GA, GB, GC);
  CntA := 0;
  MeanA0 := 0;
  for Y := RA.Top to RA.Bottom do
    for X := RA.Left to RA.Right do
    begin
      Z := HeightAt(X, Y);
      if not IsNan(Z) then
      begin
        MeanA0 := MeanA0 + (Z - (GA * X + GB * Y + GC));
        Inc(CntA);
      end;
    end;
  CntB := 0;
  MeanB0 := 0;
  for Y := RB.Top to RB.Bottom do
    for X := RB.Left to RB.Right do
    begin
      Z := HeightAt(X, Y);
      if not IsNan(Z) then
      begin
        MeanB0 := MeanB0 + (Z - (GA * X + GB * Y + GC));
        Inc(CntB);
      end;
    end;
  if (CntA < 3) or (CntB < 3) then
    Exit;
  if (MeanB0 / CntB) <= (MeanA0 / CntA) then
    RSub := RB
  else
    RSub := RA;

  SubCnt := 0;
  SX := 0; SY := 0; SZ := 0; SXX := 0; SXY := 0; SYY := 0; SXZ := 0; SYZ := 0;
  for Y := RSub.Top to RSub.Bottom do
    for X := RSub.Left to RSub.Right do
    begin
      Z := HeightAt(X, Y);
      if not IsNan(Z) then
      begin
        Inc(SubCnt);
        SX := SX + X;
        SY := SY + Y;
        SZ := SZ + Z;
        SXX := SXX + Double(X) * X;
        SXY := SXY + Double(X) * Y;
        SYY := SYY + Double(Y) * Y;
        SXZ := SXZ + X * Z;
        SYZ := SYZ + Y * Z;
      end;
    end;
  if SubCnt < 3 then
    Exit;
  FitPlane3x3(SX, SY, SZ, SXX, SXY, SYY, SXZ, SYZ, SubCnt, Res.PlaneA, Res.PlaneB, Res.PlaneC);

  CntA := 0;
  MeanA := 0;
  for Y := RA.Top to RA.Bottom do
    for X := RA.Left to RA.Right do
    begin
      Z := HeightAt(X, Y);
      if not IsNan(Z) then
      begin
        MeanA := MeanA + (Z - (Res.PlaneA * X + Res.PlaneB * Y + Res.PlaneC));
        Inc(CntA);
      end;
    end;
  CntB := 0;
  MeanB := 0;
  for Y := RB.Top to RB.Bottom do
    for X := RB.Left to RB.Right do
    begin
      Z := HeightAt(X, Y);
      if not IsNan(Z) then
      begin
        MeanB := MeanB + (Z - (Res.PlaneA * X + Res.PlaneB * Y + Res.PlaneC));
        Inc(CntB);
      end;
    end;
  MeanA := MeanA / CntA;
  MeanB := MeanB / CntB;
  VarA := 0;
  for Y := RA.Top to RA.Bottom do
    for X := RA.Left to RA.Right do
    begin
      Z := HeightAt(X, Y);
      if not IsNan(Z) then
        VarA := VarA + Sqr((Z - (Res.PlaneA * X + Res.PlaneB * Y + Res.PlaneC)) - MeanA);
    end;
  VarA := VarA / CntA;
  VarB := 0;
  for Y := RB.Top to RB.Bottom do
    for X := RB.Left to RB.Right do
    begin
      Z := HeightAt(X, Y);
      if not IsNan(Z) then
        VarB := VarB + Sqr((Z - (Res.PlaneA * X + Res.PlaneB * Y + Res.PlaneC)) - MeanB);
    end;
  VarB := VarB / CntB;

  Res.RectA := RA;
  Res.RectB := RB;
  Res.MeanA := MeanA;
  Res.MeanB := MeanB;
  Res.CountA := CntA;
  Res.CountB := CntB;
  Res.StepHeight := Abs(MeanA - MeanB);
  Res.StepHeightStd := Sqrt(VarA + VarB);
  Result := True;
end;

end.
