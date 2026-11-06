unit unit_SeriesTable;

interface

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  Aurelius.Types.Nullable,
  unit_ItemTypes, unit_SeriesColumn, unit_SeriesSlot;

const
  SERIES_ROOT_KEY = 'root';

type
  TSeriesHit = record
    RootItemId, ItemId, ValueId, ValueTypeId: Integer;
    RecType: TRecType;
    Value, Tol: Double;
    SourceKey: string;
    Planned: Boolean;
  end;

  TSeriesValueTypeInfo = record
    Id: Integer;
    Title, Units: string;
  end;

  TSeriesSourceInfo = record
    Key, Caption: string;
  end;

  TSeriesPlannedLevel = record
    ValueTypeId: Integer;
    Value: Double;
  end;

  TSeriesRowState = (srsPlanned, srsDeposited, srsMeasured, srsFailed);

  TSeriesRowInput = record
    MemberId, ItemId, SlotId: Integer;
    Title: string;
    Failed, HasMember: Boolean;
    Origin: TSeriesSlotOrigin;
    Levels: TArray<TSeriesPlannedLevel>;
  end;

  TSeriesColumnPref = record
    RecType: TRecType;
    ValueTypeId: Integer;
    SourceKey: string;
    Role: TSeriesColumnRole;
    SortOrder: Integer;
    EntryLabel: string;
  end;

  TSeriesFactorSpec = record
    ValueTypeId: Integer;
    RangeMin, RangeMax: Nullable<Double>;
    EntryLabel: string;
  end;

  TSeriesFixedSpec = record
    ValueTypeId: Integer;
    Value, Tol: Double;
    EntryLabel: string;
  end;

  TSeriesResponseSpec = record
    ValueTypeId: Integer;
    EntryLabel: string;
  end;

  TSeriesPlan = record
    Factors: TArray<TSeriesFactorSpec>;
    Fixed: TArray<TSeriesFixedSpec>;
    Responses: TArray<TSeriesResponseSpec>;
    TargetFolderId: Integer;
  end;

  TSeriesPoint = TArray<Double>;

  TSeriesTableColumn = record
    RecType: TRecType;
    ValueTypeId: Integer;
    SourceKey: string;
    Caption, Units: string;
    Role: TSeriesColumnRole;
  end;

  TSeriesCell = record
    Hits: TArray<TSeriesHit>;
    HasPlanned, Deviation: Boolean;
    PlannedValue: Double;
    function IsMissing: Boolean;
    function IsAmbiguous: Boolean;
  end;

  TSeriesTableRow = record
    MemberId, ItemId, SlotId: Integer;
    Title: string;
    Failed: Boolean;
    Origin: TSeriesSlotOrigin;
    State: TSeriesRowState;
    Cells: TArray<TSeriesCell>;
  end;

  TSeriesTable = record
    Columns: TArray<TSeriesTableColumn>;
    Rows: TArray<TSeriesTableRow>;
    Excluded: TArray<Integer>;
    function ColumnIndex(ARecType: TRecType; AValueTypeId: Integer;
      const ASourceKey: string): Integer;
  end;

function SeriesActionTypeKey(AActionTypeId: Integer): string;
function SeriesLevelKey(ALevel: TItemLevel): string;
function SeriesEntryCaption(const ATitle, AEntryLabel: string): string;
function BuildSeriesTable(const ARows: TArray<TSeriesRowInput>;
  const AHits: TArray<TSeriesHit>; const ATypes: TArray<TSeriesValueTypeInfo>;
  const ASources: TArray<TSeriesSourceInfo>; const APrefs: TArray<TSeriesColumnPref>;
  const AFixed: TArray<TSeriesFixedSpec>; AIncludeFailed: Boolean): TSeriesTable;

implementation

function SeriesActionTypeKey(AActionTypeId: Integer): string;
begin
  Result := 'at:' + IntToStr(AActionTypeId);
end;

function SeriesLevelKey(ALevel: TItemLevel): string;
begin
  Result := 'lvl:' + IntToStr(Ord(ALevel));
end;

function SeriesEntryCaption(const ATitle, AEntryLabel: string): string;
begin
  if AEntryLabel = '' then
    Result := ATitle
  else
    Result := ATitle + ' (' + AEntryLabel + ')';
end;

function TSeriesCell.IsMissing: Boolean;
begin
  Result := Length(Hits) = 0;
