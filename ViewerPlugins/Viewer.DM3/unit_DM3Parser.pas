unit unit_DM3Parser;

interface

uses
  System.SysUtils, System.Classes, System.Math,
  Winapi.Windows, Vcl.Graphics;

type
  TDM3Metadata = record
    Width: Integer;
    Height: Integer;
    DataType: Integer;
    PixelDepth: Integer;
    ScaleX: Double;
    ScaleY: Double;
    Units: string;
    Voltage: Double;
    ActualMagnification: Double;
    IndicatedMagnification: Double;
    Microscope: string;
    CameraName: string;
    AcquisitionDate: string;
    AcquisitionTime: string;
    ExposureTime: Double;
    Cs: Double;
    IlluminationMode: string;
    ImageName: string;
    OperationMode: string;
    BeamCurrent: Double;
    ConvergenceAngle: Double;
    AlphaTilt: Double;
    BetaTilt: Double;
    Defocus: Double;
    STEMCameraLength: Double;
    ProbeSize: Double;
    procedure Clear;
  end;

  TDM3TagValue = record
    IntVal: Int64;
    FloatVal: Double;
    StrVal: string;
    DataOffset: Int64;
    DataSize: Int64;
    IsString: Boolean;
    IsFloat: Boolean;
  end;

  TDM3File = class
  private
    FStream: TStream;
    FOwnedStream: TMemoryStream;
    FVersion: Integer;
    FRootLength: Integer;
    FLittleEndian: Boolean;
    FMetadata: TDM3Metadata;
    FFileName: string;
    FMainImageOffset: Int64;
    FMainImageSize: Int64;
    FThumbImageOffset: Int64;
    FThumbImageSize: Int64;
    FThumbWidth: Integer;
    FThumbHeight: Integer;
    FThumbDataType: Integer;
    FTags: TStringList;
    FTagValues: array of TDM3TagValue;

    function ReadBE16: Word;
    function ReadBE32: Cardinal;
    procedure ReadHeader;
    procedure ParseTagGroup(const Path: string; IsRoot: Boolean);
    procedure ParseTagEntry(const Path: string);
    procedure ReadTagByInfo(const Path: string; const Info: array of Cardinal);
    function ReadTypedValue(TypeCode: Integer): TDM3TagValue;

    procedure AddTag(const Path: string; const Value: TDM3TagValue);
    function FindTag(const Path: string): Integer;
    function GetTagInt(const Path: string; ADefault: Int64 = 0): Int64;
    function GetTagFloat(const Path: string; ADefault: Double = 0): Double;
    function GetTagStr(const Path: string; const ADefault: string = ''): string;

    procedure ExtractMetadata;
    procedure FindImageData;
    function NormalizeToGrayscale8(AOffset, ASize: Int64; W, H, DType: Integer): Vcl.Graphics.TBitmap;
    function ReadRGBA(AOffset, ASize: Int64; W, H: Integer): Vcl.Graphics.TBitmap;
    procedure SetGrayscalePalette(Bmp: Vcl.Graphics.TBitmap);

    procedure SwapBytes2(P: PByte); inline;
    procedure SwapBytes4(P: PByte); inline;
    procedure SwapBytes8(P: PByte); inline;
  public
    constructor Create;
    destructor Destroy; override;

    procedure ParseFromFile(const AFileName: string);
    procedure ParseFromStream(AStream: TStream);
    function GetBitmap: Vcl.Graphics.TBitmap;
    function GetThumbnail: Vcl.Graphics.TBitmap;

    property Metadata: TDM3Metadata read FMetadata;
    property FileName: string read FFileName;
  end;

  EDM3Error = class(Exception);

implementation

const
  // Sanity cap for image dimensions read from the independent (untrusted)
  // ImageData.Dimensions tags. Real TEM/STEM detectors top out far below this;
  // anything larger is treated as a corrupt/malicious file and rejected before
  // any allocation or pixel-buffer access. Keeps Int64(W)*Int64(H) well-defined
  // and prevents the 32-bit W*H multiply from overflowing.
  MAX_DM3_DIM = 65536;

