unit dlg_SearchSetup;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, unit_SearchArtifacts;

type
  TSetupMode = (smInstall, smVerify);

  TSearchSetupWorker = class(TThread)
  private
    FLock: TCriticalSection;
    FMode: TSetupMode;
    FManifest: TSearchArtifactManifest;
    FRoot: string;
    FCancel, FFinished, FCancelled: Boolean;
    FDone, FTotal: Int64;
    FCurrentFile, FError: string;
    FReport: TArtifactReport;
    function IsCancelled: Boolean;
    procedure Publish(DoneBytes, TotalBytes: Int64; const CurrentFile: string);
  protected
    procedure Execute; override;
  public
    constructor Create(Mode: TSetupMode; const Manifest: TSearchArtifactManifest;
      const Root: string);
    destructor Destroy; override;
    procedure Cancel;
    procedure Snapshot(out DoneBytes, TotalBytes: Int64; out CurrentFile: string;
      out Finished: Boolean);
    property Mode: TSetupMode read FMode;
    property Cancelled: Boolean read FCancelled;
    property Error: string read FError;
    property Report: TArtifactReport read FReport;
  end;

  TdlgSearchSetup = class(TForm)
    lblState: TLabel;
    lblSize: TLabel;
    lblFolder: TLabel;
    lblLicense: TLabel;
    lvParts: TListView;
    lblIndex: TLabel;
    lblFile: TLabel;
    barProgress: TProgressBar;
    btnInstall: TButton;
    btnVerify: TButton;
    btnRemove: TButton;
    btnClose: TButton;
    tmrPoll: TTimer;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnInstallClick(Sender: TObject);
    procedure btnVerifyClick(Sender: TObject);
    procedure btnRemoveClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure tmrPollTimer(Sender: TObject);
  private
    FManifest: TSearchArtifactManifest;
    FManifestOk: Boolean;
    FRoot: string;
    FWorker: TSearchSetupWorker;
    FInstalled, FComplete, FVerified: Boolean;
    FOnReleasing, FOnChanged: TProc;
    FIndexStatus: TFunc<string>;
    procedure LoadManifest;
    procedure ApplyReport(const Report: TArtifactReport; Verified: Boolean);
    procedure FillParts(const Report: TArtifactReport; Verified: Boolean);
    function DownloadSizeText: string;
    function PartTermsText: string;
    procedure RecheckSizes;
    procedure UpdateButtons;
    procedure UpdateIndexText;
    procedure StartWorker(Mode: TSetupMode);
    procedure StopWorker;
    procedure FinishWorker;
    function ArtifactFoldersExist: Boolean;
    procedure NotifyChanged;
  public
    class procedure Execute(const OnReleasing, OnChanged: TProc;
      const IndexStatus: TFunc<string>);
  end;

implementation

{$R *.dfm}

uses
  System.IOUtils, Vcl.Dialogs, System.UITypes, unit_SearchArtifactInstall;

