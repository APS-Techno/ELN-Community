unit dlg_AuditLog;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls,
  unit_AuditLog;

type
  TdlgAuditLog = class(TForm)
    pnlTop: TPanel;
    lblFrom: TLabel;
    dtpFrom: TDateTimePicker;
    lblTo: TLabel;
    dtpTo: TDateTimePicker;
    lblEntity: TLabel;
    cmbEntityType: TComboBox;
    lblOp: TLabel;
    cmbOperation: TComboBox;
    lblUser: TLabel;
    cmbUser: TComboBox;
    btnRefresh: TButton;
    ListView: TListView;
    pnlBottom: TPanel;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
  private
    FUserIds: TList<Integer>;
    procedure PopulateFilters;
    procedure PopulateUsers;
    procedure RefreshList;
  public
    class procedure ShowLog;
  end;

implementation

uses
  unit_DataModel,
  unit_User,
  unit_TimeHelper;

{$R *.dfm}


class procedure TdlgAuditLog.ShowLog;
var
  Dialog: TdlgAuditLog;
begin
  Dialog := TdlgAuditLog.Create(Application);
  try
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

procedure TdlgAuditLog.FormCreate(Sender: TObject);
begin
  FUserIds := TList<Integer>.Create;
  dtpFrom.Date := Date - 30;
  dtpTo.Date := Date;
  PopulateFilters;
  PopulateUsers;
  RefreshList;
end;

procedure TdlgAuditLog.FormDestroy(Sender: TObject);
begin
  FUserIds.Free;
end;

procedure TdlgAuditLog.PopulateFilters;
var
  ET: TAuditEntityType;
  Op: TAuditOperation;
begin
  cmbEntityType.Items.BeginUpdate;
  try
    cmbEntityType.Items.Clear;
    cmbEntityType.Items.Add('(All)');
    for ET := Low(TAuditEntityType) to High(TAuditEntityType) do
      cmbEntityType.Items.Add(AuditEntityTypeNames[ET]);
    cmbEntityType.ItemIndex := 0;
  finally
    cmbEntityType.Items.EndUpdate;
  end;

  cmbOperation.Items.BeginUpdate;
  try
    cmbOperation.Items.Clear;
    cmbOperation.Items.Add('(All)');
    for Op := Low(TAuditOperation) to High(TAuditOperation) do
      cmbOperation.Items.Add(AuditOperationNames[Op]);
    cmbOperation.ItemIndex := 0;
  finally
    cmbOperation.Items.EndUpdate;
  end;
end;

procedure TdlgAuditLog.PopulateUsers;
var
  Users: TList<TUser>;
  User: TUser;
begin
  FUserIds.Clear;
  FUserIds.Add(0); 

  cmbUser.Items.BeginUpdate;
  try
    cmbUser.Items.Clear;
    cmbUser.Items.Add('(All)');
    Users := Model.Authors.List;
    try
      for User in Users do
      begin
        cmbUser.Items.Add(User.DisplayName);
        FUserIds.Add(User.Id);
      end;
    finally
      Users.Free;
    end;
    cmbUser.ItemIndex := 0;
  finally
    cmbUser.Items.EndUpdate;
  end;
end;

procedure TdlgAuditLog.RefreshList;
var
  Logs: TAuditLogs;
  Entry: TAuditLog;
  ListItem: TListItem;
  EntityTypeFilter, OperationFilter, UserFilter: Integer;
  User: TUser;
begin
  EntityTypeFilter := cmbEntityType.ItemIndex - 1; 
  OperationFilter := cmbOperation.ItemIndex - 1;

  if cmbUser.ItemIndex > 0 then
    UserFilter := FUserIds[cmbUser.ItemIndex]
  else
    UserFilter := 0;

  ListView.Items.BeginUpdate;
  try
    ListView.Items.Clear;

    Logs := Model.AuditLog.GetLogs(dtpFrom.Date, dtpTo.Date,
      EntityTypeFilter, OperationFilter, UserFilter);
    try
      for Entry in Logs do
      begin
        ListItem := ListView.Items.Add;
        ListItem.Caption := FormatDateTime('yyyy-mm-dd hh:nn:ss', FromUTC(Entry.Timestamp));
        ListItem.SubItems.Add(AuditEntityTypeNames[Entry.EntityType]);
        ListItem.SubItems.Add(IntToStr(Entry.EntityId));
        ListItem.SubItems.Add(AuditOperationNames[Entry.Operation]);

        User := Model.Authors.GetUser(Entry.UserId);
        if Assigned(User) then
          ListItem.SubItems.Add(User.DisplayName)
        else
          ListItem.SubItems.Add('User #' + IntToStr(Entry.UserId));

        ListItem.SubItems.Add(Entry.Description);
      end;
    finally
      Logs.Free;
    end;
  finally
    ListView.Items.EndUpdate;
  end;
end;

procedure TdlgAuditLog.btnRefreshClick(Sender: TObject);
begin
  RefreshList;
end;

end.