function DM3TypeSize(TypeCode: Cardinal): Integer;
begin
  case TypeCode of
    2, 4:  Result := 2;  // int16/uint16
    3, 5:  Result := 4;  // int32/uint32
    6:     Result := 4;  // float32
    7:     Result := 8;  // float64
    8:     Result := 1;  // bool
    9:     Result := 1;  // int8/char
    10:    Result := 2;  // uint16 (strings)
    11:    Result := 4;  // uint32
    12:    Result := 8;  // float64
  else
    Result := 1;
  end;
end;


procedure TDM3Metadata.Clear;
begin
  Width := 0;
  Height := 0;
  DataType := 0;
  PixelDepth := 0;
  ScaleX := 0;
  ScaleY := 0;
  Units := '';
  Voltage := 0;
  ActualMagnification := 0;
  IndicatedMagnification := 0;
  Microscope := '';
  CameraName := '';
  AcquisitionDate := '';
  AcquisitionTime := '';
  ExposureTime := 0;
  Cs := 0;
  IlluminationMode := '';
  ImageName := '';
  OperationMode := '';
  BeamCurrent := 0;
  ConvergenceAngle := 0;
  AlphaTilt := 0;
  BetaTilt := 0;
  Defocus := 0;
  STEMCameraLength := 0;
  ProbeSize := 0;
end;


constructor TDM3File.Create;
begin
  inherited;
  FTags := TStringList.Create;
  FTags.CaseSensitive := True;
  FMetadata.Clear;
end;

destructor TDM3File.Destroy;
begin
  FTags.Free;
  FOwnedStream.Free;
  inherited;
end;

procedure TDM3File.SwapBytes2(P: PByte);
var
  T: Byte;
begin
  T := P[0]; P[0] := P[1]; P[1] := T;
end;

procedure TDM3File.SwapBytes4(P: PByte);
var
  T: Byte;
begin
  T := P[0]; P[0] := P[3]; P[3] := T;
  T := P[1]; P[1] := P[2]; P[2] := T;
end;

procedure TDM3File.SwapBytes8(P: PByte);
var
  T: Byte;
begin
  T := P[0]; P[0] := P[7]; P[7] := T;
  T := P[1]; P[1] := P[6]; P[6] := T;
  T := P[2]; P[2] := P[5]; P[5] := T;
  T := P[3]; P[3] := P[4]; P[4] := T;
end;

function TDM3File.ReadBE16: Word;
begin
  FStream.ReadBuffer(Result, 2);
  Result := Swap(Result);
end;

function TDM3File.ReadBE32: Cardinal;
var
  Buf: array[0..3] of Byte;
begin
  FStream.ReadBuffer(Buf, 4);
  Result := (Cardinal(Buf[0]) shl 24) or (Cardinal(Buf[1]) shl 16) or
            (Cardinal(Buf[2]) shl 8) or Cardinal(Buf[3]);
end;

procedure TDM3File.ReadHeader;
var
  ByteOrder: Cardinal;
begin
  FVersion := ReadBE32;
  if FVersion <> 3 then
    raise EDM3Error.CreateFmt('Not a DM3 file (version=%d)', [FVersion]);
  FRootLength := ReadBE32;
  ByteOrder := ReadBE32;
  FLittleEndian := (ByteOrder = 1);
end;

procedure TDM3File.ParseTagGroup(const Path: string; IsRoot: Boolean);
var
  IsSorted: Byte;
  IsOpen: Byte;
  NumTags: Cardinal;
  I: Cardinal;
  TagType: Byte;
  NameLen: Word;
  TagName: AnsiString;
  FullPath: string;
begin
  FStream.ReadBuffer(IsSorted, 1);
  FStream.ReadBuffer(IsOpen, 1);
  NumTags := ReadBE32;

  for I := 0 to NumTags - 1 do
  begin
    // Stop if fewer than 7 bytes remain (min tag: 1 type + 2 name_len + 4 marker)
    if FStream.Position + 7 > FStream.Size then
      Exit;

    FStream.ReadBuffer(TagType, 1);

    NameLen := ReadBE16;
    if NameLen > 0 then
    begin
      SetLength(TagName, NameLen);
      FStream.ReadBuffer(TagName[1], NameLen);
    end
    else
      TagName := AnsiString(IntToStr(I));

    if Path = '' then
      FullPath := string(TagName)
    else
      FullPath := Path + '.' + string(TagName);

    if TagType = 20 then
      ParseTagGroup(FullPath, False)
    else if TagType = 21 then
      ParseTagEntry(FullPath)
    else
      Exit;
  end;
