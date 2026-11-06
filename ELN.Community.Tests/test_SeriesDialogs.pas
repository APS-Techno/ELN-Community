unit test_SeriesDialogs;

interface

uses
  System.SysUtils, System.UITypes, Vcl.Forms, DUnitX.TestFramework, unit_LocalNotebook,
  unit_ValueType, unit_SeriesTable;

type
  [TestFixture]
  TSeriesDialogTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FProjectId, FFolderId: Integer;
    FPower, FPressure, FArFlow, FThickness: TValueType;
    FExercise: TProc<TForm>;
    FNestedExercise: TProc<TForm>;
    FDialogError: string;
    function NewType(const ATitle, AUnits: string): TValueType;
    function Shown(AType: TValueType): string;
    function Plan(const AFactors: array of TValueType): TSeriesPlan;
    procedure Fire(Sender: TObject);
    procedure FireNested(Sender: TObject);
    procedure Drive(const AExercise: TProc<TForm>; const ARun: TProc);
    procedure DriveNested(const AOpen: TProc; const AExercise: TProc<TForm>);
    procedure AddFactorThroughDialog(ADialog: TForm; AType: TValueType);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure PlanDialogShowsPlanFoldersAndLevels;
    [Test] procedure PlanDialogWithPointsEditsOnlyFactorLabels;
    [Test] procedure PlanDialogTwoFactorsReturnsGridText;
    [Test] procedure EntryDialogReturnsFactorRangeAndSkipsUsedTypes;
    [Test] procedure EntryDialogReturnsFixedValueAndTolerance;
    [Test] procedure EntryDialogConvertsTypedUnits;
    [Test] procedure EntryDialogFiltersTypesByCategory;
    [Test] procedure FixedAddOpensFixedEntryAndFillsFixedList;
    [Test] procedure DoubleClickEditsTheClickedList;
    [Test] procedure SecondFactorLabelSitsAboveItsLevels;
  end;

implementation

uses
  System.IOUtils, Vcl.ExtCtrls, Aurelius.Types.Nullable,
  unit_Project, unit_ProjectModel,
  dlg_SeriesPlan, dlg_SeriesPlanEntry, unit_SeriesPlanInput;

const
  Password = 'Synthetic-Series-Dialog-Only!';

function Response(AValueTypeId: Integer): TSeriesResponseSpec;
begin
  Result := Default(TSeriesResponseSpec);
  Result.ValueTypeId := AValueTypeId;
end;

function TSeriesDialogTests.NewType(const ATitle, AUnits: string): TValueType;
begin
  Result := TValueType.Create;
  Result.Symbol := Copy(ATitle, 4, 2);
  Result.Title := ATitle;
  Result.Units := AUnits;
  Result.CreatedDate := Now;
  FNotebook.Manager.Save(Result);
end;

function TSeriesDialogTests.Shown(AType: TValueType): string;
begin
  Result := AType.Symbol + ' '#$2014' ' + AType.Title + ' (' + AType.Units + ')';
end;

procedure TSeriesDialogTests.Setup;
var
  Projects: TProjectsModel;
  Project: TProject;
  Folder: TFolder;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-SeriesDialogs-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    FProjectId := Projects.AddProject('Dialog project', '', FNotebook.Principal).Id;
  finally
    Projects.Free;
  end;
  Project := FNotebook.Manager.Find<TProject>(FProjectId);
  Folder := TFolder.Create;
  Folder.Title := 'Calibrations';
  Folder.CreatedDate := Now;
  Folder.CreatedBy := FNotebook.Principal.Id;
  Project.Folders.Add(Folder);
  FNotebook.Manager.Flush;
  FFolderId := Folder.Id;
  FPower := NewType('Sx Power', 'W');
  FPressure := NewType('Sx Pressure', 'mTorr');
  FArFlow := NewType('Sx Ar flow', 'sccm');
  FThickness := NewType('Sx Thickness', 'nm');
  FNotebook.Manager.Flush;
  FDialogError := '';
end;

