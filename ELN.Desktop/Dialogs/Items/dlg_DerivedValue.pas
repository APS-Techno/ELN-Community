unit dlg_DerivedValue;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  RzEdit, RzLabel, RzButton, Vcl.ExtCtrls, RzPanel,
  Aurelius.Engine.ObjectManager,
  unit_Item, unit_DerivedFormulas, unit_DerivedValueModel;

type
  TdlgDerivedValue = class(TForm)
    pnlButtons: TRzPanel;
    btnSave: TRzBitBtn;
    btnCancel: TRzBitBtn;
    pnlMain: TRzPanel;
    lblFormula: TRzLabel;
    lbFormula: TListBox;
    lblExpression: TRzLabel;
    lblRoles: TRzLabel;
    lbRoles: TListBox;
    lblCandidates: TRzLabel;
    lbCandidates: TListBox;
    lblResult: TRzLabel;
    lblDescription: TRzLabel;
    edDescription: TRzEdit;
    procedure lbFormulaClick(Sender: TObject);
    procedure lbRolesClick(Sender: TObject);
    procedure lbCandidatesClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FModel: TDerivedValueModel;
    FItem: TItem;
    FFormulas: TArray<TDerivedFormula>;
    FFormula: TDerivedFormula;
    FChosen: TArray<TArray<TValue>>;
    FCandidates: TArray<TValue>;
    FComputation: TDerivedComputation;
    FValid: Boolean;
    FToleranceFactor: Double;
    procedure ShowRoles;
    procedure ShowCandidates;
    procedure Recompute;
    function Inputs: TArray<TDerivedInputRef>;
  public
    destructor Destroy; override;
    procedure Load(Manager: TObjectManager; Item: TItem; ToleranceFactor: Double);
    function Store(UserId: Integer): TValue;
    property Valid: Boolean read FValid;
    property Computation: TDerivedComputation read FComputation;
  end;

function ShowDerivedValueDialog(Item: TItem): Boolean;

implementation

uses
  unit_DataModel,
  unit_DialogHelper,
  unit_ValueChecks,
  dlg_Value;

{$R *.dfm}

function ValueText(Value: TValue): string;
begin
  Result := Format('#%d  %g %s', [Value.Id, Value.Value, Value.ValueType.Units]).TrimRight;
  if Value.Description <> '' then
    Result := Result + '  ' + Value.Description;
  if Assigned(Value.Item) then
    Result := Result + '  [' + Value.Item.Title + ']';
end;

destructor TdlgDerivedValue.Destroy;
begin
  FModel.Free;
  inherited;
end;

procedure TdlgDerivedValue.Load(Manager: TObjectManager; Item: TItem;
  ToleranceFactor: Double);
var
  F: TDerivedFormula;
begin
  FreeAndNil(FModel);
  FModel := TDerivedValueModel.Create(Manager);
  FItem := Item;
  FToleranceFactor := ToleranceFactor;
  FFormulas := CurrentDerivedFormulas;
  lbFormula.Items.Clear;
  for F in FFormulas do
    lbFormula.Items.Add(F.Title + ' (' + F.Id + ', version ' + IntToStr(F.Version) + ')');
  if lbFormula.Items.Count > 0 then
  begin
    lbFormula.ItemIndex := 0;
    lbFormulaClick(lbFormula);
  end;
end;

procedure TdlgDerivedValue.lbFormulaClick(Sender: TObject);
begin
  if lbFormula.ItemIndex < 0 then
    Exit;
  FFormula := FFormulas[lbFormula.ItemIndex];
  lblExpression.Caption := FFormula.Expression + '   ' + FFormula.ResultTitle +
    ' in ' + FFormula.ResultUnits;
  FChosen := nil;
  SetLength(FChosen, Length(FFormula.Roles));
  ShowRoles;
  if lbRoles.Items.Count > 0 then
    lbRoles.ItemIndex := 0;
  ShowCandidates;
  Recompute;
end;

procedure TdlgDerivedValue.ShowRoles;
var
  I, Selected: Integer;
  Text: string;
begin
  Selected := lbRoles.ItemIndex;
  lbRoles.Items.BeginUpdate;
  try
    lbRoles.Items.Clear;
    for I := 0 to High(FFormula.Roles) do
    begin
      Text := FFormula.Roles[I].Name + ' - ' + FFormula.Roles[I].TypeTitle;
      if FFormula.Roles[I].Units <> '' then
        Text := Text + ' (' + FFormula.Roles[I].Units + ')';
      if Length(FChosen[I]) = 1 then
        Text := Text + ': ' + ValueText(FChosen[I][0])
      else if Length(FChosen[I]) > 1 then
        Text := Text + ': mean of ' + IntToStr(Length(FChosen[I])) + ' values'
      else
        Text := Text + ': not selected';
      lbRoles.Items.Add(Text);
    end;
  finally
    lbRoles.Items.EndUpdate;
  end;
  if (Selected >= 0) and (Selected < lbRoles.Items.Count) then
    lbRoles.ItemIndex := Selected;