end;

procedure TDM3File.ParseTagEntry(const Path: string);
var
  Marker: array[0..3] of AnsiChar;
  InfoLen: Cardinal;
  Info: array of Cardinal;
  I: Integer;
begin
  FStream.ReadBuffer(Marker, 4);
  if Marker <> '%%%%' then
    raise EDM3Error.Create('Missing %%%% marker at tag ' + Path);

  InfoLen := ReadBE32;
  // DM3 tag-info arrays are small (scalar = 1, array-of-scalar = 3, structs
  // rarely exceed ~20). Cap defensively so a file with InfoLen = $40000000
  // cannot trigger a multi-gigabyte SetLength / OOM before we hit EOF reading
  // the bogus length.
  if InfoLen > 1000 then
    raise EDM3Error.CreateFmt(
      'Implausible tag InfoLen (%d) at tag %s — refusing to allocate.',
      [InfoLen, Path]);

  if (InfoLen = 0) or (Int64(InfoLen) * 4 > FStream.Size - FStream.Position) then
    raise EDM3Error.Create('Truncated tag descriptor at tag ' + Path);

  SetLength(Info, InfoLen);
  for I := 0 to Integer(InfoLen) - 1 do
    Info[I] := ReadBE32;

  ReadTagByInfo(Path, Info);
end;

procedure TDM3File.ReadTagByInfo(const Path: string; const Info: array of Cardinal);
var
  Value: TDM3TagValue;
  FieldCount: Integer;
  ArrayLen: Cardinal;
  ElementSize: Integer;
  TotalSize: Int64;
  Saved: Int64;
  S: string;
  J: Integer;
  Ch: Word;

  function StructSize(CountIndex, FirstFieldIndex, Trailing: Integer): Integer;
  var
    Count: Cardinal;
    K, Size: Integer;
    Required: Int64;
  begin
    if Length(Info) <= CountIndex then
      raise EDM3Error.Create('Truncated struct descriptor at tag ' + Path);
    Count := Info[CountIndex];
    Required := Int64(FirstFieldIndex) + Int64(Count) * 2 + Trailing;
    if Required <> Length(Info) then
      raise EDM3Error.Create('Invalid struct field count at tag ' + Path);
    FieldCount := Integer(Count);
    Result := 0;
    for K := 0 to FieldCount - 1 do
    begin
      Size := DM3TypeSize(Info[FirstFieldIndex + 2 * K + 1]);
      if (Info[FirstFieldIndex + 2 * K + 1] < 2) or
         (Info[FirstFieldIndex + 2 * K + 1] > 12) then
        raise EDM3Error.Create('Unsupported struct field type at tag ' + Path);
      Inc(Result, Size);
    end;
  end;

  procedure RequirePayload(Size: Int64);
  begin
    if (Size < 0) or (Size > FStream.Size - FStream.Position) then
      raise EDM3Error.Create('Truncated tag payload at tag ' + Path);
  end;