procedure TSeriesDialogTests.TearDown;
begin
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TSeriesDialogTests.Plan(const AFactors: array of TValueType): TSeriesPlan;
var
  I: Integer;
begin
  Result := Default(TSeriesPlan);
  SetLength(Result.Factors, Length(AFactors));
  for I := 0 to High(AFactors) do
    Result.Factors[I].ValueTypeId := AFactors[I].Id;
  SetLength(Result.Fixed, 1);
  Result.Fixed[0].ValueTypeId := FArFlow.Id;
  Result.Fixed[0].Value := 20;
  Result.Fixed[0].Tol := 1;
  Result.Responses := [Response(FThickness.Id)];
end;

procedure TSeriesDialogTests.Fire(Sender: TObject);
var
  Form: TForm;
begin
  TTimer(Sender).Enabled := False;
  Form := Screen.ActiveForm;
  try
    FExercise(Form);
  except
    on E: Exception do
    begin
      FDialogError := E.Message;
      if Assigned(Form) then
        Form.ModalResult := mrCancel;
    end;
  end;
end;

procedure TSeriesDialogTests.Drive(const AExercise: TProc<TForm>; const ARun: TProc);
var
  Timer: TTimer;
begin
  FDialogError := '';
  FExercise := AExercise;
  Timer := TTimer.Create(nil);
  try
    Timer.Interval := 1;
    Timer.OnTimer := Fire;
    Timer.Enabled := True;
    ARun();
  finally
    Timer.Free;
  end;
  Assert.AreEqual('', FDialogError);
end;

procedure TSeriesDialogTests.FireNested(Sender: TObject);
var
  Form: TForm;
begin
  TTimer(Sender).Enabled := False;
  Form := Screen.ActiveForm;
  try
    FNestedExercise(Form);
  except
    on E: Exception do
    begin
      FDialogError := E.Message;
      if Assigned(Form) then
        Form.ModalResult := mrCancel;
    end;
  end;
end;

procedure TSeriesDialogTests.DriveNested(const AOpen: TProc; const AExercise: TProc<TForm>);
var
  Timer: TTimer;
begin
  FNestedExercise := AExercise;
  Timer := TTimer.Create(nil);
  try
    Timer.Interval := 1;
    Timer.OnTimer := FireNested;
    Timer.Enabled := True;
    AOpen();
  finally
    Timer.Free;
  end;
  if FDialogError <> '' then
    raise Exception.Create(FDialogError);
end;

procedure TSeriesDialogTests.PlanDialogShowsPlanFoldersAndLevels;
var
  Title, Purpose, Levels: string;
  P: TSeriesPlan;
  Accepted: Boolean;
begin
  P := Plan([FPower]);
  P.Factors[0].RangeMin := 50.0;
  P.Factors[0].RangeMax := 500.0;
  P.TargetFolderId := FFolderId;
  Title := 'Ti rate';
  Purpose := 'Calibrate';
  Levels := '100; 200';
  Accepted := False;
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlan;
    begin
      D := F as TdlgSeriesPlan;
      Assert.AreEqual(1, D.lvFactors.Items.Count);
      Assert.AreEqual('Sx Power, W', D.lvFactors.Items[0].Caption);
      Assert.AreEqual('50 to 500', D.lvFactors.Items[0].SubItems[1]);
      Assert.AreEqual(1, D.lvFixed.Items.Count);
      Assert.AreEqual(1, D.lvResponses.Items.Count);
      Assert.AreEqual(2, D.cbFolder.Items.Count);
      Assert.AreEqual('Calibrations', D.cbFolder.Items[1]);
      Assert.AreEqual(1, D.cbFolder.ItemIndex);
      Assert.IsTrue(D.edLevelsA.Visible);
      Assert.IsFalse(D.edLevelsB.Visible);
      Assert.AreEqual('100; 200', D.edLevelsA.Text);
      Assert.IsTrue(D.btnFactorAdd.Enabled);
      Assert.IsFalse(D.btnFactorEdit.Enabled, 'nothing selected');
      D.edTitle.Text := '  Ti rate v2  ';
      D.edLevelsA.Text := '100; 200; 300';
      D.cbFolder.ItemIndex := 0;
      D.btnOKClick(D.btnOK);
    end,
    procedure
    begin
      Accepted := TdlgSeriesPlan.Execute(FNotebook.Manager, FProjectId, Title,
        Purpose, P, Levels, False);
    end);
  Assert.IsTrue(Accepted);
  Assert.AreEqual('Ti rate v2', Title);
  Assert.AreEqual('Calibrate', Purpose);
  Assert.AreEqual('100; 200; 300', Levels);
  Assert.AreEqual(0, P.TargetFolderId);
  Assert.AreEqual(FPower.Id, P.Factors[0].ValueTypeId);
  Assert.AreEqual(500.0, P.Factors[0].RangeMax.Value, 0.0);
  Assert.AreEqual<NativeInt>(1, Length(P.Fixed));
  Assert.AreEqual<NativeInt>(1, Length(P.Responses));
