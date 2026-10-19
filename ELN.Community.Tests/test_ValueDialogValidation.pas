unit test_ValueDialogValidation;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TValueDialogValidationTests = class
  public
    [Test] procedure IncompatibleInputCannotCloseOrMutateValue;
    [Test] procedure InvalidNumberCannotCloseOrMutateValue;
    [Test] procedure InvalidToleranceCannotMutateValue;
    [Test] procedure CompatibleInputAppliesConvertedValue;
    [Test] procedure OutOfRangeValueNeedsConfirmation;
    [Test] procedure ToleranceLargerThanValueNeedsConfirmation;
    [Test] procedure EditedReaderValueBecomesManual;
    [Test] procedure UntouchedReaderValueKeepsSourceAndNumber;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, Vcl.Forms, Vcl.Controls,
  Aurelius.Types.Nullable,
  dlg_Value, dlg_UnitConverter, unit_Item, unit_ItemTypes, unit_ValueType,
  unit_ValueSource;

procedure CheckRefusedInput(const Input, Tolerance: string);
var
  Dialog: TdlgValue;
  Types: TList<TValueType>;
  Selected, OriginalType: TValueType;
  Value: TValue;
  CanClose, ConverterOpened: Boolean;
begin
  Selected := TValueType.Create;
  OriginalType := TValueType.Create;
  Value := TValue.Create;
  Dialog := TdlgValue.Create(nil);
  try
    Selected.Title := 'Molar concentration';
    Selected.Symbol := 'c';
    Selected.Units := 'mol/L';
    OriginalType.Units := 'K';
    Value.ValueType := OriginalType;
    Value.Value := 7.5;
    Value.Tol := 0.2;
    Value.RecType := TRecType.EXP_CONDITION;
    Value.Description := 'Original result';
    Types := TList<TValueType>.Create;
    Types.Add(Selected);
    Dialog.LoadValueTypes(Types);
    Dialog.rgRecType.ItemIndex := Ord(TRecType.TEST_RESULT);
    Dialog.edValue.Text := Input;
    Dialog.edTolerance.Text := Tolerance;
    Dialog.edDescription.Text := 'Rejected draft';
    Dialog.ModalResult := mrOk;
    CanClose := Dialog.CloseQuery;
    Assert.IsFalse(CanClose, 'Invalid input must keep the dialog open');
    Assert.WillRaise(procedure begin Dialog.ApplyTo(Value); end, EConvertError);
    Assert.AreSame(OriginalType, Value.ValueType);
    Assert.AreEqual<Double>(7.5, Value.Value);
    Assert.AreEqual<Double>(0.2, Value.Tol);
    Assert.IsTrue(Value.RecType = TRecType.EXP_CONDITION);
    Assert.AreEqual('Original result', Value.Description);
    if Tolerance <> 'not-a-number' then
    begin
      // Auto-dismiss an incorrectly opened converter so a regression fails
      // an assertion instead of hanging the non-interactive test runner.
      ConverterOpened := False;
      TThread.ForceQueue(nil,
        procedure
        begin
          if Screen.ActiveCustomForm is TdlgUnitConverter then
          begin
            ConverterOpened := True;
            TdlgUnitConverter(Screen.ActiveCustomForm).ModalResult := mrCancel;
          end;
        end);
      try
        Dialog.btnConvertClick(Dialog.btnConvert);
      finally
        CheckSynchronize(0);
      end;
      Assert.IsFalse(ConverterOpened, 'Invalid input must not open a zero-valued converter');
      Assert.AreEqual(Input, Dialog.edValue.Text);
      Assert.IsTrue(Dialog.lblBaseValue.Caption <> '');
    end;
  finally
    Dialog.Free;
    Value.Free;
    OriginalType.Free;
    Selected.Free;
  end;
end;

procedure TValueDialogValidationTests.IncompatibleInputCannotCloseOrMutateValue;
begin
  CheckRefusedInput('20 mg/mL', '0.1');
