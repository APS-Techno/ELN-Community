unit unit_JSONCompact;

interface

uses
  System.JSON;

function SmartNum(const Value: Double): TJSONNumber;

/// Shortest text (15 to 17 significant digits) that parses back to the
/// identical Double; integral values up to 2^53 as integers; NaN and
/// infinity as null. Caller owns the result.
function ExactNum(const Value: Double): TJSONValue;

{ Deep-clone a JSON value tree, rounding all numbers to 6 significant digits.
  Caller owns the returned value; Source is NOT freed. }
function CompactJSON(const Source: TJSONValue): TJSONValue;

implementation

uses
  System.SysUtils, System.Math;

var
  JSONFmt: TFormatSettings;

function SmartNum(const Value: Double): TJSONNumber;
var
  S: string;
begin
  if Value = 0 then
    Exit(TJSONNumber.Create(0));

  if (Frac(Value) = 0) and (Abs(Value) < MaxInt) then
    Exit(TJSONNumber.Create(Trunc(Value)));

  S := Format('%.6g', [Value], JSONFmt);
  Result := TJSONNumber.Create(StrToFloat(S, JSONFmt));
end;

{$IFDEF MSWINDOWS}
// Delphi's Win64 float/text conversion is not correctly rounded in the last
// digit; the UCRT digit generator and parser are.
function crt_ecvt_s(Buffer: PAnsiChar; SizeInBytes: NativeUInt; Value: Double;
  Count: Integer; Dec, Sign: PInteger): Integer; cdecl;
  external 'ucrtbase.dll' name '_ecvt_s';
function crt_strtod(Str: PAnsiChar; EndPtr: PPAnsiChar): Double; cdecl;
  external 'ucrtbase.dll' name 'strtod';

function DigitsText(const Digits: string; Dec, Precision: Integer;
  Negative: Boolean): string;
var
  Count, Exponent: Integer;
begin
  Count := Length(Digits);
  Exponent := Dec - 1;
  if (Exponent < -4) or (Exponent >= Precision) then
  begin
    Result := Digits[1];
    if Count > 1 then
      Result := Result + '.' + Copy(Digits, 2, MaxInt);
    if Exponent >= 0 then
      Result := Result + 'e+' + IntToStr(Exponent)
    else
      Result := Result + 'e-' + IntToStr(-Exponent);
  end
  else if Dec <= 0 then
    Result := '0.' + StringOfChar('0', -Dec) + Digits
  else if Dec >= Count then
    Result := Digits + StringOfChar('0', Dec - Count)
  else
    Result := Copy(Digits, 1, Dec) + '.' + Copy(Digits, Dec + 1, MaxInt);
  if Negative then
    Result := '-' + Result;
end;

function ExactText(const Value: Double): string;
var
  Buffer: array[0..31] of AnsiChar;
  Precision, Dec, Sign: Integer;
  Digits: string;
  Text: AnsiString;
  Stop: PAnsiChar;
begin
  for Precision := 15 to 17 do
  begin
    if crt_ecvt_s(@Buffer[0], Length(Buffer), Value, Precision, @Dec, @Sign) <> 0 then
      raise EConvertError.Create('A number could not be formatted.');
    Digits := string(AnsiString(PAnsiChar(@Buffer[0])));
    while (Length(Digits) > 1) and (Digits[Length(Digits)] = '0') do
      SetLength(Digits, Length(Digits) - 1);
    Result := DigitsText(Digits, Dec, Precision, Sign <> 0);
    Text := AnsiString(Result);
    if crt_strtod(PAnsiChar(Text), @Stop) = Value then
      Exit;
  end;
end;
{$ELSE}
function ExactText(const Value: Double): string;
var
  Digits: Integer;
  Back: Double;
begin
  for Digits := 15 to 17 do
  begin
    Result := FloatToStrF(Value, ffGeneral, Digits, 0, JSONFmt);
    if TryStrToFloat(Result, Back, JSONFmt) and (Back = Value) then
      Exit;
  end;
end;
{$ENDIF}

function ExactNum(const Value: Double): TJSONValue;
const
  MAX_EXACT_INTEGER = 9007199254740992.0;
begin
  if IsNan(Value) or IsInfinite(Value) then
    Exit(TJSONNull.Create);
  if (Value = 0) and (PInt64(@Value)^ < 0) then
    Exit(TJSONNumber.Create('-0'));
  if (Frac(Value) = 0) and (Abs(Value) <= MAX_EXACT_INTEGER) then
    Exit(TJSONNumber.Create(Trunc(Value)));
  Result := TJSONNumber.Create(ExactText(Value));
end;

function CompactJSON(const Source: TJSONValue): TJSONValue;
var
  SrcObj: TJSONObject;
  SrcArr: TJSONArray;
  Pair: TJSONPair;
  I: Integer;
begin
  if Source is TJSONObject then
  begin
    SrcObj := TJSONObject(Source);
    Result := TJSONObject.Create;
    for I := 0 to SrcObj.Count - 1 do
    begin
      Pair := SrcObj.Pairs[I];
      TJSONObject(Result).AddPair(Pair.JsonString.Value,
        CompactJSON(Pair.JsonValue));
    end;
  end
  else if Source is TJSONArray then
  begin
    SrcArr := TJSONArray(Source);
    Result := TJSONArray.Create;
    for I := 0 to SrcArr.Count - 1 do
      TJSONArray(Result).AddElement(CompactJSON(SrcArr.Items[I]));
  end
  else if Source is TJSONNumber then
    Result := SmartNum(TJSONNumber(Source).AsDouble)
  else if Source is TJSONString then
    Result := TJSONString.Create(TJSONString(Source).Value)
  else if Source is TJSONBool then
    Result := TJSONBool.Create(TJSONBool(Source).AsBoolean)
  else if Source is TJSONNull then
    Result := TJSONNull.Create
  else
    Result := TJSONNull.Create;
end;

initialization
  JSONFmt := TFormatSettings.Create;
  JSONFmt.DecimalSeparator := '.';

end.