end;

procedure TSeriesDialogTests.PlanDialogWithPointsEditsOnlyFactorLabels;
var
  Title, Purpose, Levels: string;
  P: TSeriesPlan;
  Accepted: Boolean;
begin
  P := Plan([FPower]);
  Title := 'Ti rate';
  Purpose := '';
  Levels := '100';
  Accepted := False;
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlan;
    begin
      D := F as TdlgSeriesPlan;
      Assert.IsFalse(D.btnFactorAdd.Enabled);
      Assert.IsTrue(D.lblFactorNote.Visible);
      Assert.IsFalse(D.edLevelsA.Visible, 'levels are added with Add point');
      D.lvFactors.ItemIndex := 0;
      Assert.IsTrue(D.btnFactorEdit.Enabled, 'the label of a factor can still change');
      Assert.IsFalse(D.btnFactorRemove.Enabled);
      DriveNested(
        procedure
        begin
          D.ListDblClick(D.lvFactors);
        end,
        procedure(E: TForm)
        var
          Entry: TdlgSeriesPlanEntry;
        begin
          Entry := E as TdlgSeriesPlanEntry;
          Assert.IsFalse(Entry.lbType.Enabled, 'the value type is locked');
          Assert.IsFalse(Entry.edFirst.Enabled, 'the range is locked');
          Entry.edEntryLabel.Text := '  Mo layer ';
          Entry.btnOKClick(Entry.btnOK);
        end);
      Assert.AreEqual('Mo layer', D.lvFactors.Items[0].SubItems[0]);
      D.btnOKClick(D.btnOK);
    end,
    procedure
    begin
      Accepted := TdlgSeriesPlan.Execute(FNotebook.Manager, FProjectId, Title,
        Purpose, P, Levels, True);
    end);
  Assert.IsTrue(Accepted);
  Assert.AreEqual('', Levels, 'a series with points returns no initial levels');
  Assert.AreEqual(FPower.Id, P.Factors[0].ValueTypeId);
  Assert.AreEqual('Mo layer', P.Factors[0].EntryLabel);
end;

procedure TSeriesDialogTests.PlanDialogTwoFactorsReturnsGridText;
var
  Title, Purpose, Levels: string;
  P: TSeriesPlan;
  Accepted: Boolean;
begin
  P := Plan([FPower, FPressure]);
  Title := 'Grid';
  Purpose := '';
  Levels := '';
  Accepted := False;
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlan;
    begin
      D := F as TdlgSeriesPlan;
      Assert.IsFalse(D.btnFactorAdd.Enabled, 'two factors is the limit');
      Assert.IsTrue(D.edLevelsA.Visible);
      Assert.IsTrue(D.edLevelsB.Visible);
      Assert.AreEqual('Levels of Sx Power, W', D.lblLevelsA.Caption);
      Assert.AreEqual('Levels of Sx Pressure, mTorr', D.lblLevelsB.Caption);
      D.edLevelsA.Text := '100; 200';
      D.edLevelsB.Text := '1; 2';
      D.btnOKClick(D.btnOK);
    end,
    procedure
    begin
      Accepted := TdlgSeriesPlan.Execute(FNotebook.Manager, FProjectId, Title,
        Purpose, P, Levels, False);
    end);
  Assert.IsTrue(Accepted);
  Assert.AreEqual('100; 200|1; 2', Levels);
