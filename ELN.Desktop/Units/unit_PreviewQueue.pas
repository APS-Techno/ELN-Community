unit unit_PreviewQueue;

interface

uses
  System.SysUtils, System.Classes, Vcl.ExtCtrls,
  unit_ELNPluginTypes, frame_ContentViewer;

type
  TPreviewQueueItem = record
    FileId: Int64;
    ItemId: Integer;
    FilePath: string;
    PreviewPath: string;
    Extension: string;
  end;

  TPreviewStatusEvent = procedure(const AText: string) of object;
  TPreviewUpdateEvent = procedure(FileId: Int64; const PreviewPath: string) of object;
  TKeyValuesExtractedEvent = procedure(ItemId: Integer; FileId: Int64;
    const ReaderId, ReaderVersion: string;
    const KeyValues: TArray<TPluginKeyValue>) of object;

  TPreviewQueue = class
  private
    FQueue: TArray<TPreviewQueueItem>;
    FIndex: Integer;
    FTimer: TTimer;
    FContentViewer: TframeContentViewer;
    FOnStatus: TPreviewStatusEvent;
    FOnUpdate: TPreviewUpdateEvent;
    FOnComplete: TNotifyEvent;
    FOnKeyValuesExtracted: TKeyValuesExtractedEvent;
    procedure TimerFire(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; AContentViewer: TframeContentViewer);
    destructor Destroy; override;
    procedure Start(const AQueue: TArray<TPreviewQueueItem>);
    procedure Stop;
    function IsRunning: Boolean;
    property OnStatus: TPreviewStatusEvent read FOnStatus write FOnStatus;
    property OnUpdate: TPreviewUpdateEvent read FOnUpdate write FOnUpdate;
    property OnComplete: TNotifyEvent read FOnComplete write FOnComplete;
    property OnKeyValuesExtracted: TKeyValuesExtractedEvent read FOnKeyValuesExtracted write FOnKeyValuesExtracted;
  end;

implementation

uses
  Vcl.Graphics,
  Vcl.Imaging.PngImage,
  unit_ELNPluginCore,
  unit_DataModel;


constructor TPreviewQueue.Create(AOwner: TComponent; AContentViewer: TframeContentViewer);
begin
  inherited Create;
  FContentViewer := AContentViewer;
  // Own the timer (Create(nil) + free it in the destructor) instead of tying its
  // lifetime to AOwner, so a FreeAndNil(FPreviewQueue)/recreate per re-login does
  // not strand an owner-parented TTimer.
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 200;
  FTimer.OnTimer := TimerFire;
end;

destructor TPreviewQueue.Destroy;
begin
  FTimer.Enabled := False;
  FTimer.Free;
  inherited;
end;

procedure TPreviewQueue.Start(const AQueue: TArray<TPreviewQueueItem>);
begin
  if Length(AQueue) = 0 then Exit;
  Stop;
  FQueue := AQueue;
  FIndex := 0;
  FTimer.Enabled := True;
end;

procedure TPreviewQueue.Stop;
begin
  FTimer.Enabled := False;
  SetLength(FQueue, 0);
  FIndex := 0;
end;

function TPreviewQueue.IsRunning: Boolean;
begin
  Result := FTimer.Enabled;
end;

procedure TPreviewQueue.TimerFire(Sender: TObject);
var
  QItem: TPreviewQueueItem;
  Plugin: IViewerPlugin;
  PreviewProvider: IPreviewProvider;
  KVProvider: IKeyValueProvider;
  Bmp: TBitmap;
  Png: TPngImage;
  PreviewOwner: TComponent;
begin
  // Session guard: if the user has logged out (model torn down / rebuilt),
  // abort rather than write extracted values via a stale session VM.
  if (Model = nil) or (Model.User = nil) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;

  if FIndex > High(FQueue) then
  begin
    FTimer.Enabled := False;
    SetLength(FQueue, 0);
    FIndex := 0;
    if Assigned(FOnStatus) then
      FOnStatus('');
    if Assigned(FOnComplete) then
      FOnComplete(Self);
    Exit;
  end;

  QItem := FQueue[FIndex];
  Inc(FIndex);

  if Assigned(FOnStatus) then
    FOnStatus(Format('Generating preview %d of %d...', [FIndex, Length(FQueue)]));

  if not FileExists(QItem.FilePath) then Exit;

  PreviewOwner := TComponent.Create(nil);
  try
  Plugin := FContentViewer.LoadPreviewPlugin(QItem.FilePath,
    QItem.ItemId, QItem.FileId, PreviewOwner);
  if not Assigned(Plugin) then Exit;

  if Assigned(FOnKeyValuesExtracted) then
  begin
    if Supports(Plugin, IKeyValueProvider, KVProvider) then
    begin
      var KVs := KVProvider.GetKeyValues;
      if Length(KVs) > 0 then
      begin
        var ReaderId, ReaderVersion: string;
        ReaderIdentityOf(Plugin, ReaderId, ReaderVersion);
        FOnKeyValuesExtracted(QItem.ItemId, QItem.FileId, ReaderId,
          ReaderVersion, KVs);
      end;
    end;
  end;

  if not Supports(Plugin, IPreviewProvider, PreviewProvider) then Exit;

  Bmp := PreviewProvider.GetPreview(400, 300);
  if not Assigned(Bmp) then Exit;
  // Bmp ownership is transferred to us; guard everything after acquisition so it
  // is always freed even if ForceDirectories / TPngImage.Create raises (e.g. a
  // bad path or a dropped share) — otherwise the bitmap leaks once per queued
  // file.
  try
    ForceDirectories(ExtractFilePath(QItem.PreviewPath));
    Png := TPngImage.Create;
    try
      Png.Assign(Bmp);
      Png.SaveToFile(QItem.PreviewPath);
    finally
      Png.Free;
    end;
  finally
    Bmp.Free;
  end;

  Model.Storage.CopyIn(QItem.PreviewPath,
    Format('previews/[1000]/%.*d_%.*d.png', [5, QItem.ItemId, 5, QItem.FileId]));

  if Assigned(FOnUpdate) then
    FOnUpdate(QItem.FileId, QItem.PreviewPath);
  finally
    KVProvider := nil;
    PreviewProvider := nil;
    Plugin := nil;
    PreviewOwner.Free;
  end;
end;

end.