begin
  if (Length(Info) = 0) or
     ((Length(Info) = 1) and ((Info[0] = 15) or (Info[0] = 20))) then
    raise EDM3Error.Create('Truncated tag descriptor at tag ' + Path);

  if Length(Info) = 1 then
  begin
    Value := ReadTypedValue(Info[0]);
    AddTag(Path, Value);
    Exit;
  end;

  if Info[0] = 20 then
  begin
    // Array type — inner type is Info[1..N-2], array length is Info[N-1]
    if Info[1] = 15 then
    begin
      // [20, 15, nameLen, fieldCount, (nameLen, fieldType)..., arrayLen]
      ElementSize := StructSize(3, 4, 1);
      ArrayLen := Info[High(Info)];
      TotalSize := Int64(ElementSize) * Int64(ArrayLen);
      RequirePayload(TotalSize);

      Value := Default(TDM3TagValue);
      Value.DataOffset := FStream.Position;
      Value.DataSize := TotalSize;

      // Small single-uint16-field struct array → likely a string
      if (FieldCount = 1) and (Info[5] = 10) and (ArrayLen < 10000) then
      begin
        Saved := FStream.Position;
        S := '';
        for J := 0 to Integer(ArrayLen) - 1 do
        begin
          Ch := ReadBE16;
          if FLittleEndian then
            Ch := Swap(Ch);
          if Ch = 0 then Break;
          S := S + Char(Ch);
        end;
        FStream.Position := Saved;
        Value.StrVal := S;
        Value.IsString := True;
      end;

      FStream.Position := Value.DataOffset + TotalSize;
      AddTag(Path, Value);
    end
    else if Length(Info) = 3 then
    begin
      // Simple array: [20, elementType, arrayLen]
      ArrayLen := Info[High(Info)];
      ElementSize := DM3TypeSize(Info[1]);
      TotalSize := Int64(ElementSize) * Int64(ArrayLen);
      if ElementSize <= 0 then
        raise EDM3Error.Create('Unsupported array element type at tag ' + Path);
      RequirePayload(TotalSize);

      Value := Default(TDM3TagValue);
      Value.DataOffset := FStream.Position;
      Value.DataSize := TotalSize;

      // uint16 array → likely a string
      if (Info[1] = 10) and (ArrayLen < 10000) then
      begin
        Saved := FStream.Position;
        S := '';
        for J := 0 to Integer(ArrayLen) - 1 do
        begin
          Ch := ReadBE16;
          if FLittleEndian then
            Ch := Swap(Ch);
          if Ch = 0 then Break;
          S := S + Char(Ch);
        end;
        FStream.Position := Saved;
        Value.StrVal := S;
        Value.IsString := True;
      end;

      FStream.Position := Value.DataOffset + TotalSize;
      AddTag(Path, Value);
    end
    else
      raise EDM3Error.Create('Invalid array descriptor at tag ' + Path);
  end
  else if Info[0] = 15 then
  begin
    // Single struct: [15, nameLen(0), fieldCount, (0, fieldType)...]
    ElementSize := StructSize(2, 3, 0);
    RequirePayload(ElementSize);

    Value := Default(TDM3TagValue);
    Value.DataOffset := FStream.Position;
    Value.DataSize := ElementSize;
    FStream.Position := FStream.Position + ElementSize;
    AddTag(Path, Value);
  end
  else
  begin
    Value := ReadTypedValue(Info[0]);
    AddTag(Path, Value);
  end;
end;

function TDM3File.ReadTypedValue(TypeCode: Integer): TDM3TagValue;
var
  Buf: array[0..7] of Byte;
begin
  Result := Default(TDM3TagValue);
  case TypeCode of
    2: begin
      FStream.ReadBuffer(Buf, 2);
      if not FLittleEndian then SwapBytes2(@Buf);
      Result.IntVal := SmallInt(PWord(@Buf)^);
    end;
    3: begin
      FStream.ReadBuffer(Buf, 4);
      if not FLittleEndian then SwapBytes4(@Buf);
      Result.IntVal := Integer(PCardinal(@Buf)^);
    end;
    4: begin
      FStream.ReadBuffer(Buf, 2);
      if not FLittleEndian then SwapBytes2(@Buf);
      Result.IntVal := PWord(@Buf)^;
    end;
    5: begin
      FStream.ReadBuffer(Buf, 4);
      if not FLittleEndian then SwapBytes4(@Buf);
      Result.IntVal := PCardinal(@Buf)^;
    end;
    6: begin
      FStream.ReadBuffer(Buf, 4);
      if not FLittleEndian then SwapBytes4(@Buf);
      Result.FloatVal := PSingle(@Buf)^;
      Result.IsFloat := True;
    end;
    7: begin
      FStream.ReadBuffer(Buf, 8);
      if not FLittleEndian then SwapBytes8(@Buf);
      Result.FloatVal := PDouble(@Buf)^;
      Result.IsFloat := True;
    end;
    8: begin
      FStream.ReadBuffer(Buf, 1);
      Result.IntVal := Buf[0];
    end;
    9: begin
      FStream.ReadBuffer(Buf, 1);
      Result.IntVal := ShortInt(Buf[0]);
    end;
    10: begin
      FStream.ReadBuffer(Buf, 2);
      if not FLittleEndian then SwapBytes2(@Buf);
      Result.IntVal := PWord(@Buf)^;
    end;
    11: begin
      FStream.ReadBuffer(Buf, 4);
      if not FLittleEndian then SwapBytes4(@Buf);
      Result.IntVal := PCardinal(@Buf)^;
    end;
    12: begin
      FStream.ReadBuffer(Buf, 8);
      if not FLittleEndian then SwapBytes8(@Buf);
      Result.FloatVal := PDouble(@Buf)^;
      Result.IsFloat := True;
    end;
  else
    FStream.ReadBuffer(Buf, 4);
    Result.IntVal := PCardinal(@Buf)^;
  end;
