unit unit_SearchIndexStore;

interface

uses
  System.SysUtils, System.Generics.Collections,
  unit_SearchPassages, unit_TextEmbedder, unit_VectorSearch, unit_TextExtractors;

type
  ESearchIndexError = class(Exception);

  TStoredPassage = record
    Key: string;
    ProjectId, ItemId: Integer;
    FileId: Int64;
    Field: TPassageField;
    ContentHash: string;
  end;

  TTextHit = record
    Key: string;
    Rank: Integer;
  end;

  TSearchIndexStore = class
  private
    FPath: string;
    FEmbedderIdentity: string;
    FDimension: Integer;
    FDb: Pointer;
    FWasReset: Boolean;
    FInBatch: Boolean;
    FLastCode: Integer;
    FStatements: TDictionary<string, Pointer>;
    procedure Check(Code: Integer; const What: string);
    function Prepare(const Sql: string): Pointer;
    procedure Exec(const Sql: string);
    procedure BindText(Stmt: Pointer; Index: Integer; const Value: string);
    procedure BindInt(Stmt: Pointer; Index: Integer; Value: Int64);
    procedure OpenDb;
    procedure CloseDb;
    procedure DeleteStoreFiles;
    function IsCompatible: Boolean;
    function HasTables: Boolean;
    procedure EnsureSchema;
    procedure CreateSchema;
    function MatchQuery(const Table, Match: string; const ProjectIds: TArray<Integer>;
      Limit: Integer; const Items: TItemFilter): TArray<TTextHit>;
  public
    constructor Open(const Path, EmbedderIdentity: string; Dimension: Integer);
    destructor Destroy; override;
    function ReadCatalog: TDictionary<string, TStoredPassage>;
    procedure BeginBatch;
    procedure CommitBatch;
    procedure RollbackBatch;
    procedure Upsert(const P: TSearchPassage; const Vector: TEmbeddingVector);
    procedure UpdateCoordinates(const P: TSearchPassage);
    procedure Delete(const Key: string);
    function ReadFileText(FileId: Int64; out Md5, Extractor: string;
      out Outcome: TExtractOutcome; out Text: string): Boolean; overload;
    function ReadFileText(FileId: Int64; out Md5, Extractor: string;
      out Outcome: TExtractOutcome; out Text: string; out Size, LastWrite: Int64): Boolean; overload;
    procedure WriteFileText(FileId: Int64; const Md5, Extractor: string;
      Outcome: TExtractOutcome; const Detail, Text: string; Size: Int64 = -1;
      LastWrite: Int64 = 0);
    procedure UpdateFileStamp(FileId, Size, LastWrite: Int64);
    procedure DeleteFileTextExcept(const LiveFileIds: TArray<Int64>);
    procedure LoadVectors(Index: TExactVectorIndex);
    function MatchWords(const Query: string; const ProjectIds: TArray<Integer>;
      Limit: Integer; const Items: TItemFilter): TArray<TTextHit>;
    function MatchTrigrams(const Query: string; const ProjectIds: TArray<Integer>;
      Limit: Integer; const Items: TItemFilter): TArray<TTextHit>;
    function PassageText(const Key: string): string;
    procedure ReplaceItemContexts(const Rows: TArray<TItemContextEntry>);
    function ReadItemContext(ItemId: Integer; out PartsJson: string): Boolean;
    property WasReset: Boolean read FWasReset;
  end;

const
  SearchIndexSchemaVersion = '2';
  StoreBusyTimeoutMs = 10000;

implementation

uses
  System.IOUtils, System.Character, Aurelius.Drivers.SQLite.Import;

const
  TrigramMinChars = 3;
  NotADatabaseCode = 26;
  CorruptCode = 11;
  BusyCode = 5;
  WalRetries = 100;
  WalRetryDelayMs = 50;

constructor TSearchIndexStore.Open(const Path, EmbedderIdentity: string; Dimension: Integer);
var
  Attempt: Integer;
begin
  inherited Create;
  FStatements := TDictionary<string, Pointer>.Create;
  if Dimension < 1 then
    raise ESearchIndexError.Create('Vector dimension must be positive');
  if not LoadSQLiteLibrary then
    raise ESearchIndexError.CreateFmt('Cannot load SQLite (tried: %s)', [SQLiteLibraryNames]);
  FPath := Path;
  FEmbedderIdentity := EmbedderIdentity;
  FDimension := Dimension;
  for Attempt := 1 downto 0 do
  begin
    OpenDb;
    try
      EnsureSchema;
      Break;
    except
      on ESearchIndexError do
      begin
        if (Attempt = 0) or not (FLastCode in [NotADatabaseCode, CorruptCode]) then
          raise;
        CloseDb;
        DeleteStoreFiles;
        FWasReset := True;
      end;
    end;
  end;
