unit dlg_SeriesLink;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ExtCtrls, RzPanel, RzCommon,
  Aurelius.Engine.ObjectManager,
  unit_User,
  unit_ProjectAccessPolicy,
  unit_SeriesLinkVM;

type
  TdlgSeriesLink = class(TForm)
    lblSeries: TLabel;
    lstSeries: TListBox;
    lblPoint: TLabel;
    cmbPoint: TComboBox;
    chkNew: TCheckBox;
    lblPreview: TLabel;
    lstPreview: TListBox;
    pnlButtons: TRzPanel;
    btnOK: TButton;
    btnCancel: TButton;
    procedure lstSeriesClick(Sender: TObject);
    procedure cmbPointChange(Sender: TObject);
    procedure chkNewClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FVM: TSeriesLinkVM;
    FApplied: TSeriesLinkResult;
    procedure ShowState;
  public
    class function Execute(AManager: TObjectManager; AUser: TUser;
      const AAccess: IProjectAccessPolicy; AProjectId: Integer;
      const AItemIds: TArray<Integer>): Integer; static;
  end;

implementation

{$R *.dfm}

uses
  System.UITypes,
  Vcl.Dialogs,
  unit_SeriesModel,
  unit_SeriesVM;

const
  ByValueText = '(match by value)';

procedure TdlgSeriesLink.ShowState;
var
  Line: string;
begin
  lstPreview.Items.BeginUpdate;
  try
    lstPreview.Items.Clear;
    for Line in FVM.Lines do
      lstPreview.Items.Add(Line);
  finally
    lstPreview.Items.EndUpdate;
  end;
  lblPoint.Visible := FVM.CanChoosePoint;
  cmbPoint.Visible := FVM.CanChoosePoint;
  if FVM.CanChoosePoint then
  begin
    cmbPoint.Items.Clear;
    cmbPoint.Items.Add(ByValueText);
    for Line in FVM.PointTexts do
      cmbPoint.Items.Add(Line);
    cmbPoint.ItemIndex := FVM.PointIndex + 1;
  end;
  chkNew.Enabled := FVM.PointIndex < 0;
  btnOK.Enabled := FVM.CanApply;
end;

procedure TdlgSeriesLink.lstSeriesClick(Sender: TObject);
begin
  if lstSeries.ItemIndex >= 0 then
  begin
    FVM.SelectSeries(lstSeries.ItemIndex);
    ShowState;
  end;
end;

procedure TdlgSeriesLink.cmbPointChange(Sender: TObject);
begin
  FVM.ChoosePoint(cmbPoint.ItemIndex - 1);
  ShowState;
end;

procedure TdlgSeriesLink.chkNewClick(Sender: TObject);
begin
  FVM.CreateMissing := chkNew.Checked;
  ShowState;
end;

procedure TdlgSeriesLink.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if ModalResult <> mrOk then
    Exit;
  try
    FApplied := FVM.Apply;
  except
    on E: ESeriesError do
    begin
      MessageDlg(E.Message, mtWarning, [mbOK], 0);
      FVM.SelectSeries(FVM.SeriesIndex);
      ShowState;
      CanClose := False;
      Exit;
    end;
  end;
  if FApplied.Linked = 0 then
  begin
    MessageDlg('Nothing was linked.', mtInformation, [mbOK], 0);
    CanClose := False;
    Exit;
  end;
  if FApplied.Skipped > 0 then
    MessageDlg(Format('%d linked, %d skipped.', [FApplied.Linked, FApplied.Skipped]),
      mtInformation, [mbOK], 0);
end;

class function TdlgSeriesLink.Execute(AManager: TObjectManager; AUser: TUser;
  const AAccess: IProjectAccessPolicy; AProjectId: Integer;
  const AItemIds: TArray<Integer>): Integer;
var
  Dlg: TdlgSeriesLink;
  S: TSeriesSummary;
begin
  Result := 0;
  Dlg := TdlgSeriesLink.Create(Application);
  try
    try
      Dlg.FVM := TSeriesLinkVM.Create(AManager, AUser, AAccess, AProjectId, AItemIds);
    except
      on E: ESeriesError do
      begin
        MessageDlg(E.Message, mtWarning, [mbOK], 0);
        Exit;
      end;
    end;
    try
      if Length(Dlg.FVM.Series) = 0 then
      begin
        MessageDlg('This project has no active series. Start a series first.',
          mtInformation, [mbOK], 0);
        Exit;
      end;
      for S in Dlg.FVM.Series do
        Dlg.lstSeries.Items.Add(Format('%s  (%s)', [S.Title, TSeriesVM.ProgressText(S)]));
      Dlg.lstSeries.ItemIndex := Dlg.FVM.SeriesIndex;
      Dlg.ShowState;
      if Dlg.ShowModal = mrOk then
        Result := Dlg.FApplied.SeriesId;
    finally
      Dlg.FVM.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
