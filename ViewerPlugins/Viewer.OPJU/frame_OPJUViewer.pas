unit frame_OPJUViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.IOUtils, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.Imaging.pngimage,
  RzCommon, RzPanel;

type
  TOPJUThumbnail = record
    Png: TPngImage;
    IsGraph: Boolean;
  end;

  TframeOPJUViewer = class(TFrame)
  private
    FTopPanel: TRzPanel;
    FFileLabel: TLabel;
    FVersionLabel: TLabel;
    FClientPanel: TPanel;
    FImages: array[0..3] of TImage;
    FDisplayedCount: Integer;
    FThumbnails: TList<TOPJUThumbnail>;

    procedure CreateUI;
    procedure ClearThumbnails;
    procedure LayoutImages;
    procedure ParseOPJU(const Data: TBytes);
    function ExtractVersion(const Data: TBytes): string;
    function FindPNGs(const Data: TBytes): TList<TOPJUThumbnail>;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const AFileName: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
  end;

implementation

uses
  unit_ELNPreviewUtils;

{$R *.dfm}

const
  PNG_SIGNATURE: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);
  IEND_MARKER: array[0..3] of Byte = ($49, $45, $4E, $44);
  MAX_THUMBNAILS = 4;

constructor TframeOPJUViewer.Create(AOwner: TComponent);
begin
  inherited;
  FThumbnails := TList<TOPJUThumbnail>.Create;
  FDisplayedCount := 0;
  CreateUI;
end;

destructor TframeOPJUViewer.Destroy;
begin
  ClearThumbnails;
  FThumbnails.Free;
  inherited;
end;

procedure TframeOPJUViewer.CreateUI;
var
  I: Integer;
begin
  FTopPanel := TRzPanel.Create(Self);
  FTopPanel.Parent := Self;
  FTopPanel.Align := alTop;
  FTopPanel.Height := 40;
  FTopPanel.BorderOuter := fsNone;

  FFileLabel := TLabel.Create(Self);
  FFileLabel.Parent := FTopPanel;
  FFileLabel.Left := 8;
  FFileLabel.Top := 4;
  FFileLabel.Font.Style := [fsBold];
  FFileLabel.Caption := '';

  FVersionLabel := TLabel.Create(Self);
  FVersionLabel.Parent := FTopPanel;
  FVersionLabel.Left := 8;
  FVersionLabel.Top := 22;
  FVersionLabel.Caption := '';

  FClientPanel := TPanel.Create(Self);
  FClientPanel.Parent := Self;
  FClientPanel.Align := alClient;
  FClientPanel.BevelOuter := bvNone;
  FClientPanel.ParentBackground := True;

  for I := 0 to 3 do
  begin
    FImages[I] := TImage.Create(Self);
    FImages[I].Parent := FClientPanel;
    FImages[I].Visible := False;
    FImages[I].Proportional := True;
    FImages[I].Center := True;
    FImages[I].Stretch := True;
  end;
end;

procedure TframeOPJUViewer.ClearThumbnails;
var
  I: Integer;
  Thumb: TOPJUThumbnail;
begin
  for Thumb in FThumbnails do
    Thumb.Png.Free;
  FThumbnails.Clear;

  for I := 0 to 3 do
  begin
    FImages[I].Picture.Assign(nil);
    FImages[I].Visible := False;
  end;
  FDisplayedCount := 0;
end;

procedure TframeOPJUViewer.LoadFromFile(const AFileName: string);
var
  Data: TBytes;
begin
  ClearThumbnails;

  if not FileExists(AFileName) then
    Exit;

  FFileLabel.Caption := ExtractFileName(AFileName);

  Data := TFile.ReadAllBytes(AFileName);
  ParseOPJU(Data);
end;

procedure TframeOPJUViewer.ParseOPJU(const Data: TBytes);
var
  Version: string;
  AllPNGs: TList<TOPJUThumbnail>;
  Thumb: TOPJUThumbnail;
  Graphs, Tables: TList<TOPJUThumbnail>;
  DisplayList: TList<TOPJUThumbnail>;
  I, Count: Integer;
begin
  Version := ExtractVersion(Data);
  if Version <> '' then
    FVersionLabel.Caption := 'Origin ' + Version
  else
    FVersionLabel.Caption := '';

  AllPNGs := FindPNGs(Data);
  try
    if AllPNGs.Count = 0 then
      Exit;

    Graphs := TList<TOPJUThumbnail>.Create;
    Tables := TList<TOPJUThumbnail>.Create;
    try
      for Thumb in AllPNGs do
      begin
        if Thumb.IsGraph then
          Graphs.Add(Thumb)
        else
          Tables.Add(Thumb);
      end;

      if Graphs.Count > 0 then
        DisplayList := Graphs
      else
        DisplayList := Tables;

      Count := DisplayList.Count;
      if Count > MAX_THUMBNAILS then
        Count := MAX_THUMBNAILS;

      for I := 0 to Count - 1 do
      begin
        FThumbnails.Add(DisplayList[I]);
        FImages[I].Picture.Graphic := DisplayList[I].Png;
        FImages[I].Visible := True;
      end;
      FDisplayedCount := Count;

      for Thumb in AllPNGs do
      begin
        if not FThumbnails.Contains(Thumb) then
          Thumb.Png.Free;
      end;
    finally
      Graphs.Free;
      Tables.Free;
    end;
  finally
    AllPNGs.Free;
  end;

  LayoutImages;
