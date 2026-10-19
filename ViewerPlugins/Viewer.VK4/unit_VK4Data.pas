{$POINTERMATH ON}
unit unit_VK4Data;

interface

uses
  System.SysUtils, System.Classes, System.Math;

type
  EVK4Error = class(Exception);

  TVK4Channel = (vcColorPeak, vcColorLight, vcLightIntensity, vcHeight);

  TVK4RGB = record
    R, G, B: Byte;
  end;

  TVK4Settings = record
    Year, Month, Day, Hour, Minute, Second: Cardinal;
    LensMag: Cardinal;
    OpticalZoom: Cardinal;
  end;

  TVK4ImageData = record
    Width, Height: Cardinal;
    Valid: Boolean;
    DataRGB: TArray<TVK4RGB>;
    DataU16: TArray<Word>;
  end;

  TVK4Data = class
  private
    FFileName: string;
    FSettings: TVK4Settings;
    FTitle: string;
    FLensName: string;
    FMinHeight, FMaxHeight: Double;
    FPhysWidth, FPhysHeight: Double;
    FPixelXum, FPixelYum: Double;
    FZStepUm: Double;
    FColorW, FColorH: array[0..1] of Cardinal;
    FColor: array[0..1] of TArray<TVK4RGB>;
    FLightW, FLightH: Cardinal;
    FLight: TArray<Word>;
    FHeightW, FHeightH: Cardinal;
    FHeight: TArray<Cardinal>;
    procedure Reset;
    procedure ReadColor(const B: TBytes; Ofs: Cardinal; Idx: Integer);
    procedure ReadLight(const B: TBytes; Ofs: Cardinal);
    procedure ReadHeight(const B: TBytes; Ofs: Cardinal);
    procedure ReadSettings(const B: TBytes; Ofs: Cardinal);
    procedure ReadStrings(const B: TBytes; Ofs: Cardinal);
    procedure Finish;
  public
    constructor Create;
    procedure ParseFromFile(const AFileName: string);
    function HasChannel(Ch: TVK4Channel): Boolean;
    function ChannelWidth(Ch: TVK4Channel): Cardinal;
    function ChannelHeight(Ch: TVK4Channel): Cardinal;
    function GetImageData(Ch: TVK4Channel): TVK4ImageData;
    function HeightAt(X, Y: Integer): Double;
    function LightAt(X, Y: Integer): Word;
    function PhysXAt(X: Integer): Double;
    function PhysYAt(Y: Integer): Double;
    property FileName: string read FFileName;
    property Settings: TVK4Settings read FSettings;
    property Title: string read FTitle;
    property LensName: string read FLensName;
    property MinHeight: Double read FMinHeight;
    property MaxHeight: Double read FMaxHeight;
    property PhysWidth: Double read FPhysWidth;
    property PhysHeight: Double read FPhysHeight;
    property PixelXum: Double read FPixelXum;
    property PixelYum: Double read FPixelYum;
  end;

implementation

const
  Magic: array[0..3] of Byte = (Ord('V'), Ord('K'), Ord('4'), Ord('_'));
  OffsetTablePos = 12;
  OffsetCount = 18;
  OfsSettings = 0;
  OfsColorA = 1;
  OfsColorB = 2;
  OfsLight = 3;
  OfsHeight = 6;
  OfsStrings = 16;
  ImageHeaderSize = 20;
  MonoExtraSize = 776;
  MaxSide = 16384;
  MaxPixels = 100000000;
  MinSettingsSize = 180;
  PicometresPerMicrometre = 1.0e6;

function RdU32(const B: TBytes; Pos: Int64): Cardinal;
begin
  if (Pos < 0) or (Pos + 4 > Length(B)) then
    raise EVK4Error.CreateFmt('VK4: read past end of file at offset %d', [Pos]);
  Result := PCardinal(@B[Pos])^;
end;

