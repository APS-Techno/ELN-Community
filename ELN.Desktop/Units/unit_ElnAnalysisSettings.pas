unit unit_ElnAnalysisSettings;

interface

uses
  System.Classes, System.SysUtils,
  unit_ELNPluginCore;

type
  TElnAnalysisSettings = class(TInterfacedObject, IElnAnalysisSettings)
  public
    function Apply(FileId: Int64; const ReaderId, ExpectedJson, NewJson: string;
      out CurrentJson: string): TAnalysisApplyResult;
    function CurrentUserId: Integer;
  end;

procedure InstallElnAnalysisSettings;
procedure UninstallElnAnalysisSettings;

function AnalysisStatusText(const Status: string): string;

function PluginLoadErrorText(const Plugin: IViewerPlugin;
  const Fallback: string): string;

function AttachAnalysisContext(const Plugin: IViewerPlugin;
  const FilePath: string; FileId: Int64): IAnalysisKeyValueProvider;

implementation

uses
  System.IOUtils,
  unit_DataModel, unit_AnalysisSettingsModel;

function StoredContentHash(FileId: Int64): string;
var
  StoragePath, TempPath: string;
begin
  Result := '';
  StoragePath := StringReplace(Model.GetFileName(FileId), '\', '/', [rfReplaceAll]);
  if (StoragePath = '') or not Model.Storage.Exists(StoragePath) then
    Exit;
  TempPath := TPath.Combine(TPath.GetTempPath,
    'ELN_Analysis_' + TGUID.NewGuid.ToString + '.tmp');
  Model.Storage.CopyOut(StoragePath, TempPath);
  try
    Result := TAnalysisSettingsModel.ContentHash(TempPath);
  finally
    TFile.Delete(TempPath);
  end;
end;

function AnalysisStatusText(const Status: string): string;
begin
  if Status = '' then
    Result := ''
  else if Status = ANALYSIS_STATUS_NO_PLATEAU then
    Result := 'No analysis interval qualified; interval-based values were not extracted.' +
      sLineBreak
  else if Status = ANALYSIS_STATUS_STALE_SELECTION then
    Result := 'The shared analysis interval was set for a different version of ' +
      'this file; review and apply it again in the viewer.' + sLineBreak
  else if Status = ANALYSIS_STATUS_INTERVAL_UNUSABLE then
    Result := 'The analysis interval cannot be used for this file; ' +
      'interval-based values were not extracted.' + sLineBreak
  else
    Result := 'Analysis status: ' + Status + sLineBreak;
end;

function PluginLoadErrorText(const Plugin: IViewerPlugin;
  const Fallback: string): string;
var
  Analysis: IAnalysisKeyValueProvider;
begin
  Result := Fallback;
  if Supports(Plugin, IAnalysisKeyValueProvider, Analysis) and
    (Analysis.GetLoadError <> '') then
    Result := Analysis.GetLoadError;
end;

function AttachAnalysisContext(const Plugin: IViewerPlugin;
  const FilePath: string; FileId: Int64): IAnalysisKeyValueProvider;
var
  Context: TAnalysisContext;
  Settings: TAnalysisSettingsModel;
  ReaderId, ReaderVersion: string;
begin
  if not Supports(Plugin, IAnalysisKeyValueProvider, Result) then
    Exit(nil);
  ReaderIdentityOf(Plugin, ReaderId, ReaderVersion);
  Context := Default(TAnalysisContext);
  Context.Kind := ackCurrent;
  Context.FileId := FileId;
  Settings := TAnalysisSettingsModel.Create(Model.Manager);
  try
    Settings.CurrentSelection(ReaderId, FileId, FilePath, Context.FileHash,
      Context.SharedSelection);
  finally
    Settings.Free;
  end;
  Result.SetAnalysisContext(Context);
end;

function TElnAnalysisSettings.Apply(FileId: Int64; const ReaderId, ExpectedJson,
  NewJson: string; out CurrentJson: string): TAnalysisApplyResult;
const
  Mapped: array[TAnalysisApplyStatus] of TAnalysisApplyResult = (aarApplied,
    aarConflict, aarDenied, aarSigned, aarHashMismatch, aarInvalid, aarTooLarge);
var
  Settings: TAnalysisSettingsModel;
begin
  CurrentJson := '';
  if not Assigned(Model) or not Assigned(Model.Manager) then
    Exit(aarInvalid);
  Settings := TAnalysisSettingsModel.Create(Model.Manager);
  try
    Result := Mapped[Settings.ApplySelection(Model.Access, Model.User, ReaderId,
      FileId, ExpectedJson, NewJson, StoredContentHash(FileId), CurrentJson)];
  finally
    Settings.Free;
  end;
end;

function TElnAnalysisSettings.CurrentUserId: Integer;
begin
  if Assigned(Model) and Assigned(Model.User) then
    Result := Model.User.Id
  else
    Result := 0;
end;

procedure InstallElnAnalysisSettings;
begin
  ElnAnalysisSettings := TElnAnalysisSettings.Create;
end;

procedure UninstallElnAnalysisSettings;
begin
  ElnAnalysisSettings := nil;
end;

end.
