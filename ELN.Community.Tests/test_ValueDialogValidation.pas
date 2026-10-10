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
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, Vcl.Forms, Vcl.Controls,
  dlg_Value, dlg_UnitConverter, unit_Item, unit_ItemTypes, unit_ValueType;

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

initialization
  TDUnitX.RegisterTestFixture(TValueDialogValidationTests);

end.
