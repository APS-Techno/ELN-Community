unit unit_XRFXParser;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.IOUtils,
  System.StrUtils,
  System.Zip, System.JSON, System.Generics.Collections;

type
  TXRFXStructureSummary = record
    StructureType: string;
    D, Gamma, Sigma: Double;
    N: Integer;
  end;

  TXRFXOptimizerInfo = record
    Population, Iterations, StagnationLimit: Integer;
  end;

  TXRFXElementResult = record
    Line: string;
    PeakR: Double;
    FWHM: Double;
  end;

  TXRFXManifest = record
    Version: Integer;
    Created: string;
    Generator: string;
    FoM: Double;
    TargetLines: TArray<string>;
    ElementPool: TArray<string>;
    Substrate: string;
    Structure: TXRFXStructureSummary;
    Optimizer: TXRFXOptimizerInfo;
    PerElement: TArray<TXRFXElementResult>;
    CurveFiles: TArray<string>;
  end;

  TXRFXLayer = record
    Material: string;
    Thickness: Double;
    Roughness: Double;
    Density: Double;
  end;

  TXRFXStack = record
    StackType: string;
    N: Integer;
    Layers: TArray<TXRFXLayer>;
  end;

  TXRFXStructure = record
    Stacks: TArray<TXRFXStack>;
    Substrate: TXRFXLayer;
  end;

  TXRFXCurveData = record
    Element: string;
    Theta: TArray<Double>;
    Refl: TArray<Double>;
  end;

  TXRFXLoadedResult = record
    FileName: string;
    TempDir: string;
    Manifest: TXRFXManifest;
    Structure: TXRFXStructure;
    Curves: TArray<TXRFXCurveData>;
  end;

function LoadXRFXFile(const FileName: string): TXRFXLoadedResult;
procedure CleanupXRFXTemp(const TempDir: string);

function  LoadManifest(const ManifestPath: string): TXRFXManifest;
function  LoadXRCStructure(const JsonPath: string): TXRFXStructure;
function  LoadCurveFiles(const CurvesDir: string): TArray<TXRFXCurveData>;

implementation

procedure ExtractXRFXPackage(const XRFXPath, TempDir: string);
var
  Zip: TZipFile;
  I: Integer;
  NormRoot, NormDest, Entry: string;
begin
  if not TDirectory.Exists(TempDir) then
    TDirectory.CreateDirectory(TempDir);

  // System.Zip's TZipFile does not guard against entries whose relative path
  // escapes the extraction directory (zip-slip). Validate each entry's
  // canonicalised destination against the confinement root before extracting.
  NormRoot := IncludeTrailingPathDelimiter(TPath.GetFullPath(TempDir));

  Zip := TZipFile.Create;
  try
    Zip.Open(XRFXPath, zmRead);
    try
      for I := 0 to Zip.FileCount - 1 do
      begin
        Entry := Zip.FileNames[I];
        NormDest := TPath.GetFullPath(TPath.Combine(TempDir, Entry));
        if not StartsText(NormRoot, NormDest) then
          raise Exception.CreateFmt(
            'Refusing to extract XRFX entry outside temp directory: %s',
            [Entry]);
      end;
      Zip.ExtractAll(TempDir);
    finally
      Zip.Close;
    end;
  finally
    Zip.Free;
  end;
end;

function LoadManifest(const ManifestPath: string): TXRFXManifest;
var
  Content: string;
  JSON, JStruct, JOpt, JFiles: TJSONObject;
  JLines, JPool, JPerElem, JCurves: TJSONArray;
  JElem: TJSONObject;
  i: Integer;
begin
  Content := TFile.ReadAllText(ManifestPath);
  JSON := TJSONObject.ParseJSONValue(Content) as TJSONObject;
  try
    Result.Version := JSON.GetValue<Integer>('version');
    Result.Created := JSON.GetValue<string>('created', '');

    if JSON.FindValue('generator') <> nil then
      Result.Generator := JSON.GetValue<string>('generator');

    Result.FoM := JSON.GetValue<Double>('fom');
    Result.Substrate := JSON.GetValue<string>('substrate');

    JLines := JSON.GetValue<TJSONArray>('target_lines');
    SetLength(Result.TargetLines, JLines.Count);
    for i := 0 to JLines.Count - 1 do
      Result.TargetLines[i] := JLines.Items[i].Value;

    JPool := JSON.GetValue<TJSONArray>('element_pool');
    SetLength(Result.ElementPool, JPool.Count);
    for i := 0 to JPool.Count - 1 do
      Result.ElementPool[i] := JPool.Items[i].Value;

    JStruct := JSON.GetValue<TJSONObject>('structure_summary');
    Result.Structure.StructureType := JStruct.GetValue<string>('type');
    Result.Structure.D := JStruct.GetValue<Double>('d');
    Result.Structure.Gamma := JStruct.GetValue<Double>('gamma');
    Result.Structure.N := JStruct.GetValue<Integer>('N');
    Result.Structure.Sigma := JStruct.GetValue<Double>('sigma');

    JOpt := JSON.GetValue<TJSONObject>('optimizer');
    Result.Optimizer.Population := JOpt.GetValue<Integer>('population');
    Result.Optimizer.Iterations := JOpt.GetValue<Integer>('iterations');
    Result.Optimizer.StagnationLimit := JOpt.GetValue<Integer>('stagnation_limit');

    JPerElem := JSON.GetValue<TJSONArray>('per_element');
    SetLength(Result.PerElement, JPerElem.Count);
    for i := 0 to JPerElem.Count - 1 do
    begin
      JElem := JPerElem.Items[i] as TJSONObject;
      Result.PerElement[i].Line := JElem.GetValue<string>('line');
      Result.PerElement[i].PeakR := JElem.GetValue<Double>('peak_R');
      Result.PerElement[i].FWHM := JElem.GetValue<Double>('fwhm');
    end;

    if JSON.FindValue('files') <> nil then
    begin
      JFiles := JSON.GetValue<TJSONObject>('files');
      if JFiles.FindValue('curves') <> nil then
      begin
        JCurves := JFiles.GetValue<TJSONArray>('curves');
        SetLength(Result.CurveFiles, JCurves.Count);
        for i := 0 to JCurves.Count - 1 do
          Result.CurveFiles[i] := JCurves.Items[i].Value;
      end;
    end;
  finally
    JSON.Free;
  end;
