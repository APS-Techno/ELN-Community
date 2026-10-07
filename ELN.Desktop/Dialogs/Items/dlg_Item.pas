{*
  dlg_Item.pas — Item creation/editing dialog (ShowItemDialog)

  Simplified dialog for Item-level entries only (Specimen, Model, Other, Wiki).
  For action-oriented items (Proc/Action levels), use dlg_Action instead.

  Entry point
  -----------
  ShowItemDialog(Mode, Item)
    Mode — dmNew: create; dmEdit: update existing TItem
    Item — var parameter; caller passes in a TItem to populate or read back
*}
unit dlg_Item;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, RzRadGrp,
  RzEdit, RzLabel, RzButton, Vcl.ExtCtrls, RzPanel, Vcl.ValEdit,
  unit_DlgConstants, unit_ItemTypes, unit_Item, Vcl.Mask, Vcl.Grids;

type
  TdlgItem = class(TForm)
    RzPanel2: TRzPanel;
    btnSave: TRzBitBtn;
    btnCancel: TRzBitBtn;
    RzPanel1: TRzPanel;
    RzLabel1: TRzLabel;
    RzLabel2: TRzLabel;
    rgItemType: TRzRadioGroup;
    edTitle: TRzEdit;
    edComment: TRzEdit;
    lblProperties: TRzLabel;
    btnAddProp: TRzButton;
    btnRemoveProp: TRzButton;
    vleProps: TValueListEditor;
    procedure btnAddPropClick(Sender: TObject);
    procedure btnRemovePropClick(Sender: TObject);
  private
    procedure PopulateItemTypes;
  public
    { Public declarations }
  end;

  function ShowItemDialog(const Mode: TDlgMode; var Item: TItem): boolean;

implementation

uses
  System.Rtti,
  System.JSON,
  unit_DialogHelper;

{$R *.dfm}

function ShowItemDialog(const Mode: TDlgMode; var Item: TItem): boolean;
var
  ItemRef: TItem;
begin
  ItemRef := Item;

  Result := ExecuteDialog(TdlgItem,
    // Setup procedure
    procedure(Dialog: TForm)
    var
      D: TdlgItem;
      i: Integer;
      JSONObj: TJSONObject;
    begin
      D := TdlgItem(Dialog);
      D.PopulateItemTypes;

      case Mode of
        dmNew: begin
                 D.Caption := 'Add new item';
                 D.rgItemType.ItemIndex := 0;
                 D.edTitle.Text := '';
                 D.edComment.Text := '';
               end;
        dmEdit: begin
                  D.Caption := 'Edit item';

                  // Set item type
                  for i := 0 to D.rgItemType.Items.Count - 1 do
                    if TItemType(Integer(D.rgItemType.Items.Objects[i])) = ItemRef.Type_ then
                    begin
                      D.rgItemType.ItemIndex := i;
                      Break;
                    end;

                  D.edTitle.Text := ItemRef.Title;
                  D.edComment.Text := ItemRef.Description;

                  // Load Properties JSON into key-value grid
                  if ItemRef.Properties <> '' then
                  begin
                    JSONObj := TJSONObject.ParseJSONValue(ItemRef.Properties) as TJSONObject;
                    if Assigned(JSONObj) then
                    try
                      for i := 0 to JSONObj.Count - 1 do
                        D.vleProps.InsertRow(
                          JSONObj.Pairs[i].JsonString.Value,
                          JSONObj.Pairs[i].JsonValue.Value, True);
                    finally
                      JSONObj.Free;
                    end;
                  end;
                end;
      end;
    end,
    // Extract procedure
    procedure(Dialog: TForm)
    var
      D: TdlgItem;
      JSONObj: TJSONObject;
      i: Integer;
      Key: string;
    begin
      D := TdlgItem(Dialog);
      ItemRef.Level := TItemLevel.Item;
      ItemRef.Type_ := TItemType(Integer(D.rgItemType.Items.Objects[D.rgItemType.ItemIndex]));
      ItemRef.Title := D.edTitle.Text;
      ItemRef.Description := D.edComment.Text;
      ItemRef.ActionType := nil;

      // Serialize Properties from key-value grid to JSON
      JSONObj := TJSONObject.Create;
      try
        for i := 0 to D.vleProps.Strings.Count - 1 do
        begin
          Key := D.vleProps.Strings.Names[i];
          if Key <> '' then
            JSONObj.AddPair(Key, D.vleProps.Strings.ValueFromIndex[i]);
        end;
        if JSONObj.Count > 0 then
          ItemRef.Properties := JSONObj.ToString
        else
          ItemRef.Properties := '';
      finally
        JSONObj.Free;
      end;
    end
  );
end;

{ TdlgItem }

procedure TdlgItem.PopulateItemTypes;
var
  ItemType: TItemType;
begin
  rgItemType.Items.Clear;
  for ItemType := Low(TItemType) to High(TItemType) do
    if ItemType in [TItemType.Specimen, TItemType.Model, TItemType.Wiki, TItemType.Other] then
      rgItemType.Items.AddObject(TRttiEnumerationType.GetName(ItemType), TObject(Ord(ItemType)));
end;

procedure TdlgItem.btnAddPropClick(Sender: TObject);
begin
  vleProps.InsertRow('', '', True);
end;

procedure TdlgItem.btnRemovePropClick(Sender: TObject);
begin
  if (vleProps.Strings.Count > 0) and (vleProps.Row >= 1) then
    vleProps.DeleteRow(vleProps.Row);
end;

end.
