unit dlg_AuditRuleEditor;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.CheckLst, Vcl.Dialogs,
  RzLabel, RzButton, RzPanel, RzEdit,
  unit_AuditRule, unit_AuditModel;

type
  TdlgAuditRuleEditor = class(TForm)
    pnlLeft: TRzPanel;
    lbRules: TListBox;
    pnlLeftButtons: TRzPanel;
    btnAdd: TRzButton;
    btnDelete: TRzButton;
    pnlRight: TRzPanel;
    pnlRightButtons: TRzPanel;
    btnSave: TRzButton;
    pnlContent: TRzPanel;
    lblTitle: TRzLabel;
    lblActionType: TRzLabel;
    lblEquipment: TRzLabel;
    lblSeverity: TRzLabel;
    lblDescription: TRzLabel;
    lblFileTypes: TRzLabel;
    lblValueTypes: TRzLabel;
    edTitle: TRzEdit;
    cbActionType: TComboBox;
    cbEquipment: TComboBox;
    cbSeverity: TComboBox;
    chkActive: TCheckBox;
    memDescription: TMemo;
    clbFileTypes: TCheckListBox;
    clbValueTypes: TCheckListBox;
    procedure DoAddRule(Sender: TObject);
    procedure DoDeleteRule(Sender: TObject);
    procedure DoSaveRule(Sender: TObject);
    procedure DoRuleSelect(Sender: TObject);
  private
    FRules: TAuditRules;
    FCurrentRule: TAuditRule;
    FActionTypeIds: TList<Integer>;
    FEquipmentIds: TList<Integer>;
    FFileTypeIds: TList<Integer>;
    FValueTypeIds: TList<Integer>;

    procedure LoadRules;
    procedure LoadLookups;
    procedure SelectRule(Index: Integer);
    function ValidateCurrentRule: Boolean;
    procedure SaveCurrentRule;
    procedure EnableEditor(Enable: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    class procedure Execute;
  end;

implementation

{$R *.dfm}

uses
  unit_DataModel,
  unit_ActionType,
  unit_Equipment,
  unit_FileType,
  unit_ValueType,
  unit_User,
  unit_TimeHelper;

{ TdlgAuditRuleEditor }

constructor TdlgAuditRuleEditor.Create(AOwner: TComponent);
begin
  inherited;
  FActionTypeIds := TList<Integer>.Create;
  FEquipmentIds := TList<Integer>.Create;
  FFileTypeIds := TList<Integer>.Create;
  FValueTypeIds := TList<Integer>.Create;
end;

destructor TdlgAuditRuleEditor.Destroy;
begin
  FreeAndNil(FValueTypeIds);
  FreeAndNil(FFileTypeIds);
  FreeAndNil(FEquipmentIds);
  FreeAndNil(FActionTypeIds);
  inherited;
end;

procedure TdlgAuditRuleEditor.LoadLookups;
var
  ActionTypes: TActionTypes;
  AT: TActionType;
  Equipments: TEquipments;
  Eq: TEquipment;
  FileTypes: TFileTypes;
  FT: TFileType;
  ValueTypes: TList<TValueType>;
  VT: TValueType;
begin
  { Action Types }
  cbActionType.Items.Clear;
  FActionTypeIds.Clear;
  ActionTypes := Model.Manager.Find<TActionType>.List;
  try
    for AT in ActionTypes do
    begin
      cbActionType.Items.Add(AT.Title);
      FActionTypeIds.Add(AT.Id);
    end;
  finally
    ActionTypes.Free;
  end;

  { Equipments }
  cbEquipment.Items.Clear;
  FEquipmentIds.Clear;
  Equipments := Model.Manager.Find<TEquipment>.List;
  try
    for Eq in Equipments do
    begin
      cbEquipment.Items.Add(Eq.Model + ' - ' + Eq.Manufacturer);
      FEquipmentIds.Add(Eq.Id);
    end;
  finally
    Equipments.Free;
  end;

  { File Types }
  clbFileTypes.Items.Clear;
  FFileTypeIds.Clear;
  FileTypes := Model.Manager.Find<TFileType>.List;
  try
    for FT in FileTypes do
    begin
      clbFileTypes.Items.Add(FT.Ext + ' - ' + FT.Description);
      FFileTypeIds.Add(FT.Id);
    end;
  finally
    FileTypes.Free;
  end;

  { Value Types }
  clbValueTypes.Items.Clear;
  FValueTypeIds.Clear;
  ValueTypes := Model.Manager.Find<TValueType>.List;
  try
    for VT in ValueTypes do
    begin
      clbValueTypes.Items.Add(VT.Symbol + ' - ' + VT.Title + ' (' + VT.Units + ')');
      FValueTypeIds.Add(VT.Id);
    end;
  finally
    ValueTypes.Free;
  end;

  { Severity }
  cbSeverity.Items.Clear;
  cbSeverity.Items.Add('Error');
  cbSeverity.Items.Add('Warning');
end;

procedure TdlgAuditRuleEditor.LoadRules;
var
  Rule: TAuditRule;
  Display: string;
begin
  FRules := Model.AuditRules.GetAllRules;
  lbRules.Items.Clear;
  for Rule in FRules do
  begin
    Display := Rule.Title;
    if not Rule.IsActive then
      Display := Display + ' (inactive)';
    lbRules.Items.Add(Display);
  end;

  FCurrentRule := nil;
  if lbRules.Items.Count > 0 then
  begin
    lbRules.ItemIndex := 0;
    SelectRule(0);
  end
  else
    EnableEditor(False);
end;

procedure TdlgAuditRuleEditor.SelectRule(Index: Integer);
var
  I: Integer;
  RuleFile: TAuditRuleFile;
  RuleValue: TAuditRuleValue;
  IdxFound: Integer;
begin
  if (Index < 0) or (Index >= FRules.Count) then
  begin
    EnableEditor(False);
    Exit;
  end;

  FCurrentRule := FRules[Index];
  EnableEditor(True);

  { Title }
  edTitle.Text := FCurrentRule.Title;

  { Severity }
  cbSeverity.ItemIndex := Ord(FCurrentRule.Severity);

  { Active }
  chkActive.Checked := FCurrentRule.IsActive;

  { Description }
  memDescription.Text := FCurrentRule.Description;

  { Clear all lookups first }
  cbActionType.ItemIndex := -1;
  cbEquipment.ItemIndex := -1;
  for I := 0 to clbFileTypes.Count - 1 do
    clbFileTypes.Checked[I] := False;
  for I := 0 to clbValueTypes.Count - 1 do
    clbValueTypes.Checked[I] := False;

  { Skip proxy access for new (unpersisted) rules }
  if FCurrentRule.Id = 0 then
    Exit;

  { Action Type }
  if Assigned(FCurrentRule.ActionType) then
  begin
    IdxFound := FActionTypeIds.IndexOf(FCurrentRule.ActionType.Id);
    if IdxFound >= 0 then
      cbActionType.ItemIndex := IdxFound;
  end;

  { Equipment }
  if Assigned(FCurrentRule.Equipment) then
  begin
    IdxFound := FEquipmentIds.IndexOf(FCurrentRule.Equipment.Id);
    if IdxFound >= 0 then
      cbEquipment.ItemIndex := IdxFound;
  end;

  { Required File Types }
  for RuleFile in FCurrentRule.RequiredFiles do
  begin
    if Assigned(RuleFile.FileType) then
    begin
      IdxFound := FFileTypeIds.IndexOf(RuleFile.FileType.Id);
      if IdxFound >= 0 then
        clbFileTypes.Checked[IdxFound] := True;
    end;
  end;

  { Required Value Types }
  for RuleValue in FCurrentRule.RequiredValues do
  begin
    if Assigned(RuleValue.ValueType) then
    begin
      IdxFound := FValueTypeIds.IndexOf(RuleValue.ValueType.Id);
      if IdxFound >= 0 then
        clbValueTypes.Checked[IdxFound] := True;
    end;
  end;
end;

function TdlgAuditRuleEditor.ValidateCurrentRule: Boolean;
var
  I: Integer;
  HasChecked: Boolean;
begin
  Result := False;

  if Trim(edTitle.Text) = '' then
  begin
    MessageDlg('Title is required.', mtWarning, [mbOK], 0);
    edTitle.SetFocus;
    Exit;
  end;

  if cbActionType.ItemIndex < 0 then
  begin
    MessageDlg('Please select an Action Type.', mtWarning, [mbOK], 0);
    cbActionType.SetFocus;
    Exit;
  end;

  if cbEquipment.ItemIndex < 0 then
  begin
    MessageDlg('Please select an Equipment.', mtWarning, [mbOK], 0);
    cbEquipment.SetFocus;
    Exit;
  end;

  HasChecked := False;
  for I := 0 to clbFileTypes.Count - 1 do
    if clbFileTypes.Checked[I] then
    begin
      HasChecked := True;
      Break;
    end;
  if not HasChecked then
  begin
    for I := 0 to clbValueTypes.Count - 1 do
      if clbValueTypes.Checked[I] then
      begin
        HasChecked := True;
        Break;
      end;
  end;

  if not HasChecked then
  begin
    MessageDlg('At least one required file type or value type must be checked.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Result := True;
end;

procedure TdlgAuditRuleEditor.SaveCurrentRule;
var
  I: Integer;
  Idx: Integer;
  SavedId: Integer;
  WasNew: Boolean;
  RuleFile: TAuditRuleFile;
  RuleValue: TAuditRuleValue;
  ActionTypeId, EquipmentId: Integer;
begin
  if FCurrentRule = nil then Exit;
  if not ValidateCurrentRule then Exit;

  WasNew := FCurrentRule.Id = 0;

  { Read control values into rule }
  FCurrentRule.Title := Trim(edTitle.Text);
  FCurrentRule.Description := memDescription.Text;
  FCurrentRule.IsActive := chkActive.Checked;

  if cbSeverity.ItemIndex >= 0 then
    FCurrentRule.Severity := TAuditSeverity(cbSeverity.ItemIndex);

  { Action Type }
  ActionTypeId := FActionTypeIds[cbActionType.ItemIndex];
  FCurrentRule.ActionType := Model.Manager.Find<TActionType>(ActionTypeId);

  { Equipment }
  EquipmentId := FEquipmentIds[cbEquipment.ItemIndex];
  FCurrentRule.Equipment := Model.Manager.Find<TEquipment>(EquipmentId);

  { Audit fields }
  FCurrentRule.ModifiedBy := Model.User.Id;
  FCurrentRule.ModifiedDate := UTCNow;

  { Check for duplicate rule }
  if Model.AuditRules.RuleExistsFor(ActionTypeId, EquipmentId, FCurrentRule.Id) then
    MessageDlg('A rule already exists for this Action Type and Equipment combination. ' +
      'The rule will be saved, but you may want to review for duplicates.',
      mtWarning, [mbOK], 0);

  { Save the rule header first }
  Model.AuditRules.SaveRule(FCurrentRule);
  SavedId := FCurrentRule.Id;

  { For new rules, evict and reload to get initialized proxies }
  if WasNew then
  begin
    Idx := FRules.IndexOf(FCurrentRule);
    Model.Manager.Evict(FCurrentRule);
    FCurrentRule := Model.Manager.Find<TAuditRule>(SavedId);
    if Idx >= 0 then
      FRules[Idx] := FCurrentRule;
  end;

  { Now proxies are valid — rebuild child collections }
  FCurrentRule.RequiredFiles.Clear;
  for I := 0 to clbFileTypes.Count - 1 do
  begin
    if clbFileTypes.Checked[I] then
    begin
      RuleFile := TAuditRuleFile.Create;
      RuleFile.AuditRule := FCurrentRule;
      RuleFile.FileType := Model.Manager.Find<TFileType>(FFileTypeIds[I]);
      FCurrentRule.RequiredFiles.Add(RuleFile);
    end;
  end;

  FCurrentRule.RequiredValues.Clear;
  for I := 0 to clbValueTypes.Count - 1 do
  begin
    if clbValueTypes.Checked[I] then
    begin
      RuleValue := TAuditRuleValue.Create;
      RuleValue.AuditRule := FCurrentRule;
      RuleValue.ValueType := Model.Manager.Find<TValueType>(FValueTypeIds[I]);
      FCurrentRule.RequiredValues.Add(RuleValue);
    end;
  end;

  Model.Manager.Flush;

  { Refresh list display }
  Idx := FRules.IndexOf(FCurrentRule);
  LoadRules;
  if (Idx >= 0) and (Idx < lbRules.Items.Count) then
  begin
    lbRules.ItemIndex := Idx;
    SelectRule(Idx);
  end;
end;

procedure TdlgAuditRuleEditor.DoAddRule(Sender: TObject);
var
  Rule: TAuditRule;
begin
  Rule := TAuditRule.Create;
  Rule.Title := 'New Rule';
  Rule.IsActive := True;
  Rule.Severity := asError;
  Rule.CreatedBy := Model.User.Id;
  Rule.CreatedDate := UTCNow;

  { Add to in-memory list — don't persist until user clicks Save }
  FRules.Add(Rule);
  lbRules.Items.Add(Rule.Title);
  lbRules.ItemIndex := lbRules.Items.Count - 1;
  SelectRule(lbRules.ItemIndex);
  edTitle.SetFocus;
end;

procedure TdlgAuditRuleEditor.DoDeleteRule(Sender: TObject);
begin
  if FCurrentRule = nil then Exit;

  if MessageDlg('Delete rule "' + FCurrentRule.Title + '"?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  if FCurrentRule.Id > 0 then
    Model.AuditRules.DeleteRule(FCurrentRule)
  else
    FCurrentRule.Free;

  FCurrentRule := nil;
  LoadRules;
end;

procedure TdlgAuditRuleEditor.DoSaveRule(Sender: TObject);
var
  Idx: Integer;
  Display: string;
begin
  SaveCurrentRule;
  if FCurrentRule = nil then Exit;

  { Update list entry to reflect saved title }
  Idx := FRules.IndexOf(FCurrentRule);
  if Idx >= 0 then
  begin
    Display := FCurrentRule.Title;
    if not FCurrentRule.IsActive then
      Display := Display + ' (inactive)';
    lbRules.Items[Idx] := Display;
  end;
end;

procedure TdlgAuditRuleEditor.DoRuleSelect(Sender: TObject);
begin
  if lbRules.ItemIndex < 0 then Exit;
  SelectRule(lbRules.ItemIndex);
end;

procedure TdlgAuditRuleEditor.EnableEditor(Enable: Boolean);
begin
  edTitle.Enabled := Enable;
  cbActionType.Enabled := Enable;
  cbEquipment.Enabled := Enable;
  cbSeverity.Enabled := Enable;
  chkActive.Enabled := Enable;
  memDescription.Enabled := Enable;
  clbFileTypes.Enabled := Enable;
  clbValueTypes.Enabled := Enable;
  btnSave.Enabled := Enable;
  btnDelete.Enabled := Enable;

  if not Enable then
  begin
    edTitle.Text := '';
    cbActionType.ItemIndex := -1;
    cbEquipment.ItemIndex := -1;
    cbSeverity.ItemIndex := -1;
    chkActive.Checked := False;
    memDescription.Clear;
  end;
end;

class procedure TdlgAuditRuleEditor.Execute;
var
  Dlg: TdlgAuditRuleEditor;
begin
  if not Model.Access.CanEditReferenceData(Model.Manager, Model.User) then
  begin
    MessageDlg('You do not have permission to manage audit rules.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Dlg := TdlgAuditRuleEditor.Create(Application);
  try
    Dlg.LoadLookups;
    Dlg.LoadRules;
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

end.