end;

destructor TSearchIndexStore.Destroy;
begin
  if FInBatch then
    try
      Exec('ROLLBACK');
    except
    end;
  CloseDb;
  FStatements.Free;
  inherited;
end;

procedure TSearchIndexStore.Check(Code: Integer; const What: string);
begin
  if Code <> SQLITE_OK then
  begin
    FLastCode := Code;
    raise ESearchIndexError.CreateFmt('%s failed (%d): %s', [What, Code, string(f_sqlite3_errmsg16(FDb))]);
  end;
end;

procedure TSearchIndexStore.OpenDb;
var
  Handle: Pointer;
  Code: Integer;
begin
  Handle := nil;
  Code := f_sqlite3_open16(PChar(FPath), Handle);
  FDb := Handle;
  if Code <> SQLITE_OK then
    try
      Check(Code, 'open ' + FPath);
    finally
      CloseDb;
    end;
  Exec('PRAGMA busy_timeout = ' + IntToStr(StoreBusyTimeoutMs));
end;

procedure TSearchIndexStore.CloseDb;
var
  Stmt: Pointer;
begin
  for Stmt in FStatements.Values do
    f_sqlite3_finalize(Stmt);
  FStatements.Clear;
  if FDb <> nil then
  begin
    f_sqlite3_close(FDb);
    FDb := nil;
  end;
  FInBatch := False;
end;

procedure TSearchIndexStore.DeleteStoreFiles;
var
  Suffix: string;
begin
  for Suffix in ['', '-wal', '-shm', '-journal'] do
    if TFile.Exists(FPath + Suffix) then
      TFile.Delete(FPath + Suffix);
end;

function TSearchIndexStore.Prepare(const Sql: string): Pointer;
var
  Tail: PChar;
begin
  if FStatements.TryGetValue(Sql, Result) then
  begin
    f_sqlite3_reset(Result);
    f_sqlite3_clear_bindings(Result);
    Exit;
  end;
  Result := nil;
  Check(f_sqlite3_prepare16_v2(FDb, PChar(Sql), -1, Result, Tail), Sql);
  FStatements.Add(Sql, Result);
end;

procedure TSearchIndexStore.Exec(const Sql: string);
var
  Stmt: Pointer;
  Rc: Integer;
  Msg: string;
begin
  Stmt := Prepare(Sql);
  repeat
    Rc := f_sqlite3_step(Stmt);
  until Rc <> SQLITE_ROW;
  if Rc <> SQLITE_DONE then
    Msg := string(f_sqlite3_errmsg16(FDb));
  FLastCode := Rc;
  f_sqlite3_reset(Stmt);
  if Rc <> SQLITE_DONE then
    raise ESearchIndexError.CreateFmt('%s failed (%d): %s', [Sql, Rc, Msg]);
end;

procedure TSearchIndexStore.BindText(Stmt: Pointer; Index: Integer; const Value: string);
begin
  Check(f_sqlite3_bind_text16(Stmt, Index, PChar(Value), Length(Value) * SizeOf(Char),
    SQLITE_TRANSIENT), 'bind');
end;

procedure TSearchIndexStore.BindInt(Stmt: Pointer; Index: Integer; Value: Int64);
begin
  Check(f_sqlite3_bind_int64(Stmt, Index, Value), 'bind');
end;

function TSearchIndexStore.IsCompatible: Boolean;
var
  Stmt: Pointer;
  Rc: Integer;
  Version, Identity, Dim, Key: string;