end;

procedure TdlgDerivedValue.ShowCandidates;
var
  V, C: TValue;
  Role: Integer;
begin
  lbCandidates.Items.BeginUpdate;
  try
    lbCandidates.Items.Clear;
    FCandidates := nil;
    Role := lbRoles.ItemIndex;
    if (Role < 0) or (Role > High(FFormula.Roles)) or (FItem = nil) then
      Exit;
    lbCandidates.MultiSelect := FFormula.Roles[Role].Mean;
    FCandidates := FModel.Candidates(FItem, FFormula.Roles[Role]);
    for V in FCandidates do
    begin
      lbCandidates.Items.Add(ValueText(V));
      for C in FChosen[Role] do
        if V = C then
          lbCandidates.Selected[lbCandidates.Items.Count - 1] := True;
    end;
  finally
    lbCandidates.Items.EndUpdate;
  end;
end;

procedure TdlgDerivedValue.lbRolesClick(Sender: TObject);
begin
  ShowCandidates;
end;

procedure TdlgDerivedValue.lbCandidatesClick(Sender: TObject);
var
  Role, I: Integer;
  Picked: TArray<TValue>;
begin
  Role := lbRoles.ItemIndex;
  if (Role < 0) or (Role > High(FChosen)) then
    Exit;
  Picked := nil;
  for I := 0 to lbCandidates.Items.Count - 1 do
    if lbCandidates.Selected[I] then
    begin
      SetLength(Picked, Length(Picked) + 1);
      Picked[High(Picked)] := FCandidates[I];
    end;
  FChosen[Role] := Picked;
  ShowRoles;
  Recompute;
end;

function TdlgDerivedValue.Inputs: TArray<TDerivedInputRef>;
var
  I, J: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to High(FChosen) do
    for J := 0 to High(FChosen[I]) do
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Role := FFormula.Roles[I].Name;
      Result[High(Result)].ValueId := FChosen[I][J].Id;
    end;
end;

procedure TdlgDerivedValue.Recompute;
var
  I: Integer;
begin
  FValid := False;
  btnSave.Enabled := False;
  for I := 0 to High(FChosen) do
    if Length(FChosen[I]) = 0 then
    begin
      lblResult.Caption := 'Select a stored value for every role.';
      Exit;
    end;
  try
    FComputation := FModel.Compute(FItem, FFormula.Id, Inputs);
  except
    on E: EDerivedValueError do
    begin
      lblResult.Caption := E.Message;
      Exit;
    end;
  end;
  FValid := True;
  btnSave.Enabled := True;
  lblResult.Caption := Format('%s = %s %s', [FFormula.ResultTitle,
    FloatToStrF(FComputation.Number, ffGeneral, 4, 0), FFormula.ResultUnits]);
end;

procedure TdlgDerivedValue.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Issues: TValueIssues;
begin
  if ModalResult <> mrOk then
  begin
    CanClose := True;
    Exit;
  end;
  CanClose := FValid;
  if not CanClose then
    Exit;
  Issues := CheckValue(FComputation.ResultType, FComputation.Number, 0, FToleranceFactor);
  if Issues <> [] then
    CanClose := ConfirmValueIssues('Please check this value: ' +
      DescribeValueIssues(Issues, FComputation.ResultType, FComputation.Number, 0,
      FToleranceFactor) + '.' + sLineBreak + sLineBreak + 'Store it anyway?');
end;

function TdlgDerivedValue.Store(UserId: Integer): TValue;
begin
  if not FValid then
    raise EDerivedValueError.Create('The Derived value is not complete');
  Result := FModel.Store(FItem, FComputation, edDescription.Text, UserId,
    'Added derived value to item "' + FItem.Title + '"');
end;

function ShowDerivedValueDialog(Item: TItem): Boolean;
begin
  Result := ExecuteDialog(TdlgDerivedValue,
    procedure(Dialog: TForm)
    begin
      TdlgDerivedValue(Dialog).Load(Model.Manager, Item,
        LoadToleranceFactor(Model.Manager));
    end,
    procedure(Dialog: TForm)
    begin
      TdlgDerivedValue(Dialog).Store(Model.User.Id);
    end);
end;

end.