end;

procedure TSeriesDialogTests.EntryDialogReturnsFactorRangeAndSkipsUsedTypes;
var
  Factor: TSeriesFactorSpec;
  Accepted: Boolean;
begin
  Factor := Default(TSeriesFactorSpec);
  Accepted := False;
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlanEntry;
      I: Integer;
    begin
      D := F as TdlgSeriesPlanEntry;
      Assert.IsTrue(D.lbType.Items.IndexOf(Shown(FPower)) >= 0, 'a free type is offered');
      for I := 0 to D.lbType.Items.Count - 1 do
        Assert.AreNotEqual(Shown(FArFlow), D.lbType.Items[I], 'the used type is not offered');
      Assert.IsTrue(D.edFirst.Visible);
      Assert.AreEqual('Range minimum (optional)', D.lblFirst.Caption);
      D.lbType.ItemIndex := D.lbType.Items.IndexOf(Shown(FPower));
      D.edFirst.Text := '1.5';
      D.edSecond.Text := '';
      D.btnOKClick(D.btnOK);
    end,
    procedure
    begin
      Accepted := TdlgSeriesPlanEntry.ExecuteFactor(FNotebook.Manager,
        [FArFlow.Id], False, Factor);
    end);
  Assert.IsTrue(Accepted);
  Assert.AreEqual(FPower.Id, Factor.ValueTypeId);
  Assert.IsTrue(Factor.RangeMin.HasValue);
  Assert.AreEqual(1.5, Factor.RangeMin.Value, 1e-12);
  Assert.IsFalse(Factor.RangeMax.HasValue);
end;

procedure TSeriesDialogTests.EntryDialogReturnsFixedValueAndTolerance;
var
  Fixed: TSeriesFixedSpec;
  Accepted: Boolean;
begin
  Fixed := Default(TSeriesFixedSpec);
  Fixed.ValueTypeId := FArFlow.Id;
  Fixed.Value := 20;
  Accepted := False;
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlanEntry;
    begin
      D := F as TdlgSeriesPlanEntry;
      Assert.AreEqual(Shown(FArFlow), D.lbType.Items[D.lbType.ItemIndex],
        'the edited type is preselected');
      Assert.AreEqual('20', D.edFirst.Text);
      D.edFirst.Text := '25';
      D.edSecond.Text := '0.5';
      D.btnOKClick(D.btnOK);
    end,
    procedure
    begin
      Accepted := TdlgSeriesPlanEntry.ExecuteFixed(FNotebook.Manager, [], Fixed);
    end);
  Assert.IsTrue(Accepted);
  Assert.AreEqual(FArFlow.Id, Fixed.ValueTypeId);
  Assert.AreEqual(25.0, Fixed.Value, 1e-12);
  Assert.AreEqual(0.5, Fixed.Tol, 1e-12);
end;

procedure TSeriesDialogTests.EntryDialogConvertsTypedUnits;
var
  Fixed: TSeriesFixedSpec;
  Accepted: Boolean;
begin
  Fixed := Default(TSeriesFixedSpec);
  Fixed.ValueTypeId := FPressure.Id;
  Fixed.Value := 5;
  Accepted := False;
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlanEntry;
    begin
      D := F as TdlgSeriesPlanEntry;
      Assert.AreEqual('Value, mTorr', D.lblFirst.Caption);
      D.edFirst.Text := '0.4 Pa';
      Assert.AreEqual('Value = ' + SeriesNumberText(0.4 / 0.133322368) + ' mTorr',
        D.lblConversion.Caption);
      D.edSecond.Text := '0.1 Torr';
      D.btnOKClick(D.btnOK);
    end,
    procedure
    begin
      Accepted := TdlgSeriesPlanEntry.ExecuteFixed(FNotebook.Manager, [], Fixed);
    end);
  Assert.IsTrue(Accepted);
  Assert.AreEqual(0.4 / 0.133322368, Fixed.Value, 1e-9);
  Assert.AreEqual(100.0, Fixed.Tol, 1e-9);
