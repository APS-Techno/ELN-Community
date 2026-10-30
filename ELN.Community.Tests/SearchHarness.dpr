program SearchHarness;

{$APPTYPE CONSOLE}

uses
  System.TypInfo,
  System.StrUtils,
{$IFDEF MSWINDOWS}
  unit_LocalNotebook,
  unit_NotebookStorage,
{$ENDIF}
  unit_ItemTypes,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Math,
  System.Diagnostics,
  System.Generics.Collections,
  System.Generics.Defaults,
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.PsAPI,
{$ENDIF}
{$IFDEF POSIX}
  Posix.Dlfcn,
{$ENDIF}
  Aurelius.Drivers.SQLite.Import,
  unit_NativeLibrary in '..\ELN.Search\unit_NativeLibrary.pas',
  unit_OnnxRuntimeApi in '..\ELN.Search\unit_OnnxRuntimeApi.pas',
  unit_UnigramTokenizer in '..\ELN.Search\unit_UnigramTokenizer.pas',
  unit_TextEmbedder in '..\ELN.Search\unit_TextEmbedder.pas',
  unit_VectorSearch in '..\ELN.Search\unit_VectorSearch.pas',
  unit_SearchPassages in '..\ELN.Search\unit_SearchPassages.pas',
  unit_PassageContext in '..\ELN.Search\unit_PassageContext.pas',
  unit_SearchDocumentProvider in '..\ELN.Model\unit_SearchDocumentProvider.pas',
  unit_SearchIndexStore in '..\ELN.Search\unit_SearchIndexStore.pas',
  unit_TarGz in '..\ELN.Search\unit_TarGz.pas',
  unit_SearchArtifactInstall in '..\ELN.Search\unit_SearchArtifactInstall.pas',
  unit_SearchIndexer in '..\ELN.Search\unit_SearchIndexer.pas',
  unit_SearchArtifacts in '..\ELN.Search\unit_SearchArtifacts.pas',
  unit_PdfiumApi in '..\ELN.Search\unit_PdfiumApi.pas',
  unit_TextExtractors in '..\ELN.Search\unit_TextExtractors.pas',
  unit_MarkupEntities in '..\ELN.Search\unit_MarkupEntities.pas',
  unit_TextStreamDecoder in '..\ELN.Search\unit_TextStreamDecoder.pas',
  unit_XmlTextScanner in '..\ELN.Search\unit_XmlTextScanner.pas',
  unit_OpenXmlPackage in '..\ELN.Search\unit_OpenXmlPackage.pas',
  unit_OfficeTextExtractors in '..\ELN.Search\unit_OfficeTextExtractors.pas',
  unit_MarkupTextExtractors in '..\ELN.Search\unit_MarkupTextExtractors.pas',
  unit_JsonTextExtractor in '..\ELN.Search\unit_JsonTextExtractor.pas',
  unit_RtfTextExtractor in '..\ELN.Search\unit_RtfTextExtractor.pas',
  unit_TextExtractorRegistry in '..\ELN.Search\unit_TextExtractorRegistry.pas',
  unit_FileTextStage in '..\ELN.Search\unit_FileTextStage.pas',
  unit_CrossEncoder in '..\ELN.Search\unit_CrossEncoder.pas',
  unit_HybridSearch in '..\ELN.Search\unit_HybridSearch.pas',
  unit_SearchMetrics in '..\ELN.Search\unit_SearchMetrics.pas',
  unit_SearchTestSupport in 'unit_SearchTestSupport.pas';

type
  TCorpusDocument = record
    Id: string;
    Scope: string;
    Text: string;
  end;

  THarnessOptions = record
    ArtifactRoot: string;
    CorpusPath: string;
    Query: string;
    Scopes: TArray<string>;
    TopK: Integer;
    BatchSize: Integer;
    Threads: Integer;
    BenchCopies: Integer;
    Fts5: Boolean;
    SQLiteLibrary: string;
    VerifyReference: Boolean;
    Notebook: string;
    StorageDir: string;
    EvalFile: string;
    EvalCorpus: string;
    Tuning: THybridSearchOptions;
    EvalModes: string;
    PerQueryFile: string;
    ComparePath: string;
    ExportCandidatesFile: string;
    Context: TPassageContextMode;
    RenameProject: Integer;
    RerankLatency: Boolean;
    RerankBatch: Integer;
    RerankTokens: Integer;
    InstallRoot: string;
  end;

procedure Usage;
begin
  Writeln('SearchHarness [options]');
  Writeln('  --artifacts DIR      search artifact root (default: ELN_SEARCH_ARTIFACTS, else %LOCALAPPDATA%\APS-ELN\search-artifacts on Windows');
  Writeln('                       or $XDG_DATA_HOME/APS-ELN/search-artifacts (~/.local/share when unset) on Linux)');
  Writeln('  --notebook DB        Windows only: index a COPY of a notebook (opened with TLocalNotebook.Open) into DB.search.sqlite and report; with --query also search it');
  Writeln('  --storage DIR        attachment root of the notebook copy (default: the root saved in the notebook)');
  Writeln('  --corpus FILE        corpus JSON (default: ELN.Community.Tests\Fixtures\Search\corpus.json)');
  Writeln('  --query TEXT         run one query instead of the corpus queries');
  Writeln('  --scope A,B          eligible scopes for --query (default: all corpus scopes)');
  Writeln('  --top N              results per query (default 5)');
  Writeln('  --batch N            passage batch size (default 8)');
  Writeln('  --threads N          ONNX Runtime intra-op threads (default 0 = runtime default)');
  Writeln('  --bench N            also encode the corpus N times and report throughput');
  Writeln('  --verify-reference   compare tokens and vectors with the reference fixtures');
  Writeln('  --eval FILE          run the queries in FILE (eval-dev.json, eval-heldout.json or eval-heldout-2.json) through words, trigram, vector and hybrid search and print the metric tables');
  Writeln('  --eval-corpus FILE   evaluation corpus for --eval (default: ELN.Community.Tests\Fixtures\Search\eval-corpus.json)');
  Writeln('  --modes A,B          modes for --eval: any of words, trigram, vector, hybrid, rerank (default: the first four; rerank needs the reranker files in the artifact root)');
  Writeln('  --rrf-k N            RRF constant of the fusion (default 60)');
  Writeln('  --candidates N       candidates of each list (default 50)');
  Writeln('  --list-weight NAME=X weight of the list words, trigram or vector (default 1, repeatable)');
  Writeln('  --field-weight NAME=X weight of a passage field, for example ItemTitle or FileText (default 1, repeatable)');
  Writeln('  --per-query FILE     write one line for each mode and query (tab separated) to FILE');
  Writeln('  --compare FILE       compare each query with a --per-query file of an earlier run and print the queries that changed');
  Writeln('  --export-candidates FILE  write the top 20 hybrid item groups of each query with their passage texts, and the item ids after them (JSON), to FILE');
  Writeln('  --context MODE       none, item or full: the context of each passage in the embedding input (default: the provider default). item = project and item title, full = all parts');
  Writeln('  --rename-project ID  after --eval, rename project ID in the corpus and sync again; print the re-embed counts and time (needs --context item or full)');
  Writeln('  --rerank-depth N     groups of the hybrid list that the reranker reorders in the rerank mode (default 20)');
  Writeln('  --rerank-latency     time the reranker for 20 pairs of --rerank-tokens tokens (default 400); --rerank-batch N sets the batch size; --threads sets the runtime threads');
  Writeln('  --fts5               probe FTS5 in the sqlite3.dll that Aurelius loads, on a temporary database');
  Writeln('  --install-artifacts DIR  download and install the artifacts of the platform manifest into DIR with the program installer');
  Writeln('  --sqlite FILE        sqlite3.dll to load for --fts5 (default: Aurelius search order)');
end;

function FixturePath(const Name: string): string;
begin
  Result := SearchFixturePath(Name);
end;

function ResolveFixture(const Path: string): string;
begin
  if TFile.Exists(Path) then
    Result := Path
  else
    Result := FixturePath(Path);
end;

function ParseContextMode(const Value: string): TPassageContextMode;
begin
  if SameText(Value, 'none') then Result := pcmNone
  else if SameText(Value, 'item') then Result := pcmItem
  else if SameText(Value, 'full') then Result := pcmFull
  else raise EArgumentException.CreateFmt('Unknown context mode %s (use none, item or full)', [Value]);
end;

function ParseOptions: THarnessOptions;
var
  I: Integer;

  function Next: string;
  begin
    Inc(I);
    if I > ParamCount then
      raise EArgumentException.CreateFmt('Missing value after %s', [ParamStr(I - 1)]);
    Result := ParamStr(I);
  end;

  procedure SplitSpec(const Spec: string; out Name: string; out Value: Double);
  var
    P: Integer;
  begin
    P := Pos('=', Spec);
    if P < 2 then
      raise EArgumentException.CreateFmt('Expected NAME=VALUE, got %s', [Spec]);
    Name := Copy(Spec, 1, P - 1);
    Value := StrToFloat(Copy(Spec, P + 1, MaxInt), TFormatSettings.Invariant);
  end;

  procedure SetListWeight(var Tuning: THybridSearchOptions; const Spec: string);
  var
    Name: string;
    Value: Double;
    Index: Integer;
  begin
    SplitSpec(Spec, Name, Value);
    Index := GetEnumValue(TypeInfo(TSearchHitSource), 'hs' + Name);
    if Index < 0 then
      raise EArgumentException.CreateFmt('Unknown list %s', [Name]);
    Tuning.ListWeights[TSearchHitSource(Index)] := Value;
  end;

  procedure SetFieldWeight(var Tuning: THybridSearchOptions; const Spec: string);
  var
    Name: string;
    Value: Double;
    Index: Integer;
  begin
    SplitSpec(Spec, Name, Value);
    Index := GetEnumValue(TypeInfo(TPassageField), 'pf' + Name);
    if Index < 0 then
      raise EArgumentException.CreateFmt('Unknown field %s', [Name]);
    Tuning.FieldWeights[TPassageField(Index)] := Value;
  end;

