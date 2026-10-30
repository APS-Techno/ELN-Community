unit unit_TextExtractorRegistry;

interface

uses
  System.SysUtils, System.Generics.Collections, unit_TextExtractors;

type
  TTextExtractorRegistry = class
  private
    FByExtension: TDictionary<string, ITextExtractor>;
    FExtractors: TList<ITextExtractor>;
  public
    constructor Create(const PdfiumLibraryPath: string);
    destructor Destroy; override;
    procedure Register(const Extractor: ITextExtractor; const Extensions: array of string);
    function ForExtension(const Ext: string): ITextExtractor;
    function Identity: string;
  end;

const
  SupportedFileTextExtensions: array[0..11] of string = ('.pdf', '.docx', '.pptx', '.xlsx',
    '.html', '.htm', '.json', '.xml', '.csv', '.rtf', '.md', '.txt');

implementation

uses
  System.Generics.Defaults, unit_OfficeTextExtractors, unit_MarkupTextExtractors,
  unit_JsonTextExtractor, unit_RtfTextExtractor;

constructor TTextExtractorRegistry.Create(const PdfiumLibraryPath: string);
begin
  inherited Create;
  FByExtension := TDictionary<string, ITextExtractor>.Create;
  FExtractors := TList<ITextExtractor>.Create;
  Register(TPdfTextExtractor.Create(PdfiumLibraryPath), ['.pdf']);
  Register(TDocxTextExtractor.Create, ['.docx']);
  Register(TPptxTextExtractor.Create, ['.pptx']);
  Register(TXlsxTextExtractor.Create, ['.xlsx']);
  Register(THtmlTextExtractor.Create, ['.html', '.htm']);
  Register(TJsonTextExtractor.Create, ['.json']);
  Register(TXmlTextExtractor.Create, ['.xml']);
  Register(TPlainTextExtractor.Create('csv-text'), ['.csv']);
  Register(TRtfTextExtractor.Create, ['.rtf']);
  Register(TPlainTextExtractor.Create('plain-text'), ['.md', '.txt']);
end;

destructor TTextExtractorRegistry.Destroy;
begin
  FExtractors.Free;
  FByExtension.Free;
  inherited;
end;

procedure TTextExtractorRegistry.Register(const Extractor: ITextExtractor; const Extensions: array of string);
var
  Ext: string;
begin
  FExtractors.Add(Extractor);
  for Ext in Extensions do
    FByExtension.AddOrSetValue(LowerCase(Ext), Extractor);
end;

function TTextExtractorRegistry.ForExtension(const Ext: string): ITextExtractor;
begin
  if not FByExtension.TryGetValue(LowerCase(Ext), Result) then
    Result := nil;
end;

function TTextExtractorRegistry.Identity: string;
var
  Ids: TArray<string>;
  I: Integer;
begin
  SetLength(Ids, FExtractors.Count);
  for I := 0 to FExtractors.Count - 1 do
    Ids[I] := FExtractors[I].Id + ':' + IntToStr(FExtractors[I].Version);
  TArray.Sort<string>(Ids, TStringComparer.Ordinal);
  Result := string.Join(';', Ids);
end;

end.