begin
  Result := False;
  try
    Stmt := Prepare('SELECT key, value FROM meta');
    Version := '';
    Identity := '';
    Dim := '';
    repeat
      Rc := f_sqlite3_step(Stmt);
      if Rc = SQLITE_ROW then
      begin
        Key := string(f_sqlite3_column_text16(Stmt, 0));
        if Key = 'schema_version' then Version := string(f_sqlite3_column_text16(Stmt, 1))
        else if Key = 'embedder_identity' then Identity := string(f_sqlite3_column_text16(Stmt, 1))
        else if Key = 'dimension' then Dim := string(f_sqlite3_column_text16(Stmt, 1));
      end;
    until Rc <> SQLITE_ROW;
    f_sqlite3_reset(Stmt);
    if Rc <> SQLITE_DONE then
      Exit;
    if (Version <> SearchIndexSchemaVersion) or (Identity <> FEmbedderIdentity) or
      (Dim <> IntToStr(FDimension)) then
      Exit;
    Exec('SELECT 1 FROM passages LIMIT 1');
    Exec('SELECT 1 FROM passages_words LIMIT 1');
    Exec('SELECT 1 FROM passages_tri LIMIT 1');
    Exec('SELECT size, last_write FROM file_text LIMIT 1');
    Result := True;
  except
    on ESearchIndexError do
      Result := False;
  end;
end;

function TSearchIndexStore.HasTables: Boolean;
var
  Stmt: Pointer;
begin
  Stmt := Prepare('SELECT 1 FROM sqlite_master WHERE type = ''table'' LIMIT 1');
  Result := f_sqlite3_step(Stmt) = SQLITE_ROW;
  f_sqlite3_reset(Stmt);
end;

procedure TSearchIndexStore.EnsureSchema;
var
  Name: string;
  Code, Tries: Integer;
begin
  Tries := 0;
  repeat
    try
      Exec('PRAGMA journal_mode=WAL');
      Break;
    except
      on ESearchIndexError do
      begin
        Inc(Tries);
        if (FLastCode <> BusyCode) or (Tries >= WalRetries) then
          raise;
        Sleep(WalRetryDelayMs);
      end;
    end;
  until False;
  Exec('BEGIN IMMEDIATE');
  try
    if not IsCompatible then
    begin
      FWasReset := FWasReset or HasTables;
      for Name in ['passages_ai', 'passages_ad', 'passages_au'] do
        Exec('DROP TRIGGER IF EXISTS ' + Name);
      for Name in ['passages_words', 'passages_tri', 'passages', 'file_text', 'item_context', 'meta'] do
        Exec('DROP TABLE IF EXISTS ' + Name);
    end;
    CreateSchema;
    Exec('COMMIT');
  except
    Code := FLastCode;
    try
      Exec('ROLLBACK');
    except
    end;
    FLastCode := Code;
    raise;
  end;
end;

procedure TSearchIndexStore.CreateSchema;
const
  Statements: array[0..12] of string = (
    'CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)',
    'CREATE TABLE IF NOT EXISTS passages(id INTEGER PRIMARY KEY, key TEXT UNIQUE NOT NULL, ' +
      'project_id INTEGER, item_id INTEGER, file_id INTEGER, field INTEGER, text TEXT, ' +
      'content_hash TEXT, vector BLOB)',
    'CREATE VIRTUAL TABLE IF NOT EXISTS passages_words USING fts5(text, content=''passages'', ' +
      'content_rowid=''id'', tokenize=''unicode61 remove_diacritics 2'')',
    'CREATE VIRTUAL TABLE IF NOT EXISTS passages_tri USING fts5(text, content=''passages'', ' +
      'content_rowid=''id'', tokenize=''trigram'')',
    'CREATE TRIGGER IF NOT EXISTS passages_ai AFTER INSERT ON passages BEGIN ' +
      'INSERT INTO passages_words(rowid, text) VALUES (new.id, new.text); ' +
      'INSERT INTO passages_tri(rowid, text) VALUES (new.id, new.text); END',
    'CREATE TRIGGER IF NOT EXISTS passages_ad AFTER DELETE ON passages BEGIN ' +
      'INSERT INTO passages_words(passages_words, rowid, text) VALUES (''delete'', old.id, old.text); ' +
      'INSERT INTO passages_tri(passages_tri, rowid, text) VALUES (''delete'', old.id, old.text); END',
    'CREATE TRIGGER IF NOT EXISTS passages_au AFTER UPDATE OF text ON passages BEGIN ' +
      'INSERT INTO passages_words(passages_words, rowid, text) VALUES (''delete'', old.id, old.text); ' +
      'INSERT INTO passages_tri(passages_tri, rowid, text) VALUES (''delete'', old.id, old.text); ' +
      'INSERT INTO passages_words(rowid, text) VALUES (new.id, new.text); ' +
      'INSERT INTO passages_tri(rowid, text) VALUES (new.id, new.text); END',
    'CREATE TABLE IF NOT EXISTS file_text(file_id INTEGER PRIMARY KEY, content_md5 TEXT, ' +
      'extractor TEXT, outcome INTEGER, detail TEXT, text TEXT, size INTEGER, last_write INTEGER)',
    'CREATE INDEX IF NOT EXISTS passages_item ON passages(item_id)',
    'CREATE TABLE IF NOT EXISTS item_context(item_id INTEGER PRIMARY KEY, parts TEXT)',
    'INSERT OR REPLACE INTO meta(key, value) VALUES (''schema_version'', ?1)',
    'INSERT OR REPLACE INTO meta(key, value) VALUES (''embedder_identity'', ?1)',
    'INSERT OR REPLACE INTO meta(key, value) VALUES (''dimension'', ?1)');