procedure CheckRange(const B: TBytes; Pos, Size: Int64);
begin
  if (Pos < 0) or (Size < 0) or (Pos + Size > Length(B)) then
    raise EVK4Error.CreateFmt('VK4: block at %d (%d bytes) exceeds file size %d',
      [Pos, Size, Length(B)]);
end;

procedure ReadImageHeader(const B: TBytes; Ofs: Cardinal; ExpectBpp: Cardinal;
  ExtraBytes: Int64; out W, H: Cardinal; out DataPos, DataSize: Int64);
var
  Bpp, Declared: Cardinal;
begin
  W := RdU32(B, Ofs);
  H := RdU32(B, Int64(Ofs) + 4);
  Bpp := RdU32(B, Int64(Ofs) + 8);
  Declared := RdU32(B, Int64(Ofs) + 16);
  if (W = 0) or (H = 0) or (W > MaxSide) or (H > MaxSide) or
     (Int64(W) * H > MaxPixels) then
    raise EVK4Error.CreateFmt('VK4: unreasonable image size %dx%d', [W, H]);
  if Bpp <> ExpectBpp then
    raise EVK4Error.CreateFmt('VK4: unexpected bit depth %d at offset %d', [Bpp, Ofs]);
  DataSize := Int64(W) * H * (Bpp div 8);
  if Int64(Declared) <> DataSize then
    raise EVK4Error.CreateFmt('VK4: size field mismatch at offset %d', [Ofs]);
  DataPos := Int64(Ofs) + ImageHeaderSize + ExtraBytes;
  CheckRange(B, DataPos, DataSize);
end;

constructor TVK4Data.Create;
begin
  inherited Create;
  Reset;
end;

procedure TVK4Data.Reset;
var
  I: Integer;
begin
  FFileName := '';
  FSettings := Default(TVK4Settings);
  FTitle := '';
  FLensName := '';
  FMinHeight := NaN;
  FMaxHeight := NaN;
  FPhysWidth := 0;
  FPhysHeight := 0;
  FPixelXum := 0;
  FPixelYum := 0;
  FZStepUm := 0;
  for I := 0 to 1 do
  begin
    FColorW[I] := 0;
    FColorH[I] := 0;
    FColor[I] := nil;
  end;
  FLightW := 0;
  FLightH := 0;
  FLight := nil;
  FHeightW := 0;
  FHeightH := 0;
  FHeight := nil;
end;

procedure TVK4Data.ReadColor(const B: TBytes; Ofs: Cardinal; Idx: Integer);
var
  W, H: Cardinal;
  Pos, Size: Int64;
  I: Integer;
  Src: PByte;
begin
  ReadImageHeader(B, Ofs, 24, 0, W, H, Pos, Size);
  SetLength(FColor[Idx], Int64(W) * H);
  Src := @B[Pos];
  for I := 0 to High(FColor[Idx]) do
  begin
    FColor[Idx][I].B := Src[0];
    FColor[Idx][I].G := Src[1];
    FColor[Idx][I].R := Src[2];
    Inc(Src, 3);
  end;
  FColorW[Idx] := W;
  FColorH[Idx] := H;
end;

procedure TVK4Data.ReadLight(const B: TBytes; Ofs: Cardinal);
var
  W, H: Cardinal;
  Pos, Size: Int64;
begin
  ReadImageHeader(B, Ofs, 16, MonoExtraSize, W, H, Pos, Size);
  SetLength(FLight, Int64(W) * H);
  Move(B[Pos], FLight[0], Size);
  FLightW := W;
  FLightH := H;
end;

procedure TVK4Data.ReadHeight(const B: TBytes; Ofs: Cardinal);
var
  W, H: Cardinal;
  Pos, Size: Int64;
begin
  ReadImageHeader(B, Ofs, 32, MonoExtraSize, W, H, Pos, Size);
  SetLength(FHeight, Int64(W) * H);
  Move(B[Pos], FHeight[0], Size);
  FHeightW := W;
  FHeightH := H;
end;

procedure TVK4Data.ReadSettings(const B: TBytes; Ofs: Cardinal);
var
  Size: Cardinal;
  P: Int64;