end;

function LoadXRCStructure(const JsonPath: string): TXRFXStructure;
var
  Content: string;
  JSON, JStack, JSubs, JLayer: TJSONObject;
  JStacks, JLayers: TJSONArray;
  JType: TJSONValue;
  i, j: Integer;
begin
  Content := TFile.ReadAllText(JsonPath);
  JSON := TJSONObject.ParseJSONValue(Content) as TJSONObject;
  try
    JStacks := JSON.GetValue<TJSONArray>('Stacks');
    SetLength(Result.Stacks, JStacks.Count);
    for i := 0 to JStacks.Count - 1 do
    begin
      JStack := JStacks.Items[i] as TJSONObject;
      JType := JStack.FindValue('T');
      if JType <> nil then
        Result.Stacks[i].StackType := JType.Value
      else
        Result.Stacks[i].StackType := '';
      Result.Stacks[i].N := JStack.GetValue<Integer>('N');

      JLayers := JStack.GetValue<TJSONArray>('Layers');
      SetLength(Result.Stacks[i].Layers, JLayers.Count);
      for j := 0 to JLayers.Count - 1 do
      begin
        JLayer := JLayers.Items[j] as TJSONObject;
        Result.Stacks[i].Layers[j].Material  := JLayer.GetValue<string>('M');
        Result.Stacks[i].Layers[j].Thickness := JLayer.GetValue<Double>('H');
        Result.Stacks[i].Layers[j].Roughness := JLayer.GetValue<Double>('s');
        Result.Stacks[i].Layers[j].Density   := JLayer.GetValue<Double>('r');
      end;
    end;

    JSubs := JSON.GetValue<TJSONObject>('Subs');
    Result.Substrate.Material  := JSubs.GetValue<string>('M');
    Result.Substrate.Roughness := JSubs.GetValue<Double>('s');
    Result.Substrate.Density   := JSubs.GetValue<Double>('r');
    Result.Substrate.Thickness := 0;
  finally
    JSON.Free;
  end;
end;

function LoadCurveFiles(const CurvesDir: string): TArray<TXRFXCurveData>;
var
  FileNames: TStringDynArray;
  i, j: Integer;
  Lines: TStringDynArray;
  Parts: TArray<string>;
  ThetaList: TList<Double>;
  ReflList: TList<Double>;
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';

  if not TDirectory.Exists(CurvesDir) then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  FileNames := TDirectory.GetFiles(CurvesDir, '*.dat');
  SetLength(Result, Length(FileNames));

  for i := 0 to High(FileNames) do
  begin
    Result[i].Element := TPath.GetFileNameWithoutExtension(FileNames[i]);
    Lines := TFile.ReadAllLines(FileNames[i]);

    ThetaList := TList<Double>.Create;
    ReflList := TList<Double>.Create;
    try
      for j := 0 to High(Lines) do
      begin
        if Lines[j].StartsWith('Theta') or (Trim(Lines[j]) = '') then
          Continue;
        Parts := Lines[j].Split([#9]);
        if Length(Parts) >= 2 then
        begin
          ThetaList.Add(StrToFloat(Trim(Parts[0]), FS));
          ReflList.Add(StrToFloat(Trim(Parts[1]), FS));
        end;
      end;
      Result[i].Theta := ThetaList.ToArray;
      Result[i].Refl := ReflList.ToArray;
    finally
      ThetaList.Free;
      ReflList.Free;
    end;
  end;
end;

procedure CleanupXRFXTemp(const TempDir: string);
begin
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);
end;

function LoadXRFXFile(const FileName: string): TXRFXLoadedResult;
var
  BaseTempDir, XRCPath, CurvesDir: string;
begin
  Result := Default(TXRFXLoadedResult);
  Result.FileName := FileName;

  BaseTempDir := TPath.Combine(TPath.GetTempPath, 'ELN_XRFX');
  if not TDirectory.Exists(BaseTempDir) then
    TDirectory.CreateDirectory(BaseTempDir);

  Result.TempDir := TPath.Combine(BaseTempDir, TGUID.NewGuid.ToString);
  try
    ExtractXRFXPackage(FileName, Result.TempDir);

    Result.Manifest := LoadManifest(TPath.Combine(Result.TempDir, 'manifest.json'));

    XRCPath := TPath.Combine(Result.TempDir, 'best_structure_xrc.json');
    if TFile.Exists(XRCPath) then
      Result.Structure := LoadXRCStructure(XRCPath);

    CurvesDir := TPath.Combine(Result.TempDir, 'best_curves');
    Result.Curves := LoadCurveFiles(CurvesDir);
  except
    CleanupXRFXTemp(Result.TempDir);
    raise;
  end;
end;

end.
