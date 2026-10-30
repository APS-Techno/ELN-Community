unit unit_SearchArtifactInstall;

interface

uses
  System.SysUtils, System.Classes, unit_TextEmbedder, unit_SearchArtifacts, unit_TarGz;

type
  IArtifactFetcher = interface
    ['{2EBDEABD-0F73-4C7D-9D78-91EFDDBC08FF}']
    procedure Fetch(const Url, TargetPath: string; const Progress: TProc<Int64>;
      const Cancelled: TCancelCheck);
  end;

  TArtifactProxy = record
    Enabled: Boolean;
    Host: string;
    Port: Integer;
    User, Password: string;
  end;

  TTransferResult = record
    Status: Integer;
    Refused: Boolean;
  end;

  EArtifactTransientError = class(ESearchArtifactError);

  IArtifactTransport = interface
    ['{7C1D4E52-8B0A-4F63-9E7D-2A5B6C8D9E10}']
    function Get(const Url: string; RangeStart: Int64; const Target: TStream;
      const BeforeBody: TFunc<Int64, Boolean>; const Progress: TProc<Int64>;
      const Cancelled: TCancelCheck): TTransferResult;
  end;

  THttpArtifactFetcher = class(TInterfacedObject, IArtifactFetcher)
  private
    FTransport: IArtifactTransport;
    FBackoffMs: TArray<Integer>;
    FTotal: Int64;
    procedure CheckCancelled(const Cancelled: TCancelCheck);
    procedure Backoff(Milliseconds: Integer; const Cancelled: TCancelCheck);
    function Attempt(const Url, TargetPath: string; const Progress: TProc<Int64>;
      const Cancelled: TCancelCheck): Boolean;
  public
    constructor Create(const Transport: IArtifactTransport = nil; const BackoffMs: TArray<Integer> = nil);
    procedure Fetch(const Url, TargetPath: string; const Progress: TProc<Int64>;
      const Cancelled: TCancelCheck);
  end;

  TInstallProgress = reference to procedure(DoneBytes, TotalBytes: Int64; const CurrentFile: string);

procedure InstallSearchArtifacts(const Manifest: TSearchArtifactManifest; const Root: string;
  const Fetcher: IArtifactFetcher; const Progress: TInstallProgress; const Cancelled: TCancelCheck);

function ResolveArtifactProxy(const Url, HttpsProxy, HttpProxy, NoProxy: string): TArtifactProxy;
function EnvironmentArtifactProxy(const Url: string): TArtifactProxy;
function IsTransientNetworkException(E: Exception): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.Zip, System.Math, System.Diagnostics,
  System.Net.URLClient, System.Net.HttpClient, System.NetEncoding, System.Types;

function EnvValue(const Name: string): string;
begin
  Result := GetEnvironmentVariable(Name);
  if Result = '' then
    Result := GetEnvironmentVariable(LowerCase(Name));
end;

function ProxyBypassed(const Host, NoProxy: string): Boolean;
var
  Entry, Suffix: string;
begin
  for Entry in NoProxy.Split([',']) do
  begin
    Suffix := Entry.Trim.ToLower;
    if Suffix = '' then
      Continue;
    if Suffix = '*' then
      Exit(True);
    Suffix := Suffix.TrimLeft(['.']);
    if (Host = Suffix) or Host.EndsWith('.' + Suffix) then
      Exit(True);
  end;
  Result := False;
end;

function MaskProxyCredentials(const Value: string): string;
var
  Rest, Prefix: string;
  P: Integer;
begin
  Rest := Value.Trim;
  Prefix := '';
  P := Rest.IndexOf('://');
  if P >= 0 then
  begin
    Prefix := Rest.Substring(0, P + 3);
    Rest := Rest.Substring(P + 3);
  end;
  P := Rest.LastIndexOf('@');
  if P >= 0 then
    Rest := '***' + Rest.Substring(P);
  Result := Prefix + Rest;
