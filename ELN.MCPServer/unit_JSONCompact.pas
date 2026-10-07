unit unit_JSONCompact;

interface

uses
  System.JSON;

{ Create a TJSONNumber with smart rounding (6 significant digits max).
  Integer values are emitted as integers for compactness. }
function SmartNum(const Value: Double): TJSONNumber;

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

  // Integer values: emit without decimal point
  if (Frac(Value) = 0) and (Abs(Value) < MaxInt) then
    Exit(TJSONNumber.Create(Trunc(Value)));

  // Round to 6 significant digits via %.6g (shortest representation)
  S := Format('%.6g', [Value], JSONFmt);
  Result := TJSONNumber.Create(StrToFloat(S, JSONFmt));
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