constructor TSearchSetupWorker.Create(Mode: TSetupMode;
  const Manifest: TSearchArtifactManifest; const Root: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FMode := Mode;
  FManifest := Manifest;
  FRoot := Root;
end;

destructor TSearchSetupWorker.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TSearchSetupWorker.Cancel;
begin
  FLock.Enter;
  try
    FCancel := True;
  finally
    FLock.Leave;
  end;
end;

function TSearchSetupWorker.IsCancelled: Boolean;
begin
  FLock.Enter;
  try
    Result := FCancel;
  finally
    FLock.Leave;
  end;
end;

procedure TSearchSetupWorker.Publish(DoneBytes, TotalBytes: Int64;
  const CurrentFile: string);
begin
  FLock.Enter;
  try
    FDone := DoneBytes;
    FTotal := TotalBytes;
    FCurrentFile := CurrentFile;
  finally
    FLock.Leave;
  end;
end;

procedure TSearchSetupWorker.Snapshot(out DoneBytes, TotalBytes: Int64;
  out CurrentFile: string; out Finished: Boolean);
begin
  FLock.Enter;
  try
    DoneBytes := FDone;
    TotalBytes := FTotal;
    CurrentFile := FCurrentFile;
    Finished := FFinished;
  finally
    FLock.Leave;
  end;
end;

procedure TSearchSetupWorker.Execute;
begin
  try
    case FMode of
      smInstall:
        InstallSearchArtifacts(FManifest, FRoot, THttpArtifactFetcher.Create,
          procedure(DoneBytes, TotalBytes: Int64; const CurrentFile: string)
          begin
            Publish(DoneBytes, TotalBytes, CurrentFile);
          end, IsCancelled);
      smVerify:
        FReport := CheckArtifactReport(FManifest, FRoot, True);
    end;
  except
    on EOperationCancelled do
      FCancelled := True;
    on E: Exception do
      FError := E.Message;
  end;
  FLock.Enter;
  try
    FFinished := True;
  finally
    FLock.Leave;
  end;
end;

class procedure TdlgSearchSetup.Execute(const OnReleasing, OnChanged: TProc;
  const IndexStatus: TFunc<string>);
var
  Dialog: TdlgSearchSetup;
begin
  Dialog := TdlgSearchSetup.Create(Application);
  try
    Dialog.FOnReleasing := OnReleasing;
    Dialog.FOnChanged := OnChanged;
    Dialog.FIndexStatus := IndexStatus;
    Dialog.LoadManifest;
    Dialog.UpdateIndexText;
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

procedure TdlgSearchSetup.LoadManifest;
var
  Path: string;
begin
  FRoot := SearchArtifactRoot;
  lblFolder.Caption := 'Target folder: ' + FRoot;
  lblFolder.Hint := FRoot;
  Path := TSearchArtifactManifest.DefaultPath;
  FManifestOk := False;
  if not TFile.Exists(Path) then
    lblState.Caption := 'State: Not available. The file search-artifacts.json is missing beside the program.'
  else
    try
      FManifest := TSearchArtifactManifest.LoadFromFile(Path);
      FManifestOk := True;
    except
      on E: Exception do
        lblState.Caption := 'State: Not available. ' + E.Message;
    end;
  if FManifestOk then
  begin
    lblSize.Caption := DownloadSizeText;
    lblLicense.Caption := PartTermsText;
    RecheckSizes;
  end
  else
  begin
    lblSize.Caption := 'Download size: unknown';
    lblLicense.Caption := ' ';
  end;
  UpdateButtons;
end;

function TdlgSearchSetup.DownloadSizeText: string;
const
  Megabyte = 1024 * 1024;
var
  Part: TArtifactPart;
  RequiredBytes, OptionalBytes: Int64;
begin
  RequiredBytes := 0;
  OptionalBytes := 0;
  for Part in FManifest.Parts do
    if Part.Optional then
      Inc(OptionalBytes, Part.Size)
    else
      Inc(RequiredBytes, Part.Size);
  Result := Format('Download size: %.0f MB (required %.0f MB, optional %.0f MB)',
    [(RequiredBytes + OptionalBytes) / Megabyte, RequiredBytes / Megabyte, OptionalBytes / Megabyte]);
end;

function TdlgSearchSetup.PartTermsText: string;
var
  Part: TArtifactPart;
begin
  Result := '';
  for Part in FManifest.Parts do
    if Part.DataTerms <> '' then
    begin
      if Result <> '' then
        Result := Result + sLineBreak;
      Result := Result + Part.Name + ': ' + Part.DataTerms;
    end;
  if Result = '' then
    Result := ' ';
end;

procedure TdlgSearchSetup.FillParts(const Report: TArtifactReport; Verified: Boolean);
const
  Megabyte = 1024 * 1024;
var
  I: Integer;
  Item: TListItem;
  StateText: string;
begin
  lvParts.Items.BeginUpdate;
  try
    lvParts.Items.Clear;
    for I := 0 to High(Report.Parts) do
    begin
      case Report.Checks[I].State of
        asReady:
          if Verified then
            StateText := 'Verified'
          else
            StateText := 'Installed';
        asMissing: StateText := 'Missing';
        asWrongSize: StateText := 'Wrong size';
        asWrongHash: StateText := 'Wrong checksum';
      end;
      Item := lvParts.Items.Add;
      Item.Caption := Report.Parts[I].Name;
      if Report.Parts[I].Optional then
        Item.SubItems.Add('Optional')
      else
        Item.SubItems.Add('Required');
      Item.SubItems.Add(Report.Parts[I].License);
      Item.SubItems.Add(Format('%.1f MB', [Report.Parts[I].Size / Megabyte]));
      Item.SubItems.Add(StateText);
    end;
  finally
    lvParts.Items.EndUpdate;
  end;
end;

procedure TdlgSearchSetup.ApplyReport(const Report: TArtifactReport; Verified: Boolean);
var
  Suffix: string;
begin
  FInstalled := Report.Readiness <> arNotReady;
  FComplete := Report.Readiness = arReady;
  FVerified := FInstalled and Verified;
  FillParts(Report, FVerified);
  if Report.Readiness = arReadyOptionalMissing then
    Suffix := ' (optional parts missing)'
  else
    Suffix := '';
  if FVerified then
    lblState.Caption := 'State: Installed and verified' + Suffix
  else if FInstalled then
    lblState.Caption := 'State: Installed' + Suffix
  else if Report.Required.State = asMissing then
    lblState.Caption := 'State: Not installed'
  else
    lblState.Caption := 'State: Not installed. ' + Report.Required.FirstProblem;
  UpdateButtons;
end;

procedure TdlgSearchSetup.RecheckSizes;
begin
  ApplyReport(CheckArtifactReport(FManifest, FRoot, False), False);
end;

function TdlgSearchSetup.ArtifactFoldersExist: Boolean;
var
  M: TArtifactModel;
  A: TArtifactArchive;
begin
  Result := False;
  if not FManifestOk then
    Exit;
  for M in FManifest.Models do
    if TDirectory.Exists(TPath.Combine(FRoot, M.Folder)) then
      Exit(True);
  for A in FManifest.Archives do
    if TDirectory.Exists(TPath.Combine(FRoot, A.Folder)) then
      Exit(True);
end;

procedure TdlgSearchSetup.UpdateButtons;
var
  Idle: Boolean;
begin
  Idle := FWorker = nil;
  btnInstall.Enabled := FManifestOk and Idle and not FComplete;
  btnVerify.Enabled := FManifestOk and Idle and ArtifactFoldersExist;
  btnRemove.Enabled := btnVerify.Enabled;
  if Idle then
    btnClose.Caption := 'Close'
  else if FWorker.Mode = smInstall then
    btnClose.Caption := 'Cancel'
  else
    btnClose.Caption := 'Close';
end;

procedure TdlgSearchSetup.UpdateIndexText;
begin
  if Assigned(FIndexStatus) then
    lblIndex.Caption := 'Index: ' + FIndexStatus()
  else
    lblIndex.Caption := 'Index:';
end;

procedure TdlgSearchSetup.NotifyChanged;
begin
  if Assigned(FOnChanged) then
    FOnChanged();
end;

procedure TdlgSearchSetup.StartWorker(Mode: TSetupMode);
begin
  FWorker := TSearchSetupWorker.Create(Mode, FManifest, FRoot);
  barProgress.Position := 0;
  if Mode = smVerify then
    lblState.Caption := 'State: Checking...';
  UpdateButtons;
  FWorker.Start;
end;

procedure TdlgSearchSetup.StopWorker;
var
  Worker: TSearchSetupWorker;
begin
  if FWorker = nil then
    Exit;
  Worker := FWorker;
  FWorker := nil;
  Worker.Cancel;
  Worker.WaitFor;
  Worker.Free;
end;

procedure TdlgSearchSetup.FinishWorker;
var
  Worker: TSearchSetupWorker;
  Mode: TSetupMode;
  ErrorText: string;
  WasCancelled: Boolean;
  Report: TArtifactReport;
begin
  Worker := FWorker;
  FWorker := nil;
  try
    Worker.WaitFor;
    Mode := Worker.Mode;
    ErrorText := Worker.Error;
    WasCancelled := Worker.Cancelled;
    Report := Worker.Report;
  finally
    Worker.Free;
  end;
  barProgress.Position := 0;
  lblFile.Caption := ' ';
  if (ErrorText <> '') or WasCancelled then
  begin
    RecheckSizes;
    if WasCancelled and (ErrorText = '') then
      lblFile.Caption := 'Download cancelled';
    if (Mode = smInstall) and FInstalled then
      NotifyChanged;
    if ErrorText <> '' then
      MessageDlg(ErrorText, mtError, [mbOK], 0);
    Exit;
  end;
  if Mode = smInstall then
    Report := CheckArtifactReport(FManifest, FRoot, False);
  ApplyReport(Report, True);
  if FInstalled then
    NotifyChanged;
end;

procedure TdlgSearchSetup.tmrPollTimer(Sender: TObject);
var
  DoneBytes, TotalBytes: Int64;
  CurrentFile: string;
  Finished: Boolean;
begin
  UpdateIndexText;
  if FWorker = nil then
    Exit;
  FWorker.Snapshot(DoneBytes, TotalBytes, CurrentFile, Finished);
  if Finished then
  begin
    FinishWorker;
    Exit;
  end;
  if TotalBytes > 0 then
    barProgress.Position := Integer(DoneBytes * barProgress.Max div TotalBytes);
  lblFile.Caption := CurrentFile;
end;

procedure TdlgSearchSetup.btnInstallClick(Sender: TObject);
begin
  if Assigned(FOnReleasing) then
    FOnReleasing();
  StartWorker(smInstall);
end;

procedure TdlgSearchSetup.btnVerifyClick(Sender: TObject);
begin
  StartWorker(smVerify);
end;

procedure TdlgSearchSetup.btnRemoveClick(Sender: TObject);
var
  M: TArtifactModel;
  A: TArtifactArchive;
begin
  if MessageDlg('Remove the downloaded model and runtime files from' + sLineBreak + FRoot + '?',
    mtConfirmation, [mbYes, mbNo], 0, mbNo) <> mrYes then
    Exit;
  if Assigned(FOnReleasing) then
    FOnReleasing();
  try
    for M in FManifest.Models do
      if TDirectory.Exists(TPath.Combine(FRoot, M.Folder)) then
        TDirectory.Delete(TPath.Combine(FRoot, M.Folder), True);
    for A in FManifest.Archives do
      if TDirectory.Exists(TPath.Combine(FRoot, A.Folder)) then
        TDirectory.Delete(TPath.Combine(FRoot, A.Folder), True);
    if TDirectory.Exists(FRoot) and TDirectory.IsEmpty(FRoot) then
      TDirectory.Delete(FRoot);
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
  RecheckSizes;
  UpdateIndexText;
end;

procedure TdlgSearchSetup.btnCloseClick(Sender: TObject);
begin
  if (FWorker <> nil) and (FWorker.Mode = smInstall) then
    FWorker.Cancel
  else
    Close;
end;

procedure TdlgSearchSetup.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  StopWorker;
  CanClose := True;
end;

end.