end;

procedure TDM3File.AddTag(const Path: string; const Value: TDM3TagValue);
var
  Idx: Integer;
begin
  Idx := FTags.Count;
  FTags.Add(Path);
  SetLength(FTagValues, Idx + 1);
  FTagValues[Idx] := Value;
end;

function TDM3File.FindTag(const Path: string): Integer;
begin
  Result := FTags.IndexOf(Path);
end;

function TDM3File.GetTagInt(const Path: string; ADefault: Int64): Int64;
var
  Idx: Integer;
begin
  Idx := FindTag(Path);
  if Idx >= 0 then
  begin
    if FTagValues[Idx].IsFloat then
      Result := Round(FTagValues[Idx].FloatVal)
    else
      Result := FTagValues[Idx].IntVal;
  end
  else
    Result := ADefault;
end;

function TDM3File.GetTagFloat(const Path: string; ADefault: Double): Double;
var
  Idx: Integer;
begin
  Idx := FindTag(Path);
  if Idx >= 0 then
  begin
    if FTagValues[Idx].IsFloat then
      Result := FTagValues[Idx].FloatVal
    else
      Result := FTagValues[Idx].IntVal;
  end
  else
    Result := ADefault;
end;

function TDM3File.GetTagStr(const Path: string; const ADefault: string): string;
var
  Idx: Integer;
begin
  Idx := FindTag(Path);
  if (Idx >= 0) and FTagValues[Idx].IsString then
    Result := FTagValues[Idx].StrVal
  else
    Result := ADefault;
end;

procedure TDM3File.FindImageData;
var
  I: Integer;
  MaxSize, Size: Int64;
  MaxIdx, ThumbIdx: Integer;
  Prefix: string;
begin
  MaxSize := 0;
  MaxIdx := -1;
  ThumbIdx := -1;

  for I := 0 to FTags.Count - 1 do
  begin
    if FTags[I].Contains('ImageList.') and FTags[I].EndsWith('ImageData.Data') then
    begin
      Size := FTagValues[I].DataSize;
      if Size > MaxSize then
      begin
        if MaxIdx >= 0 then
          ThumbIdx := MaxIdx;
        MaxSize := Size;
        MaxIdx := I;
      end
      else if (ThumbIdx < 0) or (Size < FTagValues[ThumbIdx].DataSize) then
        ThumbIdx := I;
    end;
  end;

  if MaxIdx >= 0 then
  begin
    FMainImageOffset := FTagValues[MaxIdx].DataOffset;
    FMainImageSize := FTagValues[MaxIdx].DataSize;

    Prefix := Copy(FTags[MaxIdx], 1, Pos('ImageData.Data', FTags[MaxIdx]) - 1);
    FMetadata.Width := GetTagInt(Prefix + 'ImageData.Dimensions.0', 0);
    FMetadata.Height := GetTagInt(Prefix + 'ImageData.Dimensions.1', 0);
    FMetadata.DataType := GetTagInt(Prefix + 'ImageData.DataType', 0);
    FMetadata.ImageName := GetTagStr(Prefix + 'Name', '');
  end;

  if ThumbIdx >= 0 then
  begin
    FThumbImageOffset := FTagValues[ThumbIdx].DataOffset;
    FThumbImageSize := FTagValues[ThumbIdx].DataSize;

    Prefix := Copy(FTags[ThumbIdx], 1, Pos('ImageData.Data', FTags[ThumbIdx]) - 1);
    FThumbWidth := GetTagInt(Prefix + 'ImageData.Dimensions.0', 0);
    FThumbHeight := GetTagInt(Prefix + 'ImageData.Dimensions.1', 0);
    FThumbDataType := GetTagInt(Prefix + 'ImageData.DataType', 0);
  end;

  case FMetadata.DataType of
    1:  FMetadata.PixelDepth := 2;
    2:  FMetadata.PixelDepth := 4;
    6:  FMetadata.PixelDepth := 1;
    7:  FMetadata.PixelDepth := 4;
    9:  FMetadata.PixelDepth := 1;
    10: FMetadata.PixelDepth := 2;
    11: FMetadata.PixelDepth := 4;
    12: FMetadata.PixelDepth := 8;
    23: FMetadata.PixelDepth := 4;
  end;
