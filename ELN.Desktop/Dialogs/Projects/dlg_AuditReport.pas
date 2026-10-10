unit dlg_AuditReport;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Dialogs,
  unit_AuditRule, unit_AuditModel;

type
  TNavigateItemProc = procedure(Sender: TObject; ProjectId, FolderId, ItemId: Integer) of object;

  TdlgAuditReport = class(TForm)
    pnlTop: TPanel;
    lblTarget: TLabel;
    lblSummary: TLabel;
    lblTimestamp: TLabel;
    lvResults: TListView;
    pnlBottom: TPanel;
    btnGoTo: TButton;
    btnExport: TButton;
    btnClose: TButton;
    procedure FormDestroy(Sender: TObject);
    procedure btnGoToClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure lvResultsDblClick(Sender: TObject);
    procedure lvResultsCustomDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure lvResultsCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
      SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
  private
    FReport: TAuditReport;
    FOnNavigate: TNavigateItemProc;
    procedure PopulateGrid;
    procedure NavigateToSelected;
  public
    class procedure Execute(ProjectId, FolderId: Integer; NavigateProc: TNavigateItemProc);
  end;

implementation

uses
  System.StrUtils,
  unit_DataModel,
  unit_Project,
  unit_TimeHelper;

{$R *.dfm}

const
  clSevError   = TColor($2020CC);   
  clSevWarning = TColor($0080CC);   


procedure TdlgAuditReport.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FReport);
end;

procedure TdlgAuditReport.PopulateGrid;
var
  V: TAuditViolation;
  LI: TListItem;
  Missing: string;
  ErrorCount, WarningCount, HealthCount, RuleCount: Integer;
begin
  lvResults.Items.BeginUpdate;
  try
    lvResults.Items.Clear;
    for V in FReport.Violations do
    begin
      LI := lvResults.Items.Add;
      case V.Category of
        acHealth: LI.Caption := 'Health';
        acRule:   LI.Caption := 'Rule';
      end;
      case V.RuleSeverity of
        asError:   LI.SubItems.Add('Error');
        asWarning: LI.SubItems.Add('Warning');
      end;
      LI.SubItems.Add(V.ItemTitle);
      LI.SubItems.Add(V.ProjectPath);
      LI.SubItems.Add(V.RuleTitle);

      Missing := '';
      if V.MissingFiles <> '' then
        Missing := V.MissingFiles;
      if V.MissingValues <> '' then
      begin
        if Missing <> '' then
          Missing := Missing + ', ';
        Missing := Missing + V.MissingValues;
      end;
      LI.SubItems.Add(Missing);

      LI.Data := Pointer(V.ItemId);
    end;
  finally
    lvResults.Items.EndUpdate;
  end;

  lblTarget.Caption := FReport.TargetTitle;

  HealthCount := 0;
  RuleCount := 0;
  ErrorCount := 0;
  WarningCount := 0;
  for V in FReport.Violations do
  begin
    case V.Category of
      acHealth: Inc(HealthCount);
      acRule:   Inc(RuleCount);
    end;
    case V.RuleSeverity of
      asError:   Inc(ErrorCount);
      asWarning: Inc(WarningCount);
    end;
  end;

  lblSummary.Caption := Format('Checked %d items: %d health issues, %d rule violations (%d errors, %d warnings)',
    [FReport.TotalItemsChecked, HealthCount, RuleCount, ErrorCount, WarningCount]);

  lblTimestamp.Caption := 'Run: ' + FormatDateTime('yyyy-mm-dd hh:nn', FromUTC(FReport.RunDate));
end;

procedure TdlgAuditReport.lvResultsCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  Sender.Canvas.Font.Style := [fsBold];
  if Item.Caption = 'Health' then
    Sender.Canvas.Font.Color := clGray
  else
    Sender.Canvas.Font.Color := clWindowText;
end;

