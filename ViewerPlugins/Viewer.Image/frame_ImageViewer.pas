unit frame_ImageViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls,
  RzCommon, RzPanel, RzButton;

type
  TframeImageViewer = class(TFrame)
    ScrollBox: TScrollBox;
    Image: TImage;
  private
    FToolbar: TRzPanel;
    FBtnCopy: TRzBitBtn;
    FBtnSave: TRzBitBtn;
    FBtnFit: TRzBitBtn;
    FBtnActual: TRzBitBtn;
    FBtnZoomIn: TRzBitBtn;
    FBtnZoomOut: TRzBitBtn;
    FLblZoom: TLabel;
    FDlgSave: TSaveDialog;

    FZoom: Double;
    FFitMode: Boolean;
    FOrigW: Integer;
    FOrigH: Integer;

    procedure CreateToolbar;
    procedure UpdateImageLayout;
    procedure ApplyZoom(NewZoom: Double);

    procedure BtnCopyClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnFitClick(Sender: TObject);
    procedure BtnActualClick(Sender: TObject);
    procedure BtnZoomInClick(Sender: TObject);
    procedure BtnZoomOutClick(Sender: TObject);
    procedure ScrollBoxResize(Sender: TObject);
    procedure ScrollBoxMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ImageDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure ImageLoaded;
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function SaveState: string;
    procedure RestoreState(const AState: string);
  end;

implementation

uses
  System.Math, System.JSON, ClipBrd, Vcl.Imaging.pngimage, unit_ELNPreviewUtils;

{$R *.dfm}

constructor TframeImageViewer.Create(AOwner: TComponent);
begin
  inherited;
  FZoom := 1.0;
  FFitMode := True;
  FOrigW := 0;
  FOrigH := 0;

  Image.Stretch := True;
  Image.Proportional := True;
  Image.Center := False;

  ScrollBox.OnResize := ScrollBoxResize;
  ScrollBox.OnMouseWheel := ScrollBoxMouseWheel;
  Image.OnDblClick := ImageDblClick;

  CreateToolbar;
end;

procedure TframeImageViewer.CreateToolbar;
var
  PPI: Integer;

  function S(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, PPI, 96);
  end;

begin
  PPI := CurrentPPI;

  FToolbar := TRzPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alBottom;
  FToolbar.Height := S(34);
  FToolbar.BorderOuter := fsNone;
  FToolbar.AlignWithMargins := True;

  FBtnCopy := TRzBitBtn.Create(Self);
  FBtnCopy.Parent := FToolbar;
  FBtnCopy.Align := alLeft;
  FBtnCopy.AlignWithMargins := True;
  FBtnCopy.Width := S(80);
  FBtnCopy.Caption := 'Copy';
  FBtnCopy.OnClick := BtnCopyClick;

  FBtnSave := TRzBitBtn.Create(Self);
  FBtnSave.Parent := FToolbar;
  FBtnSave.Align := alLeft;
  FBtnSave.AlignWithMargins := True;
  FBtnSave.Width := S(80);
  FBtnSave.Caption := 'Save As';
  FBtnSave.OnClick := BtnSaveClick;

  // Right side: zoom controls (added right-to-left)
  FBtnZoomOut := TRzBitBtn.Create(Self);
  FBtnZoomOut.Parent := FToolbar;
  FBtnZoomOut.Align := alRight;
  FBtnZoomOut.AlignWithMargins := True;
  FBtnZoomOut.Width := S(36);
  FBtnZoomOut.Caption := #$2212;
  FBtnZoomOut.OnClick := BtnZoomOutClick;

  FBtnZoomIn := TRzBitBtn.Create(Self);
  FBtnZoomIn.Parent := FToolbar;
  FBtnZoomIn.Align := alRight;
  FBtnZoomIn.AlignWithMargins := True;
  FBtnZoomIn.Width := S(36);
  FBtnZoomIn.Caption := '+';
  FBtnZoomIn.OnClick := BtnZoomInClick;

  FLblZoom := TLabel.Create(Self);
  FLblZoom.Parent := FToolbar;
  FLblZoom.Align := alRight;
  FLblZoom.AlignWithMargins := True;
  FLblZoom.Layout := tlCenter;
  FLblZoom.Caption := '  Fit  ';

  FBtnActual := TRzBitBtn.Create(Self);
  FBtnActual.Parent := FToolbar;
  FBtnActual.Align := alRight;
  FBtnActual.AlignWithMargins := True;
  FBtnActual.Width := S(56);
  FBtnActual.Caption := '100%';
  FBtnActual.OnClick := BtnActualClick;

  FBtnFit := TRzBitBtn.Create(Self);
  FBtnFit.Parent := FToolbar;
  FBtnFit.Align := alRight;
  FBtnFit.AlignWithMargins := True;
  FBtnFit.Width := S(56);
  FBtnFit.Caption := 'Fit';
  FBtnFit.OnClick := BtnFitClick;

  FDlgSave := TSaveDialog.Create(Self);
  FDlgSave.Filter := 'PNG Image|*.png|BMP Image|*.bmp|All Files|*.*';
  FDlgSave.DefaultExt := 'png';
end;

procedure TframeImageViewer.ImageLoaded;
begin
  if Assigned(Image.Picture.Graphic) and not Image.Picture.Graphic.Empty then
  begin
    FOrigW := Image.Picture.Graphic.Width;
    FOrigH := Image.Picture.Graphic.Height;
  end
  else
  begin
    FOrigW := 0;
    FOrigH := 0;
  end;
  FFitMode := True;
  UpdateImageLayout;
