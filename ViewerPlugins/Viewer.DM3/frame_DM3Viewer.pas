unit frame_DM3Viewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, RzPanel, RzStatus,
  unit_ELNPluginCore, unit_ELNPluginTypes, unit_DM3Parser;

type
  TframeDM3Viewer = class(TFrame)
    ScrollBox: TScrollBox;
    Image: TImage;
    pnlMeta: TPanel;
    lblInfo: TLabel;
    Status: TRzStatusBar;
    pnlFile: TRzStatusPane;
    pnlDims: TRzStatusPane;
    pnlScale: TRzStatusPane;
  private
    FDM3: TDM3File;
    procedure ClearView;
    function FormatMetadata(const M: TDM3Metadata): string;
  public
    destructor Destroy; override;
    procedure LoadFromFile(const AFileName: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
  end;

implementation

uses
  System.Generics.Collections, System.JSON, unit_ELNPreviewUtils;

{$R *.dfm}

destructor TframeDM3Viewer.Destroy;
begin
  FDM3.Free;
  inherited;
end;

procedure TframeDM3Viewer.ClearView;
begin
  Image.Picture := nil;
  lblInfo.Caption := '';
  pnlFile.Caption := '';
  pnlDims.Caption := '';
  pnlScale.Caption := '';
  FreeAndNil(FDM3);
end;

function TframeDM3Viewer.FormatMetadata(const M: TDM3Metadata): string;
var
  SL: TStringList;

  procedure AddLine(const Name, Value: string);
  begin
    if Value <> '' then
      SL.Add(Name + ': ' + Value);
  end;

  procedure AddFloatLine(const Name: string; Value: Double; const Suffix: string = '');
  begin
    if Value <> 0 then
    begin
      if Suffix <> '' then
        SL.Add(Name + ': ' + FormatFloat('0.##', Value) + ' ' + Suffix)
      else
        SL.Add(Name + ': ' + FormatFloat('0.##', Value));
    end;
  end;

begin
  SL := TStringList.Create;
  try
    AddLine('Name', M.ImageName);
    SL.Add(Format('Size: %d x %d', [M.Width, M.Height]));

    if M.Voltage > 0 then
    begin
      if M.Voltage >= 1000 then
        SL.Add(Format('Voltage: %.0f kV', [M.Voltage / 1000]))
      else
        SL.Add(Format('Voltage: %.0f V', [M.Voltage]));
    end;

    AddFloatLine('Magnification', M.ActualMagnification, 'x');
    if (M.IndicatedMagnification > 0) and (M.IndicatedMagnification <> M.ActualMagnification) then
      AddFloatLine('Indicated Mag', M.IndicatedMagnification, 'x');

    if (M.ScaleX > 0) and (M.Units <> '') then
      SL.Add(Format('Scale: %s %s/px', [FormatFloat('0.####', M.ScaleX), M.Units]));

    AddLine('Microscope', M.Microscope);
    AddLine('Mode', M.OperationMode);
    AddLine('Illumination', M.IlluminationMode);
    AddLine('Camera', M.CameraName);
    AddFloatLine('Exposure', M.ExposureTime, 's');
    AddFloatLine('Cs', M.Cs, 'mm');

    if M.BeamCurrent <> 0 then
    begin
      if Abs(M.BeamCurrent) < 1e-9 then
        SL.Add(Format('Beam current: %.2f pA', [M.BeamCurrent * 1e12]))
      else if Abs(M.BeamCurrent) < 1e-6 then
        SL.Add(Format('Beam current: %.2f nA', [M.BeamCurrent * 1e9]))
      else
        SL.Add(Format('Beam current: %.2g A', [M.BeamCurrent]));
    end;

    AddFloatLine('Conv. angle', M.ConvergenceAngle, 'mrad');
    AddFloatLine('Defocus', M.Defocus, 'nm');
    AddFloatLine('Probe size', M.ProbeSize, 'nm');
    AddFloatLine('STEM CL', M.STEMCameraLength, 'mm');

    if (M.AlphaTilt <> 0) or (M.BetaTilt <> 0) then
    begin
      if M.BetaTilt <> 0 then
        SL.Add(Format('Tilt: '#$3B1'=%.1f'#$B0' '#$3B2'=%.1f'#$B0,
          [M.AlphaTilt, M.BetaTilt]))
      else
        SL.Add(Format('Tilt: '#$3B1'=%.1f'#$B0, [M.AlphaTilt]));
    end;

    if (M.AcquisitionDate <> '') or (M.AcquisitionTime <> '') then
      AddLine('Acquired', Trim(M.AcquisitionDate + ' ' + M.AcquisitionTime));

    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TframeDM3Viewer.LoadFromFile(const AFileName: string);
var
  Bmp: TBitmap;
  M: TDM3Metadata;
  ScaleStr: string;
begin
  ClearView;

  FDM3 := TDM3File.Create;
  try
    FDM3.ParseFromFile(AFileName);
    Bmp := FDM3.GetBitmap;
  except
    on E: Exception do
    begin
      // Malformed/corrupt DM3 — show a viewer error instead of propagating an
      // exception (e.g. AV) up to the host application.
      pnlFile.Caption := ' ' + ExtractFileName(AFileName) +
        ' — unable to read DM3 file';
      Exit;
    end;
  end;

  if Bmp <> nil then
  begin
    Image.Picture.Assign(Bmp);
    Bmp.Free;
  end;

  M := FDM3.Metadata;

  lblInfo.Caption := FormatMetadata(M);

  pnlFile.Caption := ' ' + ExtractFileName(AFileName);
  pnlDims.Caption := Format(' %d x %d', [M.Width, M.Height]);

  if (M.ScaleX > 0) and (M.Units <> '') then
    ScaleStr := Format(' %s %s/px', [FormatFloat('0.####', M.ScaleX), M.Units])
  else
    ScaleStr := '';
  pnlScale.Caption := ScaleStr;
end;

function TframeDM3Viewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Thumb: TBitmap;
begin
  Result := nil;
  if FDM3 = nil then
    Exit;

  // Use embedded thumbnail for speed. Guard the parse/scale so a malformed or
  // oversized thumbnail Data array (EOutOfMemory / EReadError from a crafted
  // file) yields no preview instead of propagating an exception to the host —
  // matching the LoadFromFile guard above.
  try
    Thumb := FDM3.GetThumbnail;
    if Thumb <> nil then
    try
      Result := CreateScaledPreview(Thumb, MaxW, MaxH);
    finally
      Thumb.Free;
    end;
  except
    on E: Exception do
      Result := nil;
  end;
end;

function TframeDM3Viewer.GetKeyValues: TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  KV: TPluginKeyValue;
  M: TDM3Metadata;

  procedure Add(const AName: string; AValue: Double; const AUnits: string;
    ARecType: TPluginRecType; AIsKey: Boolean = False);
  begin
    if AValue <> 0 then
    begin
      KV.Name := AName;
      KV.Value := AValue;
      KV.Units := AUnits;
      KV.RecType := ARecType;
      KV.IsKey := AIsKey;
      List.Add(KV);
    end;
  end;

begin
  Result := nil;
  if FDM3 = nil then
    Exit;

  M := FDM3.Metadata;
  List := TList<TPluginKeyValue>.Create;
  try
    Add('Voltage', M.Voltage, 'V', prCondition, True);
    Add('Magnification', M.ActualMagnification, 'x', prCondition, True);
    Add('Exposure', M.ExposureTime, 's', prCondition);
    Add('Cs', M.Cs, 'mm', prCondition);
    Add('Beam Current', M.BeamCurrent, 'A', prCondition);
    Add('Convergence Angle', M.ConvergenceAngle, 'mrad', prCondition);
    Add('Alpha Tilt', M.AlphaTilt, 'deg', prCondition);
    Add('Beta Tilt', M.BetaTilt, 'deg', prCondition);
    Add('Defocus', M.Defocus, 'nm', prCondition);
    Add('STEM Camera Length', M.STEMCameraLength, 'mm', prCondition);
    Add('Probe Size', M.ProbeSize, 'nm', prCondition);
    Add('Scale X', M.ScaleX, M.Units + '/px', prResult, True);
    Add('Scale Y', M.ScaleY, M.Units + '/px', prResult);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TframeDM3Viewer.GetDetailedInfo: string;
var
  J: TJSONObject;
  M: TDM3Metadata;
begin
  Result := '';
  if FDM3 = nil then
    Exit;

  M := FDM3.Metadata;
  J := TJSONObject.Create;
  try
    J.AddPair('width', TJSONNumber.Create(M.Width));
    J.AddPair('height', TJSONNumber.Create(M.Height));
    J.AddPair('dataType', TJSONNumber.Create(M.DataType));
    J.AddPair('pixelDepth', TJSONNumber.Create(M.PixelDepth));
    J.AddPair('scaleX', JNum(M.ScaleX));
    J.AddPair('scaleY', JNum(M.ScaleY));
    J.AddPair('units', M.Units);
    J.AddPair('voltage_V', JNum(M.Voltage));
    J.AddPair('actualMagnification', JNum(M.ActualMagnification));
    J.AddPair('indicatedMagnification', JNum(M.IndicatedMagnification));
    J.AddPair('microscope', M.Microscope);
    J.AddPair('cameraName', M.CameraName);
    J.AddPair('acquisitionDate', M.AcquisitionDate);
    J.AddPair('acquisitionTime', M.AcquisitionTime);
    J.AddPair('exposureTime_s', JNum(M.ExposureTime));
    J.AddPair('cs_mm', JNum(M.Cs));
    J.AddPair('illuminationMode', M.IlluminationMode);
    J.AddPair('imageName', M.ImageName);
    J.AddPair('operationMode', M.OperationMode);
    J.AddPair('beamCurrent_A', JNum(M.BeamCurrent));
    J.AddPair('convergenceAngle_mrad', JNum(M.ConvergenceAngle));
    J.AddPair('alphaTilt_deg', JNum(M.AlphaTilt));
    J.AddPair('betaTilt_deg', JNum(M.BetaTilt));
    J.AddPair('defocus_nm', JNum(M.Defocus));
    J.AddPair('stemCameraLength_mm', JNum(M.STEMCameraLength));
    J.AddPair('probeSize_nm', JNum(M.ProbeSize));
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

end.
