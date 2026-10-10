unit unit_TemplateMigrationSeed;

interface

uses
  Aurelius.Engine.ObjectManager;

type
  TTemplateMigrationSeed = class
  public
    // Caller owns transaction lifetime.
    class procedure Run(Mgr: TObjectManager); static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Criteria.Linq,
  unit_Template, unit_EquipmentType;

type
  TMap = TDictionary<string, TArray<string>>;

function BuildReverseMapping: TMap;
  procedure Add(M: TMap; const Cat: string; const Types: array of string);
  var
    Arr: TArray<string>; I: Integer;
  begin
    SetLength(Arr, Length(Types));
    for I := Low(Types) to High(Types) do Arr[I] := Types[I];
    M.AddOrSetValue(LowerCase(Cat), Arr);
  end;
begin
  Result := TMap.Create;
  Add(Result, 'Deposition',     ['Deposition System']);
  Add(Result, 'Treatment',      ['Furnace']);
  Add(Result, 'Simulation',     ['Software']);
  Add(Result, 'Testing',        ['Mechanical Tester']);
  Add(Result, 'Characterization',
    ['AFM', 'Diffractometer', 'Electron Microscope', 'Profiler', 'Spectrometer']);
  Add(Result, 'Measurement',
    ['AFM', 'Diffractometer', 'Electron Microscope', 'Profiler', 'Spectrometer', 'Balance']);
  Add(Result, 'Spectroscopy',   ['Spectrometer']);
end;

function BuildTypeIdIndex(Mgr: TObjectManager): TDictionary<string, Integer>;
var
  All: TList<TEquipmentType>; ET: TEquipmentType;
begin
  Result := TDictionary<string, Integer>.Create;
  All := Mgr.Find<TEquipmentType>.List;
  try
    for ET in All do
      Result.AddOrSetValue(LowerCase(ET.Type_), ET.Id);
  finally
    All.Free;
  end;
end;

function JoinExists(Mgr: TObjectManager; TplId, TypeId: Integer): Boolean;
var
  L: TList<TTemplateEquipmentType>;
begin
  L := Mgr.Find<TTemplateEquipmentType>
    .Where((Linq['FTemplate.Id'] = TplId) and (Linq['FEquipmentType.Id'] = TypeId))
    .List;
  try
    Result := L.Count > 0;
  finally
    L.Free;
  end;
end;

class procedure TTemplateMigrationSeed.Run(Mgr: TObjectManager);
var
  Mapping: TMap;
  TypeIndex: TDictionary<string, Integer>;
  Templates: TList<TTemplate>;
  T: TTemplate;
  CatKey: string;
  TypeNames: TArray<string>;
  TypeName: string;
  TypeId: Integer;
  Tpl: TTemplate;
  ET: TEquipmentType;
  Join: TTemplateEquipmentType;
begin
  Mapping := BuildReverseMapping;
  TypeIndex := BuildTypeIdIndex(Mgr);
  try
    Templates := Mgr.Find<TTemplate>.List;
    try
      for T in Templates do
      begin
        CatKey := LowerCase(T.Category);
        if not Mapping.TryGetValue(CatKey, TypeNames) then Continue;
        for TypeName in TypeNames do
        begin
          if not TypeIndex.TryGetValue(LowerCase(TypeName), TypeId) then Continue;
          if JoinExists(Mgr, T.Id, TypeId) then Continue;
          Tpl := Mgr.Find<TTemplate>(T.Id);
          ET := Mgr.Find<TEquipmentType>(TypeId);
          if (Tpl = nil) or (ET = nil) then Continue;
          Join := TTemplateEquipmentType.Create;
          Join.Template := Tpl;
          Join.EquipmentType := ET;
          Mgr.Save(Join);
        end;
      end;
    finally
      Templates.Free;
    end;
  finally
    Mapping.Free;
    TypeIndex.Free;
  end;
end;

end.