end;

procedure TValueDialogValidationTests.InvalidNumberCannotCloseOrMutateValue;
begin
  CheckRefusedInput('not-a-number', '0.1');
end;

procedure TValueDialogValidationTests.InvalidToleranceCannotMutateValue;
begin
  CheckRefusedInput('20 mmol/L', 'not-a-number');
end;

procedure TValueDialogValidationTests.CompatibleInputAppliesConvertedValue;
var
  Dialog: TdlgValue;
  Types: TList<TValueType>;
  Selected: TValueType;
  Value: TValue;
  CanClose: Boolean;
begin
  Selected := TValueType.Create;
  Value := TValue.Create;
  Dialog := TdlgValue.Create(nil);
  try
    Selected.Units := 'mol/L';
    Types := TList<TValueType>.Create;
    Types.Add(Selected);
    Dialog.LoadValueTypes(Types);
    Dialog.rgRecType.ItemIndex := Ord(TRecType.TEST_RESULT);
    Dialog.edValue.Text := '20 mmol/L';
    Dialog.edTolerance.Text := '';
    Dialog.ModalResult := mrOk;
    CanClose := Dialog.CloseQuery;
    Assert.IsTrue(CanClose);
    Dialog.ApplyTo(Value);
    Assert.AreSame(Selected, Value.ValueType);
    Assert.AreEqual<Double>(0.02, Value.Value);
    Assert.AreEqual<Double>(0, Value.Tol);
  finally
    Dialog.Free;
    Value.Free;
    Selected.Free;
  end;
end;

function NewDialog(ValueType: TValueType): TdlgValue;
var
  Types: TList<TValueType>;
begin
  Result := TdlgValue.Create(nil);
  Types := TList<TValueType>.Create;
  Types.Add(ValueType);
  Result.LoadValueTypes(Types);
end;

procedure TValueDialogValidationTests.OutOfRangeValueNeedsConfirmation;
var
  Dialog: TdlgValue;
  Thickness: TValueType;
  Value: TValue;
  Saved: TValueIssueConfirmation;
  Answer: Boolean;
  Question: string;
begin
  Saved := ConfirmValueIssues;
  Thickness := TValueType.Create;
  Value := TValue.Create;
  Dialog := nil;
  try
    ConfirmValueIssues :=
      function(const Text: string): Boolean
      begin
        Question := Text;
        Result := Answer;
      end;
    Thickness.Units := 'm';
    Thickness.RangeMin := 1e-9;
    Thickness.RangeMax := 1e-5;
    Value.Value := 7.5e-8;
    Dialog := NewDialog(Thickness);
    Dialog.edValue.Text := '319.4';
    Dialog.edTolerance.Text := '';
    Dialog.ModalResult := mrOk;

    Answer := False;
    Assert.IsFalse(Dialog.CloseQuery, 'Declining must keep the dialog open');
    Assert.Contains(Question, 'plausible maximum');
    Assert.AreEqual<Double>(7.5e-8, Value.Value, 'Declining must not change the value');

    Answer := True;
    Question := '';
    Assert.IsTrue(Dialog.CloseQuery, 'Accepting must close the dialog');
    Assert.IsTrue(Question <> '', 'The out-of-range value must be confirmed');
    Dialog.ApplyTo(Value);
    Assert.AreEqual<Double>(319.4, Value.Value);
  finally
    ConfirmValueIssues := Saved;
    Dialog.Free;
    Value.Free;
    Thickness.Free;
  end;
end;

procedure TValueDialogValidationTests.ToleranceLargerThanValueNeedsConfirmation;
var
  Dialog: TdlgValue;
  Thickness: TValueType;
  Saved: TValueIssueConfirmation;
  Question: string;