end;

function ParseProxyUrl(const Value: string): TArtifactProxy;
var
  Rest, Authority, UserInfo, HostPort, PortText: string;
  P: Integer;
begin
  Result := Default(TArtifactProxy);
  Rest := Value.Trim;
  P := Rest.IndexOf('://');
  if P >= 0 then
  begin
    if not SameText(Rest.Substring(0, P), 'http') then
      raise ESearchArtifactError.CreateFmt('Proxy setting "%s" must use the http scheme',
        [MaskProxyCredentials(Value)]);
    Rest := Rest.Substring(P + 3);
  end;
  P := Rest.IndexOf('/');
  if P >= 0 then
    Authority := Rest.Substring(0, P)
  else
    Authority := Rest;
  P := Authority.LastIndexOf('@');
  if P >= 0 then
  begin
    UserInfo := Authority.Substring(0, P);
    HostPort := Authority.Substring(P + 1);
    P := UserInfo.IndexOf(':');
    if P >= 0 then
    begin
      Result.User := TNetEncoding.URL.Decode(UserInfo.Substring(0, P));
      Result.Password := TNetEncoding.URL.Decode(UserInfo.Substring(P + 1));
    end
    else
      Result.User := TNetEncoding.URL.Decode(UserInfo);
  end
  else
    HostPort := Authority;
  P := HostPort.LastIndexOf(':');
  if P < 0 then
    raise ESearchArtifactError.CreateFmt('Proxy setting "%s" has no port', [MaskProxyCredentials(Value)]);
  Result.Host := HostPort.Substring(0, P);
  PortText := HostPort.Substring(P + 1);
  if (Result.Host = '') or not TryStrToInt(PortText, Result.Port) or (Result.Port < 1) or
    (Result.Port > 65535) then
    raise ESearchArtifactError.CreateFmt('Proxy setting "%s" is not host:port', [MaskProxyCredentials(Value)]);
  Result.Enabled := True;
end;

function ResolveArtifactProxy(const Url, HttpsProxy, HttpProxy, NoProxy: string): TArtifactProxy;
var
  Uri: TURI;
  Setting: string;
begin
  Result := Default(TArtifactProxy);
  Uri := TURI.Create(Url);
  if SameText(Uri.Scheme, 'https') then
  begin
    Setting := HttpsProxy;
    if Setting = '' then
      Setting := HttpProxy;
  end
  else
    Setting := HttpProxy;
  if Setting.Trim = '' then
    Exit;
  if ProxyBypassed(Uri.Host.ToLower, NoProxy) then
    Exit;
  Result := ParseProxyUrl(Setting);
end;

function EnvironmentArtifactProxy(const Url: string): TArtifactProxy;
begin
  Result := ResolveArtifactProxy(Url, EnvValue('HTTPS_PROXY'), EnvValue('HTTP_PROXY'), EnvValue('NO_PROXY'));
end;

function IsTransientNetworkException(E: Exception): Boolean;
begin
  Result := (E is ENetURIClientException) or (E is ENetURIRequestException) or
    (E is ENetURIResponseException);
end;

const
  CopyBufferSize = 256 * 1024;
  MaxRedirects = 20;
  ConnectTimeoutMs = 30000;
  ReceiveTimeoutMs = 120000;
  BackoffSliceMs = 50;
  CancelPollMs = 20;

