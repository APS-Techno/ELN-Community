unit unit_ProtocolPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms,
  unit_ELNPluginCore,
  frame_ProtocolViewer;

type

  TELNProtocolViewerPlugin = class(TELNBaseViewerPlugin, IProtocolEditor)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    procedure DisplayText(const Caption, Text: string); override;

    { IProtocolEditor }
    procedure LoadTemplate(const TemplateHtml: string; const FormData: string);
    procedure LoadFreeText(const FormData: string);
    function  GetFormData: string;
    procedure SetReadOnly(Value: Boolean);
    function  GetReadOnly: Boolean;
    procedure PrepareForReparent;
    procedure SetOnDirty(const AHandler: TNotifyEvent);
  end;

  procedure Register;
  procedure UnRegister;

implementation

var
  APlugin: TELNProtocolViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNProtocolViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNProtocolViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeProtocolViewer.Create(nil);
end;

function TELNProtocolViewerPlugin.GetParams: TPluginParams;
begin
  Result.PType   := ptText;
  Result.Ext     := '.protocol';
  Result.IntOpen := True;
end;

procedure TELNProtocolViewerPlugin.DisplayText(const Caption, Text: string);
var
  Parts: TArray<string>;
  ProtocolType, Status, CreatedDate, ModifiedDate, FormData, TemplateHtml: string;
  EquipModel, EquipManufacturer, EquipLocation: string;
begin
  // Text is encoded as: ProtocolType#1Status#1CreatedDate#1ModifiedDate#1FormData#1TemplateHtml
  //                      #1EquipModel#1EquipManufacturer#1EquipLocation
  Parts := Text.Split([#1]);

  if Length(Parts) >= 1 then ProtocolType      := Parts[0] else ProtocolType := '';
  if Length(Parts) >= 2 then Status            := Parts[1] else Status := '';
  if Length(Parts) >= 3 then CreatedDate       := Parts[2] else CreatedDate := '';
  if Length(Parts) >= 4 then ModifiedDate      := Parts[3] else ModifiedDate := '';
  if Length(Parts) >= 5 then FormData          := Parts[4] else FormData := '';
  if Length(Parts) >= 6 then TemplateHtml      := Parts[5] else TemplateHtml := '';
  if Length(Parts) >= 7 then EquipModel        := Parts[6] else EquipModel := '';
  if Length(Parts) >= 8 then EquipManufacturer := Parts[7] else EquipManufacturer := '';
  if Length(Parts) >= 9 then EquipLocation     := Parts[8] else EquipLocation := '';

  if TemplateHtml <> '' then
    TframeProtocolViewer(FFrame).ShowProtocolWithTemplate(Caption, ProtocolType, Status, CreatedDate,
      ModifiedDate, FormData, TemplateHtml, EquipModel, EquipManufacturer, EquipLocation)
  else
    TframeProtocolViewer(FFrame).ShowProtocol(Caption, ProtocolType, Status, CreatedDate,
      ModifiedDate, FormData, EquipModel, EquipManufacturer, EquipLocation);
end;

{ IProtocolEditor }

procedure TELNProtocolViewerPlugin.LoadTemplate(const TemplateHtml: string;
  const FormData: string);
begin
  TframeProtocolViewer(FFrame).LoadTemplate(TemplateHtml, FormData);
end;

procedure TELNProtocolViewerPlugin.LoadFreeText(const FormData: string);
begin
  TframeProtocolViewer(FFrame).LoadFreeText(FormData);
end;

function TELNProtocolViewerPlugin.GetFormData: string;
begin
  Result := TframeProtocolViewer(FFrame).GetFormData;
end;

procedure TELNProtocolViewerPlugin.SetReadOnly(Value: Boolean);
begin
  TframeProtocolViewer(FFrame).ReadOnly := Value;
end;

function TELNProtocolViewerPlugin.GetReadOnly: Boolean;
begin
  Result := TframeProtocolViewer(FFrame).ReadOnly;
end;

procedure TELNProtocolViewerPlugin.PrepareForReparent;
begin
  TframeProtocolViewer(FFrame).PrepareForReparent;
end;

procedure TELNProtocolViewerPlugin.SetOnDirty(const AHandler: TNotifyEvent);
begin
  TframeProtocolViewer(FFrame).OnDirty := AHandler;
end;

end.