end;

function TSeriesCell.IsAmbiguous: Boolean;
begin
  Result := Length(Hits) > 1;
end;

function TSeriesTable.ColumnIndex(ARecType: TRecType; AValueTypeId: Integer;
  const ASourceKey: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Columns) do
    if (Columns[I].RecType = ARecType) and (Columns[I].ValueTypeId = AValueTypeId)
      and (Columns[I].SourceKey = ASourceKey) then
      Exit(I);
  Result := -1;
end;

function FindPref(const APrefs: TArray<TSeriesColumnPref>;
  const AColumn: TSeriesTableColumn; out APref: TSeriesColumnPref): Boolean;
var
  P: TSeriesColumnPref;
begin
  for P in APrefs do
    if (P.RecType = AColumn.RecType) and (P.ValueTypeId = AColumn.ValueTypeId)
      and (P.SourceKey = AColumn.SourceKey) then
    begin
      APref := P;
      Exit(True);
    end;
  Result := False;
end;

function PlanEntryLabel(const APrefs: TArray<TSeriesColumnPref>;
  ARecType: TRecType; AValueTypeId: Integer): string;
var
  P: TSeriesColumnPref;
begin
  for P in APrefs do
    if (P.RecType = ARecType) and (P.ValueTypeId = AValueTypeId)
      and (P.SourceKey = '') and (P.EntryLabel <> '') then
      Exit(P.EntryLabel);
  Result := '';
end;

function SourceCaption(const AKey: string;
  const ASources: TArray<TSeriesSourceInfo>): string;
var
  S: TSeriesSourceInfo;
begin
  if AKey = SERIES_ROOT_KEY then
    Exit('deposition');
  for S in ASources do
    if S.Key = AKey then
      Exit(S.Caption);
  Result := AKey;
end;

function BuildSeriesTable(const ARows: TArray<TSeriesRowInput>;
  const AHits: TArray<TSeriesHit>; const ATypes: TArray<TSeriesValueTypeInfo>;
  const ASources: TArray<TSeriesSourceInfo>; const APrefs: TArray<TSeriesColumnPref>;
  const AFixed: TArray<TSeriesFixedSpec>; AIncludeFailed: Boolean): TSeriesTable;
var
  Included: TList<TSeriesRowInput>;
  Cols: TList<TSeriesTableColumn>;
  Row: TSeriesRowInput;
  H: TSeriesHit;
  Pref: TSeriesColumnPref;
  Keys: TDictionary<string, Boolean>;
  FirstSource: TDictionary<string, string>;
  Split: TDictionary<string, Boolean>;
  TypeIdx: TDictionary<Integer, Integer>;
  IncludedIds: TDictionary<Integer, Boolean>;
  ByRoot: TDictionary<Integer, TList<Integer>>;
  ColIdx: TDictionary<string, Integer>;
  CellHits: TArray<TList<TSeriesHit>>;
  RootHits: TList<Integer>;
  K, RK, Stored: string;
  I, J, Idx, HI: Integer;
  Lv: TSeriesPlannedLevel;
  X: TSeriesFixedSpec;

  function KeyOf(ARec: TRecType; AVt: Integer): string;
  begin
    Result := IntToStr(Ord(ARec)) + '|' + IntToStr(AVt);
  end;

  procedure AddColumn(ARec: TRecType; AVt: Integer; const ASource: string);
  var
    C: TSeriesTableColumn;
    TI: Integer;
  begin
    TI := TypeIdx[AVt];
    C.RecType := ARec;
    C.ValueTypeId := AVt;
    C.SourceKey := ASource;
    C.Caption := SeriesEntryCaption(ATypes[TI].Title,
      PlanEntryLabel(APrefs, ARec, AVt));
    if ASource <> '' then
      C.Caption := C.Caption + ' [' + SourceCaption(ASource, ASources) + ']';
    C.Units := ATypes[TI].Units;
    if FindPref(APrefs, C, Pref) then
      C.Role := Pref.Role
    else
      C.Role := scrShown;
    Cols.Add(C);
  end;

  function Differs(APlan, APlanTol: Double; const AHit: TSeriesHit): Boolean;
  var
    Tol: Double;
  begin
    Tol := APlanTol;
    if Tol <= 0 then
      Tol := AHit.Tol;
    if Tol < 0 then
      Tol := 0;
    Result := Abs(AHit.Value - APlan) > Tol;
  end;

  function RowMeasured(AHitIdx: TList<Integer>): Boolean;
  var
    P: TSeriesColumnPref;
    Q: Integer;
    Found: Boolean;
  begin
    for P in APrefs do
    begin
      if P.Role <> scrResponse then
        Continue;
      Found := False;
      if AHitIdx <> nil then
        for Q in AHitIdx do
          if not AHits[Q].Planned and (AHits[Q].RecType = P.RecType)
            and (AHits[Q].ValueTypeId = P.ValueTypeId)
            and ((P.SourceKey = '') or (AHits[Q].SourceKey = P.SourceKey)) then
          begin
            Found := True;
            Break;
          end;
      if not Found then
        Exit(False);
    end;
    Result := True;
  end;