end;

procedure TSeriesDialogTests.EntryDialogFiltersTypesByCategory;
var
  Picked: TSeriesResponseSpec;
  Accepted: Boolean;
begin
  FPressure.CatID := 1;
  FNotebook.Manager.Flush;
  Picked := Response(FPressure.Id);
  Accepted := False;
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlanEntry;
    begin
      D := F as TdlgSeriesPlanEntry;
      Assert.AreEqual(2, D.lbCategory.ItemIndex, 'the category of the edited type is selected');
      Assert.AreEqual(-1, D.lbType.Items.IndexOf(Shown(FPower)),
        'types of other categories are not listed');
      Assert.AreEqual(Shown(FPressure), D.lbType.Items[D.lbType.ItemIndex]);
      D.lbCategory.ItemIndex := 0;
      D.lbCategoryClick(D.lbCategory);
      Assert.IsTrue(D.lbType.Items.IndexOf(Shown(FPower)) >= 0, '(All) lists every type');
      Assert.AreEqual(Shown(FPressure), D.lbType.Items[D.lbType.ItemIndex],
        'switching category keeps the selected type');
      D.lbCategory.ItemIndex := 1;
      D.lbCategoryClick(D.lbCategory);
      Assert.AreEqual(-1, D.lbType.Items.IndexOf(Shown(FPressure)));
      D.lbType.ItemIndex := D.lbType.Items.IndexOf(Shown(FPower));
      D.edEntryLabel.Text := 'Total stack';
      D.btnOKClick(D.btnOK);
    end,
    procedure
    begin
      Accepted := TdlgSeriesPlanEntry.ExecuteResponse(FNotebook.Manager, [], Picked);
    end);
  Assert.IsTrue(Accepted);
  Assert.AreEqual(FPower.Id, Picked.ValueTypeId);
  Assert.AreEqual('Total stack', Picked.EntryLabel);
end;

procedure TSeriesDialogTests.FixedAddOpensFixedEntryAndFillsFixedList;
var
  Title, Purpose, Levels: string;
  P: TSeriesPlan;
  Accepted: Boolean;
begin
  P := Plan([FPower]);
  Title := 'Fixed add';
  Purpose := '';
  Levels := '';
  Accepted := False;
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlan;
    begin
      D := F as TdlgSeriesPlan;
      DriveNested(
        procedure
        begin
          D.btnFixedAdd.Click;
        end,
        procedure(E: TForm)
        var
          Entry: TdlgSeriesPlanEntry;
        begin
          Entry := E as TdlgSeriesPlanEntry;
          Assert.AreEqual('Value', Entry.lblFirst.Caption, 'Fixed Add opens the fixed entry');
          Entry.lbType.ItemIndex := Entry.lbType.Items.IndexOf(Shown(FPressure));
          Entry.edFirst.Text := '5';
          Entry.edSecond.Text := '0.2';
          Entry.btnOKClick(Entry.btnOK);
        end);
      Assert.AreEqual(1, D.lvFactors.Items.Count, 'factors unchanged');
      Assert.AreEqual(2, D.lvFixed.Items.Count, 'the new condition is listed as fixed');
      D.btnOKClick(D.btnOK);
    end,
    procedure
    begin
      Accepted := TdlgSeriesPlan.Execute(FNotebook.Manager, FProjectId, Title,
        Purpose, P, Levels, False);
    end);
  Assert.IsTrue(Accepted);
  Assert.AreEqual(1, Integer(Length(P.Factors)));
  Assert.AreEqual(2, Integer(Length(P.Fixed)));
  Assert.AreEqual(FPressure.Id, P.Fixed[1].ValueTypeId);
  Assert.AreEqual(5.0, P.Fixed[1].Value, 1e-12);
  Assert.AreEqual(0.2, P.Fixed[1].Tol, 1e-12);
end;

