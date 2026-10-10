unit dlg_HypothesisEdit;


interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  RzPanel, RzCommon;

type
  TdlgHypothesisEdit = class(TForm)
    lblTitle: TLabel;
    edTitle: TEdit;
    lblStatement: TLabel;
    memStatement: TMemo;
    lblChange: TLabel;
    memChange: TMemo;
    pnlBottom: TRzPanel;
    lblKeyValue: TLabel;
    cbKeyValue: TComboBox;
    btnOK: TButton;
    btnCancel: TButton;
    procedure btnOKClick(Sender: TObject);
  private
    FShowChange: Boolean;
    FTypeIds: TList<Integer>;
  public
    destructor Destroy; override;
    class function Execute(const ACaption: string; AShowChange: Boolean;
      var ATitle, AStatement, AChange: string;
      var AKeyValueTypeId: Integer): Boolean; static;
  end;

implementation

{$R *.dfm}

uses
  unit_DataModel,
  unit_ValueType;

destructor TdlgHypothesisEdit.Destroy;
begin
  FTypeIds.Free;
  inherited;
end;

procedure TdlgHypothesisEdit.btnOKClick(Sender: TObject);
begin
  // Mirrors CheckProposal so the user is told before the round trip; the model
  // re-checks anyway.
  if Trim(edTitle.Text) = '' then
  begin
    MessageDlg('A title is required.', mtWarning, [mbOK], 0);
    edTitle.SetFocus;
    Exit;
  end;
  if Trim(memStatement.Text) = '' then
  begin
    MessageDlg('Write what you expect and why.', mtWarning, [mbOK], 0);
    memStatement.SetFocus;
    Exit;
  end;
  if FShowChange and (Trim(memChange.Text) = '') then
  begin
    MessageDlg('Describe what differs from the parent hypothesis.', mtWarning, [mbOK], 0);
    memChange.SetFocus;
    Exit;
  end;
  ModalResult := mrOk;
end;

class function TdlgHypothesisEdit.Execute(const ACaption: string;
  AShowChange: Boolean; var ATitle, AStatement, AChange: string;
  var AKeyValueTypeId: Integer): Boolean;
var
  Dlg: TdlgHypothesisEdit;
  Types: TList<TValueType>;
  VT: TValueType;
  I: Integer;
begin
  Dlg := TdlgHypothesisEdit.Create(Application);
  try
    Dlg.Caption := ACaption;
    Dlg.FShowChange := AShowChange;
    Dlg.lblChange.Visible := AShowChange;
    Dlg.memChange.Visible := AShowChange;
    Dlg.edTitle.Text := ATitle;
    Dlg.memStatement.Text := AStatement;
    Dlg.memChange.Text := AChange;

    Dlg.FTypeIds := TList<Integer>.Create;
    Dlg.cbKeyValue.Items.Add('(none)');
    Dlg.FTypeIds.Add(0);
    Types := Model.ValueTypes.GetTypes;
    try
      for VT in Types do
      begin
        Dlg.cbKeyValue.Items.Add(Format('%s  (%s, %s)', [VT.Title, VT.Symbol, VT.Units]));
        Dlg.FTypeIds.Add(VT.Id);
      end;
    finally
      Types.Free;
    end;
    Dlg.cbKeyValue.ItemIndex := 0;
    for I := 0 to Dlg.FTypeIds.Count - 1 do
      if Dlg.FTypeIds[I] = AKeyValueTypeId then
        Dlg.cbKeyValue.ItemIndex := I;

    Result := Dlg.ShowModal = mrOk;
    if Result then
    begin
      ATitle := Trim(Dlg.edTitle.Text);
      AStatement := Dlg.memStatement.Text;
      AChange := Dlg.memChange.Text;
      AKeyValueTypeId := Dlg.FTypeIds[Dlg.cbKeyValue.ItemIndex];
    end;
  finally
    Dlg.Free;
  end;
end;

end.