begin
  P := Ofs;
  Size := RdU32(B, P);
  if Size < MinSettingsSize then
    raise EVK4Error.Create('VK4: settings block too small');
  CheckRange(B, P, Size);
  FSettings.Year := RdU32(B, P + 4);
  FSettings.Month := RdU32(B, P + 8);
  FSettings.Day := RdU32(B, P + 12);
  FSettings.Hour := RdU32(B, P + 16);
  FSettings.Minute := RdU32(B, P + 20);
  FSettings.Second := RdU32(B, P + 24);
  FSettings.OpticalZoom := RdU32(B, P + 72);
  FSettings.LensMag := RdU32(B, P + 96) div 10;
  FPixelXum := RdU32(B, P + 168) / PicometresPerMicrometre;
  FPixelYum := RdU32(B, P + 172) / PicometresPerMicrometre;
  FZStepUm := RdU32(B, P + 176) / PicometresPerMicrometre;
end;

procedure TVK4Data.ReadStrings(const B: TBytes; Ofs: Cardinal);
var
  P: Int64;

  function ReadStr: string;
  var
    N: Cardinal;
  begin
    N := RdU32(B, P);
    if N > 4096 then
      raise EVK4Error.Create('VK4: string too long');
    CheckRange(B, P + 4, Int64(N) * 2);
    SetString(Result, PChar(@B[P + 4]), N);
    Inc(P, 4 + Int64(N) * 2);
  end;

begin
  P := Ofs;
  FTitle := ReadStr;
  FLensName := ReadStr;
end;

procedure TVK4Data.Finish;
var
  I: Integer;
  V: Cardinal;
  MinV, MaxV: Cardinal;
  Any: Boolean;
  W, H: Cardinal;
begin
  if Length(FHeight) > 0 then
  begin
    if (FPixelXum <= 0) or (FPixelYum <= 0) or (FZStepUm <= 0) then
      raise EVK4Error.Create('VK4: missing scale information for height data');
    Any := False;
    MinV := 0;
    MaxV := 0;
    for I := 0 to High(FHeight) do
    begin
      V := FHeight[I];
      if V = 0 then
        Continue;
      if not Any then
      begin
        MinV := V;
        MaxV := V;
        Any := True;
      end
      else
      begin
        if V < MinV then
          MinV := V;
        if V > MaxV then
          MaxV := V;
      end;
    end;
    if Any then
    begin
      FMinHeight := MinV * FZStepUm;
      FMaxHeight := MaxV * FZStepUm;
    end;
  end;
  if FHeightW > 0 then
  begin
    W := FHeightW;
    H := FHeightH;
  end
  else if FLightW > 0 then
  begin
    W := FLightW;
    H := FLightH;
  end
  else
  begin
    W := FColorW[0];
    H := FColorH[0];
  end;
  FPhysWidth := (W - 1) * FPixelXum;
  FPhysHeight := (H - 1) * FPixelYum;
end;

procedure TVK4Data.ParseFromFile(const AFileName: string);
var
  B: TBytes;
  Ofs: array[0..OffsetCount - 1] of Cardinal;
  I: Integer;
  FS: TFileStream;
