unit unit_DSRViewerPanel;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Mask, RzEdit, Vcl.Imaging.pngimage,
  Vcl.ExtCtrls, RzPanel, XMLDOC, Xml.XMLIntf, RzButton, RzLabel, RzCommon;

type
  TVariable = record
    Parent: Integer;
    Name, Value, Caption, U: string;
  end;

  TVariables = array of TVariable;

  TDSCViewerPanel = class(TRzPanel)
  private
    FXML: IXMLDocument;

    FBitmap: TBitmap;
    FTitle: TRzLabel;
    FScript : String;

    FGroups: array of TRzGroupbox;
    FEdits: array of TLabeledEdit;
    FVariables: TVariables;

    FEditsCount: Integer;

    XScale, YScale: single;

    procedure AddEdit(EditNode:IXmlNode; GroupID: Integer; var XOffset, YOffset: Integer);
    procedure BuildForm(const IgnoreScript: boolean = False);
    procedure AddGroup(GroupCaption: string);
    procedure Clear;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromString(Lines: string; IgnoreScript: Boolean = False);
  end;

implementation


procedure TDSCViewerPanel.AddEdit( EditNode:IXmlNode; GroupID: Integer; var XOffset, YOffset: Integer);
var
  CaptionWidth : integer;
  EditCaption: string;
begin
  SetLength(FEdits, FEditsCount + 1);
  SetLength(FVariables, FEditsCount + 1);
  FEdits[FEditsCount] := TLabeledEdit.Create(Self);

  FVariables[FEditsCount].Name := EditNode.NodeName;
  FVariables[FEditsCount].Caption := EditNode.Attributes['caption'];
  FVariables[FEditsCount].Value := EditNode.NodeValue;
  FVariables[FEditsCount].U := EditNode.Attributes['unit'];
  FVariables[FEditsCount].Parent := GroupID;


  EditCaption := Format('%s (%s)',[StringReplace(FVariables[FEditsCount].Caption, '_', ' ', [rfReplaceAll]), FVariables[FEditsCount].U]);

  FBitmap.Canvas.Font.Size := 8;
  FBitmap.Canvas.Font.Style := [fsBold];
  CaptionWidth := FBitmap.Canvas.TextWidth(EditCaption) + Round(8 * XScale);
  if CaptionWidth < Round(70 * XScale) then CaptionWidth := Round(70 * XScale);

  with FEdits[FEditsCount] do
  begin
    Tag := FEditsCount;
    Hint := FVariables[FEditsCount].Name;
    ShowHint := True;
    Parent := FGroups[GroupID];
    ParentFont := False;
    Font.Size := 8;
    Font.Style := [];
    Top:= Round(YOffset);
    Left := Round(XOffset);
    Width := CaptionWidth;
    EditLabel.Font.Size := 8;
    EditLabel.Font.Style := [fsBold];
    EditLabel.Caption := EditCaption;
    Text := FVariables[FEditsCount].Value;
    XOffset := XOffset + Width + Round(16 * XScale);
  end;

end;

procedure TDSCViewerPanel.Clear;
var
  i: Integer;
begin

  for i := 0 to High(FEdits) do
    FEdits[i].Free;

  for i := 0 to High(FGroups) do
    FGroups[i].Free;

  SetLength(FVariables, 0);
  SetLength(FEdits, 0);
  SetLength(FGroups, 0);

  FEditsCount := 0;
end;

constructor TDSCViewerPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  BorderOuter := fsFlatRounded;
  XScale := Screen.PixelsPerInch / 96;
  YScale := XScale;

  ShowCaption := False;

  FBitmap := TBitmap.Create;
  FXML := TXMLDocument.Create(nil);

  FTitle := TRzLabel.Create(Self);
  with FTitle do
  begin
    Parent := Self;
    AlignWithMargins := True;
    Align := alTop;
    Font.Size := 5;
    Font.Style := [fsBold];
    Alignment := taCenter;
  end;
end;


procedure TDSCViewerPanel.AddGroup(GroupCaption: string);
var
  Index: Integer;
begin
  Index := Length(FGroups);
  SetLength(FGroups, Index + 1);

  FGroups[Index] := TRzGroupBox.Create(Self);
  with FGroups[Index] do
  begin
    Caption := StringReplace(GroupCaption, '_', ' ', [rfReplaceAll]);
    Parent := Self;
    Top := 10;
    Align := alTop;
    AlignWithMargins := True;
    Margins.Top := 0;
    Margins.Bottom := 0;
    Height := Round(70 * YScale);
    Font.Size := 10;
    Font.Style := [fsBold];
    GroupStyle := gsBanner;
    Tag := 900 + Index;
  end;
end;

procedure TDSCViewerPanel.BuildForm;
var
    Root, GroupNode, EditNode:IXmlNode;
    i, j: Integer;
    XOffset, YOffset : integer;
begin
  Self.Visible := False;
  try
    FXML.Active := True;
    Root := FXML.DocumentElement;

    GroupNode := Root.ChildNodes.Nodes[0];
    FTitle.Caption := GroupNode.ChildNodes['Title'].NodeValue;

    for i := 1 to Root.ChildNodes.Count - 1 do
    begin
      GroupNode := Root.ChildNodes.Nodes[i];

      if GroupNode.NodeName = 'Script' then
      begin
        FScript := GroupNode.NodeValue;
        if Not IgnoreScript then
          GroupNode.NodeValue := '...';
        Continue;
      end;

      AddGroup(GroupNode.NodeName);

      XOffSet := Round(10 * XScale); YOffset := round(40 * YScale);
      for j := 0 to GroupNode.ChildNodes.Count - 1 do
      begin
        EditNode := GroupNode.ChildNodes[j];

        if EditNode.NodeName = 'hr' then
        begin
          XOffSet := Round(10 * XScale);
          Inc(YOffset, Round(40 * YScale));
          FGroups[i - 1].Height := FGroups[i - 1].Height + Round(42 * YScale);
          Continue;
        end;

        AddEdit(EditNode, i - 1, XOffset, YOffset);
        inc(FEditsCount);
      end;
    end;

    for I := High(FGroups) downto 0 do
      FGroups[i].Top := 10;

  finally
    Self.Visible := True;
    Self.Update;
  end;
end;

procedure TDSCViewerPanel.LoadFromString(Lines: string; IgnoreScript: Boolean = False);
begin
  Clear;
  FXML.ParseOptions := FXML.ParseOptions - [poResolveExternals];
  FXML.LoadFromXML(Lines);
  BuildForm(IgnoreScript);
end;

procedure TDSCViewerPanel.LoadFromFile(const FileName: string);
begin
  Clear;
  // Strip poResolveExternals — DSR forms never use external DTDs/entities;
  // leaving this enabled allows XXE file exfiltration via metadata rendering.
  FXML.ParseOptions := FXML.ParseOptions - [poResolveExternals];
  FXML.LoadFromFile(FileName);
  BuildForm;
end;

destructor TDSCViewerPanel.Destroy;
begin
  Clear;
  FreeAndNil(FBitmap);
  FreeAndNil(FTitle);
  inherited Destroy;
end;

end.