end;

function TframeOPJUViewer.ExtractVersion(const Data: TBytes): string;
var
  I: Integer;
  Ch: AnsiChar;
begin
  // Header: "CPYUA <version> <number>"
  Result := '';
  if Length(Data) < 5 then
    Exit;

  if not ((Data[0] = Ord('C')) and (Data[1] = Ord('P')) and
          (Data[2] = Ord('Y')) and (Data[3] = Ord('U')) and
          (Data[4] = Ord('A'))) then
    Exit;

  I := 6; // skip 'CPYUA '
  while (I < Length(Data)) and (I < 64) do
  begin
    Ch := AnsiChar(Data[I]);
    if (Ch < #32) or (Ch > #126) then
      Break;
    Result := Result + Char(Ch);
    Inc(I);
  end;
  Result := Trim(Result);
end;

function TframeOPJUViewer.FindPNGs(const Data: TBytes): TList<TOPJUThumbnail>;
var
  I, J, DataLen, PngStart: Integer;
  PngEnd: Integer;
  Found: Boolean;
  Stream: TMemoryStream;
  Png: TPngImage;
  Thumb: TOPJUThumbnail;
begin
  Result := TList<TOPJUThumbnail>.Create;
  DataLen := Length(Data);
  PngEnd := 0;
  I := 0;

  while I < DataLen - 8 do
  begin
    if (Data[I]   = PNG_SIGNATURE[0]) and (Data[I+1] = PNG_SIGNATURE[1]) and
       (Data[I+2] = PNG_SIGNATURE[2]) and (Data[I+3] = PNG_SIGNATURE[3]) and
       (Data[I+4] = PNG_SIGNATURE[4]) and (Data[I+5] = PNG_SIGNATURE[5]) and
       (Data[I+6] = PNG_SIGNATURE[6]) and (Data[I+7] = PNG_SIGNATURE[7]) then
    begin
      PngStart := I;

      Found := False;
      J := I + 8;
      while J < DataLen - 7 do
      begin
        if (Data[J]   = IEND_MARKER[0]) and (Data[J+1] = IEND_MARKER[1]) and
           (Data[J+2] = IEND_MARKER[2]) and (Data[J+3] = IEND_MARKER[3]) then
        begin
          PngEnd := J + 4 + 4; // IEND + 4 bytes CRC
          if PngEnd > DataLen then
            PngEnd := DataLen;
          Found := True;
          Break;
        end;
        Inc(J);
      end;

      if Found then
      begin
        Stream := TMemoryStream.Create;
        try
          Stream.WriteBuffer(Data[PngStart], PngEnd - PngStart);
          Stream.Position := 0;

          Png := TPngImage.Create;
          try
            Png.LoadFromStream(Stream);

            Thumb.Png := Png;
            Thumb.IsGraph := Png.Height < Png.Width;
            Result.Add(Thumb);

            Png := nil; // ownership transferred
          finally
            Png.Free; // only frees if exception occurred
          end;
        finally
          Stream.Free;
        end;

        I := PngEnd;
        Continue;
      end;
    end;

    Inc(I);
  end;
end;

procedure TframeOPJUViewer.Resize;
begin
  inherited;
  if FDisplayedCount > 0 then
    LayoutImages;
end;

procedure TframeOPJUViewer.LayoutImages;
const
  PAD = 4;
var
  CW, CH, HalfW, HalfH: Integer;
begin
  CW := FClientPanel.ClientWidth;
  CH := FClientPanel.ClientHeight;
  HalfW := CW div 2;
  HalfH := CH div 2;

  case FDisplayedCount of
    1: begin
      FImages[0].SetBounds(PAD, PAD, CW - PAD * 2, CH - PAD * 2);
    end;
    2: begin
      FImages[0].SetBounds(PAD, PAD, HalfW - PAD * 2, CH - PAD * 2);
      FImages[1].SetBounds(HalfW + PAD, PAD, CW - HalfW - PAD * 2, CH - PAD * 2);
    end;
    3: begin
      FImages[0].SetBounds(PAD, PAD, HalfW - PAD * 2, HalfH - PAD * 2);
      FImages[1].SetBounds(HalfW + PAD, PAD, CW - HalfW - PAD * 2, HalfH - PAD * 2);
      FImages[2].SetBounds(PAD, HalfH + PAD, HalfW - PAD * 2, CH - HalfH - PAD * 2);
    end;
    4: begin
      FImages[0].SetBounds(PAD, PAD, HalfW - PAD * 2, HalfH - PAD * 2);
      FImages[1].SetBounds(HalfW + PAD, PAD, CW - HalfW - PAD * 2, HalfH - PAD * 2);
      FImages[2].SetBounds(PAD, HalfH + PAD, HalfW - PAD * 2, CH - HalfH - PAD * 2);
      FImages[3].SetBounds(HalfW + PAD, HalfH + PAD, CW - HalfW - PAD * 2, CH - HalfH - PAD * 2);
    end;
  end;
end;

function TframeOPJUViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
begin
  Result := nil;
  if FDisplayedCount = 0 then
    Exit;

  Result := CreateScaledPreview(FThumbnails[0].Png, MaxW, MaxH);
end;

end.
