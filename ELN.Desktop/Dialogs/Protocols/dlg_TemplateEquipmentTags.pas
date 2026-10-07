unit dlg_TemplateEquipmentTags;

interface

uses
  System.SysUtils, System.Generics.Collections, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.CheckLst, Vcl.ExtCtrls, Vcl.Controls,
  RzPanel, RzButton, RzLabel,
  unit_EquipmentType, unit_Equipment;

type
  TdlgTemplateEquipmentTags = class(TForm)
    pnlBottom: TRzPanel;
    btnOK: TRzButton;
    btnCancel: TRzButton;
    pnlLeft: TRzPanel;
    lblTypes: TRzLabel;
    clbTypes: TCheckListBox;
    pnlRight: TRzPanel;
    lblDevices: TRzLabel;
    clbDevices: TCheckListBox;
    spltMid: TSplitter;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure clbTypesClickCheck(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
  private
    FTypes: TList<TEquipmentType>;     // reference only — not owned
    FAllDevices: TList<TEquipment>;    // reference only — not owned
    FSelectedTypeIds: TList<Integer>;
    FSelectedDeviceIds: TList<Integer>;
    procedure RebuildDevicesPane;
    function CheckedTypeIds: TList<Integer>;
    function CheckedDeviceIds: TList<Integer>;
  public
    procedure Setup(AllTypes: TList<TEquipmentType>; AllDevices: TList<TEquipment>;
      const InitialTypeIds, InitialDeviceIds: TArray<Integer>);
    function ResultTypeIds: TArray<Integer>;
    function ResultDeviceIds: TArray<Integer>;
  end;

implementation

{$R *.dfm}

procedure TdlgTemplateEquipmentTags.FormCreate(Sender: TObject);
begin
  FSelectedTypeIds := TList<Integer>.Create;
  FSelectedDeviceIds := TList<Integer>.Create;
end;

procedure TdlgTemplateEquipmentTags.FormDestroy(Sender: TObject);
begin
  FSelectedTypeIds.Free;
  FSelectedDeviceIds.Free;
end;

procedure TdlgTemplateEquipmentTags.Setup(AllTypes: TList<TEquipmentType>;
  AllDevices: TList<TEquipment>; const InitialTypeIds, InitialDeviceIds: TArray<Integer>);
var
  ET: TEquipmentType;
  I: Integer;
  IdSet: TDictionary<Integer, Boolean>;
begin
  FTypes := AllTypes;
  FAllDevices := AllDevices;
  FSelectedTypeIds.Clear;
  for I in InitialTypeIds do FSelectedTypeIds.Add(I);
  FSelectedDeviceIds.Clear;
  for I in InitialDeviceIds do FSelectedDeviceIds.Add(I);

  clbTypes.Items.BeginUpdate;
  try
    clbTypes.Items.Clear;
    IdSet := TDictionary<Integer, Boolean>.Create;
    try
      for I in InitialTypeIds do IdSet.AddOrSetValue(I, True);
      for ET in FTypes do
      begin
        clbTypes.Items.AddObject(ET.Type_, TObject(ET.Id));
        clbTypes.Checked[clbTypes.Items.Count - 1] := IdSet.ContainsKey(ET.Id);
      end;
    finally
      IdSet.Free;
    end;
  finally
    clbTypes.Items.EndUpdate;
  end;
  RebuildDevicesPane;
end;

procedure TdlgTemplateEquipmentTags.clbTypesClickCheck(Sender: TObject);
begin
  RebuildDevicesPane;
end;

procedure TdlgTemplateEquipmentTags.RebuildDevicesPane;
var
  CheckedTypes: TList<Integer>;
  TypeSet: TDictionary<Integer, Boolean>;
  DevIdSet: TDictionary<Integer, Boolean>;
  E: TEquipment;
  I: Integer;
  TypeName: string;
begin
  CheckedTypes := CheckedTypeIds;
  TypeSet := TDictionary<Integer, Boolean>.Create;
  DevIdSet := TDictionary<Integer, Boolean>.Create;
  try
    for I in CheckedTypes do TypeSet.AddOrSetValue(I, True);
    for I in FSelectedDeviceIds do DevIdSet.AddOrSetValue(I, True);

    clbDevices.Items.BeginUpdate;
    try
      clbDevices.Items.Clear;
      for E in FAllDevices do
      begin
        if not Assigned(E.EquipmentType) then Continue;
        if not TypeSet.ContainsKey(E.EquipmentType.Id) then Continue;
        TypeName := E.EquipmentType.Type_;
        clbDevices.Items.AddObject(E.Model + '  [' + TypeName + ']',
          TObject(E.Id));
        clbDevices.Checked[clbDevices.Items.Count - 1] := DevIdSet.ContainsKey(E.Id);
      end;
    finally
      clbDevices.Items.EndUpdate;
    end;
  finally
    CheckedTypes.Free;
    TypeSet.Free;
    DevIdSet.Free;
  end;
end;

function TdlgTemplateEquipmentTags.CheckedTypeIds: TList<Integer>;
var
  I: Integer;
begin
  Result := TList<Integer>.Create;
  for I := 0 to clbTypes.Items.Count - 1 do
    if clbTypes.Checked[I] then
      Result.Add(NativeInt(clbTypes.Items.Objects[I]));
end;

function TdlgTemplateEquipmentTags.CheckedDeviceIds: TList<Integer>;
var
  I: Integer;
begin
  Result := TList<Integer>.Create;
  for I := 0 to clbDevices.Items.Count - 1 do
    if clbDevices.Checked[I] then
      Result.Add(NativeInt(clbDevices.Items.Objects[I]));
end;

procedure TdlgTemplateEquipmentTags.btnOKClick(Sender: TObject);
var
  CT, CD: TList<Integer>;
  I: Integer;
begin
  CT := CheckedTypeIds;
  CD := CheckedDeviceIds;
  try
    FSelectedTypeIds.Clear;
    for I in CT do FSelectedTypeIds.Add(I);
    FSelectedDeviceIds.Clear;
    for I in CD do FSelectedDeviceIds.Add(I);
  finally
    CT.Free;
    CD.Free;
  end;
  ModalResult := mrOk;
end;

function TdlgTemplateEquipmentTags.ResultTypeIds: TArray<Integer>;
begin
  Result := FSelectedTypeIds.ToArray;
end;

function TdlgTemplateEquipmentTags.ResultDeviceIds: TArray<Integer>;
begin
  Result := FSelectedDeviceIds.ToArray;
end;

end.