end;

procedure TDM3File.ExtractMetadata;
var
  I: Integer;
  Path: string;
begin
  FMetadata.ScaleX := GetTagFloat('ImageList.1.ImageData.Calibrations.Dimension.0.Scale', 0);
  FMetadata.ScaleY := GetTagFloat('ImageList.1.ImageData.Calibrations.Dimension.1.Scale', 0);
  FMetadata.Units := GetTagStr('ImageList.1.ImageData.Calibrations.Dimension.0.Units', '');

  for I := 0 to FTags.Count - 1 do
  begin
    Path := FTags[I];

    if Path.EndsWith('Microscope Info.Voltage') then
      FMetadata.Voltage := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.Actual Magnification') then
      FMetadata.ActualMagnification := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.Indicated Magnification') then
      FMetadata.IndicatedMagnification := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.Microscope') then
      FMetadata.Microscope := GetTagStr(Path)
    else if Path.EndsWith('Microscope Info.Cs(mm)') then
      FMetadata.Cs := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.Illumination Mode') then
      FMetadata.IlluminationMode := GetTagStr(Path)
    else if Path.EndsWith('Microscope Info.Operation Mode') then
      FMetadata.OperationMode := GetTagStr(Path)
    else if Path.EndsWith('Microscope Info.Beam Current (A)') or
            Path.EndsWith('Microscope Info.Beam Current') then
      FMetadata.BeamCurrent := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.Convergence Angle (mrad)') or
            Path.EndsWith('Microscope Info.Convergence Angle') then
      FMetadata.ConvergenceAngle := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.Alpha Tilt (deg)') or
            Path.EndsWith('Microscope Info.Alpha Tilt') then
      FMetadata.AlphaTilt := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.Beta Tilt (deg)') or
            Path.EndsWith('Microscope Info.Beta Tilt') then
      FMetadata.BetaTilt := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.Defocus (nm)') or
            Path.EndsWith('Microscope Info.Defocus') then
      FMetadata.Defocus := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.STEM Camera Length') then
      FMetadata.STEMCameraLength := GetTagFloat(Path)
    else if Path.EndsWith('Microscope Info.Probe Size (nm)') or
            Path.EndsWith('Microscope Info.Probe Size') then
      FMetadata.ProbeSize := GetTagFloat(Path)
    else if Path.EndsWith('Acquisition.Device.Name') then
      FMetadata.CameraName := GetTagStr(Path)
    else if Path.EndsWith('DataBar.Acquisition Date') then
      FMetadata.AcquisitionDate := GetTagStr(Path)
    else if Path.EndsWith('DataBar.Acquisition Time') then
      FMetadata.AcquisitionTime := GetTagStr(Path)
    else if Path.EndsWith('Acquisition.Parameters.High Level.Exposure (s)') then
      FMetadata.ExposureTime := GetTagFloat(Path);
  end;
end;

procedure TDM3File.ParseFromFile(const AFileName: string);
var
  FS: TFileStream;
begin
  FFileName := AFileName;
  FreeAndNil(FOwnedStream);
  FOwnedStream := TMemoryStream.Create;
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    FOwnedStream.CopyFrom(FS, 0);
  finally
    FS.Free;
  end;
  ParseFromStream(FOwnedStream);
end;