begin
  Saved := ConfirmValueIssues;
  Thickness := TValueType.Create;
  Dialog := nil;
  try
    ConfirmValueIssues :=
      function(const Text: string): Boolean
      begin
        Question := Text;
        Result := False;
      end;
    Thickness.Units := 'm';
    Dialog := NewDialog(Thickness);
    Dialog.edValue.Text := '2.279e-05';
    Dialog.edTolerance.Text := '0.0602';
    Dialog.ModalResult := mrOk;
    Assert.IsFalse(Dialog.CloseQuery);
    Assert.Contains(Question, 'larger than the value magnitude');
  finally
    ConfirmValueIssues := Saved;
    Dialog.Free;
    Thickness.Free;
  end;
end;

procedure TValueDialogValidationTests.EditedReaderValueBecomesManual;
var
  Dialog: TdlgValue;
  Thickness: TValueType;
  Value: TValue;
  Saved: TValueIssueConfirmation;
begin
  Saved := ConfirmValueIssues;
  Thickness := TValueType.Create;
  Value := TValue.Create;
  Dialog := nil;
  try
    ConfirmValueIssues :=
      function(const Text: string): Boolean
      begin
        Result := True;
      end;
    Thickness.Units := 'm';
    Value.ValueType := Thickness;
    Value.RecType := TRecType.TEST_RESULT;
    Value.Value := 2.5;
    ApplySource(Value, TValueSourceInfo.Reader(7, 'synthetic.reader', '1.2',
      'Thickness', 'm', 1));
    Dialog := NewDialog(Thickness);
    Dialog.LoadValue(Value, 'scan.dat');
    Assert.Contains(Dialog.lblSource.Caption, 'synthetic.reader');
    Assert.Contains(Dialog.lblSource.Caption, 'scan.dat');
    Dialog.edValue.Text := '3';
    Dialog.ModalResult := mrOk;
    Assert.IsTrue(Dialog.CloseQuery);
    Dialog.ApplyTo(Value);
    Assert.AreEqual<Double>(3, Value.Value);
    Assert.IsTrue(Value.EffectiveSourceKind = vskManual);
    Assert.IsTrue(Value.SourceFileId.HasValue);
    Assert.AreEqual<Int64>(7, Value.SourceFileId.Value);
    Assert.Contains(Value.SourceNote, 'synthetic.reader');
    Assert.AreEqual('', Value.ReaderId);
  finally
    ConfirmValueIssues := Saved;
    Dialog.Free;
    Value.Free;
    Thickness.Free;
  end;
end;

procedure TValueDialogValidationTests.UntouchedReaderValueKeepsSourceAndNumber;
const
  Stored = 2.27912345e-05;
var
  Dialog: TdlgValue;
  Thickness: TValueType;
  Value: TValue;
  Saved: TValueIssueConfirmation;
begin
  Saved := ConfirmValueIssues;
  Thickness := TValueType.Create;
  Value := TValue.Create;
  Dialog := nil;
  try
    ConfirmValueIssues :=
      function(const Text: string): Boolean
      begin
        Result := True;
      end;
    Thickness.Units := 'm';
    Value.ValueType := Thickness;
    Value.Value := Stored;
    ApplySource(Value, TValueSourceInfo.Reader(7, 'synthetic.reader', '1.2',
      'Thickness', 'm', 1));
    Dialog := NewDialog(Thickness);
    Dialog.LoadValue(Value, '');
    Dialog.edDescription.Text := 'Only the description changes';
    Dialog.ModalResult := mrOk;
    Assert.IsTrue(Dialog.CloseQuery);
    Dialog.ApplyTo(Value);
    Assert.AreEqual<Double>(Stored, Value.Value);
    Assert.IsTrue(Value.EffectiveSourceKind = vskReader);
    Assert.AreEqual('Only the description changes', Value.Description);
  finally
    ConfirmValueIssues := Saved;
    Dialog.Free;
    Value.Free;
    Thickness.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TValueDialogValidationTests);

end.
