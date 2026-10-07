unit unit_ELNThumbnailList;

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  unit_ELNFilePreview;

type
  TELNThumbnailList = class(TScrollBox)
  private
    { Private declarations }
    Images: array of TELNFilePreview;
    FLastSelected: Integer;
    FOwnerID: Integer;

    procedure Resize(Sender: TObject); reintroduce;
    procedure CreateImage(const Index, ID: Integer);
  protected
    { Protected declarations }
  public
    { Public declarations }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure AddEmpty(const ID: Integer; FileName: string);
    procedure Add(const ID: Integer; FileCaption, FileName: string);
    procedure AddFromStream(const FileName: string; ID: Integer; var Stream: TStream);
    procedure Update(const ID: Integer; const FileName: string); reintroduce;
    procedure UpdateFromStream(const ID: Integer; Stream: TStream);
    procedure Delete(const ID: Integer);
    procedure Clear;
    procedure Repaint; override;

    procedure Select(const ID: Integer);
    procedure SelectLast;
    procedure SetLabel(const ID: Integer; Comment, FileName: string);
    property OwnerID: Integer read FOwnerID write FOwnerID;
  published
    { Published declarations }
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('ELN.Components', [TELNThumbnailList]);
end;

{ TELNThumbnailList }

procedure TELNThumbnailList.CreateImage(const Index, ID: Integer);
begin
  Images[Index]        := TELNFilePreview.Create(Self);
  Images[Index].Parent := Self;
  Images[Index].ID     := ID;
  Images[Index].Left   := Self.ClientHeight + 200 * Index;
  Images[Index].Width  := Self.ClientHeight * 4 div 3;
  Images[Index].Align  := alLeft;
  Images[Index].StyleName := Self.StyleName;

  if Index = 0 then Select(ID);
end;

procedure TELNThumbnailList.Add;
var
  i: Integer;
begin
  i := Length(Images);
  SetLength(Images, i + 1);
  CreateImage(i, ID);
  Images[i].FileCaption := FileCaption;
  if FileExists(FileName) then
    Images[i].LoadImage(FileName);
end;

procedure TELNThumbnailList.AddEmpty;
var
  i: Integer;
begin
  i := Length(Images);
  SetLength(Images, i + 1);
  CreateImage(i, ID);
end;

procedure TELNThumbnailList.AddFromStream(const FileName: string; ID: Integer;
  var Stream: TStream);
var
  i: Integer;
begin
  i := Length(Images);
  SetLength(Images, i + 1);
  CreateImage(i, ID);
  Images[i].LoadfromStream(FileName, Stream);
end;

procedure TELNThumbnailList.Clear;
var
  i: Integer;
begin
  inherited ;
  for I := 0 to High(Images) do
    FreeAndNil(Images[i]);

  SetLength(Images, 0);
  FLastSelected := 0;
end;

constructor TELNThumbnailList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  //scrlPanel
  Name := 'scrlPanel';
  Width := 649;
  Height := 209;
  VertScrollBar.Visible := False;
  BorderStyle := bsNone;

  Self.OnResize := Resize;
end;

procedure TELNThumbnailList.Delete(const ID: Integer);
begin

end;

destructor TELNThumbnailList.Destroy;
begin
  Clear;
  inherited;
end;

procedure TELNThumbnailList.Repaint;
var
  i: Integer;
begin
  inherited Repaint;
  for I := 0 to High(Images) do
    Images[i].Repaint;
end;

procedure TELNThumbnailList.Resize(Sender: TObject);
var
  i: Integer;
begin
  for I := 0 to High(Images) do
    if Assigned(Images[i]) then
      Images[i].Width := Images[i].Height * 4 div 3;
end;

procedure TELNThumbnailList.Select(const ID: Integer);
var
  i: Integer;
begin
  if Length(Images) = 0 then Exit;

  Images[FLastSelected].Selected := False;
  for I := 0 to High(Images) do
    if (Images[i].ID = ID) then
    begin
      Images[i].Selected  := True;
      FLastSelected := i;
      Break;
    end;
end;

procedure TELNThumbnailList.SelectLast;
begin
  if Length(Images) = 0 then Exit;

  Images[FLastSelected].Selected := False;
  Images[High(Images)].Selected  := True;
  FLastSelected := High(Images);
end;

procedure TELNThumbnailList.SetLabel(const ID: Integer; Comment,
  FileName: string);
var
  i: Integer;
begin
  for I := 0 to High(Images) do
    if Images[i].ID = ID then
    begin
      Images[i].FileCaption    := FileName;
      Break;
    end;

end;

procedure TELNThumbnailList.Update(const ID: Integer; const FileName: string);
var
  i: Integer;
begin
  for I := 0 to High(Images) do
    if Images[i].ID = ID then
    begin
      if FileExists(FileName) then
        Images[i].LoadImage(FileName);
      Break;
    end;
end;

procedure TELNThumbnailList.UpdateFromStream(const ID: Integer; Stream: TStream);
var
  i: Integer;
begin
  if not Assigned(Stream) then Exit;
  for I := 0 to High(Images) do
    if Images[i].ID = ID then
    begin
      Images[i].LoadfromStream('', Stream);
      Break;
    end;
end;

end.




