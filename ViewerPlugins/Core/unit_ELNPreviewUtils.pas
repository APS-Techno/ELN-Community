unit unit_ELNPreviewUtils;

interface

uses
  Vcl.Graphics;

function CreateScaledPreview(Source: TGraphic; MaxW, MaxH: Integer): TBitmap;

implementation

uses
  System.SysUtils,
  Winapi.Wincodec;

function CreateScaledPreview(Source: TGraphic; MaxW, MaxH: Integer): TBitmap;
var
  NewWidth, NewHeight: Integer;
  AspectRatio: Double;
  Factory: IWICImagingFactory;
  Scaler: IWICBitmapScaler;
  WIC: TWICImage;
begin
  Result := nil;
  if (Source = nil) or Source.Empty then
    Exit;

  AspectRatio := Source.Width / Source.Height;
  if Source.Width / MaxW > Source.Height / MaxH then
  begin
    NewWidth := MaxW;
    NewHeight := Trunc(MaxW / AspectRatio);
  end
  else
  begin
    NewHeight := MaxH;
    NewWidth := Trunc(MaxH * AspectRatio);
  end;
  if NewWidth <= 0 then NewWidth := 1;
  if NewHeight <= 0 then NewHeight := 1;

  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf32bit;
    Result.SetSize(Source.Width, Source.Height);
    Result.Canvas.Draw(0, 0, Source);

    WIC := TWICImage.Create;
    try
      Factory := TWICImage.ImagingFactory;
      WIC.Assign(Result);
      Factory.CreateBitmapScaler(Scaler);
      Scaler.Initialize(WIC.Handle, NewWidth, NewHeight,
                        WICBitmapInterpolationModeHighQualityCubic);
      WIC.Handle := IWICBitmap(Scaler);
      Result.Assign(WIC);
      Scaler := nil;
      Factory := nil;
    finally
      WIC.Free;
    end;
  except
    FreeAndNil(Result);
  end;
end;

end.
