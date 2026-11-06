unit unit_SeriesExport;

interface

uses
  unit_SeriesTable;

function SeriesTableToText(const ATable: TSeriesTable; ADelimiter: Char): string;

implementation

uses
  System.SysUtils, System.Classes, unit_SeriesColumn;

function Escape(const AField: string; ADelimiter: Char): string;
begin
  if ADelimiter = ',' then
  begin
    if AField.IndexOfAny([',', '"', #13, #10]) >= 0 then
      Result := '"' + AField.Replace('"', '""') + '"'
    else
      Result := AField;
  end
  else
    Result := AField.Replace(#9, ' ').Replace(#13, ' ').Replace(#10, ' ');
end;

function DataHits(const ACell: TSeriesCell): TArray<TSeriesHit>;
var
  H: TSeriesHit;
begin
  Result := nil;
  for H in ACell.Hits do
    if not H.Planned then
      Result := Result + [H];
end;

function HasTol(const ATable: TSeriesTable; AColumn: Integer): Boolean;
var
  R: TSeriesTableRow;
  D: TArray<TSeriesHit>;
begin
  for R in ATable.Rows do
  begin
    if (R.State = srsPlanned) or (AColumn > High(R.Cells)) then
      Continue;
    D := DataHits(R.Cells[AColumn]);
    if (Length(D) = 1) and (D[0].Tol > 0) then
      Exit(True);
  end;
  Result := False;
end;

function SeriesTableToText(const ATable: TSeriesTable; ADelimiter: Char): string;
var
  Names, Units, Fields: TStringList;
  Shown, Tols: TArray<Boolean>;
  Builder: TStringBuilder;
  I, J: Integer;
  Cell: TSeriesCell;
  D: TArray<TSeriesHit>;
  S: string;

  procedure Flush(AList: TStringList);
  var
    K: Integer;
  begin
    for K := 0 to AList.Count - 1 do
    begin
      if K > 0 then
        Builder.Append(ADelimiter);
      Builder.Append(Escape(AList[K], ADelimiter));
    end;
    Builder.Append(#13#10);
  end;

begin
  SetLength(Shown, Length(ATable.Columns));
  SetLength(Tols, Length(ATable.Columns));
  Names := TStringList.Create;
  Units := TStringList.Create;
  Fields := TStringList.Create;
  Builder := TStringBuilder.Create;
  try
    Names.Capacity := Length(ATable.Columns) + 1;
    Names.Add('Item');
    Units.Add('');
    for I := 0 to High(ATable.Columns) do
    begin
      Shown[I] := ATable.Columns[I].Role <> scrHidden;
      if not Shown[I] then
        Continue;
      Names.Add(ATable.Columns[I].Caption);
      Units.Add(ATable.Columns[I].Units);
      Tols[I] := HasTol(ATable, I);
      if Tols[I] then
      begin
        Names.Add(#$00B1' ' + ATable.Columns[I].Caption);
        Units.Add(ATable.Columns[I].Units);
      end;
    end;
    Flush(Names);
    Flush(Units);

    for I := 0 to High(ATable.Rows) do
    begin
      if ATable.Rows[I].State = srsPlanned then
        Continue;
      Fields.Clear;
      Fields.Add(ATable.Rows[I].Title);
      for J := 0 to High(ATable.Columns) do
      begin
        if not Shown[J] then
          Continue;
        if J <= High(ATable.Rows[I].Cells) then
          Cell := ATable.Rows[I].Cells[J]
        else
          Cell.Hits := nil;
        D := DataHits(Cell);
        if Length(D) = 0 then
        begin
          Fields.Add('');
          if Tols[J] then
            Fields.Add('');
        end
        else if Length(D) > 1 then
        begin
          S := '';
          for var H in D do
          begin
            if S <> '' then
              S := S + '; ';
            S := S + FloatToStr(H.Value, TFormatSettings.Invariant);
          end;
          Fields.Add(S);
          if Tols[J] then
            Fields.Add('');
        end
        else
        begin
          Fields.Add(FloatToStr(D[0].Value, TFormatSettings.Invariant));
          if Tols[J] then
          begin
            if D[0].Tol > 0 then
              Fields.Add(FloatToStr(D[0].Tol, TFormatSettings.Invariant))
            else
              Fields.Add('');
          end;
        end;
      end;
      Flush(Fields);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
    Fields.Free;
    Units.Free;
    Names.Free;
  end;
end;

end.
