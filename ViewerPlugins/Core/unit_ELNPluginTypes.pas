unit unit_ELNPluginTypes;


interface

uses
  System.JSON;

type
  TPluginRecType = (prCondition, prResult);

  TPluginKeyValue = record
    Name: string;
    Value: Double;
    Units: string;
    Description: string;
    RecType: TPluginRecType;
    IsKey: Boolean;
  end;

{ Create a TJSONNumber rounded to 6 significant digits.
  Use this instead of TJSONNumber.Create(Double) in GetDetailedInfo
  to avoid emitting 15-digit floats. }
function JNum(const Value: Double): TJSONNumber;

implementation

uses
  System.SysUtils;

var
  JSONFmt: TFormatSettings;

function JNum(const Value: Double): TJSONNumber;
var
  S: string;
begin
  if Value = 0 then
    Exit(TJSONNumber.Create(0));
  if (Frac(Value) = 0) and (Abs(Value) < MaxInt) then
    Exit(TJSONNumber.Create(Trunc(Value)));
  S := Format('%.6g', [Value], JSONFmt);
  Result := TJSONNumber.Create(S);
end;

initialization
  JSONFmt := TFormatSettings.Create;
  JSONFmt.DecimalSeparator := '.';

end.