var
  I: Integer;
  Stmt: Pointer;
  Values: array[10..12] of string;
begin
  Values[10] := SearchIndexSchemaVersion;
  Values[11] := FEmbedderIdentity;
  Values[12] := IntToStr(FDimension);
  for I := 0 to 12 do
  begin
    if I < 10 then
      Exec(Statements[I])
    else
    begin
      Stmt := Prepare(Statements[I]);
      BindText(Stmt, 1, Values[I]);
      if f_sqlite3_step(Stmt) <> SQLITE_DONE then
        Check(f_sqlite3_errcode(FDb), 'meta');
      f_sqlite3_reset(Stmt);
    end;
  end;
end;

procedure TSearchIndexStore.BeginBatch;
begin
  if FInBatch then
    raise ESearchIndexError.Create('A batch is already open');
  Exec('BEGIN IMMEDIATE');
  FInBatch := True;
end;

procedure TSearchIndexStore.CommitBatch;
begin
  if not FInBatch then
    raise ESearchIndexError.Create('No batch is open');
  Exec('COMMIT');
  FInBatch := False;
end;

procedure TSearchIndexStore.RollbackBatch;
begin
  if not FInBatch then
    Exit;
  FInBatch := False;
  try
    Exec('ROLLBACK');
  except
    on ESearchIndexError do;
  end;
end;

function TSearchIndexStore.ReadCatalog: TDictionary<string, TStoredPassage>;
var
  Stmt: Pointer;
  Rc: Integer;
  Row: TStoredPassage;
begin
  Result := TDictionary<string, TStoredPassage>.Create;
  try
    Stmt := Prepare('SELECT key, project_id, item_id, file_id, field, content_hash FROM passages');
    try
      repeat
        Rc := f_sqlite3_step(Stmt);
        if Rc = SQLITE_ROW then
        begin
          Row.Key := string(f_sqlite3_column_text16(Stmt, 0));
          Row.ProjectId := f_sqlite3_column_int(Stmt, 1);
          Row.ItemId := f_sqlite3_column_int(Stmt, 2);
          Row.FileId := f_sqlite3_column_int64(Stmt, 3);
          Row.Field := TPassageField(f_sqlite3_column_int(Stmt, 4));
          Row.ContentHash := string(f_sqlite3_column_text16(Stmt, 5));
          Result.Add(Row.Key, Row);
        end;
      until Rc <> SQLITE_ROW;
      if Rc <> SQLITE_DONE then
        Check(Rc, 'read catalog');
    finally
      f_sqlite3_reset(Stmt);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TSearchIndexStore.Upsert(const P: TSearchPassage; const Vector: TEmbeddingVector);
var
  Stmt: Pointer;
  Rc: Integer;
  Msg: string;
begin
  if Length(Vector) <> FDimension then
    raise ESearchIndexError.CreateFmt('Vector for %s has dimension %d, expected %d',
      [P.Key, Length(Vector), FDimension]);
  Stmt := Prepare('INSERT INTO passages(key, project_id, item_id, file_id, field, text, content_hash, vector) ' +
    'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8) ON CONFLICT(key) DO UPDATE SET ' +
    'project_id = excluded.project_id, item_id = excluded.item_id, file_id = excluded.file_id, ' +
    'field = excluded.field, text = excluded.text, content_hash = excluded.content_hash, ' +
    'vector = excluded.vector');
  BindText(Stmt, 1, P.Key);
  BindInt(Stmt, 2, P.ProjectId);
  BindInt(Stmt, 3, P.ItemId);
  BindInt(Stmt, 4, P.FileId);
  BindInt(Stmt, 5, Ord(P.Field));
  BindText(Stmt, 6, P.Text);
  BindText(Stmt, 7, P.ContentHash);
  Check(f_sqlite3_bind_blob(Stmt, 8, @Vector[0], Length(Vector) * SizeOf(Single), SQLITE_TRANSIENT), 'bind');
  Rc := f_sqlite3_step(Stmt);
  if Rc <> SQLITE_DONE then
    Msg := string(f_sqlite3_errmsg16(FDb));
  f_sqlite3_reset(Stmt);
  if Rc <> SQLITE_DONE then
    raise ESearchIndexError.CreateFmt('Upsert %s failed (%d): %s', [P.Key, Rc, Msg]);