procedure TDM3File.ParseFromStream(AStream: TStream);
begin
  FStream := AStream;
  FStream.Position := 0;
  FTags.Clear;
  SetLength(FTagValues, 0);
  FMetadata.Clear;
  FMainImageOffset := 0;
  FMainImageSize := 0;
  FThumbImageOffset := 0;
  FThumbImageSize := 0;

  ReadHeader;
  try
    ParseTagGroup('', True);
  except
    on EReadError do ;
  end;
  FindImageData;
  ExtractMetadata;
end;

procedure TDM3File.SetGrayscalePalette(Bmp: Vcl.Graphics.TBitmap);
var
  Pal: array[0..255] of TRGBQuad;
  I: Integer;
begin
  for I := 0 to 255 do
  begin
    Pal[I].rgbRed := I;
    Pal[I].rgbGreen := I;
    Pal[I].rgbBlue := I;
    Pal[I].rgbReserved := 0;
  end;
  SetDIBColorTable(Bmp.Canvas.Handle, 0, 256, Pal);
end;

function TDM3File.NormalizeToGrayscale8(AOffset, ASize: Int64; W, H, DType: Integer): Vcl.Graphics.TBitmap;
var
  RawBuf: TBytes;
  Pixels: array of Double;
  N, I: Integer;
  ElementSize: Integer;
  MinVal, MaxVal, Range: Double;
  V: Double;
  Gray: Byte;
  Row: PByte;
  X, Y: Integer;
begin
  Result := nil;
  if (W <= 0) or (H <= 0) or (ASize <= 0) then
    Exit;
  // Reject absurd dimensions before any allocation or 32-bit W*H multiply.
  // W/H come from independent Dimensions tags and are not otherwise bounded.
  if (W > MAX_DM3_DIM) or (H > MAX_DM3_DIM) then
    Exit;
  // Reject sizes that extend beyond the file — a crafted DM3 with a bogus
  // array-length tag would otherwise trigger a multi-hundred-MB SetLength
  // before ReadBuffer eventually hits EOF.
  if (AOffset < 0) or (AOffset + ASize > FStream.Size) then
    Exit;

  // Per-pixel byte size for the chosen data type (must match the decode cases
  // below). Unknown types are unrenderable — bail before touching the buffer.
  case DType of
    1, 10:    ElementSize := 2;  // int16 / uint16
    2, 7, 11: ElementSize := 4;  // float32 / int32 / uint32
    6, 9:     ElementSize := 1;  // uint8 / int8
    12:       ElementSize := 8;  // float64
  else
    Exit;
  end;

  // Heap-over-read guard: the recorded Data array (ASize bytes) must be large
  // enough to hold W*H elements. Computed in Int64 to avoid 32-bit overflow on
  // crafted huge dimensions with a tiny Data array.
  if Int64(W) * Int64(H) * ElementSize > ASize then
    Exit;

  N := W * H;
  SetLength(RawBuf, ASize);
  FStream.Position := AOffset;
  FStream.ReadBuffer(RawBuf[0], ASize);

  SetLength(Pixels, N);

  case DType of
    1:
      for I := 0 to N - 1 do
      begin
        if not FLittleEndian then SwapBytes2(@RawBuf[I * 2]);
        Pixels[I] := PSmallInt(@RawBuf[I * 2])^;
      end;
    2:
      for I := 0 to N - 1 do
      begin
        if not FLittleEndian then SwapBytes4(@RawBuf[I * 4]);
        Pixels[I] := PSingle(@RawBuf[I * 4])^;
      end;
    6:
      for I := 0 to N - 1 do
        Pixels[I] := RawBuf[I];
    7:
      for I := 0 to N - 1 do
      begin
        if not FLittleEndian then SwapBytes4(@RawBuf[I * 4]);
        Pixels[I] := PInteger(@RawBuf[I * 4])^;
      end;
    9:
      for I := 0 to N - 1 do
        Pixels[I] := PShortInt(@RawBuf[I])^;
    10:
      for I := 0 to N - 1 do
      begin
        if not FLittleEndian then SwapBytes2(@RawBuf[I * 2]);
        Pixels[I] := PWord(@RawBuf[I * 2])^;
      end;
    11:
      for I := 0 to N - 1 do
      begin
        if not FLittleEndian then SwapBytes4(@RawBuf[I * 4]);
        Pixels[I] := PCardinal(@RawBuf[I * 4])^;
      end;
    12:
      for I := 0 to N - 1 do
      begin
        if not FLittleEndian then SwapBytes8(@RawBuf[I * 8]);
        Pixels[I] := PDouble(@RawBuf[I * 8])^;
      end;
  else
    Exit;
  end;

  MinVal := Pixels[0];
  MaxVal := Pixels[0];
  for I := 1 to N - 1 do
  begin
    if Pixels[I] < MinVal then MinVal := Pixels[I];
    if Pixels[I] > MaxVal then MaxVal := Pixels[I];
  end;

  Range := MaxVal - MinVal;
  if Range < 1E-10 then
    Range := 1;

  Result := Vcl.Graphics.TBitmap.Create;
  try
    Result.PixelFormat := pf8bit;
    Result.SetSize(W, H);
    SetGrayscalePalette(Result);

    for Y := 0 to H - 1 do
    begin
      Row := Result.ScanLine[Y];
      for X := 0 to W - 1 do
      begin
        V := Pixels[Y * W + X];
        Gray := EnsureRange(Round(255 * (V - MinVal) / Range), 0, 255);
        Row[X] := Gray;
      end;
    end;
  except
    FreeAndNil(Result);
  end;
