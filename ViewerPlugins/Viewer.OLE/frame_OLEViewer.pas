unit frame_OLEViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.OleCtnrs;

type
  TframeOLEViewer = class(TFrame)
  private
    FOleContainer: TOleContainer;
    procedure EnsureContainer;
  public
    procedure LoadOLEFile(const AFileName: string);
  end;

implementation

{$R *.dfm}

procedure TframeOLEViewer.EnsureContainer;
begin
  if FOleContainer <> nil then
    Exit;

  FOleContainer := TOleContainer.Create(Self);
  FOleContainer.Parent := Self;
  FOleContainer.Align := alClient;
  FOleContainer.AllowInPlace := False;
  FOleContainer.AutoActivate := aaGetFocus;
  FOleContainer.BorderStyle := bsNone;
end;

procedure TframeOLEViewer.LoadOLEFile(const AFileName: string);
begin
  EnsureContainer;

  if FOleContainer.State <> osEmpty then
    FOleContainer.DestroyObject;

  FOleContainer.CreateObjectFromFile(AFileName, False);
end;

end.