end;

procedure TSearchIndexStore.UpdateCoordinates(const P: TSearchPassage);
var
  Stmt: Pointer;
  Rc: Integer;
  Msg: string;
begin
  Stmt := Prepare('UPDATE passages SET project_id = ?1, item_id = ?2 WHERE key = ?3');
  BindInt(Stmt, 1, P.ProjectId);
  BindInt(Stmt, 2, P.ItemId);
  BindText(Stmt, 3, P.Key);
  Rc := f_sqlite3_step(Stmt);
  if Rc <> SQLITE_DONE then
    Msg := string(f_sqlite3_errmsg16(FDb));
  f_sqlite3_reset(Stmt);
  if Rc <> SQLITE_DONE then
    raise ESearchIndexError.CreateFmt('Update %s failed (%d): %s', [P.Key, Rc, Msg]);
end;

procedure TSearchIndexStore.Delete(const Key: string);
var
  Stmt: Pointer;
  Rc: Integer;
  Msg: string;
begin
  Stmt := Prepare('DELETE FROM passages WHERE key = ?1');
  BindText(Stmt, 1, Key);
  Rc := f_sqlite3_step(Stmt);
  if Rc <> SQLITE_DONE then
    Msg := string(f_sqlite3_errmsg16(FDb));
  f_sqlite3_reset(Stmt);
  if Rc <> SQLITE_DONE then
    raise ESearchIndexError.CreateFmt('Delete %s failed (%d): %s', [Key, Rc, Msg]);
end;

function TSearchIndexStore.ReadFileText(FileId: Int64; out Md5, Extractor: string;
  out Outcome: TExtractOutcome; out Text: string): Boolean;
var
  Size, LastWrite: Int64;
begin
  Result := ReadFileText(FileId, Md5, Extractor, Outcome, Text, Size, LastWrite);
end;

function TSearchIndexStore.ReadFileText(FileId: Int64; out Md5, Extractor: string;
  out Outcome: TExtractOutcome; out Text: string; out Size, LastWrite: Int64): Boolean;
var
  Stmt: Pointer;
  Rc: Integer;
begin
  Md5 := '';
  Extractor := '';
  Outcome := eoNoText;
  Text := '';
  Size := -1;
  LastWrite := 0;
  Stmt := Prepare('SELECT content_md5, extractor, outcome, text, size, last_write FROM file_text ' +
    'WHERE file_id = ?1');
  BindInt(Stmt, 1, FileId);
  try
    Rc := f_sqlite3_step(Stmt);
    Result := Rc = SQLITE_ROW;
    if Result then
    begin
      Md5 := string(f_sqlite3_column_text16(Stmt, 0));
      Extractor := string(f_sqlite3_column_text16(Stmt, 1));
      Outcome := TExtractOutcome(f_sqlite3_column_int(Stmt, 2));
      Text := string(f_sqlite3_column_text16(Stmt, 3));
      Size := f_sqlite3_column_int64(Stmt, 4);
      LastWrite := f_sqlite3_column_int64(Stmt, 5);
    end
    else if Rc <> SQLITE_DONE then
      Check(Rc, 'read file text');
  finally
    f_sqlite3_reset(Stmt);
  end;
end;

procedure TSearchIndexStore.WriteFileText(FileId: Int64; const Md5, Extractor: string;
  Outcome: TExtractOutcome; const Detail, Text: string; Size, LastWrite: Int64);
var
  Stmt: Pointer;
  Rc: Integer;
  Msg: string;
