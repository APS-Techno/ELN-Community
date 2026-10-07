unit unit_TemplateTagsModel;

interface

uses
  Aurelius.Engine.ObjectManager;

type
  TTemplateTagsSnapshot = record
    EquipmentTypeIds: TArray<Integer>;
    EquipmentIds: TArray<Integer>;
  end;

  TTemplateTagsModel = class
  public
    /// <summary>Read existing tag rows from the join tables for the given
    /// template. Empty arrays when no rows. Caller manages transaction.</summary>
    class function LoadTagsFor(Mgr: TObjectManager;
      TemplateId: Integer): TTemplateTagsSnapshot; static;
    /// <summary>Idempotent diff: insert rows for ids in the snapshot that
    /// aren't already present; remove rows that exist but aren't in the
    /// snapshot. Caller is responsible for the transaction lifetime —
    /// SaveTagsFor does not Flush.</summary>
    class procedure SaveTagsFor(Mgr: TObjectManager;
      TemplateId: Integer; const Snap: TTemplateTagsSnapshot); static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Criteria.Linq,
  unit_Template, unit_Equipment, unit_EquipmentType;

function ToSet(const A: TArray<Integer>): TDictionary<Integer, Boolean>;
var
  I: Integer;
begin
  Result := TDictionary<Integer, Boolean>.Create;
  for I in A do
    Result.AddOrSetValue(I, True);
end;

class function TTemplateTagsModel.LoadTagsFor(Mgr: TObjectManager;
  TemplateId: Integer): TTemplateTagsSnapshot;
var
  TypeJoins: TList<TTemplateEquipmentType>;
  EqJoins: TList<TTemplateEquipment>;
  I: Integer;
begin
  TypeJoins := Mgr.Find<TTemplateEquipmentType>
    .Where(Linq['FTemplate.Id'] = TemplateId)
    .List;
  try
    SetLength(Result.EquipmentTypeIds, TypeJoins.Count);
    for I := 0 to TypeJoins.Count - 1 do
      Result.EquipmentTypeIds[I] := TypeJoins[I].EquipmentType.Id;
  finally
    TypeJoins.Free;
  end;
  EqJoins := Mgr.Find<TTemplateEquipment>
    .Where(Linq['FTemplate.Id'] = TemplateId)
    .List;
  try
    SetLength(Result.EquipmentIds, EqJoins.Count);
    for I := 0 to EqJoins.Count - 1 do
      Result.EquipmentIds[I] := EqJoins[I].Equipment.Id;
  finally
    EqJoins.Free;
  end;
end;

class procedure TTemplateTagsModel.SaveTagsFor(Mgr: TObjectManager;
  TemplateId: Integer; const Snap: TTemplateTagsSnapshot);
var
  T: TTemplate;
  ET: TEquipmentType; E: TEquipment;
  WantTypes, WantEquip: TDictionary<Integer, Boolean>;
  HaveTypeIds, HaveEqIds: TDictionary<Integer, Boolean>;
  ExistingType: TList<TTemplateEquipmentType>;
  ExistingEq: TList<TTemplateEquipment>;
  TypeJoin: TTemplateEquipmentType;
  EqJoin: TTemplateEquipment;
  I: Integer;
begin
  T := Mgr.Find<TTemplate>(TemplateId);
  if T = nil then
    raise Exception.CreateFmt('TemplateId %d not found', [TemplateId]);

  WantTypes := ToSet(Snap.EquipmentTypeIds);
  WantEquip := ToSet(Snap.EquipmentIds);
  HaveTypeIds := TDictionary<Integer, Boolean>.Create;
  HaveEqIds   := TDictionary<Integer, Boolean>.Create;
  try
    ExistingType := Mgr.Find<TTemplateEquipmentType>
      .Where(Linq['FTemplate.Id'] = TemplateId).List;
    try
      for TypeJoin in ExistingType do
      begin
        if WantTypes.ContainsKey(TypeJoin.EquipmentType.Id) then
          HaveTypeIds.AddOrSetValue(TypeJoin.EquipmentType.Id, True)
        else
          Mgr.Remove(TypeJoin);
      end;
    finally
      ExistingType.Free;
    end;

    ExistingEq := Mgr.Find<TTemplateEquipment>
      .Where(Linq['FTemplate.Id'] = TemplateId).List;
    try
      for EqJoin in ExistingEq do
      begin
        if WantEquip.ContainsKey(EqJoin.Equipment.Id) then
          HaveEqIds.AddOrSetValue(EqJoin.Equipment.Id, True)
        else
          Mgr.Remove(EqJoin);
      end;
    finally
      ExistingEq.Free;
    end;

    for I in Snap.EquipmentTypeIds do
      if not HaveTypeIds.ContainsKey(I) then
      begin
        ET := Mgr.Find<TEquipmentType>(I);
        if ET = nil then Continue;
        TypeJoin := TTemplateEquipmentType.Create;
        TypeJoin.Template := T;
        TypeJoin.EquipmentType := ET;
        Mgr.Save(TypeJoin);
      end;

    for I in Snap.EquipmentIds do
      if not HaveEqIds.ContainsKey(I) then
      begin
        E := Mgr.Find<TEquipment>(I);
        if E = nil then Continue;
        EqJoin := TTemplateEquipment.Create;
        EqJoin.Template := T;
        EqJoin.Equipment := E;
        Mgr.Save(EqJoin);
      end;
  finally
    WantTypes.Free;
    WantEquip.Free;
    HaveTypeIds.Free;
    HaveEqIds.Free;
  end;
end;

end.