begin
  Result.ArtifactRoot := TE5EmbedderConfig.DefaultArtifactRoot;
  Result.CorpusPath := '';
  Result.Query := '';
  Result.Scopes := nil;
  Result.TopK := 5;
  Result.BatchSize := 8;
  Result.Threads := 0;
  Result.BenchCopies := 0;
  Result.Fts5 := False;
  Result.SQLiteLibrary := '';
  Result.VerifyReference := False;
  Result.Notebook := '';
  Result.StorageDir := '';
  Result.EvalFile := '';
  Result.EvalCorpus := 'eval-corpus.json';
  Result.Tuning := THybridSearchOptions.Default;
  Result.EvalModes := '';
  Result.PerQueryFile := '';
  Result.ComparePath := '';
  Result.ExportCandidatesFile := '';
  Result.Context := DefaultPassageContextMode;
  Result.RenameProject := 0;
  Result.RerankLatency := False;
  Result.RerankBatch := 0;
  Result.RerankTokens := 400;
  Result.InstallRoot := '';
  I := 1;
  while I <= ParamCount do
  begin
    if ParamStr(I) = '--artifacts' then Result.ArtifactRoot := Next
    else if ParamStr(I) = '--notebook' then Result.Notebook := Next
    else if ParamStr(I) = '--storage' then Result.StorageDir := Next
    else if ParamStr(I) = '--eval' then Result.EvalFile := Next
    else if ParamStr(I) = '--eval-corpus' then Result.EvalCorpus := Next
    else if ParamStr(I) = '--modes' then Result.EvalModes := Next
    else if ParamStr(I) = '--rrf-k' then Result.Tuning.RrfK := StrToInt(Next)
    else if ParamStr(I) = '--candidates' then Result.Tuning.CandidatesPerList := StrToInt(Next)
    else if ParamStr(I) = '--list-weight' then SetListWeight(Result.Tuning, Next)
    else if ParamStr(I) = '--field-weight' then SetFieldWeight(Result.Tuning, Next)
    else if ParamStr(I) = '--per-query' then Result.PerQueryFile := Next
    else if ParamStr(I) = '--compare' then Result.ComparePath := Next
    else if ParamStr(I) = '--export-candidates' then Result.ExportCandidatesFile := Next
    else if ParamStr(I) = '--context' then Result.Context := ParseContextMode(Next)
    else if ParamStr(I) = '--rename-project' then Result.RenameProject := StrToInt(Next)
    else if ParamStr(I) = '--rerank-depth' then Result.Tuning.RerankDepth := StrToInt(Next)
    else if ParamStr(I) = '--rerank-latency' then Result.RerankLatency := True
    else if ParamStr(I) = '--rerank-batch' then Result.RerankBatch := StrToInt(Next)
    else if ParamStr(I) = '--rerank-tokens' then Result.RerankTokens := StrToInt(Next)
    else if ParamStr(I) = '--corpus' then Result.CorpusPath := Next
    else if ParamStr(I) = '--query' then Result.Query := Next
    else if ParamStr(I) = '--scope' then Result.Scopes := Next.Split([','])
    else if ParamStr(I) = '--top' then Result.TopK := StrToInt(Next)
    else if ParamStr(I) = '--batch' then Result.BatchSize := StrToInt(Next)
    else if ParamStr(I) = '--threads' then Result.Threads := StrToInt(Next)
    else if ParamStr(I) = '--bench' then Result.BenchCopies := StrToInt(Next)
    else if ParamStr(I) = '--verify-reference' then Result.VerifyReference := True
    else if ParamStr(I) = '--fts5' then Result.Fts5 := True
    else if ParamStr(I) = '--install-artifacts' then Result.InstallRoot := Next
    else if ParamStr(I) = '--sqlite' then Result.SQLiteLibrary := Next
    else if (ParamStr(I) = '--help') or (ParamStr(I) = '-h') then
    begin
      Usage;
      Halt(0);
    end
    else
      raise EArgumentException.CreateFmt('Unknown option %s', [ParamStr(I)]);
    Inc(I);
  end;
  if Result.EvalFile <> '' then
  begin
    Result.EvalFile := ResolveFixture(Result.EvalFile);
    Result.EvalCorpus := ResolveFixture(Result.EvalCorpus);
  end
  else if (Result.CorpusPath = '') and (Result.Notebook = '') then
    Result.CorpusPath := FixturePath('corpus.json');
end;