begin
  Stmt := Prepare('INSERT OR REPLACE INTO file_text(file_id, content_md5, extractor, outcome, detail, ' +
    'text, size, last_write) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)');
  BindInt(Stmt, 1, FileId);
  BindText(Stmt, 2, Md5);
  BindText(Stmt, 3, Extractor);
  BindInt(Stmt, 4, Ord(Outcome));
  BindText(Stmt, 5, Detail);
  BindText(Stmt, 6, Text);
  if Size < 0 then
    LastWrite := 0;
  BindInt(Stmt, 7, Size);
  BindInt(Stmt, 8, LastWrite);
  Rc := f_sqlite3_step(Stmt);
  if Rc <> SQLITE_DONE then
    Msg := string(f_sqlite3_errmsg16(FDb));
  f_sqlite3_reset(Stmt);
  if Rc <> SQLITE_DONE then
    raise ESearchIndexError.CreateFmt('Write file text %d failed (%d): %s', [FileId, Rc, Msg]);
end;

procedure TSearchIndexStore.UpdateFileStamp(FileId, Size, LastWrite: Int64);
var
  Stmt: Pointer;
  Rc: Integer;
  Msg: string;
begin
  Stmt := Prepare('UPDATE file_text SET size = ?2, last_write = ?3 WHERE file_id = ?1');
  BindInt(Stmt, 1, FileId);
  BindInt(Stmt, 2, Size);
  BindInt(Stmt, 3, LastWrite);
  Rc := f_sqlite3_step(Stmt);
  if Rc <> SQLITE_DONE then
    Msg := string(f_sqlite3_errmsg16(FDb));
  f_sqlite3_reset(Stmt);
  if Rc <> SQLITE_DONE then
    raise ESearchIndexError.CreateFmt('Update file stamp %d failed (%d): %s', [FileId, Rc, Msg]);
end;

procedure TSearchIndexStore.DeleteFileTextExcept(const LiveFileIds: TArray<Int64>);
var
  Stmt: Pointer;
  Rc: Integer;
  Msg: string;
  Live: TDictionary<Int64, Boolean>;
  Stale: TList<Int64>;
  Id: Int64;
begin
  Live := TDictionary<Int64, Boolean>.Create;
  Stale := TList<Int64>.Create;
  try
    for Id in LiveFileIds do
      Live.AddOrSetValue(Id, True);
    Stmt := Prepare('SELECT file_id FROM file_text');
    try
      repeat
        Rc := f_sqlite3_step(Stmt);
        if Rc = SQLITE_ROW then
        begin
          Id := f_sqlite3_column_int64(Stmt, 0);
          if not Live.ContainsKey(Id) then
            Stale.Add(Id);
        end;
      until Rc <> SQLITE_ROW;
      if Rc <> SQLITE_DONE then
        Check(Rc, 'read file text ids');
    finally
      f_sqlite3_reset(Stmt);
    end;
    if Stale.Count = 0 then
      Exit;
    BeginBatch;
    try
      for Id in Stale do
      begin
        Stmt := Prepare('DELETE FROM file_text WHERE file_id = ?1');
        BindInt(Stmt, 1, Id);
        Rc := f_sqlite3_step(Stmt);
        if Rc <> SQLITE_DONE then
          Msg := string(f_sqlite3_errmsg16(FDb));
        f_sqlite3_reset(Stmt);
        if Rc <> SQLITE_DONE then
          raise ESearchIndexError.CreateFmt('Delete file text %d failed (%d): %s', [Id, Rc, Msg]);
      end;
      CommitBatch;
    except
      RollbackBatch;
      raise;
    end;
  finally
    Stale.Free;
    Live.Free;
  end;
end;

procedure TSearchIndexStore.LoadVectors(Index: TExactVectorIndex);
var
  Stmt: Pointer;
  Rc: Integer;
  Key: string;
  Vector: TEmbeddingVector;
  Blob: Pointer;
begin
  if Index.Dimension <> FDimension then
    raise ESearchIndexError.CreateFmt('Index dimension %d differs from store dimension %d',
      [Index.Dimension, FDimension]);
  Stmt := Prepare('SELECT key, project_id, item_id, vector, length(vector) FROM passages');
  try
    repeat
      Rc := f_sqlite3_step(Stmt);
      if Rc = SQLITE_ROW then
      begin
        Key := string(f_sqlite3_column_text16(Stmt, 0));
        if f_sqlite3_column_int(Stmt, 4) <> FDimension * SizeOf(Single) then
          raise ESearchIndexError.CreateFmt('Stored vector for %s has the wrong size', [Key]);
        Blob := f_sqlite3_column_blob(Stmt, 3);
        SetLength(Vector, FDimension);
        Move(Blob^, Vector[0], FDimension * SizeOf(Single));
        Index.Add(Key, IntToStr(f_sqlite3_column_int(Stmt, 1)), f_sqlite3_column_int(Stmt, 2), Vector);
      end;
    until Rc <> SQLITE_ROW;
    if Rc <> SQLITE_DONE then
      Check(Rc, 'load vectors');
  finally
    f_sqlite3_reset(Stmt);
  end;