begin
  Included := TList<TSeriesRowInput>.Create;
  Cols := TList<TSeriesTableColumn>.Create;
  Keys := TDictionary<string, Boolean>.Create;
  FirstSource := TDictionary<string, string>.Create;
  Split := TDictionary<string, Boolean>.Create;
  TypeIdx := TDictionary<Integer, Integer>.Create;
  IncludedIds := TDictionary<Integer, Boolean>.Create;
  ByRoot := TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
  ColIdx := TDictionary<string, Integer>.Create;
  try
    for I := 0 to High(ATypes) do
      TypeIdx.AddOrSetValue(ATypes[I].Id, I);
    for Row in ARows do
      if AIncludeFailed or not Row.Failed then
      begin
        Included.Add(Row);
        if Row.HasMember then
          IncludedIds.AddOrSetValue(Row.ItemId, True);
      end;
    Included.Sort(TComparer<TSeriesRowInput>.Construct(
      function(const A, B: TSeriesRowInput): Integer
      var
        N, Q: Integer;
      begin
        N := Length(A.Levels);
        if Length(B.Levels) < N then
          N := Length(B.Levels);
        for Q := 0 to N - 1 do
          if A.Levels[Q].Value <> B.Levels[Q].Value then
          begin
            if A.Levels[Q].Value < B.Levels[Q].Value then
              Exit(-1);
            Exit(1);
          end;
        Result := A.SlotId - B.SlotId;
        if Result = 0 then
          Result := Ord(A.Failed) - Ord(B.Failed);
        if Result = 0 then
          Result := A.MemberId - B.MemberId;
      end));

    for HI := 0 to High(AHits) do
    begin
      H := AHits[HI];
      if not TypeIdx.ContainsKey(H.ValueTypeId) or not IncludedIds.ContainsKey(H.RootItemId) then
        Continue;
      if not ByRoot.TryGetValue(H.RootItemId, RootHits) then
      begin
        RootHits := TList<Integer>.Create;
        ByRoot.Add(H.RootItemId, RootHits);
      end;
      RootHits.Add(HI);
      K := KeyOf(H.RecType, H.ValueTypeId);
      if FirstSource.TryGetValue(K, Stored) then
      begin
        if Stored <> H.SourceKey then
          Split.AddOrSetValue(K, True);
      end
      else
        FirstSource.Add(K, H.SourceKey);
    end;

    for HI := 0 to High(AHits) do
    begin
      H := AHits[HI];
      if not TypeIdx.ContainsKey(H.ValueTypeId) or not IncludedIds.ContainsKey(H.RootItemId) then
        Continue;
      K := KeyOf(H.RecType, H.ValueTypeId);
      if Split.ContainsKey(K) then
        RK := K + '|' + H.SourceKey
      else
        RK := K + '|';
      if not Keys.ContainsKey(RK) then
      begin
        Keys.Add(RK, True);
        if Split.ContainsKey(K) then
          AddColumn(H.RecType, H.ValueTypeId, H.SourceKey)
        else
          AddColumn(H.RecType, H.ValueTypeId, '');
      end;
    end;

    for Pref in APrefs do
      if (Pref.Role in [scrVaried, scrFixed, scrResponse]) and (Pref.SourceKey = '')
        and TypeIdx.ContainsKey(Pref.ValueTypeId) then
      begin
        K := KeyOf(Pref.RecType, Pref.ValueTypeId);
        RK := K + '|';
        if not Split.ContainsKey(K) and not Keys.ContainsKey(RK) then
        begin
          Keys.Add(RK, True);
          AddColumn(Pref.RecType, Pref.ValueTypeId, '');
        end;
      end;

    Result.Columns := Cols.ToArray;
    TArray.Sort<TSeriesTableColumn>(Result.Columns,
      TComparer<TSeriesTableColumn>.Construct(
        function(const A, B: TSeriesTableColumn): Integer
        var
          PA, PB: TSeriesColumnPref;
          OA, OB: Integer;
        begin
          Result := Ord(A.RecType) - Ord(B.RecType);
          if Result <> 0 then
            Exit;
          if FindPref(APrefs, A, PA) then OA := PA.SortOrder else OA := MaxInt;
          if FindPref(APrefs, B, PB) then OB := PB.SortOrder else OB := MaxInt;
          if OA <> OB then
          begin
            if OA < OB then Result := -1 else Result := 1;
            Exit;
          end;
          Result := CompareStr(A.Caption, B.Caption);
        end));

    for Idx := 0 to High(Result.Columns) do
      ColIdx.Add(KeyOf(Result.Columns[Idx].RecType, Result.Columns[Idx].ValueTypeId)
        + '|' + Result.Columns[Idx].SourceKey, Idx);

    SetLength(Result.Rows, Included.Count);
    SetLength(CellHits, Length(Result.Columns));
    for I := 0 to High(CellHits) do
      CellHits[I] := TList<TSeriesHit>.Create;
    try
      for I := 0 to Included.Count - 1 do
      begin
        Result.Rows[I].MemberId := Included[I].MemberId;
        Result.Rows[I].ItemId := Included[I].ItemId;
        Result.Rows[I].SlotId := Included[I].SlotId;
        Result.Rows[I].Title := Included[I].Title;
        Result.Rows[I].Failed := Included[I].Failed;
        Result.Rows[I].Origin := Included[I].Origin;
        SetLength(Result.Rows[I].Cells, Length(Result.Columns));
        for J := 0 to High(CellHits) do
          CellHits[J].Clear;
        if not Included[I].HasMember then
          RootHits := nil
        else if not ByRoot.TryGetValue(Included[I].ItemId, RootHits) then
          RootHits := nil;
        if RootHits <> nil then
          for HI in RootHits do
          begin
            H := AHits[HI];
            K := KeyOf(H.RecType, H.ValueTypeId);
            if Split.ContainsKey(K) then
              RK := K + '|' + H.SourceKey
            else
              RK := K + '|';
            CellHits[ColIdx[RK]].Add(H);
          end;
        for J := 0 to High(CellHits) do
        begin
          Result.Rows[I].Cells[J].Hits := CellHits[J].ToArray;
          if Result.Columns[J].RecType <> TRecType.EXP_CONDITION then
            Continue;
          for Lv in Included[I].Levels do
            if Lv.ValueTypeId = Result.Columns[J].ValueTypeId then
            begin
              if Length(Result.Rows[I].Cells[J].Hits) = 0 then
              begin
                Result.Rows[I].Cells[J].HasPlanned := True;
                Result.Rows[I].Cells[J].PlannedValue := Lv.Value;
              end
              else
                for H in Result.Rows[I].Cells[J].Hits do
                  if not H.Planned and Differs(Lv.Value, 0, H) then
                    Result.Rows[I].Cells[J].Deviation := True;
            end;
          for X in AFixed do
            if X.ValueTypeId = Result.Columns[J].ValueTypeId then
              for H in Result.Rows[I].Cells[J].Hits do
                if not H.Planned and Differs(X.Value, X.Tol, H) then
                  Result.Rows[I].Cells[J].Deviation := True;
        end;

        if not Included[I].HasMember then
          Result.Rows[I].State := srsPlanned
        else if Included[I].Failed then
          Result.Rows[I].State := srsFailed
        else if RowMeasured(RootHits) then
          Result.Rows[I].State := srsMeasured
        else
          Result.Rows[I].State := srsDeposited;
      end;
    finally
      for J := 0 to High(CellHits) do
        CellHits[J].Free;
    end;
    Result.Excluded := nil;
  finally
    ColIdx.Free;
    ByRoot.Free;
    IncludedIds.Free;
    TypeIdx.Free;
    Split.Free;
    FirstSource.Free;
    Keys.Free;
    Cols.Free;
    Included.Free;
  end;
end;

end.