end;

function TDM3File.ReadRGBA(AOffset, ASize: Int64; W, H: Integer): Vcl.Graphics.TBitmap;
var
  RawBuf: TBytes;
  Row: PByte;
  X, Y, Idx, RowOfs: Integer;
begin
  Result := nil;
  if (W <= 0) or (H <= 0) or (ASize <= 0) then
    Exit;
  if (W > MAX_DM3_DIM) or (H > MAX_DM3_DIM) then
    Exit;
  if (AOffset < 0) or (AOffset + ASize > FStream.Size) then
    Exit;
  // Heap-over-read guard: RGBA is 4 bytes/pixel, so the Data array must hold
  // W*H*4 bytes. Int64 math prevents 32-bit overflow on crafted dimensions.
  if Int64(W) * Int64(H) * 4 > ASize then
    Exit;

  SetLength(RawBuf, ASize);
  FStream.Position := AOffset;
  FStream.ReadBuffer(RawBuf[0], ASize);

  Result := Vcl.Graphics.TBitmap.Create;
  try
    Result.PixelFormat := pf32bit;
    Result.SetSize(W, H);

    for Y := 0 to H - 1 do
    begin
      Row := Result.ScanLine[Y];
      for X := 0 to W - 1 do
      begin
        Idx := (Y * W + X) * 4;
        RowOfs := X * 4;
        // DM3 RGBA: R,G,B,A -> TBitmap pf32bit: B,G,R,A
        Row[RowOfs]     := RawBuf[Idx + 2];
        Row[RowOfs + 1] := RawBuf[Idx + 1];
        Row[RowOfs + 2] := RawBuf[Idx];
        Row[RowOfs + 3] := RawBuf[Idx + 3];
      end;
    end;
  except
    FreeAndNil(Result);
  end;
end;

function TDM3File.GetBitmap: Vcl.Graphics.TBitmap;
begin
  if FMetadata.DataType = 23 then
    Result := ReadRGBA(FMainImageOffset, FMainImageSize,
                       FMetadata.Width, FMetadata.Height)
  else
    Result := NormalizeToGrayscale8(FMainImageOffset, FMainImageSize,
                                    FMetadata.Width, FMetadata.Height,
                                    FMetadata.DataType);
end;

function TDM3File.GetThumbnail: Vcl.Graphics.TBitmap;
begin
  Result := nil;
  if (FThumbImageOffset > 0) and (FThumbWidth > 0) and (FThumbHeight > 0) then
  begin
    if FThumbDataType = 23 then
      Result := ReadRGBA(FThumbImageOffset, FThumbImageSize,
                         FThumbWidth, FThumbHeight)
    else
      Result := NormalizeToGrayscale8(FThumbImageOffset, FThumbImageSize,
                                      FThumbWidth, FThumbHeight,
                                      FThumbDataType);
  end;

  if Result = nil then
    Result := GetBitmap;
end;

end.