begin
  Reset;
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    if FS.Size > High(Integer) then
      raise EVK4Error.Create('VK4: file too large');
    SetLength(B, FS.Size);
    if Length(B) > 0 then
      FS.ReadBuffer(B[0], Length(B));
  finally
    FS.Free;
  end;
  try
    if Length(B) < OffsetTablePos + OffsetCount * 4 then
      raise EVK4Error.Create('VK4: file too short');
    for I := 0 to High(Magic) do
      if B[I] <> Magic[I] then
        raise EVK4Error.Create('VK4: bad signature');
    for I := 0 to OffsetCount - 1 do
      Ofs[I] := RdU32(B, OffsetTablePos + I * 4);
    if Ofs[OfsSettings] = 0 then
      raise EVK4Error.Create('VK4: no settings block');
    ReadSettings(B, Ofs[OfsSettings]);
    if Ofs[OfsColorA] <> 0 then
      ReadColor(B, Ofs[OfsColorA], 0);
    if Ofs[OfsColorB] <> 0 then
      ReadColor(B, Ofs[OfsColorB], 1);
    if Ofs[OfsLight] <> 0 then
      ReadLight(B, Ofs[OfsLight]);
    if Ofs[OfsHeight] <> 0 then
      ReadHeight(B, Ofs[OfsHeight]);
    if Ofs[OfsStrings] <> 0 then
      ReadStrings(B, Ofs[OfsStrings]);
    if (Length(FHeight) = 0) and (Length(FLight) = 0) and
       (Length(FColor[0]) = 0) and (Length(FColor[1]) = 0) then
      raise EVK4Error.Create('VK4: no image data');
    Finish;
  except
    Reset;
    raise;
  end;
  FFileName := AFileName;
end;

function TVK4Data.HasChannel(Ch: TVK4Channel): Boolean;
begin
  Result := ChannelWidth(Ch) > 0;
end;

function TVK4Data.ChannelWidth(Ch: TVK4Channel): Cardinal;
begin
  case Ch of
    vcColorPeak: Result := FColorW[0];
    vcColorLight: Result := FColorW[1];
    vcLightIntensity: Result := FLightW;
  else
    Result := FHeightW;
  end;
end;

function TVK4Data.ChannelHeight(Ch: TVK4Channel): Cardinal;
begin
  case Ch of
    vcColorPeak: Result := FColorH[0];
    vcColorLight: Result := FColorH[1];
    vcLightIntensity: Result := FLightH;
  else
    Result := FHeightH;
  end;
end;

function TVK4Data.GetImageData(Ch: TVK4Channel): TVK4ImageData;
var
  I: Integer;
  Span: Double;
  V: Cardinal;
  MinD, MaxD: Double;
begin
  Result := Default(TVK4ImageData);
  if not HasChannel(Ch) then
    Exit;
  Result.Width := ChannelWidth(Ch);
  Result.Height := ChannelHeight(Ch);
  Result.Valid := True;
  case Ch of
    vcColorPeak: Result.DataRGB := Copy(FColor[0]);
    vcColorLight: Result.DataRGB := Copy(FColor[1]);
    vcLightIntensity: Result.DataU16 := Copy(FLight);
    vcHeight:
      begin
        SetLength(Result.DataU16, Length(FHeight));
        MinD := FMinHeight / FZStepUm;
        MaxD := FMaxHeight / FZStepUm;
        Span := MaxD - MinD;
        for I := 0 to High(FHeight) do
        begin
          V := FHeight[I];
          if (V = 0) or (Span <= 0) then
            Result.DataU16[I] := 0
          else
            Result.DataU16[I] := Round((V - MinD) / Span * 65535);
        end;
      end;
  end;
end;

function TVK4Data.HeightAt(X, Y: Integer): Double;
var
  V: Cardinal;
begin
  Result := NaN;
  if (FHeightW = 0) or (X < 0) or (Y < 0) or (Cardinal(X) >= FHeightW) or
     (Cardinal(Y) >= FHeightH) then
    Exit;
  V := FHeight[Int64(Y) * FHeightW + X];
  if V <> 0 then
    Result := V * FZStepUm;
end;

function TVK4Data.LightAt(X, Y: Integer): Word;
begin
  Result := 0;
  if (FLightW = 0) or (X < 0) or (Y < 0) or (Cardinal(X) >= FLightW) or
     (Cardinal(Y) >= FLightH) then
    Exit;
  Result := FLight[Int64(Y) * FLightW + X];
end;

function TVK4Data.PhysXAt(X: Integer): Double;
begin
  Result := X * FPixelXum;
end;

function TVK4Data.PhysYAt(Y: Integer): Double;
begin
  Result := Y * FPixelYum;
end;

end.