function LoadJson(const Path: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(TFile.ReadAllBytes(Path), 0, True);
  if not (V is TJSONObject) then
  begin
    V.Free;
    raise Exception.CreateFmt('%s is not a JSON object', [Path]);
  end;
  Result := TJSONObject(V);
end;

{$IFDEF POSIX}
function ProcText(const Path: string): string;
var
  Stream: TFileStream;
  Bytes: TBytes;
  Count, Total: Integer;
begin
  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    Total := 0;
    SetLength(Bytes, 65536);
    repeat
      if Total = Length(Bytes) then
        SetLength(Bytes, Length(Bytes) * 2);
      Count := Stream.Read(Bytes[Total], Length(Bytes) - Total);
      Inc(Total, Count);
    until Count = 0;
  finally
    Stream.Free;
  end;
  Result := TEncoding.UTF8.GetString(Bytes, 0, Total);
end;

function ProcField(const Path, Name: string): string;
var
  Line: string;
begin
  Result := '';
  try
    for Line in ProcText(Path).Split([#10]) do
      if Line.StartsWith(Name) and (Line.IndexOf(':') > 0) then
        Exit(Line.Substring(Line.IndexOf(':') + 1).Trim);
  except
    on EStreamError do
      Result := '';
  end;
end;
{$ENDIF}

function MemoryText: string;
{$IFDEF MSWINDOWS}
var
  Counters: TProcessMemoryCounters;
begin
  Counters.cb := SizeOf(Counters);
  if GetProcessMemoryInfo(GetCurrentProcess, @Counters, SizeOf(Counters)) then
    Result := Format('working set %.0f MB, peak %.0f MB, private %.0f MB',
      [Counters.WorkingSetSize / 1048576, Counters.PeakWorkingSetSize / 1048576, Counters.PagefileUsage / 1048576])
  else
    Result := 'memory counters unavailable';
end;
{$ELSE}
var
  Resident, Peak: string;
begin
  Resident := ProcField('/proc/self/status', 'VmRSS');
  Peak := ProcField('/proc/self/status', 'VmHWM');
  if (Resident = '') or (Peak = '') then
    Result := 'memory counters unavailable'
  else
    Result := Format('resident %s, peak %s', [Resident, Peak]);
end;
{$ENDIF}

function Excerpt(const Text: string; Len: Integer): string;
begin
  if Length(Text) <= Len then
    Result := Text
  else
    Result := Copy(Text, 1, Len - 3) + '...';
end;

function Median(Values: TArray<Double>): Double;
begin
  TArray.Sort<Double>(Values);
  if Length(Values) = 0 then
    Exit(0);
  if Odd(Length(Values)) then
    Result := Values[Length(Values) div 2]
  else
    Result := (Values[Length(Values) div 2 - 1] + Values[Length(Values) div 2]) / 2;
end;

function CpuName: string;
{$IFDEF MSWINDOWS}
var
  Key: HKEY;
  Buffer: array[0..255] of Char;
  Size: DWORD;
begin
  Result := 'unknown CPU';
  if RegOpenKeyEx(HKEY_LOCAL_MACHINE, 'HARDWARE\DESCRIPTION\System\CentralProcessor\0', 0, KEY_READ,
    Key) = ERROR_SUCCESS then
  try
    Size := SizeOf(Buffer);
    if RegQueryValueEx(Key, 'ProcessorNameString', nil, nil, @Buffer[0], @Size) = ERROR_SUCCESS then
      Result := Trim(string(PChar(@Buffer[0])));
  finally
    RegCloseKey(Key);
  end;
end;
{$ELSE}
begin
  Result := ProcField('/proc/cpuinfo', 'model name');
  if Result = '' then
    Result := 'unknown CPU';
end;
{$ENDIF}

procedure ProbeFts5(const LibraryPath: string);
var
  DbPath: string;
  Db: Pointer;

  procedure Check(Code: Integer; const What: string);
  begin
    if Code <> SQLITE_OK then
      raise Exception.CreateFmt('%s failed (%d): %s', [What, Code, string(f_sqlite3_errmsg16(Db))]);
  end;

  function Query(const Sql: string; const Params: array of string): TArray<string>;
  var
    Stmt: Pointer;
    Tail: PChar;
    I, Rc: Integer;
    Row: string;
  begin
    Result := nil;
    Check(f_sqlite3_prepare16_v2(Db, PChar(Sql), -1, Stmt, Tail), Sql);
    try
      for I := 0 to High(Params) do
        Check(f_sqlite3_bind_text16(Stmt, I + 1, PChar(Params[I]), Length(Params[I]) * SizeOf(Char),
          SQLITE_TRANSIENT), 'bind');
      repeat
        Rc := f_sqlite3_step(Stmt);
        if Rc = SQLITE_ROW then
        begin
          Row := '';
          for I := 0 to f_sqlite3_column_count(Stmt) - 1 do
          begin
            if I > 0 then
              Row := Row + ' | ';
            Row := Row + string(f_sqlite3_column_text16(Stmt, I));
          end;
          Result := Result + [Row];
        end
        else if Rc <> SQLITE_DONE then
          Check(Rc, Sql);
      until Rc = SQLITE_DONE;
    finally
      f_sqlite3_finalize(Stmt);
    end;
  end;

  procedure Show(const Title, Sql: string; const Params: array of string);
  var
    Row: string;
    Rows: TArray<string>;
  begin
    try
      Rows := Query(Sql, Params);
      Writeln('  ', Title, ':');
      if Length(Rows) = 0 then
        Writeln('    (no rows)');
      for Row in Rows do
        Writeln('    ', Row);
    except
      on E: Exception do
        Writeln('  ', Title, ': ERROR ', E.Message);
    end;
  end;

var
{$IFDEF MSWINDOWS}
  Module: HMODULE;
  ModulePath: array[0..MAX_PATH] of Char;
{$ENDIF}
{$IFDEF POSIX}
  Info: dl_info;
{$ENDIF}
  Corpus: TJSONObject;
  Docs: TJSONArray;
  I, DocCount: Integer;
  Word: string;
begin
  Writeln('FTS5 probe');
  if LibraryPath <> '' then
    SQLiteLibraryName := LibraryPath;
  if not LoadSQLiteLibrary then
    raise Exception.CreateFmt('Cannot load SQLite (tried: %s)', [SQLiteLibraryNames]);
{$IFDEF MSWINDOWS}
  Module := GetModuleHandle('sqlite3.dll');
  if (Module <> 0) and (GetModuleFileName(Module, ModulePath, MAX_PATH) > 0) then
    Writeln('  loaded library: ', string(ModulePath))
  else
    Writeln('  loaded library: (not found by module name)');
{$ENDIF}
{$IFDEF POSIX}
  if (dladdr(NativeUInt(@f_sqlite3_open16), Info) <> 0) and (Info.dli_fname <> nil) then
    Writeln('  loaded library: ', string(UTF8String(Info.dli_fname)), ' (requested ', SQLiteLibraryNames, ')')
  else
    Writeln('  loaded library: (unknown; requested ', SQLiteLibraryNames, ')');
{$ENDIF}
  DbPath := TPath.Combine(TPath.GetTempPath, 'eln-fts5-probe-' + TGUID.NewGuid.ToString + '.sqlite');
  Writeln('  temporary database: ', DbPath);
  Db := nil;
  Check(f_sqlite3_open16(PChar(DbPath), Db), 'open');
  try
    Show('sqlite_version', 'select sqlite_version()', []);
    Show('ENABLE_FTS5 compile option', 'select sqlite_compileoption_used(''ENABLE_FTS5'')', []);
    Show('ENABLE_FTS4 compile option', 'select sqlite_compileoption_used(''ENABLE_FTS4'')', []);
    Show('create fts5 unicode61', 'create virtual table docs using fts5(id unindexed, body, ' +
      'tokenize = ''unicode61 remove_diacritics 2'')', []);
    Show('create fts5 trigram', 'create virtual table ids using fts5(body, tokenize = ''trigram'')', []);
    Corpus := LoadJson(FixturePath('corpus.json'));
    try
      Docs := Corpus.GetValue<TJSONArray>('documents');
      for I := 0 to Docs.Count - 1 do
      begin
        Query('insert into docs(id, body) values (?, ?)',
          [Docs.Items[I].GetValue<string>('id'), Docs.Items[I].GetValue<string>('text')]);
        Query('insert into ids(body) values (?)', [Docs.Items[I].GetValue<string>('text')]);
      end;
      Word := Docs.Items[5].GetValue<string>('text').Split([' '])[5];
      DocCount := Docs.Count;
    finally
      Corpus.Free;
    end;
    Writeln(Format('  inserted %d corpus documents', [DocCount]));
    Show('match "coating"', 'select id, round(bm25(docs), 4) from docs where docs match ? order by rank',
      ['coating']);
    Show('match doc-006 word with U+0451', 'select id, round(bm25(docs), 4) from docs where docs match ? ' +
      'order by rank', [Word]);
    Show('match the same word with U+0435 (remove_diacritics)', 'select id from docs where docs match ?',
      [Word.Replace(#$0451, #$0435)]);
    Show('match phrase "SMP 2024 017" (unicode61 splits identifiers)',
      'select id from docs where docs match ?', ['"SMP 2024 017"']);
    Show('trigram substring "2024-01"', 'select substr(body, 1, 60) from ids where ids match ?', ['"2024-01"']);
  finally
    f_sqlite3_close(Db);
    TFile.Delete(DbPath);
  end;
end;

function LoadDocuments(Corpus: TJSONObject): TArray<TCorpusDocument>;
var
  Docs: TJSONArray;
  I: Integer;
begin
  Docs := Corpus.GetValue<TJSONArray>('documents');
  SetLength(Result, Docs.Count);
  for I := 0 to Docs.Count - 1 do
  begin
    Result[I].Id := Docs.Items[I].GetValue<string>('id');
    Result[I].Scope := Docs.Items[I].GetValue<string>('scope');
    Result[I].Text := Docs.Items[I].GetValue<string>('text');
  end;
end;

procedure VerifyReference(const Embedder: ITextEmbedder; const ModelDirectory: string);
var
  Reference: TJSONObject;
  Cases: TJSONArray;
  Tokenizer: TUnigramTokenizer;
  I, J, Matches: Integer;
  Expected, Actual: TArray<Int64>;
  ExpectedVector: TArray<Double>;
  Got: TEmbedding;
  Text: string;
  Diff, WorstDiff, Cosine: Double;
  Equal: Boolean;
begin
  Reference := LoadJson(FixturePath('tokenizer_reference.json'));
  Tokenizer := TUnigramTokenizer.CreateFromFile(TPath.Combine(ModelDirectory, 'tokenizer.json'));
  try
    Cases := Reference.GetValue<TJSONArray>('cases');
    Matches := 0;
    for I := 0 to Cases.Count - 1 do
    begin
      Expected := nil;
      for J := 0 to Cases.Items[I].GetValue<TJSONArray>('ids').Count - 1 do
        Expected := Expected + [Cases.Items[I].GetValue<TJSONArray>('ids').Items[J].GetValue<Int64>];
      Actual := Tokenizer.Encode(Cases.Items[I].GetValue<string>('text'));
      Equal := Length(Expected) = Length(Actual);
      for J := 0 to Min(High(Expected), High(Actual)) do
        Equal := Equal and (Expected[J] = Actual[J]);
      if Equal then
        Inc(Matches)
      else
        Writeln('  token mismatch: ', Cases.Items[I].GetValue<string>('name'));
    end;
    Writeln(Format('Tokenizer parity: %d of %d reference cases identical (tokenizers %s)',
      [Matches, Cases.Count, Reference.GetValue<string>('provenance.tokenizers')]));
  finally
    Tokenizer.Free;
    Reference.Free;
  end;

  Reference := LoadJson(FixturePath('embedding_reference.json'));
  try
    Cases := Reference.GetValue<TJSONArray>('cases');
    WorstDiff := 0;
    for I := 0 to Cases.Count - 1 do
    begin
      Text := Cases.Items[I].GetValue<string>('text');
      if Text.StartsWith(E5QueryPrefix) then
        Got := Embedder.EncodeQuery(Text.Substring(Length(E5QueryPrefix)))
      else
        Got := Embedder.EncodePassages([Text.Substring(Length(E5PassagePrefix))], olReject)[0];
      SetLength(ExpectedVector, Cases.Items[I].GetValue<TJSONArray>('vector').Count);
      Diff := 0;
      Cosine := 0;
      for J := 0 to High(ExpectedVector) do
      begin
        ExpectedVector[J] := Cases.Items[I].GetValue<TJSONArray>('vector').Items[J].GetValue<Double>;
        Diff := Max(Diff, Abs(ExpectedVector[J] - Got.Vector[J]));
        Cosine := Cosine + ExpectedVector[J] * Got.Vector[J];
      end;
      WorstDiff := Max(WorstDiff, Diff);
      Writeln(Format('  vector %d (%d tokens): max abs diff %.2e, cosine %.8f',
        [I, Got.TokenCount, Diff, Cosine]));
    end;
    Writeln(Format('Embedding parity: worst max abs diff %.2e over %d reference vectors (onnxruntime %s, numpy pooling)',
      [WorstDiff, Cases.Count, Reference.GetValue<string>('provenance.onnxruntime')]));
  finally
    Reference.Free;
  end;
end;

procedure RunQueries(const Embedder: ITextEmbedder; Index: TExactVectorIndex;
  const Docs: TArray<TCorpusDocument>; Corpus: TJSONObject; const Options: THarnessOptions;
  const AllScopes: TArray<string>);
var
  TextById: TDictionary<string, string>;
  Doc: TCorpusDocument;
  Queries: TJSONArray;
  I, J, HitCount, Asserted: Integer;
  Text, Kind, Id: string;
  Scopes, Relevant: TArray<string>;
  Hits: TArray<TVectorHit>;
  Latencies: TArray<Double>;
  Watch: TStopwatch;
  Found: Boolean;
  ScopeValue, RelevantValue: TJSONValue;
begin
  TextById := TDictionary<string, string>.Create;
  try
    for Doc in Docs do
      TextById.Add(Doc.Id, Doc.Text);
    if Options.Query <> '' then
    begin
      Queries := TJSONArray.Create;
      Queries.Add(TJSONObject.Create.AddPair('id', 'cli').AddPair('kind', 'ad-hoc').AddPair('text', Options.Query));
    end
    else
      Queries := Corpus.GetValue<TJSONArray>('queries').Clone as TJSONArray;
    try
      HitCount := 0;
      Asserted := 0;
      for I := 0 to Queries.Count - 1 do
      begin
        Id := Queries.Items[I].GetValue<string>('id');
        Kind := Queries.Items[I].GetValue<string>('kind');
        Text := Queries.Items[I].GetValue<string>('text');
        Scopes := AllScopes;
        if Options.Scopes <> nil then
          Scopes := Options.Scopes;
        ScopeValue := Queries.Items[I].FindValue('scope');
        if ScopeValue is TJSONArray then
        begin
          Scopes := nil;
          for J := 0 to TJSONArray(ScopeValue).Count - 1 do
            Scopes := Scopes + [TJSONArray(ScopeValue).Items[J].Value];
        end;
        Relevant := nil;
        RelevantValue := Queries.Items[I].FindValue('relevant');
        if RelevantValue is TJSONArray then
          for J := 0 to TJSONArray(RelevantValue).Count - 1 do
            Relevant := Relevant + [TJSONArray(RelevantValue).Items[J].Value];

        Watch := TStopwatch.StartNew;
        Hits := Index.Search(Embedder.EncodeQuery(Text).Vector, Options.TopK, Scopes, Default(TItemFilter));
        Latencies := Latencies + [Watch.Elapsed.TotalMilliseconds];

        Found := Length(Relevant) = 0;
        for J := 0 to Min(2, High(Hits)) do
          Found := Found or TArray.Contains<string>(Relevant, Hits[J].SourceId);
        if RelevantValue is TJSONArray then
        begin
          Inc(Asserted);
          if Found then
            Inc(HitCount);
        end;
        Writeln;
        Writeln(Format('%s [%s] scopes=%s: %s', [Id, Kind, string.Join(',', Scopes), Text]));
        if RelevantValue is TJSONArray then
          Writeln(Format('  expected: %s  relevant in top 3: %s', [string.Join(',', Relevant), BoolToStr(Found, True)]));
        for J := 0 to High(Hits) do
          Writeln(Format('  %d. %s  %-8s %.4f  %s', [J + 1, Hits[J].SourceId, Hits[J].Scope, Hits[J].Score,
            Excerpt(TextById[Hits[J].SourceId], 90)]));
      end;
      Writeln;
      if Asserted > 0 then
        Writeln(Format('Relevant document in top 3: %d of %d queries', [HitCount, Asserted]));
      Writeln(Format('Query latency (encode + exact search over %d vectors): median %.1f ms, max %.1f ms, n=%d',
        [Index.Count, Median(Latencies), MaxValue(Latencies), Length(Latencies)]));
    finally
      Queries.Free;
    end;
  finally
    TextById.Free;
  end;
end;

procedure WarmUpEmbedder(const Embedder: ITextEmbedder);
const
  Filler = 'SMP-2024-017 Mo/Si d=3.5 nm, T=25 C, P=1.2e-6 mbar, run 14/B; ';
var
  Texts: TArray<string>;
  Text: string;
  I: Integer;
begin
  SetLength(Texts, SyncEmbedBatch);
  for I := 0 to High(Texts) do
  begin
    Text := '';
    while Length(Text) < PassageMaxChars do
      Text := Text + Filler + IntToStr(I) + ' ';
    SetLength(Text, PassageMaxChars);
    Texts[I] := Text;
  end;
  Embedder.EncodePassages(Texts, olTruncate);
end;

{$IFDEF MSWINDOWS}
procedure RunNotebook(const Embedder: ITextEmbedder; const Options: THarnessOptions);
var
  Notebook: TLocalNotebook;
  Source: ISearchDocumentSource;
  Store: TSearchIndexStore;
  Searcher: THybridSearcher;
  Stats: TSyncStats;
  Indexer: TSearchIndexer;
  Catalog: TDictionary<string, TStoredPassage>;
  Row: TStoredPassage;
  Visible: TDictionary<Integer, Boolean>;
  Counts: array[TPassageField] of Integer;
  Field: TPassageField;
  Hits: TArray<THybridGroup>;
  Hit: THybridGroup;
  Passage: THybridHit;
  Source3: TSearchHitSource;
  SourceNames, StorePath: string;
  VisibleIds: TArray<Integer>;
  Latencies: TArray<Double>;
  Watch: TStopwatch;
  PrivateBefore: Double;
  Existed: Boolean;
  I, Total: Integer;
  Registry: TTextExtractorRegistry;
  Stage: TFileTextStage;
  Reader: IFileContentReader;

  function IndexSource: ISearchDocumentSource;
  var
    Snapshot: TSearchSnapshot;
  begin
    Snapshot := Source.ReadSnapshot(nil);
    Result := TPassageSnapshotSource.Create(
      Snapshot.Passages + Stage.BuildFilePassages(Snapshot.Files, Reader, nil, nil));
  end;

  function FileSizeOrZero(const Path: string): Int64;
  begin
    if TFile.Exists(Path) then
      Result := TFile.GetSize(Path)
    else
      Result := 0;
  end;

  function PrivateMB: Double;
  var
    Counters: TProcessMemoryCounters;
  begin
    Counters.cb := SizeOf(Counters);
    if GetProcessMemoryInfo(GetCurrentProcess, @Counters, SizeOf(Counters)) then
      Result := Counters.PagefileUsage / 1048576
    else
      Result := 0;
  end;

begin
  Notebook := TLocalNotebook.Open(Options.Notebook, Options.StorageDir);
  try
    StorePath := ChangeFileExt(Notebook.DatabasePath, '') + '.search.sqlite';
    Existed := TFile.Exists(StorePath);
    Writeln('Notebook copy: ', Notebook.DatabasePath);
    Writeln('Search store: ', StorePath, IfThen(Existed, ' (existed before this run)', ' (new)'));
    WarmUpEmbedder(Embedder);
    PrivateBefore := PrivateMB;
    Writeln(Format('Private memory baseline after one warm-up batch of %d passages of %d characters: %.0f MB',
      [SyncEmbedBatch, PassageMaxChars, PrivateBefore]));
    Source := TNotebookDocumentProvider.Create(Notebook.Manager, Options.Context);
    Reader := TStorageFileReader.Create(Notebook.Storage);
    Store := TSearchIndexStore.Open(StorePath, Embedder.Identity, Embedder.Dimension);
    Registry := TTextExtractorRegistry.Create(SearchPdfiumLibraryPath);
    Stage := TFileTextStage.Create(Store, Registry);
    try
      Writeln('Store was reset (identity or schema change): ', BoolToStr(Store.WasReset, True));
      Watch := TStopwatch.StartNew;
      Indexer := TSearchIndexer.Create(IndexSource, Store, Embedder);
      try
        Stats := Indexer.Sync;
      finally
        Indexer.Free;
      end;
      Total := Stats.Added + Stats.Changed;
      Writeln(Format('First sync: %.1f s, embedded %d (added %d, changed %d, moved %d, removed %d, unchanged %d, truncated %d): %.1f passages/s',
        [Watch.Elapsed.TotalSeconds, Total, Stats.Added, Stats.Changed, Stats.Moved, Stats.Removed,
         Stats.Unchanged, Stats.Truncated, IfThen(Watch.Elapsed.TotalSeconds > 0, Total / Watch.Elapsed.TotalSeconds, 0)]));
      Watch := TStopwatch.StartNew;
      Indexer := TSearchIndexer.Create(IndexSource, Store, Embedder);
      try
        Stats := Indexer.Sync;
      finally
        Indexer.Free;
      end;
      Writeln(Format('Second sync: %.2f s, embedded %d (added %d, changed %d, moved %d, removed %d, unchanged %d)',
        [Watch.Elapsed.TotalSeconds, Stats.Added + Stats.Changed, Stats.Added, Stats.Changed, Stats.Moved,
         Stats.Removed, Stats.Unchanged]));

      for Field := Low(TPassageField) to High(TPassageField) do
        Counts[Field] := 0;
      Catalog := Store.ReadCatalog;
      try
        for Row in Catalog.Values do
          Inc(Counts[Row.Field]);
        Writeln(Format('Passages: %d', [Catalog.Count]));
      finally
        Catalog.Free;
      end;
      for Field := Low(TPassageField) to High(TPassageField) do
        Writeln(Format('  %-20s %d', [GetEnumName(TypeInfo(TPassageField), Ord(Field)), Counts[Field]]));
      Writeln(Format('Store size: %.2f MB (database %.2f MB, WAL %.2f MB)',
        [(TFile.GetSize(StorePath) + FileSizeOrZero(StorePath + '-wal')) / 1048576,
         TFile.GetSize(StorePath) / 1048576, FileSizeOrZero(StorePath + '-wal') / 1048576]));
      Writeln(Format('Private memory after sync: %.0f MB (growth since the warm-up baseline: %.0f MB)',
        [PrivateMB, PrivateMB - PrivateBefore]));

      if Options.Query <> '' then
      begin
        Visible := Notebook.AccessPolicy.VisibleProjectIds(Notebook.Manager, Notebook.Principal);
        try
          VisibleIds := Visible.Keys.ToArray;
        finally
          Visible.Free;
        end;
        Searcher := THybridSearcher.Create(Store, Embedder, Source);
        try
          Writeln(Format('Private memory after loading the search index: %.0f MB (growth since the warm-up baseline: %.0f MB)',
            [PrivateMB, PrivateMB - PrivateBefore]));
          Hits := Searcher.Search(Options.Query, VisibleIds, 10, THybridSearchOptions.Default);
          Writeln(Format('Query "%s": %d groups in %d visible projects', [Options.Query, Length(Hits), Length(VisibleIds)]));
          for I := 0 to High(Hits) do
          begin
            Hit := Hits[I];
            SourceNames := '';
            for Source3 := Low(TSearchHitSource) to High(TSearchHitSource) do
              if Source3 in Hit.Sources then
                SourceNames := SourceNames + IfThen(SourceNames = '', '', '+') +
                  GetEnumName(TypeInfo(TSearchHitSource), Ord(Source3));
            Writeln(Format('  %d. %.5f [%s] item %d', [I + 1, Hit.Score, SourceNames, Hit.ItemId]));
            for Passage in Hit.Passages do
              Writeln(Format('       %.5f %s: %s', [Passage.Score,
                GetEnumName(TypeInfo(TPassageField), Ord(Passage.Field)),
                Excerpt(Passage.Snippet.Replace(#13, ' ').Replace(#10, ' '), 100)]));
          end;
          Latencies := nil;
          for I := 1 to 20 do
          begin
            Watch := TStopwatch.StartNew;
            Searcher.Search(Options.Query, VisibleIds, 10, THybridSearchOptions.Default);
            Latencies := Latencies + [Watch.Elapsed.TotalMilliseconds];
          end;
          Writeln(Format('Warm query latency (hybrid, 20 runs): median %.1f ms, max %.1f ms',
            [Median(Latencies), MaxValue(Latencies)]));
          Writeln(Format('Private memory after queries: %.0f MB (growth since the warm-up baseline: %.0f MB)',
            [PrivateMB, PrivateMB - PrivateBefore]));
        finally
          Searcher.Free;
        end;
      end;
    finally
      Stage.Free;
      Registry.Free;
      Store.Free;
    end;
  finally
    Source := nil;
    Notebook.Free;
  end;
end;
{$ENDIF}

type
  TEvalSource = class(TInterfacedObject, ISearchDocumentSource)
  private
    FPassages: TSearchPassages;
    FProjectOfItem: TDictionary<Integer, Integer>;
  public
    constructor Create(const Passages: TSearchPassages);
    destructor Destroy; override;
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

  TEvalQuery = record
    Id, Kind, Text: string;
    Relevant: TArray<TGradedItem>;
    Irrelevant: TArray<Integer>;
  end;

  TEvalFolder = record
    ProjectId, ParentId: Integer;
    Title: string;
  end;

  TEvalItemContext = record
    ProjectId, FolderId, ParentId: Integer;
    FolderPath: TArray<string>;
    Level: TItemLevel;
    ItemType: TItemType;
    Title, ActionType, ParentTitle: string;
  end;

  TEvalMode = record
    Name: string;
    Lists: set of TSearchHitSource;
  end;

  TEvalStats = record
    Queries: Integer;
    Recall5, Recall10, Mrr, Ndcg10: TMetricMean;
    IrrelevantAt5: Integer;
    IrrelevantQueries: Integer;
    Latencies: TArray<Double>;
  end;

constructor TEvalSource.Create(const Passages: TSearchPassages);
var
  Passage: TSearchPassage;
begin
  inherited Create;
  FPassages := Passages;
  FProjectOfItem := TDictionary<Integer, Integer>.Create;
  for Passage in Passages do
    FProjectOfItem.AddOrSetValue(Passage.ItemId, Passage.ProjectId);
end;

destructor TEvalSource.Destroy;
begin
  FProjectOfItem.Free;
  inherited;
end;

function TEvalSource.ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
begin
  Result := Default(TSearchSnapshot);
  Result.Passages := FPassages;
end;

function TEvalSource.IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
begin
  Result := FProjectOfItem.TryGetValue(ItemId, ProjectId);
end;

function Invariant(const Template: string; const Args: array of const): string;
begin
  Result := Format(Template, Args, TFormatSettings.Invariant);
end;

function MetricText(Value: Double): string;
begin
  if IsNan(Value) then
    Result := '-'
  else
    Result := Invariant('%.3f', [Value]);
end;

function EnumOrdinal(Info: PTypeInfo; const Name, What: string; ItemId: Integer): Integer;
begin
  Result := GetEnumValue(Info, Name);
  if (Result < 0) or (GetEnumName(Info, Result) <> Name) then
    raise Exception.CreateFmt('Evaluation corpus item %d: unknown %s "%s"', [ItemId, What, Name]);
end;

function LoadEvalFolders(const Corpus: TJSONObject): TDictionary<Integer, TEvalFolder>;
var
  Value: TJSONValue;
  Folder, ParentFolder: TEvalFolder;
  Id: Integer;
begin
  Result := TDictionary<Integer, TEvalFolder>.Create;
  try
    for Value in Corpus.GetValue<TJSONArray>('folders') do
    begin
      Id := Value.GetValue<Integer>('id');
      Folder.ProjectId := Value.GetValue<Integer>('project');
      Folder.ParentId := Value.GetValue<Integer>('parent');
      Folder.Title := Value.GetValue<string>('title');
      if Folder.Title = '' then
        raise Exception.CreateFmt('Evaluation corpus folder %d has no title', [Id]);
      if Result.ContainsKey(Id) then
        raise Exception.CreateFmt('Evaluation corpus folder %d is listed twice', [Id]);
      Result.Add(Id, Folder);
    end;
    for Id in Result.Keys do
    begin
      Folder := Result[Id];
      if (Folder.ParentId <> 0) and
        (not Result.TryGetValue(Folder.ParentId, ParentFolder) or (ParentFolder.ProjectId <> Folder.ProjectId)) then
        raise Exception.CreateFmt('Evaluation corpus folder %d has no parent folder %d in its project',
          [Id, Folder.ParentId]);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function LoadEvalContext(const Corpus: TJSONObject): TDictionary<Integer, TEvalItemContext>;
var
  Folders: TDictionary<Integer, TEvalFolder>;
  Value: TJSONValue;
  Folder: TEvalFolder;
  Context, ParentContext: TEvalItemContext;
  Item: TJSONObject;
  Ids: TArray<Integer>;
  ItemId, Cursor, Depth: Integer;
begin
  Folders := LoadEvalFolders(Corpus);
  try
    Result := TDictionary<Integer, TEvalItemContext>.Create;
    try
      for Value in Corpus.GetValue<TJSONArray>('items') do
      begin
        Item := Value as TJSONObject;
        ItemId := Item.GetValue<Integer>('id');
        Context := Default(TEvalItemContext);
        Context.Title := Item.GetValue<string>('title');
        Context.ProjectId := Item.GetValue<Integer>('project');
        Context.FolderId := Item.GetValue<Integer>('folder');
        Context.ParentId := Item.GetValue<Integer>('parent');
        Context.Level := TItemLevel(EnumOrdinal(TypeInfo(TItemLevel), Item.GetValue<string>('level'),
          'level', ItemId));
        Context.ItemType := TItemType(EnumOrdinal(TypeInfo(TItemType), Item.GetValue<string>('type'),
          'type', ItemId));
        Context.ActionType := Item.GetValue<string>('action_type');
        if Context.ActionType = '' then
          raise Exception.CreateFmt('Evaluation corpus item %d has no action type', [ItemId]);
        if not Folders.TryGetValue(Context.FolderId, Folder) or (Folder.ProjectId <> Context.ProjectId) then
          raise Exception.CreateFmt('Evaluation corpus item %d has no folder %d in its project',
            [ItemId, Context.FolderId]);
        Cursor := Context.FolderId;
        Depth := 0;
        while Cursor <> 0 do
        begin
          Inc(Depth);
          if Depth > Folders.Count then
            raise Exception.CreateFmt('Evaluation corpus item %d: the folder chain does not end', [ItemId]);
          Folder := Folders[Cursor];
          Context.FolderPath := [Folder.Title] + Context.FolderPath;
          Cursor := Folder.ParentId;
        end;
        if Result.ContainsKey(ItemId) then
          raise Exception.CreateFmt('Evaluation corpus item %d is listed twice', [ItemId]);
        Result.Add(ItemId, Context);
      end;
      Ids := Result.Keys.ToArray;
      for ItemId in Ids do
      begin
        Context := Result[ItemId];
        if Context.Level <> TItemLevel.Action then
        begin
          if Context.ParentId <> 0 then
            raise Exception.CreateFmt('Evaluation corpus item %d is not an action and has a parent', [ItemId]);
          Continue;
        end;
        if not Result.TryGetValue(Context.ParentId, ParentContext) or (ParentContext.Level <> TItemLevel.Proc) or
          (ParentContext.ProjectId <> Context.ProjectId) or (ParentContext.FolderId <> Context.FolderId) then
          raise Exception.CreateFmt('Evaluation corpus action %d: parent %d must be a Proc of the same project and folder',
            [ItemId, Context.ParentId]);
        Context.ParentTitle := ParentContext.Title;
        Result[ItemId] := Context;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Folders.Free;
  end;
end;

function LoadProjectTitles(const Corpus: TJSONObject): TDictionary<Integer, string>;
var
  Value: TJSONValue;
begin
  Result := TDictionary<Integer, string>.Create;
  try
    for Value in Corpus.GetValue<TJSONArray>('projects') do
      Result.AddOrSetValue(Value.GetValue<Integer>('id'), Value.GetValue<string>('name'));
  except
    Result.Free;
    raise;
  end;
end;

function LoadEvalPassages(const Corpus: TJSONObject; Mode: TPassageContextMode;
  RenamedProjectId: Integer; out ProjectIds: TArray<Integer>;
  out ItemCount: Integer): TSearchPassages;
var
  Passages: TList<TSearchPassage>;
  Projects: TDictionary<Integer, Boolean>;
  Contexts: TDictionary<Integer, TEvalItemContext>;
  ProjectTitles: TDictionary<Integer, string>;
  Items, Files: TJSONArray;
  Item, FileEntry: TJSONObject;
  Tags: TArray<string>;
  Value, TagValue: TJSONValue;
  Parts: TPassageContextParts;
  Context: TEvalItemContext;
  ItemId, ProjectId, I: Integer;
  FileId: Int64;
  KeyBase: string;

  function ContextFor(Field: TPassageField): string;
  begin
    Result := PassageContextFor(Mode, Parts, Field);
  end;

begin
  Contexts := nil;
  ProjectTitles := nil;
  Passages := TList<TSearchPassage>.Create;
  Projects := TDictionary<Integer, Boolean>.Create;
  try
    if Mode <> pcmNone then
    begin
      if not Corpus.TryGetValue<TJSONArray>('folders', Items) then
        raise Exception.Create('--context item and --context full need a corpus with folders');
      Contexts := LoadEvalContext(Corpus);
      ProjectTitles := LoadProjectTitles(Corpus);
    end
    else if RenamedProjectId <> 0 then
      raise Exception.Create('--rename-project needs --context item or --context full');
    Items := Corpus.GetValue<TJSONArray>('items');
    ItemCount := Items.Count;
    for Value in Items do
    begin
      Item := Value as TJSONObject;
      ItemId := Item.GetValue<Integer>('id');
      ProjectId := Item.GetValue<Integer>('project');
      Projects.AddOrSetValue(ProjectId, True);
      if Mode <> pcmNone then
      begin
        Context := Contexts[ItemId];
        Parts := Default(TPassageContextParts);
        Parts.ProjectTitle := ProjectTitles[ProjectId];
        if ProjectId = RenamedProjectId then
          Parts.ProjectTitle := Parts.ProjectTitle + ' renamed';
        Parts.FolderPath := Context.FolderPath;
        Parts.ItemTitle := Context.Title;
        Parts.ItemKind := GetEnumName(TypeInfo(TItemType), Ord(Context.ItemType));
        Parts.ParentTitle := Context.ParentTitle;
        Parts.ActionType := Context.ActionType;
      end;
      KeyBase := 'item:' + IntToStr(ItemId);
      AppendTextPassages(Passages, KeyBase + ':title', ProjectId, ItemId, 0, pfItemTitle,
        Item.GetValue<string>('title'), ContextFor(pfItemTitle));
      AppendTextPassages(Passages, KeyBase + ':description', ProjectId, ItemId, 0, pfItemDescription,
        Item.GetValue<string>('description'), ContextFor(pfItemDescription));
      Tags := nil;
      for TagValue in Item.GetValue<TJSONArray>('tags') do
        Tags := Tags + [TagValue.Value];
      TArray.Sort<string>(Tags);
      AppendTextPassages(Passages, KeyBase + ':tags', ProjectId, ItemId, 0, pfItemTags,
        string.Join(', ', Tags), ContextFor(pfItemTags));
      if Item.TryGetValue<TJSONArray>('files', Files) then
        for I := 0 to Files.Count - 1 do
        begin
          FileEntry := Files.Items[I] as TJSONObject;
          FileId := Int64(ItemId) * 10 + I + 1;
          AppendTextPassages(Passages, 'file:' + IntToStr(FileId) + ':name', ProjectId, ItemId, FileId,
            pfFileName, FileEntry.GetValue<string>('name'), ContextFor(pfFileName));
          AppendTextPassages(Passages, 'file:' + IntToStr(FileId) + ':text', ProjectId, ItemId, FileId,
            pfFileText, FileEntry.GetValue<string>('text'), ContextFor(pfFileText));
        end;
    end;
    ProjectIds := Projects.Keys.ToArray;
    TArray.Sort<Integer>(ProjectIds);
    Result := Passages.ToArray;
  finally
    ProjectTitles.Free;
    Contexts.Free;
    Projects.Free;
    Passages.Free;
  end;
end;

function EvalContextSummary(const Corpus: TJSONObject): string;
var
  Context: TDictionary<Integer, TEvalItemContext>;
  Item: TEvalItemContext;
  Levels: array[TItemLevel] of Integer;
  Level: TItemLevel;
  FolderRows: TJSONArray;
  MaxDepth: Integer;
begin
  if not Corpus.TryGetValue<TJSONArray>('folders', FolderRows) then
    Exit('');
  Context := LoadEvalContext(Corpus);
  try
    for Level := Low(TItemLevel) to High(TItemLevel) do
      Levels[Level] := 0;
    MaxDepth := 0;
    for Item in Context.Values do
    begin
      Inc(Levels[Item.Level]);
      MaxDepth := Max(MaxDepth, Length(Item.FolderPath));
    end;
    Result := Format('Context fields: %d folders, folder paths up to %d levels deep, items by level:',
      [FolderRows.Count, MaxDepth]);
    for Level := Low(TItemLevel) to High(TItemLevel) do
      Result := Result + Format(' %s %d', [GetEnumName(TypeInfo(TItemLevel), Ord(Level)), Levels[Level]]);
  finally
    Context.Free;
  end;
end;

function LoadEvalQueries(const Path: string): TArray<TEvalQuery>;
var
  Json: TJSONObject;
  Value, Entry: TJSONValue;
  Query: TEvalQuery;
  Graded: TGradedItem;
  Queries: TList<TEvalQuery>;
  Rows: TJSONArray;
begin
  Json := LoadJson(Path);
  Queries := TList<TEvalQuery>.Create;
  try
    for Value in Json.GetValue<TJSONArray>('queries') do
    begin
      Query := Default(TEvalQuery);
      Query.Id := Value.GetValue<string>('id');
      Query.Kind := Value.GetValue<string>('kind');
      Query.Text := Value.GetValue<string>('text');
      if Value.TryGetValue<TJSONArray>('relevant', Rows) then
        for Entry in Rows do
        begin
          Graded.ItemId := Entry.GetValue<Integer>('item');
          Graded.Grade := Entry.GetValue<Integer>('grade');
          Query.Relevant := Query.Relevant + [Graded];
        end;
      if Value.TryGetValue<TJSONArray>('irrelevant', Rows) then
        for Entry in Rows do
          Query.Irrelevant := Query.Irrelevant + [StrToInt(Entry.Value)];
      Queries.Add(Query);
    end;
    Result := Queries.ToArray;
  finally
    Queries.Free;
    Json.Free;
  end;
end;

function ItemRanking(const Groups: TArray<THybridGroup>): TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, Length(Groups));
  for I := 0 to High(Groups) do
    Result[I] := Groups[I].ItemId;
end;

procedure AddEvalResult(var Stats: TEvalStats; const Query: TEvalQuery; const Ranking: TArray<Integer>;
  LatencyMs: Double);
begin
  Inc(Stats.Queries);
  Stats.Recall5.Add(RecallAtK(Ranking, Query.Relevant, 5));
  Stats.Recall10.Add(RecallAtK(Ranking, Query.Relevant, 10));
  Stats.Mrr.Add(ReciprocalRank(Ranking, Query.Relevant));
  Stats.Ndcg10.Add(NdcgAtK(Ranking, Query.Relevant, 10));
  if Length(Query.Irrelevant) > 0 then
  begin
    Inc(Stats.IrrelevantQueries);
    Inc(Stats.IrrelevantAt5, CountAtK(Ranking, Query.Irrelevant, 5));
  end;
  Stats.Latencies := Stats.Latencies + [LatencyMs];
end;

procedure PrintEvalRow(const Name: string; const Stats: TEvalStats);
var
  Latency: Double;
  Total: Double;
  Irrelevant: string;
begin
  Total := 0;
  for Latency in Stats.Latencies do
    Total := Total + Latency;
  if Stats.IrrelevantQueries > 0 then
    Irrelevant := IntToStr(Stats.IrrelevantAt5)
  else
    Irrelevant := '-';
  Writeln(Invariant('%-16s %7d %6d %7s %7s %7s %8s %6s %8.1f %8.1f',
    [Name, Stats.Queries, Stats.Recall5.Count, MetricText(Stats.Recall5.Mean),
     MetricText(Stats.Recall10.Mean), MetricText(Stats.Mrr.Mean), MetricText(Stats.Ndcg10.Mean),
     Irrelevant, Total / Max(1, Length(Stats.Latencies)), Percentile(Stats.Latencies, 0.95)]));
end;

type
  TBaselineRow = record
    Ndcg: Double;
    Irrelevant: Integer;
  end;

  TCompareStats = record
    Better, Worse, Same: Integer;
    IrrelevantFewer, IrrelevantMore, IrrelevantSame: Integer;
  end;

const
  CompareTolerance = 1e-5;

function LoadBaseline(const Path: string): TDictionary<string, TBaselineRow>;
var
  Line: string;
  Cells: TArray<string>;
  Row: TBaselineRow;
  First: Boolean;
begin
  Result := TDictionary<string, TBaselineRow>.Create;
  try
    First := True;
    for Line in TFile.ReadAllLines(Path, TEncoding.UTF8) do
    begin
      if First then
      begin
        First := False;
        Continue;
      end;
      Cells := Line.Split([#9]);
      if Length(Cells) < 8 then
        Continue;
      if Cells[3] = '-' then
        Row.Ndcg := NaN
      else
        Row.Ndcg := StrToFloat(Cells[3], TFormatSettings.Invariant);
      if Cells[7] = '-' then
        Row.Irrelevant := -1
      else
        Row.Irrelevant := StrToInt(Cells[7]);
      Result.AddOrSetValue(Cells[0] + #9 + Cells[1], Row);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure AddComparison(var Stats: TCompareStats; const Base: TBaselineRow; Ndcg: Double;
  Irrelevant: Integer; const Query: TEvalQuery; Changes: TStrings);
begin
  if not IsNan(Ndcg) then
  begin
    if Ndcg > Base.Ndcg + CompareTolerance then
      Inc(Stats.Better)
    else if Ndcg < Base.Ndcg - CompareTolerance then
      Inc(Stats.Worse)
    else
      Inc(Stats.Same);
    if Abs(Ndcg - Base.Ndcg) > CompareTolerance then
      Changes.Add(Invariant('  %-5s %-15s nDCG@10 %s -> %s',
        [Query.Id, Query.Kind, MetricText(Base.Ndcg), MetricText(Ndcg)]));
  end;
  if Irrelevant >= 0 then
  begin
    if Irrelevant < Base.Irrelevant then
      Inc(Stats.IrrelevantFewer)
    else if Irrelevant > Base.Irrelevant then
      Inc(Stats.IrrelevantMore)
    else
      Inc(Stats.IrrelevantSame);
    if Irrelevant <> Base.Irrelevant then
      Changes.Add(Invariant('  %-5s %-15s Irr@5 %d -> %d',
        [Query.Id, Query.Kind, Base.Irrelevant, Irrelevant]));
  end;
end;

function PerQueryNumber(Value: Double): string;
begin
  if IsNan(Value) then
    Result := '-'
  else
    Result := Invariant('%.6f', [Value]);
end;

procedure AddCompareStats(var Total: TCompareStats; const Part: TCompareStats);
begin
  Inc(Total.Better, Part.Better);
  Inc(Total.Worse, Part.Worse);
  Inc(Total.Same, Part.Same);
  Inc(Total.IrrelevantFewer, Part.IrrelevantFewer);
  Inc(Total.IrrelevantMore, Part.IrrelevantMore);
  Inc(Total.IrrelevantSame, Part.IrrelevantSame);
end;

procedure PrintComparisonRow(const Name: string; const Stats: TCompareStats);
begin
  Writeln(Invariant('%-16s %7d %7d %7d %10d %9d %9d',
    [Name, Stats.Better, Stats.Worse, Stats.Same, Stats.IrrelevantFewer, Stats.IrrelevantMore,
     Stats.IrrelevantSame]));
end;

function SeriesText(const Values: array of Double): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Values) do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + Invariant('%g', [Values[I]]);
  end;
end;

function TuningText(const Tuning: THybridSearchOptions): string;
var
  Field: TPassageField;
begin
  Result := Invariant('Tuning: RrfK=%d candidates=%d list weights (vector words trigram)=%s field weights',
    [Tuning.RrfK, Tuning.CandidatesPerList,
     SeriesText([Tuning.ListWeights[hsVector], Tuning.ListWeights[hsWords], Tuning.ListWeights[hsTrigram]])]);
  for Field := Low(TPassageField) to High(TPassageField) do
    if Tuning.FieldWeights[Field] <> 1 then
      Result := Result + Invariant(' %s=%g',
        [Copy(GetEnumName(TypeInfo(TPassageField), Ord(Field)), 3, MaxInt), Tuning.FieldWeights[Field]]);
end;

const
  ExportGroupCount = 20;

function CandidatesJson(const Query: TEvalQuery; const Groups: TArray<THybridGroup>;
  TextOfKey, ContextOfKey: TDictionary<string, string>): TJSONObject;
var
  GroupList, PassageList, TailList: TJSONArray;
  GroupJson, PassageJson: TJSONObject;
  Group: THybridGroup;
  Hit: THybridHit;
  Text, ContextText: string;
  I: Integer;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('id', Query.Id);
    Result.AddPair('text', Query.Text);
    GroupList := TJSONArray.Create;
    Result.AddPair('groups', GroupList);
    for I := 0 to Min(ExportGroupCount, Length(Groups)) - 1 do
    begin
      Group := Groups[I];
      GroupJson := TJSONObject.Create;
      GroupList.AddElement(GroupJson);
      GroupJson.AddPair('item', TJSONNumber.Create(Group.ItemId));
      GroupJson.AddPair('score', TJSONNumber.Create(Group.Score));
      PassageList := TJSONArray.Create;
      GroupJson.AddPair('passages', PassageList);
      for Hit in Group.Passages do
      begin
        if not TextOfKey.TryGetValue(Hit.Key, Text) then
          raise Exception.CreateFmt('No passage text for key %s', [Hit.Key]);
        PassageJson := TJSONObject.Create;
        PassageList.AddElement(PassageJson);
        PassageJson.AddPair('key', Hit.Key);
        PassageJson.AddPair('field', Copy(GetEnumName(TypeInfo(TPassageField), Ord(Hit.Field)), 3, MaxInt));
        PassageJson.AddPair('text', Text);
        if not ContextOfKey.TryGetValue(Hit.Key, ContextText) then
          raise Exception.CreateFmt('No passage context for key %s', [Hit.Key]);
        PassageJson.AddPair('context', ContextText);
      end;
    end;
    TailList := TJSONArray.Create;
    Result.AddPair('tail', TailList);
    for I := ExportGroupCount to High(Groups) do
      TailList.AddElement(TJSONNumber.Create(Groups[I].ItemId));
  except
    Result.Free;
    raise;
  end;
end;

procedure MeasureProjectRename(const Embedder: ITextEmbedder; Store: TSearchIndexStore;
  const Options: THarnessOptions);
var
  Corpus: TJSONObject;
  Renamed: TSearchPassages;
  Passage: TSearchPassage;
  Indexer: TSearchIndexer;
  Stats: TSyncStats;
  ProjectIds: TArray<Integer>;
  ItemCount, InProject: Integer;
begin
  Corpus := LoadJson(Options.EvalCorpus);
  try
    Renamed := LoadEvalPassages(Corpus, Options.Context, Options.RenameProject, ProjectIds, ItemCount);
  finally
    Corpus.Free;
  end;
  InProject := 0;
  for Passage in Renamed do
    if Passage.ProjectId = Options.RenameProject then
      Inc(InProject);
  Indexer := TSearchIndexer.Create(TPassageSnapshotSource.Create(Renamed), Store, Embedder);
  try
    Stats := Indexer.Sync;
  finally
    Indexer.Free;
  end;
  Writeln(Format('Rename of project %d (%d of %d passages): %d re-embedded, %d unchanged, %d added, %d removed, %d moved, %d cut, %.2f s',
    [Options.RenameProject, InProject, Length(Renamed), Stats.Changed, Stats.Unchanged, Stats.Added,
     Stats.Removed, Stats.Moved, Stats.Truncated, Stats.Elapsed]));
end;

function LoadEvalItemContexts(const Corpus: TJSONObject): TArray<TItemContextEntry>;
var
  Contexts: TDictionary<Integer, TEvalItemContext>;
  ProjectTitles: TDictionary<Integer, string>;
  Pair: TPair<Integer, TEvalItemContext>;
  Parts: TPassageContextParts;
begin
  Result := nil;
  Contexts := LoadEvalContext(Corpus);
  try
    ProjectTitles := LoadProjectTitles(Corpus);
    try
      for Pair in Contexts do
      begin
        Parts := Default(TPassageContextParts);
        Parts.ProjectTitle := ProjectTitles[Pair.Value.ProjectId];
        Parts.FolderPath := Pair.Value.FolderPath;
        Parts.ItemTitle := Pair.Value.Title;
        Parts.ItemKind := GetEnumName(TypeInfo(TItemType), Ord(Pair.Value.ItemType));
        Parts.ParentTitle := Pair.Value.ParentTitle;
        Parts.ActionType := Pair.Value.ActionType;
        Result := Result + [TItemContextEntry.Make(Pair.Key, PassageContextPartsToJson(Parts))];
      end;
    finally
      ProjectTitles.Free;
    end;
  finally
    Contexts.Free;
  end;
end;

function RerankHits(Searcher: THybridSearcher; const Encoder: ICrossEncoder; const Query: string;
  const Hits: TArray<THybridGroup>; Depth: Integer): TArray<THybridGroup>;
var
  Inputs: TArray<string>;
begin
  Inputs := Searcher.RerankInputs(Hits, Depth);
  if Length(Inputs) < 2 then
    Exit(Hits);
  Result := ApplyRerankScores(Hits, Encoder.Score(Query.Trim, Inputs, nil));
end;

procedure MeasureRerankLatency(const Options: THarnessOptions);
const
  PairCount = 20;
  Runs = 9;
  Query = 'how clean must the air of the work area be';
  ContextLine = 'Multilayer deposition > Mo/Si production runs | Item: Interface roughness after annealing | Synthesis | Magnetron sputtering | Parent: Production run';
var
  Manifest: TSearchArtifactManifest;
  Config: TCrossEncoderConfig;
  Tokenizer: TUnigramTokenizer;
  Encoder: ICrossEncoder;
  Corpus: TJSONObject;
  Item, FileEntry: TJSONValue;
  Pool: TStringBuilder;
  Words: TArray<string>;
  Passages: TArray<string>;
  Times: TArray<Double>;
  Watch: TStopwatch;
  Text: string;
  I, Run, Start, Added, TotalTokens: Integer;
  Files: TJSONArray;
begin
  Manifest := TSearchArtifactManifest.LoadFromFile(PlatformManifestPath);
  Config := TCrossEncoderConfig.FromManifest(Manifest, Options.ArtifactRoot);
  if Options.RerankBatch > 0 then
    Config.BatchSize := Options.RerankBatch;
  Config.IntraOpThreads := Options.Threads;
  Pool := TStringBuilder.Create;
  try
    Corpus := LoadJson(ResolveFixture('eval-corpus.json'));
    try
      for Item in Corpus.GetValue<TJSONArray>('items') do
      begin
        Pool.Append(Item.GetValue<string>('description')).Append(' ');
        if (Item as TJSONObject).TryGetValue<TJSONArray>('files', Files) then
          for FileEntry in Files do
            Pool.Append(FileEntry.GetValue<string>('text')).Append(' ');
      end;
    finally
      Corpus.Free;
    end;
    Words := Pool.ToString.Split([' ', #10, #13], TStringSplitOptions.ExcludeEmpty);
  finally
    Pool.Free;
  end;
  Tokenizer := TUnigramTokenizer.CreateFromFile(Config.TokenizerPath);
  try
    SetLength(Passages, PairCount);
    TotalTokens := 0;
    for I := 0 to PairCount - 1 do
    begin
      Text := ContextLine + #10;
      Start := (I * 53) mod Length(Words);
      Added := 0;
      while Length(Tokenizer.EncodePair(Query, Text, CrossEncoderMaxTokens)) < Options.RerankTokens + 8 do
      begin
        Text := Text + Words[(Start + Added) mod Length(Words)] + ' ';
        Inc(Added);
      end;
      Passages[I] := Text;
      Inc(TotalTokens, Length(Tokenizer.EncodePair(Query, Text, CrossEncoderMaxTokens)));
    end;
  finally
    Tokenizer.Free;
  end;
  Watch := TStopwatch.StartNew;
  Encoder := TCrossEncoder.Create(Config);
  Writeln(Format('Reranker load: %.0f ms; batch size %d; %d pairs of %.0f tokens on average',
    [Watch.Elapsed.TotalMilliseconds, Config.BatchSize, PairCount, TotalTokens / PairCount]));
  Writeln('Memory after load: ', MemoryText);
  Watch := TStopwatch.StartNew;
  Encoder.Score(Query, Passages, nil);
  Writeln(Format('First call: %.0f ms', [Watch.Elapsed.TotalMilliseconds]));
  for Run := 1 to Runs do
  begin
    Watch := TStopwatch.StartNew;
    Encoder.Score(Query, Passages, nil);
    Times := Times + [Watch.Elapsed.TotalMilliseconds];
  end;
  TArray.Sort<Double>(Times);
  Writeln(Format('Score of %d pairs, %d runs: median %.0f ms, min %.0f ms, max %.0f ms',
    [PairCount, Runs, Times[Runs div 2], Times[0], Times[High(Times)]]));
  Writeln('Memory after scoring: ', MemoryText);
end;

procedure RunEval(const Embedder: ITextEmbedder; const Options: THarnessOptions);
const
  Modes: array[0..4] of TEvalMode = (
    (Name: 'words'; Lists: [hsWords]),
    (Name: 'trigram'; Lists: [hsTrigram]),
    (Name: 'vector'; Lists: [hsVector]),
    (Name: 'hybrid'; Lists: [hsVector, hsWords, hsTrigram]),
    (Name: 'rerank'; Lists: [hsVector, hsWords, hsTrigram]));
var
  Corpus: TJSONObject;
  Passages: TSearchPassages;
  Queries: TArray<TEvalQuery>;
  Kinds: TArray<string>;
  Stats: TArray<TEvalStats>;
  ProjectIds: TArray<Integer>;
  Ranking: TArray<Integer>;
  Hits: TArray<THybridGroup>;
  Searcher: THybridSearcher;
  Indexer: TSearchIndexer;
  Store: TSearchIndexStore;
  SyncStats: TSyncStats;
  Watch: TStopwatch;
  StorePath, Kind: string;
  ContextText: string;
  Query: TEvalQuery;
  Counts: array[TPassageField] of Integer;
  Field: TPassageField;
  Passage: TSearchPassage;
  ItemCount, ModeIndex, KindIndex, I, Unjudged: Integer;
  LatencyMs: Double;
  SearchOptions: THybridSearchOptions;
  FullListTopK, Irrelevant: Integer;
  Ndcg: Double;
  Baseline: TDictionary<string, TBaselineRow>;
  Base: TBaselineRow;
  Compare: array of TCompareStats;
  Changes: TStringList;
  PerQuery: TStringList;
  Candidates: TJSONArray;
  TextOfKey, ContextOfKey: TDictionary<string, string>;
  SelectedModes: TArray<string>;
  FullPassages: TSearchPassages;
  FullProjectIds: TArray<Integer>;
  FullItemCount: Integer;
  Encoder: ICrossEncoder;
begin
  FullListTopK := 3 * Options.Tuning.CandidatesPerList;
  SelectedModes := Options.EvalModes.Split([',']);
  Baseline := nil;
  Changes := nil;
  PerQuery := nil;
  Candidates := nil;
  TextOfKey := nil;
  ContextOfKey := nil;
  Corpus := LoadJson(Options.EvalCorpus);
  try
    Passages := LoadEvalPassages(Corpus, Options.Context, 0, ProjectIds, ItemCount);
    ContextText := EvalContextSummary(Corpus);
  finally
    Corpus.Free;
  end;
  Queries := LoadEvalQueries(Options.EvalFile);
  Kinds := nil;
  Unjudged := 0;
  for Query in Queries do
  begin
    if TArray.IndexOf<string>(Kinds, Query.Kind) < 0 then
      Kinds := Kinds + [Query.Kind];
    if Length(Query.Relevant) = 0 then
      Inc(Unjudged);
  end;

  StorePath := TPath.Combine(TPath.GetTempPath, TGUID.NewGuid.ToString + '.search.sqlite');
  try
    Store := TSearchIndexStore.Open(StorePath, Embedder.Identity, Embedder.Dimension);
    try
      Indexer := TSearchIndexer.Create(TPassageSnapshotSource.Create(Passages), Store, Embedder);
      try
        Watch := TStopwatch.StartNew;
        SyncStats := Indexer.Sync;
        Writeln(Format('Evaluation corpus %s: %d items in %d projects, %d passages embedded in %.1f s',
          [ExtractFileName(Options.EvalCorpus), ItemCount, Length(ProjectIds),
           SyncStats.Added, Watch.Elapsed.TotalSeconds]));
        Writeln(Format('Passage context: %s; %d of %d passages were cut at %d tokens',
          [LowerCase(Copy(GetEnumName(TypeInfo(TPassageContextMode), Ord(Options.Context)), 4, MaxInt)),
           SyncStats.Truncated,
           SyncStats.Added, E5MaxTokens]));
      finally
        Indexer.Free;
      end;
      for Field := Low(TPassageField) to High(TPassageField) do
        Counts[Field] := 0;
      for Passage in Passages do
        Inc(Counts[Passage.Field]);
      for Field := Low(TPassageField) to High(TPassageField) do
        if Counts[Field] > 0 then
          Writeln(Format('  %-20s %d', [GetEnumName(TypeInfo(TPassageField), Ord(Field)), Counts[Field]]));
      if ContextText <> '' then
        Writeln(ContextText);
      Writeln(Format('Query file %s: %d queries, %d without a relevant item (excluded from the means)',
        [ExtractFileName(Options.EvalFile), Length(Queries), Unjudged]));
      Writeln(Format('Each search returns up to %d item groups; the item rank is the position of its group.',
        [FullListTopK]));
      Writeln(TuningText(Options.Tuning));

      Searcher := THybridSearcher.Create(Store, Embedder, TEvalSource.Create(Passages));
      try
        if Options.ComparePath <> '' then
          Baseline := LoadBaseline(Options.ComparePath);
        Changes := TStringList.Create;
        PerQuery := TStringList.Create;
        Searcher.Search(Queries[0].Text, ProjectIds, FullListTopK, Options.Tuning);
        PerQuery.Add('mode'#9'id'#9'kind'#9'ndcg10'#9'recall10'#9'recall5'#9'mrr'#9'irr5');
        if Options.ExportCandidatesFile <> '' then
        begin
          Candidates := TJSONArray.Create;
          TextOfKey := TDictionary<string, string>.Create;
          ContextOfKey := TDictionary<string, string>.Create;
          for Passage in Passages do
            TextOfKey.Add(Passage.Key, Passage.Text);
          Corpus := LoadJson(Options.EvalCorpus);
          try
            FullPassages := LoadEvalPassages(Corpus, pcmFull, 0, FullProjectIds, FullItemCount);
          finally
            Corpus.Free;
          end;
          for Passage in FullPassages do
            ContextOfKey.Add(Passage.Key, Passage.Context);
        end;
        Encoder := nil;
        if TArray.IndexOf<string>(SelectedModes, 'rerank') >= 0 then
        begin
          Corpus := LoadJson(Options.EvalCorpus);
          try
            Store.ReplaceItemContexts(LoadEvalItemContexts(Corpus));
          finally
            Corpus.Free;
          end;
          Encoder := CreateCrossEncoder(Options.ArtifactRoot,
            TSearchArtifactManifest.LoadFromFile(PlatformManifestPath));
          Writeln('Reranker: ', Encoder.Identity);
          Writeln(Format('Rerank depth %d; the input of a group is its context line, a line feed and its first passage',
            [Options.Tuning.RerankDepth]));
        end;
        for ModeIndex := 0 to High(Modes) do
        begin
          if (Options.EvalModes <> '') and (TArray.IndexOf<string>(SelectedModes, Modes[ModeIndex].Name) < 0) then
            Continue;
          if (Options.EvalModes = '') and (Modes[ModeIndex].Name = 'rerank') then
            Continue;
          SetLength(Stats, Length(Kinds) + 1);
          for I := 0 to High(Stats) do
            Stats[I] := Default(TEvalStats);
          SetLength(Compare, Length(Kinds) + 1);
          for I := 0 to High(Compare) do
            Compare[I] := Default(TCompareStats);
          Changes.Clear;
          SearchOptions := Options.Tuning;
          SearchOptions.Lists := Modes[ModeIndex].Lists;
          for Query in Queries do
          begin
            Watch := TStopwatch.StartNew;
            Hits := Searcher.Search(Query.Text, ProjectIds, FullListTopK, SearchOptions);
            if Modes[ModeIndex].Name = 'rerank' then
              Hits := RerankHits(Searcher, Encoder, Query.Text, Hits, SearchOptions.RerankDepth);
            LatencyMs := Watch.Elapsed.TotalMilliseconds;
            Ranking := ItemRanking(Hits);
            KindIndex := TArray.IndexOf<string>(Kinds, Query.Kind);
            AddEvalResult(Stats[KindIndex], Query, Ranking, LatencyMs);
            AddEvalResult(Stats[High(Stats)], Query, Ranking, LatencyMs);
            Ndcg := NdcgAtK(Ranking, Query.Relevant, 10);
            if (Candidates <> nil) and (Modes[ModeIndex].Name = 'hybrid') then
              Candidates.AddElement(CandidatesJson(Query, Hits, TextOfKey, ContextOfKey));
            Irrelevant := -1;
            if Length(Query.Irrelevant) > 0 then
              Irrelevant := CountAtK(Ranking, Query.Irrelevant, 5);
            PerQuery.Add(Invariant('%s'#9'%s'#9'%s'#9'%s'#9'%s'#9'%s'#9'%s'#9'%s',
              [Modes[ModeIndex].Name, Query.Id, Query.Kind, PerQueryNumber(Ndcg),
               PerQueryNumber(RecallAtK(Ranking, Query.Relevant, 10)),
               PerQueryNumber(RecallAtK(Ranking, Query.Relevant, 5)),
               PerQueryNumber(ReciprocalRank(Ranking, Query.Relevant)),
               IfThen(Irrelevant >= 0, IntToStr(Irrelevant), '-')]));
            if Baseline <> nil then
            begin
              if not Baseline.TryGetValue(Modes[ModeIndex].Name + #9 + Query.Id, Base) then
                raise Exception.CreateFmt('Compare file has no row for %s %s', [Modes[ModeIndex].Name, Query.Id]);
              AddComparison(Compare[KindIndex], Base, Ndcg, Irrelevant, Query, Changes);
            end;
          end;
          if Baseline <> nil then
            for KindIndex := 0 to High(Kinds) do
              AddCompareStats(Compare[High(Compare)], Compare[KindIndex]);
          Writeln;
          Writeln('Mode: ', Modes[ModeIndex].Name);
          Writeln(Invariant('%-16s %7s %6s %7s %7s %7s %8s %6s %8s %8s',
            ['kind', 'queries', 'judged', 'R@5', 'R@10', 'MRR', 'nDCG@10', 'Irr@5', 'mean ms', 'p95 ms']));
          for KindIndex := 0 to High(Kinds) do
            PrintEvalRow(Kinds[KindIndex], Stats[KindIndex]);
          PrintEvalRow('all', Stats[High(Stats)]);
          if Baseline <> nil then
          begin
            Writeln;
            Writeln('Compared with ', ExtractFileName(Options.ComparePath),
              ' (nDCG@10 of each judged query; Irr@5 of each hard-negative query)');
            Writeln(Invariant('%-16s %7s %7s %7s %10s %9s %9s',
              ['kind', 'better', 'worse', 'same', 'irr fewer', 'irr more', 'irr same']));
            for KindIndex := 0 to High(Kinds) do
              PrintComparisonRow(Kinds[KindIndex], Compare[KindIndex]);
            PrintComparisonRow('all', Compare[High(Compare)]);
            if Changes.Count > 0 then
            begin
              Writeln('Changed queries:');
              for Kind in Changes do
                Writeln(Kind);
            end;
          end;
        end;
        if Options.PerQueryFile <> '' then
          PerQuery.SaveToFile(Options.PerQueryFile, TEncoding.UTF8);
        if Candidates <> nil then
        begin
          Corpus := TJSONObject.Create;
          try
            Corpus.AddPair('queries', Candidates);
            Candidates := nil;
            TFile.WriteAllBytes(Options.ExportCandidatesFile, TEncoding.UTF8.GetBytes(Corpus.ToJSON));
          finally
            Corpus.Free;
          end;
        end;
      finally
        Baseline.Free;
        PerQuery.Free;
        Candidates.Free;
        TextOfKey.Free;
        ContextOfKey.Free;
        Changes.Free;
        Searcher.Free;
      end;
      if Options.RenameProject <> 0 then
        MeasureProjectRename(Embedder, Store, Options);
    finally
      Store.Free;
    end;
  finally
    for Kind in ['', '-wal', '-shm'] do
      if TFile.Exists(StorePath + Kind) then
        TFile.Delete(StorePath + Kind);
  end;
end;

procedure InstallArtifacts(const Root: string);
var
  ManifestPath: string;
  Manifest: TSearchArtifactManifest;
  Check: TArtifactCheck;
  Reported: Int64;
  Watch: TStopwatch;
begin
  ManifestPath := PlatformManifestPath;
  Manifest := TSearchArtifactManifest.LoadFromFile(ManifestPath);
  Writeln(Format('Install %s into %s (%d bytes)', [ManifestPath, Root, Manifest.TotalDownloadBytes]));
  Reported := -1;
  Watch := TStopwatch.StartNew;
  InstallSearchArtifacts(Manifest, Root, THttpArtifactFetcher.Create,
    procedure(DoneBytes, TotalBytes: Int64; const CurrentFile: string)
    begin
      if (Reported < 0) or (DoneBytes - Reported >= 100 * 1048576) or (DoneBytes = TotalBytes) then
      begin
        Writeln(Format('  %d of %d MB %s', [DoneBytes div 1048576, TotalBytes div 1048576, CurrentFile]));
        Reported := DoneBytes;
      end;
    end, nil);
  Check := CheckSearchArtifacts(Manifest, Root, True);
  if Check.State <> asReady then
    raise Exception.Create('Installed artifacts are not ready: ' + Check.FirstProblem);
  Writeln(Format('Installed and verified (size and SHA-256 of every file) in %.0f s', [Watch.Elapsed.TotalSeconds]));
end;

procedure Run;
var
  Options: THarnessOptions;
  Config: TE5EmbedderConfig;
  Embedder: ITextEmbedder;
  Corpus: TJSONObject;
  Docs: TArray<TCorpusDocument>;
  Texts, AllScopes: TArray<string>;
  Embeddings: TArray<TEmbedding>;
  Index: TExactVectorIndex;
  ScopeSet: TDictionary<string, Boolean>;
  Watch: TStopwatch;
  I, Copies, Tokens: Integer;
  Bench: TArray<string>;
begin
  Options := ParseOptions;
  Writeln('Machine: ', CpuName, ', ', TThread.ProcessorCount, ' logical processors');
  if Options.Fts5 then
  begin
    ProbeFts5(Options.SQLiteLibrary);
    Exit;
  end;
  if Options.InstallRoot <> '' then
  begin
    InstallArtifacts(Options.InstallRoot);
    Exit;
  end;
  if Options.RerankLatency then
  begin
    MeasureRerankLatency(Options);
    Exit;
  end;

  Config := TE5EmbedderConfig.FromArtifactRoot(Options.ArtifactRoot);
  Config.BatchSize := Options.BatchSize;
  Config.IntraOpThreads := Options.Threads;
  Writeln('Memory before load: ', MemoryText);
  Watch := TStopwatch.StartNew;
  Embedder := TE5TextEmbedder.Create(Config);
  Writeln(Format('Model load: %.0f ms (tokenizer + ONNX session), ONNX Runtime %s',
    [Watch.Elapsed.TotalMilliseconds, TE5TextEmbedder(Embedder).RuntimeVersion]));
  Writeln('Embedder identity: ', Embedder.Identity);
  Writeln('Memory after load: ', MemoryText);

  if Options.Notebook <> '' then
  begin
{$IFDEF MSWINDOWS}
    RunNotebook(Embedder, Options);
    Exit;
{$ELSE}
    raise EArgumentException.Create('--notebook needs the local notebook storage, which is Windows only');
{$ENDIF}
  end;
  if Options.EvalFile <> '' then
  begin
    RunEval(Embedder, Options);
    Exit;
  end;

  if Options.VerifyReference then
    VerifyReference(Embedder, Config.ModelDirectory);

  Corpus := LoadJson(Options.CorpusPath);
  ScopeSet := TDictionary<string, Boolean>.Create;
  Index := TExactVectorIndex.Create(Embedder.Dimension);
  try
    Docs := LoadDocuments(Corpus);
    SetLength(Texts, Length(Docs));
    for I := 0 to High(Docs) do
    begin
      Texts[I] := Docs[I].Text;
      ScopeSet.AddOrSetValue(Docs[I].Scope, True);
    end;
    AllScopes := ScopeSet.Keys.ToArray;
    TArray.Sort<string>(AllScopes);

    Watch := TStopwatch.StartNew;
    Embeddings := Embedder.EncodePassages(Texts, olReject);
    Tokens := 0;
    for I := 0 to High(Embeddings) do
    begin
      Index.Add(Docs[I].Id, Docs[I].Scope, I + 1, Embeddings[I].Vector);
      Inc(Tokens, Embeddings[I].TokenCount);
    end;
    Writeln(Format('Indexed %d passages (%d tokens, batch %d) in %.0f ms: %.1f passages/s',
      [Length(Docs), Tokens, Options.BatchSize, Watch.Elapsed.TotalMilliseconds,
       Length(Docs) / Watch.Elapsed.TotalSeconds]));
    Writeln('Memory after indexing: ', MemoryText);

    if Options.BenchCopies > 0 then
    begin
      Bench := nil;
      for Copies := 1 to Options.BenchCopies do
        Bench := Bench + Texts;
      Watch := TStopwatch.StartNew;
      Embeddings := Embedder.EncodePassages(Bench, olReject);
      Writeln(Format('Bench: %d passages in %.0f ms: %.1f passages/s (batch %d)',
        [Length(Bench), Watch.Elapsed.TotalMilliseconds, Length(Bench) / Watch.Elapsed.TotalSeconds,
         Options.BatchSize]));
      Writeln('Memory after bench: ', MemoryText);
    end;

    RunQueries(Embedder, Index, Docs, Corpus, Options, AllScopes);
  finally
    Index.Free;
    ScopeSet.Free;
    Corpus.Free;
  end;
end;

begin
{$IFDEF MSWINDOWS}
  SetConsoleOutputCP(CP_UTF8);
{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
