unit unit_MainThreadSearchSource;

interface

uses
  System.SysUtils, System.Classes, unit_SearchPassages, unit_TextEmbedder, unit_VectorSearch,
  unit_SemanticSearchApi, unit_LocalSemanticSearch;

type
  { The Aurelius manager of the host belongs to the main thread. The search
    runs on a worker thread, so every call of the inner source is moved to the
    main thread. }
  TMainThreadSearchSource = class(TInterfacedObject, ISearchDocumentSource)
  private
    FInner: ISearchDocumentSource;
  public
    constructor Create(const Inner: ISearchDocumentSource);
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

function MainThreadFilterResolver(const Inner: TSemanticFilterResolver): TSemanticFilterResolver;

function MainThreadLimitDescriber(const Inner: TValueLimitDescriber): TValueLimitDescriber;

implementation

constructor TMainThreadSearchSource.Create(const Inner: ISearchDocumentSource);
begin
  inherited Create;
  if Inner = nil then
    raise EArgumentNilException.Create('The inner document source is required');
  FInner := Inner;
end;

function TMainThreadSearchSource.ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
var
  Snapshot: TSearchSnapshot;
begin
  if TThread.CurrentThread.ThreadID = MainThreadID then
    Exit(FInner.ReadSnapshot(Cancelled));
  Snapshot := Default(TSearchSnapshot);
  TThread.Synchronize(nil,
    procedure
    begin
      Snapshot := FInner.ReadSnapshot(Cancelled);
    end);
  Result := Snapshot;
end;

function TMainThreadSearchSource.IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
var
  Live: Boolean;
  Project: Integer;
begin
  if TThread.CurrentThread.ThreadID = MainThreadID then
    Exit(FInner.IsItemLive(ItemId, ProjectId));
  Live := False;
  Project := 0;
  TThread.Synchronize(nil,
    procedure
    begin
      Live := FInner.IsItemLive(ItemId, Project);
    end);
  ProjectId := Project;
  Result := Live;
end;

function MainThreadFilterResolver(const Inner: TSemanticFilterResolver): TSemanticFilterResolver;
begin
  if not Assigned(Inner) then
    raise EArgumentNilException.Create('The inner filter resolver is required');
  Result :=
    function(Filter: TSemanticSearchFilter; VisibleProjectIds: TArray<Integer>): TItemFilter
    var
      Resolved: TItemFilter;
    begin
      if TThread.CurrentThread.ThreadID = MainThreadID then
        Exit(Inner(Filter, VisibleProjectIds));
      TThread.Synchronize(nil,
        procedure
        begin
          Resolved := Inner(Filter, VisibleProjectIds);
        end);
      Result := Resolved;
    end;
end;

function MainThreadLimitDescriber(const Inner: TValueLimitDescriber): TValueLimitDescriber;
begin
  if not Assigned(Inner) then
    raise EArgumentNilException.Create('The inner limit describer is required');
  Result :=
    function(Constraints: TArray<TValueConstraint>): TArray<TAppliedLimit>
    var
      Described: TArray<TAppliedLimit>;
    begin
      if TThread.CurrentThread.ThreadID = MainThreadID then
        Exit(Inner(Constraints));
      TThread.Synchronize(nil,
        procedure
        begin
          Described := Inner(Constraints);
        end);
      Result := Described;
    end;
end;

end.
