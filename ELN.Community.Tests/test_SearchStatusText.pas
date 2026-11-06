unit test_SearchStatusText;

interface

uses
  DUnitX.TestFramework, unit_SemanticSearchApi;

type
  [TestFixture]
  TSearchStatusTextTests = class
  private
    function Text(const Status: TSemanticSearchStatus): string;
    function Detail: TSemanticSearchStatus;
  public
    [Test]
    procedure ReadingFiles;
    [Test]
    procedure ReadingFilesWinsOverError;
    [Test]
    procedure IncompleteWithTime;
    [Test]
    procedure IncompleteNeverHundred;
    [Test]
    procedure IncompleteZeroTotal;
    [Test]
    procedure IncompletePendingExceedsIndexed;
    [Test]
    procedure IncompleteZeroTotalWithTime;
    [Test]
    procedure CompleteWithSkipped;
    [Test]
    procedure ErrorStorage;
    [Test]
    procedure ErrorDatabase;
    [Test]
    procedure ErrorUnknownCode;
    [Test]
    procedure ErrorWithoutTime;
  end;

implementation

uses
  System.SysUtils, System.DateUtils, unit_SearchStatusText;

const
  Ellipsis = #$2026;
  Dot = ' ' + #$00B7 + ' ';

function TSearchStatusTextTests.Detail: TSemanticSearchStatus;
begin
  Result := Default(TSemanticSearchStatus);
  Result.ServerDetail := True;
  Result.State := ssIdle;
  Result.LastSyncUtc := EncodeDateTime(2026, 10, 31, 10, 58, 0, 0);
end;

function TSearchStatusTextTests.Text(const Status: TSemanticSearchStatus): string;
var
  Settings: TFormatSettings;
begin
  Settings := TFormatSettings.Create;
  Settings.ThousandSeparator := ',';
  Settings.TimeSeparator := ':';
  Result := ServerStatusText(Status,
    function(Value: TDateTime): TDateTime
    begin
      Result := Value;
    end, Settings);
end;

procedure TSearchStatusTextTests.ReadingFiles;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.State := ssSyncing;
  S.FilesDone := 1200;
  S.FilesTotal := 6000;
  Assert.AreEqual('Indexing' + Ellipsis + ' reading files 1,200 of 6,000', Text(S));
end;

procedure TSearchStatusTextTests.ReadingFilesWinsOverError;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.State := ssSyncing;
  S.FilesDone := 1200;
  S.FilesTotal := 6000;
  S.LastErrorCode := 'sync_failed';
  Assert.AreEqual('Indexing' + Ellipsis + ' reading files 1,200 of 6,000', Text(S));
end;

procedure TSearchStatusTextTests.IncompleteWithTime;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.IndexedPassages := 9376;
  S.PendingPassages := 3239;
  Assert.AreEqual('Indexing' + Ellipsis + ' 74 % (9,376 of 12,615 passages)' + Dot +
    'updated 10:58', Text(S));
end;

procedure TSearchStatusTextTests.IncompleteNeverHundred;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.IndexedPassages := 9999;
  S.PendingPassages := 1;
  Assert.AreEqual('Indexing' + Ellipsis + ' 99 % (9,999 of 10,000 passages)' + Dot +
    'updated 10:58', Text(S));
end;

procedure TSearchStatusTextTests.IncompleteZeroTotal;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.LastSyncUtc := 0;
  Assert.AreEqual('Indexing' + Ellipsis, Text(S));
end;

procedure TSearchStatusTextTests.IncompletePendingExceedsIndexed;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.IndexedPassages := 100;
  S.PendingPassages := 900;
  Assert.AreEqual('Indexing' + Ellipsis + ' 10 % (100 of 1,000 passages)' + Dot +
    'updated 10:58', Text(S));
end;

procedure TSearchStatusTextTests.IncompleteZeroTotalWithTime;
begin
  Assert.AreEqual('Indexing' + Ellipsis + Dot + 'updated 10:58', Text(Detail));
end;

procedure TSearchStatusTextTests.CompleteWithSkipped;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.LastSyncComplete := True;
  S.IndexedPassages := 12615;
  S.FilesSkipped := 12;
  Assert.AreEqual('Index complete: 12,615 passages' + Dot + 'updated 10:58' + Dot +
    '12 files skipped', Text(S));
end;

procedure TSearchStatusTextTests.ErrorStorage;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.LastErrorCode := 'storage_unavailable';
  Assert.AreEqual('Index not updated since 10:58: the file storage is not reachable', Text(S));
end;

procedure TSearchStatusTextTests.ErrorDatabase;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.LastErrorCode := 'database_unavailable';
  Assert.AreEqual('Index not updated since 10:58: the notebook database is not reachable',
    Text(S));
end;

procedure TSearchStatusTextTests.ErrorUnknownCode;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.LastErrorCode := 'future_code';
  Assert.AreEqual('Index not updated since 10:58: the sync failed', Text(S));
end;

procedure TSearchStatusTextTests.ErrorWithoutTime;
var
  S: TSemanticSearchStatus;
begin
  S := Detail;
  S.LastSyncUtc := 0;
  S.LastErrorCode := 'storage_unavailable';
  Assert.AreEqual('Index not updated: the file storage is not reachable', Text(S));
end;

initialization
  TDUnitX.RegisterTestFixture(TSearchStatusTextTests);

end.