end;

function IdsJson(const Ids: TArray<Integer>): string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to High(Ids) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + IntToStr(Ids[I]);
  end;
  Result := Result + ']';
end;

function TSearchIndexStore.MatchQuery(const Table, Match: string; const ProjectIds: TArray<Integer>;
  Limit: Integer; const Items: TItemFilter): TArray<TTextHit>;
var
  Stmt: Pointer;
  Rc, Count: Integer;
  ItemClause: string;
begin
  Result := nil;
  if (Limit < 1) or (Length(ProjectIds) = 0) then
    Exit;
  if Items.Active and (Length(Items.ItemIds) = 0) then
    Exit;
  ItemClause := '';
  if Items.Active then
    ItemClause := 'AND p.item_id IN (SELECT value FROM json_each(?4)) ';
  Stmt := Prepare('SELECT p.key FROM ' + Table + ' JOIN passages p ON p.id = ' + Table + '.rowid ' +
    'WHERE ' + Table + ' MATCH ?1 AND p.project_id IN (SELECT value FROM json_each(?2)) ' + ItemClause +
    'ORDER BY bm25(' + Table + '), p.key LIMIT ?3');
  BindText(Stmt, 1, Match);
  BindText(Stmt, 2, IdsJson(ProjectIds));
  BindInt(Stmt, 3, Limit);
  if Items.Active then
    BindText(Stmt, 4, IdsJson(Items.ItemIds));
  Count := 0;
  try
    repeat
      Rc := f_sqlite3_step(Stmt);
      if Rc = SQLITE_ROW then
      begin
        SetLength(Result, Count + 1);
        Result[Count].Key := string(f_sqlite3_column_text16(Stmt, 0));
        Result[Count].Rank := Count + 1;
        Inc(Count);
      end;
    until Rc <> SQLITE_ROW;
    if Rc <> SQLITE_DONE then
      Check(Rc, 'text search');
  finally
    f_sqlite3_reset(Stmt);
  end;
end;

function StripControlChars(const S: string): string;
var
  C: Char;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create(Length(S));
  try
    for C in S do
      if (C >= ' ') or (C = #9) or (C = #10) or (C = #13) then
        Builder.Append(C);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TSearchIndexStore.MatchWords(const Query: string; const ProjectIds: TArray<Integer>;
  Limit: Integer; const Items: TItemFilter): TArray<TTextHit>;
var
  Token, Match: string;
  Quoted: string;
  C: Char;
  HasWordChar: Boolean;
begin
  Match := '';
  for Token in StripControlChars(FoldSearchText(Query)).Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty) do
  begin
    HasWordChar := False;
    for C in Token do
      if C.IsLetterOrDigit then
      begin
        HasWordChar := True;
        Break;
      end;
    if not HasWordChar then
      Continue;
    Quoted := '"' + Token.Replace('"', '""') + '"';
    if Match <> '' then
      Match := Match + ' OR ';
    Match := Match + Quoted;
  end;
  if Match = '' then
    Exit(nil);
  Result := MatchQuery('passages_words', Match, ProjectIds, Limit, Items);
end;

function TSearchIndexStore.MatchTrigrams(const Query: string; const ProjectIds: TArray<Integer>;
  Limit: Integer; const Items: TItemFilter): TArray<TTextHit>;
var
  Folded: string;
begin
  Folded := StripControlChars(FoldSearchText(Query)).Trim;
  if Length(Folded) < TrigramMinChars then
    Exit(nil);
  Result := MatchQuery('passages_tri', '"' + Folded.Replace('"', '""') + '"', ProjectIds, Limit, Items);
end;

function TSearchIndexStore.PassageText(const Key: string): string;
var
  Stmt: Pointer;
  Rc: Integer;
begin
  Result := '';
  Stmt := Prepare('SELECT text FROM passages WHERE key = ?1');
  BindText(Stmt, 1, Key);
  try
    Rc := f_sqlite3_step(Stmt);
    if Rc = SQLITE_ROW then
      Result := string(f_sqlite3_column_text16(Stmt, 0))
    else if Rc <> SQLITE_DONE then
      Check(Rc, 'read passage');
  finally
    f_sqlite3_reset(Stmt);
  end;