procedure TSeriesDialogTests.DoubleClickEditsTheClickedList;
var
  Title, Purpose, Levels: string;
  P: TSeriesPlan;
  Accepted: Boolean;
begin
  P := Plan([FPower]);
  Title := 'Double click';
  Purpose := '';
  Levels := '';
  Accepted := False;
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlan;
    begin
      D := F as TdlgSeriesPlan;
      D.lvFixed.ItemIndex := 0;
      DriveNested(
        procedure
        begin
          D.ListDblClick(D.lvFixed);
        end,
        procedure(E: TForm)
        var
          Entry: TdlgSeriesPlanEntry;
        begin
          Entry := E as TdlgSeriesPlanEntry;
          Assert.AreEqual(Shown(FArFlow), Entry.lbType.Items[Entry.lbType.ItemIndex]);
          Entry.edFirst.Text := '22';
          Entry.btnOKClick(Entry.btnOK);
        end);
      D.lvResponses.ItemIndex := 0;
      DriveNested(
        procedure
        begin
          D.ListDblClick(D.lvResponses);
        end,
        procedure(E: TForm)
        var
          Entry: TdlgSeriesPlanEntry;
        begin
          Entry := E as TdlgSeriesPlanEntry;
          Assert.AreEqual(Shown(FThickness), Entry.lbType.Items[Entry.lbType.ItemIndex]);
          Entry.lbType.ItemIndex := Entry.lbType.Items.IndexOf(Shown(FPressure));
          Entry.btnOKClick(Entry.btnOK);
        end);
      D.btnOKClick(D.btnOK);
    end,
    procedure
    begin
      Accepted := TdlgSeriesPlan.Execute(FNotebook.Manager, FProjectId, Title,
        Purpose, P, Levels, False);
    end);
  Assert.IsTrue(Accepted);
  Assert.AreEqual(FPower.Id, P.Factors[0].ValueTypeId, 'factor untouched');
  Assert.AreEqual(22.0, P.Fixed[0].Value, 1e-12);
  Assert.AreEqual(FPressure.Id, P.Responses[0].ValueTypeId);
end;

procedure TSeriesDialogTests.AddFactorThroughDialog(ADialog: TForm; AType: TValueType);
var
  D: TdlgSeriesPlan;
begin
  D := ADialog as TdlgSeriesPlan;
  DriveNested(
    procedure
    begin
      D.btnFactorAdd.Click;
    end,
    procedure(E: TForm)
    var
      Entry: TdlgSeriesPlanEntry;
    begin
      Entry := E as TdlgSeriesPlanEntry;
      Entry.lbType.ItemIndex := Entry.lbType.Items.IndexOf(Shown(AType));
      Entry.btnOKClick(Entry.btnOK);
    end);
end;

procedure TSeriesDialogTests.SecondFactorLabelSitsAboveItsLevels;
var
  Title, Purpose, Levels: string;
  P: TSeriesPlan;
begin
  P := Plan([]);
  Title := 'Second factor';
  Purpose := '';
  Levels := '';
  Drive(
    procedure(F: TForm)
    var
      D: TdlgSeriesPlan;
    begin
      D := F as TdlgSeriesPlan;
      AddFactorThroughDialog(D, FPower);
      AddFactorThroughDialog(D, FPressure);
      Assert.AreEqual(2, D.lvFactors.Items.Count);
      Assert.IsTrue(D.edLevelsB.Visible);
      Assert.IsTrue(D.lblLevelsA.Top < D.edLevelsA.Top, 'A label above A levels');
      Assert.IsTrue(D.edLevelsA.Top < D.lblLevelsB.Top, 'A levels above B label');
      Assert.IsTrue(D.lblLevelsB.Top < D.edLevelsB.Top, 'B label above B levels');
      D.ModalResult := mrCancel;
    end,
    procedure
    begin
      TdlgSeriesPlan.Execute(FNotebook.Manager, FProjectId, Title, Purpose, P,
        Levels, False);
    end);
end;

initialization
  TDUnitX.RegisterTestFixture(TSeriesDialogTests);

end.
