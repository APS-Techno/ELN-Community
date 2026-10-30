unit unit_LocalSemanticSearch;

interface

uses
  System.SysUtils, unit_TextEmbedder, unit_VectorSearch, unit_SemanticSearchApi,
  unit_SemanticSearchService;

type
  TSemanticFilterResolver = TFunc<TSemanticSearchFilter, TArray<Integer>, TItemFilter>;

  TValueLimitDescriber = TFunc<TArray<TValueConstraint>, TArray<TAppliedLimit>>;

  TLocalSemanticSearch = class(TInterfacedObject, ISemanticSearch)
  private
    FService: TSemanticSearchService;
    FResolveFilter: TSemanticFilterResolver;
    FDescribeLimits: TValueLimitDescriber;
    function FiltersAppliedJson(const Filter: TSemanticSearchFilter): string;
  public
    constructor Create(Service: TSemanticSearchService;
      const ResolveFilter: TSemanticFilterResolver; const DescribeLimits: TValueLimitDescriber);
    function Search(const Request: TSemanticSearchRequest;
      const Cancelled: TCancelCheck): TSemanticSearchResult;
    function Status: TSemanticSearchStatus;
    function RerankerAvailable: Boolean;
    function IsRemote: Boolean;
  end;

implementation

uses
  System.JSON, unit_HybridSearch;

constructor TLocalSemanticSearch.Create(Service: TSemanticSearchService;
  const ResolveFilter: TSemanticFilterResolver; const DescribeLimits: TValueLimitDescriber);
begin
  inherited Create;
  if (Service = nil) or not Assigned(ResolveFilter) or not Assigned(DescribeLimits) then
    raise EArgumentNilException.Create('The service, the filter resolver and the limit describer are required');
  FService := Service;
  FResolveFilter := ResolveFilter;
  FDescribeLimits := DescribeLimits;
end;

function TLocalSemanticSearch.FiltersAppliedJson(const Filter: TSemanticSearchFilter): string;
const
  DateFieldNames: array[TSemanticDateField] of string = ('', 'created', 'modified');
var
  Echo, Entry: TJSONObject;
  Names, Entries: TJSONArray;
  Limit: TAppliedLimit;
  Name: string;
begin
  Echo := TJSONObject.Create;
  try
    if Filter.FolderId > 0 then
      Echo.AddPair('folder_id', TJSONNumber.Create(Filter.FolderId));
    if Length(Filter.ItemTypes) > 0 then
    begin
      Names := TJSONArray.Create;
      Echo.AddPair('item_types', Names);
      for Name in Filter.ItemTypes do
        Names.Add(Trim(Name));
    end;
    if Length(Filter.Levels) > 0 then
    begin
      Names := TJSONArray.Create;
      Echo.AddPair('levels', Names);
      for Name in Filter.Levels do
        Names.Add(Trim(Name));
    end;
    if Filter.ActionTypeId > 0 then
      Echo.AddPair('action_type_id', TJSONNumber.Create(Filter.ActionTypeId));
    if Filter.DateField <> sdfNone then
    begin
      Echo.AddPair('date_field', DateFieldNames[Filter.DateField]);
      if Filter.DateFrom > 0 then
        Echo.AddPair('date_from', FormatDateTime('yyyy-mm-dd', Filter.DateFrom));
      if Filter.DateTo > 0 then
        Echo.AddPair('date_to', FormatDateTime('yyyy-mm-dd', Filter.DateTo));
    end;
    if Length(Filter.Values) > 0 then
    begin
      Entries := TJSONArray.Create;
      Echo.AddPair('values', Entries);
      for Limit in FDescribeLimits(Filter.Values) do
      begin
        Entry := TJSONObject.Create;
        Entries.AddElement(Entry);
        Entry.AddPair('value_type', Limit.ValueType);
        Entry.AddPair('value_type_id', TJSONNumber.Create(Limit.ValueTypeId));
        Entry.AddPair('unit', Limit.Units);
        if Limit.HasMin then
          Entry.AddPair('min', TJSONNumber.Create(Limit.Min));
        if Limit.HasMax then
          Entry.AddPair('max', TJSONNumber.Create(Limit.Max));
        if Limit.RecType <> '' then
          Entry.AddPair('rec_type', Limit.RecType);
        if Limit.RequestedUnit <> '' then
          Entry.AddPair('requested_unit', Limit.RequestedUnit);
      end;
    end;
    Result := Echo.ToJSON;
  finally
    Echo.Free;
  end;
end;

function TLocalSemanticSearch.Search(const Request: TSemanticSearchRequest;
  const Cancelled: TCancelCheck): TSemanticSearchResult;
var
  Options: THybridSearchOptions;
  Applied: string;
begin
  Options := THybridSearchOptions.Default;
  if not Request.Rerank then
    Options.RerankDepth := 0;
  Applied := '';
  if not Request.Filter.IsEmpty then
  begin
    Options.ItemFilter := FResolveFilter(Request.Filter, Request.VisibleProjectIds);
    Applied := FiltersAppliedJson(Request.Filter);
  end;
  Result := FService.Search(Request.Query, Request.VisibleProjectIds, Request.TopK, Options,
    Cancelled);
  Result.FiltersApplied := Applied;
end;

function TLocalSemanticSearch.Status: TSemanticSearchStatus;
begin
  Result := FService.Status;
end;

function TLocalSemanticSearch.RerankerAvailable: Boolean;
begin
  Result := FService.RerankerAvailable;
end;

function TLocalSemanticSearch.IsRemote: Boolean;
begin
  Result := False;
end;

end.