end;

procedure TSearchIndexStore.ReplaceItemContexts(const Rows: TArray<TItemContextEntry>);
var
  Stmt: Pointer;
  Rc: Integer;
  Msg, Stored: string;
  Row: TItemContextEntry;
  Current: TDictionary<Integer, string>;
  Wanted: TDictionary<Integer, Boolean>;
  Stale: TList<Integer>;
  Changed: TList<TItemContextEntry>;
  Id: Integer;
begin
  Current := TDictionary<Integer, string>.Create;
  Wanted := TDictionary<Integer, Boolean>.Create;
  Stale := TList<Integer>.Create;
  Changed := TList<TItemContextEntry>.Create;
  try
    Stmt := Prepare('SELECT item_id, parts FROM item_context');
    try
      repeat
        Rc := f_sqlite3_step(Stmt);
        if Rc = SQLITE_ROW then
          Current.AddOrSetValue(f_sqlite3_column_int(Stmt, 0), string(f_sqlite3_column_text16(Stmt, 1)));
      until Rc <> SQLITE_ROW;
      if Rc <> SQLITE_DONE then
        Check(Rc, 'read item contexts');
    finally
      f_sqlite3_reset(Stmt);
    end;
    for Row in Rows do
    begin
      Wanted.AddOrSetValue(Row.ItemId, True);
      if not Current.TryGetValue(Row.ItemId, Stored) or (Stored <> Row.PartsJson) then
        Changed.Add(Row);
    end;
    for Id in Current.Keys do
      if not Wanted.ContainsKey(Id) then
        Stale.Add(Id);
    if (Stale.Count = 0) and (Changed.Count = 0) then
      Exit;
    BeginBatch;
    try
      for Id in Stale do
      begin
        Stmt := Prepare('DELETE FROM item_context WHERE item_id = ?1');
        BindInt(Stmt, 1, Id);
        Rc := f_sqlite3_step(Stmt);
        if Rc <> SQLITE_DONE then
          Msg := string(f_sqlite3_errmsg16(FDb));
        f_sqlite3_reset(Stmt);
        if Rc <> SQLITE_DONE then
          raise ESearchIndexError.CreateFmt('Delete item context %d failed (%d): %s', [Id, Rc, Msg]);
      end;
      for Row in Changed do
      begin
        Stmt := Prepare('INSERT OR REPLACE INTO item_context(item_id, parts) VALUES (?1, ?2)');
        BindInt(Stmt, 1, Row.ItemId);
        BindText(Stmt, 2, Row.PartsJson);
        Rc := f_sqlite3_step(Stmt);
        if Rc <> SQLITE_DONE then
          Msg := string(f_sqlite3_errmsg16(FDb));
        f_sqlite3_reset(Stmt);
        if Rc <> SQLITE_DONE then
          raise ESearchIndexError.CreateFmt('Write item context %d failed (%d): %s', [Row.ItemId, Rc, Msg]);
      end;
      CommitBatch;
    except
      RollbackBatch;
      raise;
    end;
  finally
    Changed.Free;
    Stale.Free;
    Wanted.Free;
    Current.Free;
  end;
end;

function TSearchIndexStore.ReadItemContext(ItemId: Integer; out PartsJson: string): Boolean;
var
  Stmt: Pointer;
  Rc: Integer;
begin
  PartsJson := '';
  Stmt := Prepare('SELECT parts FROM item_context WHERE item_id = ?1');
  BindInt(Stmt, 1, ItemId);
  try
    Rc := f_sqlite3_step(Stmt);
    Result := Rc = SQLITE_ROW;
    if Result then
      PartsJson := string(f_sqlite3_column_text16(Stmt, 0))
    else if Rc <> SQLITE_DONE then
      Check(Rc, 'read item context');
  finally
    f_sqlite3_reset(Stmt);
  end;
end;

{$IFDEF LINUX}
initialization
  if SQLiteLibraryName = '' then
  begin
    SQLiteLibraryName := GetEnvironmentVariable('ELN_SQLITE_LIBRARY');
    if SQLiteLibraryName = '' then
      SQLiteLibraryName := 'libsqlite3.so.0';
  end;
{$ENDIF}

end.
