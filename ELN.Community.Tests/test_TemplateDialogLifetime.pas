unit test_TemplateDialogLifetime;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TTemplateDialogLifetimeTests = class
  public
    [Test] procedure ClosingCancelsCardCallbacks;
    [Test] procedure FieldCardsInitializeAfterParentAndRetainEdits;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Grids,
  dlg_ProtocolTemplateEditor, frame_TextFieldCard, unit_NotebookSettings;

procedure TTemplateDialogLifetimeTests.ClosingCancelsCardCallbacks;
var
  Dialog: TdlgTemplateEditor;
  Card: TfrTextFieldCard;
  Root: string;
  I: Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'eln-card-lifetime-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Root);
  // Construct no settings reader until an isolated path has been selected.
  TNotebookSettings.SetConfigFile(TPath.Combine(Root, 'settings.ini'));
  try
    while CheckSynchronize(0) do ;
    Dialog := TdlgTemplateEditor.Create(nil);
    try
      Card := nil;
      for I := 0 to Dialog.ComponentCount - 1 do
        if Dialog.Components[I] is TfrTextFieldCard then
          Card := TfrTextFieldCard(Dialog.Components[I]);
      Assert.IsNotNull(Card);
      Card.cmbType.ItemIndex := Card.cmbType.Items.IndexOf('number');
      Card.cmbTypeChange(Card.cmbType);
      Card.cmbTypeChange(Card.cmbType);
    finally
      Dialog.Free;
    end;
    Assert.IsFalse(CheckSynchronize(0),
      'No queued card closure may remain after its form has been freed');
  finally
    // The isolated path remains selected; never restore a registry fallback.
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTemplateDialogLifetimeTests.FieldCardsInitializeAfterParentAndRetainEdits;
var
  Dialog: TdlgTemplateEditor;
  Card: TFrame;
  Combo: TComboBox;
  Options: TStringGrid;
  Parent: TWinControl;
  Root: string;
  I, FieldCards: Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'eln-card-parent-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Root);
  TNotebookSettings.SetConfigFile(TPath.Combine(Root, 'settings.ini'));
  try
    Dialog := TdlgTemplateEditor.Create(nil);
    try
      FieldCards := 0;
      for I := 0 to Dialog.ComponentCount - 1 do
        if Dialog.Components[I] is TFrame then
        begin
          Card := TFrame(Dialog.Components[I]);
          Combo := Card.FindComponent('cmbType') as TComboBox;
          if Combo = nil then Continue;
          Inc(FieldCards);
          Assert.IsNotNull(Card.Parent);
          Assert.IsTrue(Combo.Items.IndexOf('number') >= 0);
          Combo.ItemIndex := Combo.Items.IndexOf('number');
          Options := Card.FindComponent('sgOptions') as TStringGrid;
          if Options <> nil then
            Options.Cells[0, 1] := 'Edited option';
          Parent := Card.Parent;
          Card.Parent := nil;
          Card.Parent := Parent;
          Assert.AreEqual('number', Combo.Text,
            'Reparenting must not repopulate controls and discard the selected field type');
          if Options <> nil then
            Assert.AreEqual('Edited option', Options.Cells[0, 1],
              'Reparenting must retain edited options');
        end;
      Assert.AreEqual(8, FieldCards, 'Every field-card family must initialize successfully');
    finally
      Dialog.Free;
    end;
  finally
    TDirectory.Delete(Root, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTemplateDialogLifetimeTests);

end.