type
  TDownloadSink = class
  private
    FBeforeBody: TFunc<Int64, Boolean>;
    FProgress: TProc<Int64>;
    FStarted: Boolean;
  public
    Refused: Boolean;
    constructor Create(const BeforeBody: TFunc<Int64, Boolean>; const Progress: TProc<Int64>);
    procedure Receive(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
  end;

  TWinHttpTransport = class(TInterfacedObject, IArtifactTransport)
  public
    function Get(const Url: string; RangeStart: Int64; const Target: TStream;
      const BeforeBody: TFunc<Int64, Boolean>; const Progress: TProc<Int64>;
      const Cancelled: TCancelCheck): TTransferResult;
  end;

  TArtifactInstaller = class
  private
    FManifest: TSearchArtifactManifest;
    FRoot: string;
    FFetcher: IArtifactFetcher;
    FProgress: TInstallProgress;
    FCancelled: TCancelCheck;
    FParts: TList<string>;
    FBase: Int64;
    FCurrent: string;
    procedure ValidatePath(const RelativePath: string);
    procedure ValidateFile(const F: TArtifactFile; const Folder: string);
    procedure ValidateManifest;
    procedure CheckCancelled;
    procedure Report(DoneBytes: Int64);
    function AbsolutePath(const RelativePath: string): string;
    function InnerName(const F: TArtifactFile; const Folder: string): string;
    procedure Download(const Url, Part, DisplayName: string; Size: Int64; const Sha256: string);
    procedure Publish(const Part, Target: string);
    procedure InstallModelFile(const M: TArtifactModel; const F: TArtifactFile);
    procedure InstallModel(const M: TArtifactModel);
    procedure ExtractRuntimeFile(Zip: TZipFile; const F: TArtifactFile; const Folder: string);
    function ArchiveFilesMissing(const A: TArtifactArchive): TArray<TArtifactFile>;
    procedure ExtractTarFiles(const ArchivePart: string; const A: TArtifactArchive;
      const Missing: TArray<TArtifactFile>);
    procedure ExtractZipFiles(const ArchivePart: string; const A: TArtifactArchive;
      const Missing: TArray<TArtifactFile>);
    procedure InstallArchive(const A: TArtifactArchive);
    procedure DeleteParts;
  public
    constructor Create(const Manifest: TSearchArtifactManifest; const Root: string;
      const Fetcher: IArtifactFetcher; const Progress: TInstallProgress; const Cancelled: TCancelCheck);
    destructor Destroy; override;
    procedure Run;
  end;

{ TDownloadSink }

constructor TDownloadSink.Create(const BeforeBody: TFunc<Int64, Boolean>; const Progress: TProc<Int64>);
begin
  inherited Create;
  FBeforeBody := BeforeBody;
  FProgress := Progress;
end;

procedure TDownloadSink.Receive(const Sender: TObject; AContentLength, AReadCount: Int64;
  var AAbort: Boolean);
begin
  if not FStarted then
  begin
    FStarted := True;
    if Assigned(FBeforeBody) and not FBeforeBody(AContentLength) then
    begin
      Refused := True;
      AAbort := True;
      Exit;
    end;
  end;
  if Assigned(FProgress) then
    FProgress(AReadCount);
end;

procedure ApplyEnvironmentProxy(Client: THTTPClient; const Url: string);
var
  Proxy: TArtifactProxy;
begin
  Proxy := EnvironmentArtifactProxy(Url);
  if Proxy.Enabled then
    Client.ProxySettings := TProxySettings.Create(Proxy.Host, Proxy.Port, Proxy.User, Proxy.Password);
end;

{ TWinHttpTransport }

function TWinHttpTransport.Get(const Url: string; RangeStart: Int64; const Target: TStream;
  const BeforeBody: TFunc<Int64, Boolean>; const Progress: TProc<Int64>;
  const Cancelled: TCancelCheck): TTransferResult;
var
  Client: THTTPClient;
  Sink: TDownloadSink;
  Async: IAsyncResult;
  Response: IHTTPResponse;
  Headers: TNetHeaders;
begin
  Result := Default(TTransferResult);
  Sink := TDownloadSink.Create(BeforeBody, Progress);
  try
    Client := THTTPClient.Create;
    try
      ApplyEnvironmentProxy(Client, Url);
      Client.HandleRedirects := True;
      Client.MaxRedirects := MaxRedirects;
      Client.ConnectionTimeout := ConnectTimeoutMs;
      Client.SendTimeout := ConnectTimeoutMs;
      Client.ResponseTimeout := ReceiveTimeoutMs;
      Client.OnReceiveData := Sink.Receive;
      if RangeStart > 0 then
        Headers := [TNameValuePair.Create('Range', Format('bytes=%d-', [RangeStart]))];
      Async := Client.BeginGet(Url, Target, Headers);
      while not Async.IsCompleted do
      begin
        if Assigned(Cancelled) and Cancelled() then
        begin
          Async.Cancel;
          while not Async.IsCompleted do
            Sleep(CancelPollMs);
          try
            THTTPClient.EndAsyncHTTP(Async);
          except
            on Exception do;
          end;
          raise EOperationCancelled.Create('Search artifact download was cancelled');
        end;
        Sleep(CancelPollMs);
      end;
      try
        Response := THTTPClient.EndAsyncHTTP(Async);
      except
        on E: Exception do
        begin
          if Sink.Refused then
          begin
            Result.Refused := True;
            Exit;
          end;
          if IsTransientNetworkException(E) then
            raise EArtifactTransientError.Create(E.Message);
          raise;
        end;
      end;
      if Sink.Refused then
        Result.Refused := True
      else
        Result.Status := Response.StatusCode;
    finally
      Client.Free;
    end;
  finally
    Sink.Free;
  end;
end;

{ THttpArtifactFetcher }

constructor THttpArtifactFetcher.Create(const Transport: IArtifactTransport;
  const BackoffMs: TArray<Integer>);
begin
  inherited Create;
  FTransport := Transport;
  if FTransport = nil then
    FTransport := TWinHttpTransport.Create;
  FBackoffMs := BackoffMs;
  if FBackoffMs = nil then
    FBackoffMs := [1000, 2000, 4000, 8000, 16000];
end;

procedure THttpArtifactFetcher.CheckCancelled(const Cancelled: TCancelCheck);
begin
  if Assigned(Cancelled) and Cancelled() then
    raise EOperationCancelled.Create('Search artifact download was cancelled');
end;

procedure THttpArtifactFetcher.Backoff(Milliseconds: Integer; const Cancelled: TCancelCheck);
var
  Watch: TStopwatch;
  Remaining: Int64;
begin
  Watch := TStopwatch.StartNew;
  while True do
  begin
    CheckCancelled(Cancelled);
    Remaining := Milliseconds - Watch.ElapsedMilliseconds;
    if Remaining <= 0 then
      Break;
    Sleep(Cardinal(Min(Int64(BackoffSliceMs), Remaining)));
  end;
end;

function THttpArtifactFetcher.Attempt(const Url, TargetPath: string; const Progress: TProc<Int64>;
  const Cancelled: TCancelCheck): Boolean;
var
  Target: TFileStream;
  Offset: Int64;
  Mode: Word;
  Transfer: TTransferResult;
begin
  if TFile.Exists(TargetPath) then
    Mode := fmOpenReadWrite or fmShareDenyWrite
  else
    Mode := fmCreate;
  Target := TFileStream.Create(TargetPath, Mode);
  try
    Offset := Target.Size;
    Target.Position := Offset;
    Transfer := FTransport.Get(Url, Offset, Target,
      function(ContentLength: Int64): Boolean
      begin
        Result := True;
        if ContentLength <= 0 then
          Exit;
        if Offset = 0 then
          FTotal := ContentLength
        else if ContentLength = FTotal then
          Result := False
        else if FTotal <= 0 then
          FTotal := Offset + ContentLength;
      end,
      procedure(Bytes: Int64)
      begin
        if Assigned(Progress) then
          Progress(Offset + Bytes);
      end, Cancelled);
    if Transfer.Refused or ((Transfer.Status = 200) and (Offset > 0)) then
    begin
      Target.Size := 0;
      Exit(False);
    end;
    if (Transfer.Status = 200) or (Transfer.Status = 206) then
      Exit(True);
    Target.Size := Offset;
    if (Transfer.Status = 416) and (FTotal > 0) and (Offset >= FTotal) then
      Exit(True);
    if Transfer.Status = 416 then
      Target.Size := 0;
    if (Transfer.Status >= 500) or (Transfer.Status = 408) or (Transfer.Status = 416) or
      (Transfer.Status = 429) then
      raise EArtifactTransientError.CreateFmt('Download failed (HTTP %d): %s', [Transfer.Status, Url]);
    raise ESearchArtifactError.CreateFmt('Download failed (HTTP %d): %s', [Transfer.Status, Url]);
  finally
    Target.Free;
  end;
end;

procedure THttpArtifactFetcher.Fetch(const Url, TargetPath: string; const Progress: TProc<Int64>;
  const Cancelled: TCancelCheck);
var
  Retry: Integer;
begin
  FTotal := 0;
  Retry := 0;
  while True do
  begin
    CheckCancelled(Cancelled);
    try
      if Attempt(Url, TargetPath, Progress, Cancelled) then
        Exit;
    except
      on EArtifactTransientError do
      begin
        if Retry >= Length(FBackoffMs) then
          raise;
        Backoff(FBackoffMs[Retry], Cancelled);
        Inc(Retry);
      end;
    end;
  end;
end;

{ TArtifactInstaller }

constructor TArtifactInstaller.Create(const Manifest: TSearchArtifactManifest; const Root: string;
  const Fetcher: IArtifactFetcher; const Progress: TInstallProgress; const Cancelled: TCancelCheck);
begin
  inherited Create;
  FManifest := Manifest;
  FRoot := Root;
  FFetcher := Fetcher;
  FProgress := Progress;
  FCancelled := Cancelled;
  FParts := TList<string>.Create;
end;

destructor TArtifactInstaller.Destroy;
begin
  FParts.Free;
  inherited;
end;

procedure TArtifactInstaller.ValidatePath(const RelativePath: string);
var
  Segment: string;
begin
  if (RelativePath = '') or RelativePath.Contains(':') or TPath.IsPathRooted(RelativePath) then
    raise ESearchArtifactError.CreateFmt('Search artifact path must be relative: "%s"', [RelativePath]);
  for Segment in RelativePath.Split(['\', '/']) do
    if Segment = '..' then
      raise ESearchArtifactError.CreateFmt('Search artifact path must stay under the artifact root: "%s"',
        [RelativePath]);
end;

procedure TArtifactInstaller.ValidateFile(const F: TArtifactFile; const Folder: string);
begin
  ValidatePath(F.RelativePath);
  if not F.RelativePath.StartsWith(Folder + PathDelim, True) then
    raise ESearchArtifactError.CreateFmt('Search artifact "%s" is not under "%s"', [F.RelativePath, Folder]);
end;

procedure TArtifactInstaller.ValidateManifest;
var
  F: TArtifactFile;
  M: TArtifactModel;
  A: TArtifactArchive;
begin
  for M in FManifest.Models do
  begin
    ValidatePath(M.Folder);
    for F in M.Files do
      ValidateFile(F, M.Folder);
  end;
  for A in FManifest.Archives do
  begin
    ValidatePath(A.Folder);
    ValidatePath(A.Name);
    for F in A.Files do
      ValidateFile(F, A.Folder);
  end;
end;

procedure TArtifactInstaller.CheckCancelled;
begin
  if Assigned(FCancelled) and FCancelled() then
    raise EOperationCancelled.Create('Search artifact installation was cancelled');
end;

procedure TArtifactInstaller.Report(DoneBytes: Int64);
begin
  if Assigned(FProgress) then
    FProgress(DoneBytes, FManifest.TotalDownloadBytes, FCurrent);
end;

function TArtifactInstaller.AbsolutePath(const RelativePath: string): string;
begin
  Result := TPath.Combine(FRoot, RelativePath);
end;

function TArtifactInstaller.InnerName(const F: TArtifactFile; const Folder: string): string;
begin
  Result := F.RelativePath.Substring(Length(Folder) + 1);
end;

procedure TArtifactInstaller.Download(const Url, Part, DisplayName: string; Size: Int64;
  const Sha256: string);
begin
  FParts.Add(Part);
  if TFile.Exists(Part) then
    TFile.Delete(Part);
  FFetcher.Fetch(Url, Part,
    procedure(Bytes: Int64)
    begin
      Report(FBase + Bytes);
    end, FCancelled);
  if not ArtifactFileMatches(Part, Size, Sha256) then
    raise ESearchArtifactError.CreateFmt('Downloaded file does not match the manifest: %s', [DisplayName]);
end;

procedure TArtifactInstaller.Publish(const Part, Target: string);
begin
  if TFile.Exists(Target) then
    TFile.Delete(Target);
  TFile.Move(Part, Target);
end;

procedure TArtifactInstaller.InstallModelFile(const M: TArtifactModel; const F: TArtifactFile);
var
  Target, Url: string;
begin
  FCurrent := F.RelativePath;
  CheckCancelled;
  Target := AbsolutePath(F.RelativePath);
  if not ArtifactFileMatches(Target, F.Size, F.Sha256) then
  begin
    TDirectory.CreateDirectory(ExtractFileDir(Target));
    Url := M.BaseUrl.TrimRight(['/']) + '/' + InnerName(F, M.Folder).Replace('\', '/');
    Download(Url, Target + '.part', F.RelativePath, F.Size, F.Sha256);
    Publish(Target + '.part', Target);
  end;
  Inc(FBase, F.Size);
  Report(FBase);
end;

procedure TArtifactInstaller.InstallModel(const M: TArtifactModel);
var
  F: TArtifactFile;
begin
  for F in M.Files do
    InstallModelFile(M, F);
end;

procedure TArtifactInstaller.ExtractRuntimeFile(Zip: TZipFile; const F: TArtifactFile; const Folder: string);
var
  Names: TArray<string>;
  Wanted, Target, Part: string;
  Index, I, Count: Integer;
  Source: TStream;
  Header: TZipHeader;
  Dest: TFileStream;
  Buffer: TBytes;
begin
  CheckCancelled;
  Wanted := InnerName(F, Folder).Replace('\', '/');
  Names := Zip.FileNames;
  Index := -1;
  for I := 0 to High(Names) do
    if SameText(Names[I].Replace('\', '/'), Wanted) then
    begin
      Index := I;
      Break;
    end;
  if Index < 0 then
    raise ESearchArtifactError.CreateFmt('Runtime archive does not contain: %s', [F.RelativePath]);
  Target := AbsolutePath(F.RelativePath);
  Part := Target + '.part';
  TDirectory.CreateDirectory(ExtractFileDir(Target));
  FParts.Add(Part);
  Zip.Read(Index, Source, Header);
  try
    Dest := TFileStream.Create(Part, fmCreate);
    try
      SetLength(Buffer, CopyBufferSize);
      repeat
        Count := Source.Read(Buffer, Length(Buffer));
        if Count > 0 then
          Dest.WriteBuffer(Buffer, Count);
      until Count = 0;
    finally
      Dest.Free;
    end;
  finally
    Source.Free;
  end;
  if not ArtifactFileMatches(Part, F.Size, F.Sha256) then
    raise ESearchArtifactError.CreateFmt('Extracted file does not match the manifest: %s', [F.RelativePath]);
  Publish(Part, Target);
end;

function TArtifactInstaller.ArchiveFilesMissing(const A: TArtifactArchive): TArray<TArtifactFile>;
var
  F: TArtifactFile;
begin
  Result := nil;
  for F in A.Files do
    if not ArtifactFileMatches(AbsolutePath(F.RelativePath), F.Size, F.Sha256) then
      Result := Result + [F];
end;

procedure TArtifactInstaller.ExtractTarFiles(const ArchivePart: string; const A: TArtifactArchive;
  const Missing: TArray<TArtifactFile>);
var
  Wanted: TArray<string>;
  F: TArtifactFile;
  Folder: string;
begin
  Folder := A.Folder;
  Wanted := nil;
  for F in Missing do
    Wanted := Wanted + [InnerName(F, Folder).Replace('\', '/')];
  ExtractTarGzEntries(ArchivePart, Wanted,
    function(Name: string): string
    begin
      Result := AbsolutePath(TPath.Combine(Folder, Name.Replace('/', PathDelim))) + '.part';
      FParts.Add(Result);
    end, FCancelled);
  for F in Missing do
  begin
    if not ArtifactFileMatches(AbsolutePath(F.RelativePath) + '.part', F.Size, F.Sha256) then
      raise ESearchArtifactError.CreateFmt('Extracted file does not match the manifest: %s', [F.RelativePath]);
    Publish(AbsolutePath(F.RelativePath) + '.part', AbsolutePath(F.RelativePath));
  end;
end;

procedure TArtifactInstaller.ExtractZipFiles(const ArchivePart: string; const A: TArtifactArchive;
  const Missing: TArray<TArtifactFile>);
var
  F: TArtifactFile;
  Zip: TZipFile;
begin
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchivePart, zmRead);
    for F in Missing do
      ExtractRuntimeFile(Zip, F, A.Folder);
  finally
    Zip.Free;
  end;
end;

procedure TArtifactInstaller.InstallArchive(const A: TArtifactArchive);
var
  Missing: TArray<TArtifactFile>;
  ArchivePart: string;
begin
  FCurrent := A.Name;
  CheckCancelled;
  Missing := ArchiveFilesMissing(A);
  if Length(Missing) > 0 then
  begin
    ArchivePart := AbsolutePath(TPath.Combine(A.Folder, A.Name)) + '.part';
    TDirectory.CreateDirectory(ExtractFileDir(ArchivePart));
    Download(A.Url, ArchivePart, A.Name, A.Size, A.Sha256);
    case A.Kind of
      akZip: ExtractZipFiles(ArchivePart, A, Missing);
      akTarGz: ExtractTarFiles(ArchivePart, A, Missing);
    end;
    TFile.Delete(ArchivePart);
  end;
  Inc(FBase, A.Size);
  Report(FBase);
end;

procedure TArtifactInstaller.DeleteParts;
var
  Part: string;
begin
  for Part in FParts do
    try
      if TFile.Exists(Part) then
        TFile.Delete(Part);
    except
      on EInOutError do;
    end;
end;

procedure TArtifactInstaller.Run;
var
  A: TArtifactArchive;
  M: TArtifactModel;
  Check: TArtifactCheck;
  OptionalPass: Boolean;
begin
  ValidateManifest;
  try
    Report(0);
    for OptionalPass in [False, True] do
    begin
      for M in FManifest.Models do
        if M.Optional = OptionalPass then
          InstallModel(M);
      for A in FManifest.Archives do
        if A.Optional = OptionalPass then
          InstallArchive(A);
    end;
    FCurrent := '';
    Report(FManifest.TotalDownloadBytes);
    Check := CheckSearchArtifacts(FManifest, FRoot, True);
    if Check.State <> asReady then
      raise ESearchArtifactError.Create(Check.FirstProblem);
  except
    DeleteParts;
    raise;
  end;
end;

procedure InstallSearchArtifacts(const Manifest: TSearchArtifactManifest; const Root: string;
  const Fetcher: IArtifactFetcher; const Progress: TInstallProgress; const Cancelled: TCancelCheck);
var
  Installer: TArtifactInstaller;
begin
  Installer := TArtifactInstaller.Create(Manifest, Root, Fetcher, Progress, Cancelled);
  try
    Installer.Run;
  finally
    Installer.Free;
  end;
end;

end.