procedure TdlgAuditReport.lvResultsCustomDrawSubItem(Sender: TCustomListView;
  Item: TListItem; SubItem: Integer; State: TCustomDrawState;
  var DefaultDraw: Boolean);
begin
  if SubItem = 1 then
  begin
    if Item.SubItems.Count < 1 then Exit;
    Sender.Canvas.Font.Style := [fsBold];
    if Item.SubItems[0] = 'Error' then
      Sender.Canvas.Font.Color := clSevError
    else if Item.SubItems[0] = 'Warning' then
      Sender.Canvas.Font.Color := clSevWarning
    else
    begin
      Sender.Canvas.Font.Style := [];
      Sender.Canvas.Font.Color := clWindowText;
    end;
  end
  else
  begin
    Sender.Canvas.Font.Style := [];
    Sender.Canvas.Font.Color := clWindowText;
  end;
end;

procedure TdlgAuditReport.NavigateToSelected;
var
  LI: TListItem;
  ItemId, Idx: Integer;
  V: TAuditViolation;
begin
  LI := lvResults.Selected;
  if not Assigned(LI) then Exit;
  if not Assigned(FOnNavigate) then Exit;

  ItemId := Integer(LI.Data);
  for Idx := 0 to FReport.Violations.Count - 1 do
  begin
    if FReport.Violations[Idx].ItemId = ItemId then
    begin
      V := FReport.Violations[Idx];
      ModalResult := mrClose;
      FOnNavigate(Self, V.ProjectId, V.FolderId, V.ItemId);
      Break;
    end;
  end;
end;

procedure TdlgAuditReport.btnGoToClick(Sender: TObject);
begin
  NavigateToSelected;
end;

procedure TdlgAuditReport.lvResultsDblClick(Sender: TObject);
begin
  NavigateToSelected;
end;

procedure TdlgAuditReport.btnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Lines: TStringList;
  V: TAuditViolation;
  Missing: string;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := 'Export Data Quality Report';
    Dlg.Filter := 'CSV files (*.csv)|*.csv';
    Dlg.DefaultExt := 'csv';
    Dlg.FileName := 'DataQualityReport';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;

    Lines := TStringList.Create;
    try
      Lines.Add('Category;Severity;Item;Location;Rule;Missing');
      for V in FReport.Violations do
      begin
        Missing := '';
        if V.MissingFiles <> '' then
          Missing := V.MissingFiles;
        if V.MissingValues <> '' then
        begin
          if Missing <> '' then
            Missing := Missing + ', ';
          Missing := Missing + V.MissingValues;
        end;

        Lines.Add(Format('%s;%s;%s;%s;%s;%s', [
          IfThen(V.Category = acHealth, 'Health', 'Rule'),
          IfThen(V.RuleSeverity = asError, 'Error', 'Warning'),
          V.ItemTitle, V.ProjectPath, V.RuleTitle, Missing]));
      end;
      Lines.SaveToFile(Dlg.FileName);
    finally
      Lines.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

class procedure TdlgAuditReport.Execute(ProjectId, FolderId: Integer;
  NavigateProc: TNavigateItemProc);
var
  Dlg: TdlgAuditReport;
  Proj: TProject;
  Folder: TFolder;
  TargetTitle: string;
  Report: TAuditReport;
  SaveCursor: TCursor;
begin
  Proj := Model.Projects.GetProject(ProjectId);
  if not Assigned(Proj) then Exit;

  TargetTitle := Proj.Title;
  if FolderId > 0 then
  begin
    Folder := Model.Manager.Find<TFolder>(FolderId);
    if Assigned(Folder) then
      TargetTitle := TargetTitle + ' > ' + Folder.Title;
  end;

  SaveCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    Report := Model.AuditRules.RunAudit(ProjectId, FolderId);
  finally
    Screen.Cursor := SaveCursor;
  end;

  Dlg := TdlgAuditReport.Create(Application);
  try
    Dlg.FReport := Report;
    Dlg.FOnNavigate := NavigateProc;
    Dlg.PopulateGrid;
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

end.
