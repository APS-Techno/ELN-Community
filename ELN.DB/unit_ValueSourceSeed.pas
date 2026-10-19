unit unit_ValueSourceSeed;

// Kept below ELN.Model so the local notebook and the Commercial schema update
// seed the same rows without reversing the ELN.Model -> ELN.DB dependency.

interface

uses
  Aurelius.Engine.ObjectManager;

type
  TValueSourceSeed = class
  public
    // Adds missing default reader mappings and the value types they and the
    // built-in Derived formulas need. Existing rows are never changed.
    class procedure SeedDefaults(Manager: TObjectManager); static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_ValueType,
  unit_ReaderValueMapping;

class procedure TValueSourceSeed.SeedDefaults(Manager: TObjectManager);
var
  Types: TList<TValueType>;
  Rows: TList<TReaderValueMapping>;

  function EnsureType(const Title, Units: string): TValueType;
  var
    VT: TValueType;
  begin
    for VT in Types do
      if SameText(VT.Title, Title) and (VT.Units = Units) then
        Exit(VT);
    Result := TValueType.Create;
    Result.Title := Title;
    Result.Symbol := Title;
    if Title = 'Thickness' then Result.Symbol := 'd'
    else if Title = 'Roughness' then Result.Symbol := #$03C3
    else if Title = 'Power' then Result.Symbol := 'W'
    else if Title = 'Current' then Result.Symbol := 'I'
    else if Title = 'Voltage' then Result.Symbol := 'U'
    else if Title = 'Pressure' then Result.Symbol := 'P'
    else if Title = 'Time' then Result.Symbol := 't'
    else if Title = 'Flow' then Result.Symbol := 'F'
    else if Title = 'Hardness' then Result.Symbol := 'H'
    else if Title = 'Modulus' then Result.Symbol := 'E'
    else if Title = 'COF' then Result.Symbol := #$03BC
    else if Title = 'Wear rate' then Result.Symbol := 'WR';
    Result.Units := Units;
    Result.CatID := 0;
    Result.CreatedDate := Now;
    Manager.Save(Result);
    Types.Add(Result);
  end;

  procedure Add(const Reader, Key, UnitText, Title, TargetUnits: string;
    Factor: Double; const LabelText: string = '');
  var
    Row: TReaderValueMapping;
  begin
    for Row in Rows do
      if (Row.ReaderId = Reader) and (Row.KeyPattern = Key) and
        (Row.ReaderUnits = UnitText) then
        Exit;
    Row := TReaderValueMapping.Create;
    Row.ReaderId := Reader;
    Row.KeyPattern := Key;
    Row.ReaderUnits := UnitText;
    Row.ValueType := EnsureType(Title, TargetUnits);
    Row.Factor := Factor;
    Row.LabelText := LabelText;
    Manager.Save(Row);
    Rows.Add(Row);
  end;

  procedure UnitRules(const Reader, Pattern: string);
  begin
    Add(Reader, Pattern, 'mTorr', 'Pressure', 'Pa', 0.133322);
    Add(Reader, Pattern, 'Torr', 'Pressure', 'Pa', 133.322);
    Add(Reader, Pattern, 'sccm', 'Flow', 'sccm', 1);
    Add(Reader, Pattern, 'mA', 'Current', 'A', 0.001);
    Add(Reader, Pattern, 's', 'Time', 's', 1);
    Add(Reader, Pattern, 'sec', 'Time', 's', 1);
    Add(Reader, Pattern, 'min', 'Time', 's', 60);
    Add(Reader, Pattern, 'us', 'Time', 's', 1e-6);
    Add(Reader, Pattern, 'kHz', 'Frequency', 'Hz', 1000);
    Add(Reader, Pattern, '%', 'Duty cycle', '%', 1);
    Add(Reader, Pattern, 'W', 'Power', 'W', 1);
    Add(Reader, Pattern, 'V', 'Voltage', 'V', 1);
    Add(Reader, Pattern, 'mm', 'Distance', 'm', 0.001);
  end;

  procedure RecipeRows(const Reader: string);
  begin
    Add(Reader, 'Parameters.PowerBN', 'W', 'Power', 'W', 1, 'BN');
    Add(Reader, 'Parameters.CurrentC', 'mA', 'Current', 'A', 0.001, 'C');
    Add(Reader, 'Parameters.TimeBN', 's', 'Time', 's', 1, 'BN');
    Add(Reader, 'Parameters.TimeC', 's', 'Time', 's', 1, 'C');
    Add(Reader, 'Parameters.TimeCtop', 's', 'Time', 's', 1, 'C top');
    Add(Reader, 'Parameters.N', '', 'Periods', '', 1);
    Add(Reader, 'Deposition Conditions.N', 'N', 'Periods', '', 1);
    UnitRules(Reader, 'Parameters.<Any>');
    UnitRules(Reader, 'Deposition Conditions.<Any>');
    UnitRules(Reader, 'Layer <Material>.<Any>');
  end;

begin
  Types := Manager.Find<TValueType>.List;
  try
    Rows := Manager.Find<TReaderValueMapping>.List;
    try
      Add('aps.xrcx', 'Period', 'A', 'Period', 'm', 1e-10);
      Add('aps.xrcx', '<Material> Thickness', 'A', 'Thickness', 'm', 1e-10);
      Add('aps.xrcx', '<Material> Roughness', 'A', 'Roughness', 'm', 1e-10);
      Add('aps.xrcx', 'Chi2', '', 'Chi2', '', 1);
      Add('aps.zrw', 'Fn', 'N', 'Normal force', 'N', 1);
      Add('aps.zrw', 'Cycles', '', 'Cycles', '', 1);
      Add('aps.zrw', 'Stroke', 'mm', 'Stroke', 'mm', 1);
      Add('aps.zrw', 'Speed', 'mm/s', 'Speed', 'mm/s', 1);
      Add('aps.zrw', 'COF', '', 'COF', '', 1);
      Add('aps.fibps', 'Step Height', 'um', 'Thickness', 'm', 1e-6);
      Add('aps.fibps', 'Wear Area', 'um2', 'Wear area', 'mm' + #$00B2, 1e-6);
      Add('aps.fibps', 'Wear Volume', 'um3', 'Wear volume', 'mm' + #$00B3, 1e-9);
      Add('aps.mit', 'Hardness', 'GPa', 'Hardness', 'GPa', 1);
      Add('aps.mit', 'Modulus', 'GPa', 'Modulus', 'GPa', 1);
      Add('aps.deposition', 'Duration', 's', 'Time', 's', 1);
      Add('aps.deposition', 'BasePressure', 'Torr', 'Pressure', 'Pa', 133.322);
      RecipeRows('aps.recipe');
      RecipeRows('aps.deposition');
      EnsureType('Wear rate', 'mm' + #$00B3 + '/(N' + #$00B7 + 'mm)');
      Manager.Flush;
    finally
      Rows.Free;
    end;
  finally
    Types.Free;
  end;
end;

end.
