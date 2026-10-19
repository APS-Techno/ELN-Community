unit dlg_ValueDrift;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ComCtrls,
  RzPanel, RzLabel, RzButton,
  unit_ValueDrift;

type
  TdlgValueDrift = class(TForm)
    pnlBottom: TRzPanel;
    btnClose: TRzBitBtn;
    pnlClient: TRzPanel;
    lblSummary: TRzLabel;
    lvDrift: TListView;
  private
    procedure LoadReport(const Scope: string; const Report: TValueDriftReport);
  public
    class procedure Execute(const Scope: string; const Report: TValueDriftReport);
  end;

function DriftSummaryText(const Scope: string; const Report: TValueDriftReport): string;

implementation

uses
  unit_DataModel, unit_Item;

{$R *.dfm}

function DriftSummaryText(const Scope: string; const Report: TValueDriftReport): string;
begin
  if Report.Checked = 0 then
    Result := Format('"%s" and its sub-items hold no values read from a file ' +
      'or derived from other values.', [Scope])
  else if Length(Report.Rows) = 0 then
    Result := Format('No differences in %d Reader and Derived values of "%s" ' +
      'and its sub-items.', [Report.Checked, Scope])
  else
    Result := Format('%d of %d Reader and Derived values of "%s" and its ' +
      'sub-items differ from what the readers and formulas return today.',
      [Length(Report.Rows), Report.Checked, Scope]);
end;

function NumberText(Value: Double): string;
begin
  Result := FloatToStrF(Value, ffGeneral, 10, 0);
end;

function ReaderText(const ReaderId, ReaderVersion: string): string;
begin
  if ReaderId = '' then
    Result := ''
  else
    Result := ReaderId + ' ' + ReaderVersion;
end;

class procedure TdlgValueDrift.Execute(const Scope: string;
  const Report: TValueDriftReport);
var
  Dlg: TdlgValueDrift;
begin
  if Length(Report.Rows) = 0 then
  begin
    MessageDlg(DriftSummaryText(Scope, Report), mtInformation, [mbOK], 0);
    Exit;
  end;
  Dlg := TdlgValueDrift.Create(Application);
  try
    Dlg.LoadReport(Scope, Report);
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

procedure TdlgValueDrift.LoadReport(const Scope: string;
  const Report: TValueDriftReport);
var
  Row: TValueDriftRow;
  Entry: TListItem;
  Item: TItem;
  ItemText: string;
begin
  lblSummary.Caption := DriftSummaryText(Scope, Report);
  lvDrift.Items.BeginUpdate;
  try
    lvDrift.Items.Clear;
    for Row in Report.Rows do
    begin
      Item := Model.Manager.Find<TItem>(Row.ItemId);
      if Assigned(Item) then
        ItemText := Format('%s (%d)', [Item.Title, Row.ItemId])
      else
        ItemText := IntToStr(Row.ItemId);
      Entry := lvDrift.Items.Add;
      Entry.Caption := IntToStr(Row.ValueId);
      Entry.SubItems.Add(ItemText);
      Entry.SubItems.Add(IntToStr(Row.FileId));
      Entry.SubItems.Add(Row.KeyName);
      Entry.SubItems.Add(DriftFlagsText(Row.Flags));
      Entry.SubItems.Add(NumberText(Row.StoredValue));
      if Row.HasCurrentValue then
        Entry.SubItems.Add(NumberText(Row.CurrentValue))
      else
        Entry.SubItems.Add('');
      Entry.SubItems.Add(ReaderText(Row.StoredReaderId, Row.StoredReaderVersion));
      Entry.SubItems.Add(ReaderText(Row.CurrentReaderId, Row.CurrentReaderVersion));
      Entry.SubItems.Add(Row.Message);
    end;
  finally
    lvDrift.Items.EndUpdate;
  end;
end;

end.
