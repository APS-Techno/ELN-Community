unit unit_ELNFilePreview;

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  RzPanel,
  RzLabel,
  RzCommon,
  Vcl.Graphics;

type
  TELNFilePreview = class(TRzPanel)
  private
    { Private declarations }
    lblFileName: TRzLabel;
    Preview: TImage;

    FFileName: string;
    FId: integer;
    procedure SetSelected(const Value: Boolean);
    procedure SetFileCaption(const Value: string);
    procedure SetStyleName(const Value: string); reintroduce;

  protected
    { Protected declarations }
    procedure FOnClick(Sender: TObject);
    procedure FOnDoubleClick(Sender: TObject);
    procedure FOnMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  public
    { Public declarations }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadImage(const FileName: string);
    procedure LoadfromStream(const FileName: string; var Stream: TStream);
    procedure Clear;

    property ID: integer read FId write FId ;
    property Selected: Boolean write SetSelected;
    property FileCaption: string write SetFileCaption;
  published
    { Published declarations }
    property StyleName: string write SetStyleName;
  end;

procedure Register;

implementation

uses
  unit_PreviewMessages;

procedure Register;
begin
  RegisterComponents('ELN.Components', [TELNFilePreview]);
end;

{ eLabImagePanel }

procedure TELNFilePreview.Clear;
begin

end;

constructor TELNFilePreview.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

    //rzpPanel

  Width := 193;
  Height := 177;
  BorderOuter := fsFlatRounded;
  AlignWithMargins := True;

  BorderColor := $00E8E8E8;
  BorderWidth := 1;
  ParentBackground := True;

  //RzLabel1
  lblFileName := TRzLabel.Create(Self);

  //Preview
  Preview := TImage.Create(Self);

  //RzLabel1
  lblFileName.Parent := Self;
  lblFileName.Alignment := taCenter;
  lblFileName.Caption := '<noname>';
  lblFileName.Align := alBottom;

  //Preview
  Preview.Name := 'Preview';
  Preview.Parent := Self;
  Preview.AlignWithMargins := True;
  Preview.Align := alClient;
  Preview.AutoSize := True;
  Preview.Center := True;
  Preview.Proportional := True;
  Preview.Stretch := True;
  Preview.OnClick := FOnClick;
  Preview.OnDblClick := FOnDoubleClick;
  Preview.OnMouseUp := FOnMouseUp;

  lblFileName.OnClick := FOnClick;
  lblFileName.OnDblClick := FOnDoubleClick;
  lblFileName.OnMouseUp := FOnMouseUp;

  Self.OnClick := FOnClick;
  Self.OnDblClick := FOnDoubleClick;
  Self.OnMouseUp := FOnMouseUp;

  BorderColor := clBtnFace;
  BorderWidth := 1;

end;

destructor TELNFilePreview.Destroy;
begin
  FreeAndNil(lblFileName);
  FreeAndNil(Preview);
  inherited;
end;

procedure TELNFilePreview.LoadfromStream;
begin
  Stream.Position := 0;
  Preview.Picture.LoadFromStream(Stream);
end;

procedure TELNFilePreview.LoadImage(const FileName: string);
begin
  Preview.Picture := nil;
  Self.Repaint;
  Preview.Picture.LoadFromFile(FileName);
  FFileName := FileName;
end;

procedure TELNFilePreview.SetFileCaption(const Value: string);
begin
  lblFileName.Caption := Value;
end;

procedure TELNFilePreview.SetSelected(const Value: Boolean);
begin
  if Value then
  begin
    BorderColor := $002FA9FB;
    BorderWidth := 3;
    ParentBackground := False;
    Color := $00EEF6FC;
  end
  else begin
    BorderColor := clBtnFace;
    BorderWidth := 1;
    ParentBackground := False;
    Color := clBtnFace;
  end;
  Invalidate;
end;

procedure TELNFilePreview.SetStyleName(const Value: string);
begin
  inherited StyleName   := Value;
  lblFileName.StyleName := Value;
end;

procedure TELNFilePreview.FOnClick(Sender: TObject);
begin
  ImageClick(Self.ID);
end;

procedure TELNFilePreview.FOnDoubleClick(Sender: TObject);
begin
  ImageDBLClick(Self.ID);
end;

procedure TELNFilePreview.FOnMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  // The main form selects the file and opens the tree's file popup at the
  // cursor, so the gallery offers the same actions as the tree node.
  if Button = mbRight then
    ImageContextMenu(Self.ID);
end;

end.