end;

procedure TframeImageViewer.ApplyZoom(NewZoom: Double);
begin
  NewZoom := EnsureRange(NewZoom, 0.05, 20.0);
  FZoom := NewZoom;
  FFitMode := False;
  UpdateImageLayout;
end;

procedure TframeImageViewer.UpdateImageLayout;
var
  ImgW, ImgH, CW, CH: Integer;
begin
  if (FOrigW = 0) or (FOrigH = 0) then
    Exit;

  CW := ScrollBox.ClientWidth;
  CH := ScrollBox.ClientHeight;

  if FFitMode then
  begin
    FZoom := Min(CW / FOrigW, CH / FOrigH);
    if FZoom > 1.0 then
      FZoom := 1.0;
    FLblZoom.Caption := Format('  Fit (%d%%)  ', [Round(FZoom * 100)]);
  end
  else
    FLblZoom.Caption := Format('  %d%%  ', [Round(FZoom * 100)]);

  ImgW := Max(1, Round(FOrigW * FZoom));
  ImgH := Max(1, Round(FOrigH * FZoom));

  Image.Width := ImgW;
  Image.Height := ImgH;

  if ImgW < CW then
    Image.Left := (CW - ImgW) div 2
  else
    Image.Left := 0;

  if ImgH < CH then
    Image.Top := (CH - ImgH) div 2
  else
    Image.Top := 0;
end;

procedure TframeImageViewer.ScrollBoxResize(Sender: TObject);
begin
  UpdateImageLayout;
end;

procedure TframeImageViewer.ScrollBoxMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  Factor: Double;
begin
  if FOrigW = 0 then
    Exit;

  if WheelDelta > 0 then
    Factor := 1.25
  else
    Factor := 0.8;

  ApplyZoom(FZoom * Factor);
  Handled := True;
end;

procedure TframeImageViewer.ImageDblClick(Sender: TObject);
begin
  if FFitMode then
    ApplyZoom(1.0)
  else
    BtnFitClick(nil);
end;

procedure TframeImageViewer.BtnFitClick(Sender: TObject);
begin
  FFitMode := True;
  UpdateImageLayout;
end;

procedure TframeImageViewer.BtnActualClick(Sender: TObject);
begin
  ApplyZoom(1.0);
end;

procedure TframeImageViewer.BtnZoomInClick(Sender: TObject);
begin
  ApplyZoom(FZoom * 1.25);
end;

procedure TframeImageViewer.BtnZoomOutClick(Sender: TObject);
begin
  ApplyZoom(FZoom * 0.8);
end;

procedure TframeImageViewer.BtnCopyClick(Sender: TObject);
var
  Bmp: TBitmap;
begin
  if not Assigned(Image.Picture.Graphic) then
    Exit;

  Bmp := TBitmap.Create;
  try
    Bmp.Assign(Image.Picture.Graphic);
    Clipboard.Assign(Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure TframeImageViewer.BtnSaveClick(Sender: TObject);
var
  Ext: string;
  Png: TPngImage;
  Bmp: TBitmap;
begin
  if not Assigned(Image.Picture.Graphic) then
    Exit;

  if not FDlgSave.Execute then
    Exit;

  Ext := LowerCase(ExtractFileExt(FDlgSave.FileName));
  if Ext = '.png' then
  begin
    Png := TPngImage.Create;
    try
      Png.Assign(Image.Picture.Graphic);
      Png.SaveToFile(FDlgSave.FileName);
    finally
      Png.Free;
    end;
  end
  else
  begin
    Bmp := TBitmap.Create;
    try
      Bmp.Assign(Image.Picture.Graphic);
      Bmp.SaveToFile(FDlgSave.FileName);
    finally
      Bmp.Free;
    end;
  end;
end;

function TframeImageViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
begin
  Result := CreateScaledPreview(Image.Picture.Graphic, MaxW, MaxH);
end;

function TframeImageViewer.SaveState: string;
var
  JObj: TJSONObject;
begin
  Result := '';
  if FOrigW = 0 then Exit;

  JObj := TJSONObject.Create;
  try
    JObj.AddPair('v', TJSONNumber.Create(1));
    JObj.AddPair('zoom', TJSONNumber.Create(FZoom));
    JObj.AddPair('fitMode', TJSONBool.Create(FFitMode));
    Result := JObj.ToJSON;
  finally
    JObj.Free;
  end;
end;

procedure TframeImageViewer.RestoreState(const AState: string);
var
  JObj: TJSONObject;
  JVal: TJSONValue;
begin
  if FOrigW = 0 then Exit;

  try
    JObj := TJSONObject.ParseJSONValue(AState) as TJSONObject;
  except
    Exit;
  end;
  if not Assigned(JObj) then Exit;

  try
    JVal := JObj.GetValue('fitMode');
    if Assigned(JVal) and (JVal is TJSONBool) then
      FFitMode := (JVal as TJSONBool).AsBoolean;

    if not FFitMode then
    begin
      JVal := JObj.GetValue('zoom');
      if Assigned(JVal) and (JVal is TJSONNumber) then
        FZoom := EnsureRange(TJSONNumber(JVal).AsDouble, 0.05, 20.0);
    end;

    UpdateImageLayout;
  finally
    JObj.Free;
  end;
end;

end.
