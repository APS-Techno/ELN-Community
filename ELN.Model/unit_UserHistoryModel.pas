unit unit_UserHistoryModel;

interface

uses
  SysUtils,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  unit_UsersHistory,
  unit_Types,
  unit_TELNModel,
  unit_ELNDB_Dictionary;

type

  TUserHistoryModel = class(TELNModel)
    private
      FRec : TUsersHistory;
      FOwnsRec : Boolean;

      Dic: TUsersHistoryDictionary;
      FManager: TObjectManager;
    public
      constructor Create(Manager: TObjectManager);
      destructor Destroy; override;
      procedure OpenDataSet; override;

      procedure SaveHistory;
      procedure LoadHistory(const Id: integer);
      property UserRecord: TUsersHistory read FRec write FRec;
  end;


implementation

uses
  System.Generics.Collections;


constructor TUserHistoryModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  Dic := TUsersHistoryDictionary.Create;
  FManager := Manager;
  FRec := TUsersHistory.Create;
  FOwnsRec := True;
end;

destructor TUserHistoryModel.Destroy;
begin
  // Only free FRec if we still own the constructor-created placeholder. Once
  // LoadHistory adopts a manager-owned entity, the ObjectManager frees it —
  // freeing it here too would be a double-free.
  if FOwnsRec then
    FreeAndNil(FRec);
  FreeAndNil(Dic);
  inherited;
end;

procedure TUserHistoryModel.LoadHistory(const Id: integer);
var
  Results : TList<TUsersHistory>;
begin
  Results := FManager.Find<TUsersHistory>.Where(Dic.Userid = id).List;
  try
    if Results.Count > 0 then
    begin
      // Adopt the manager-owned row. Free the constructor placeholder we no
      // longer need and stop owning FRec so the destructor won't double-free an
      // object the ObjectManager already frees. When FRec was saved earlier,
      // the identity map hands back the SAME instance - never free that.
      if FOwnsRec and (FRec <> Results[0]) then
        FreeAndNil(FRec);
      FRec := Results[0];
      FOwnsRec := False;
    end
    else
      FRec.UserID := Id;
  finally
    Results.Free;
  end;
end;

procedure TUserHistoryModel.OpenDataSet;
begin
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDataSet.SetSourceCriteria(FManager.Find<TUsersHistory>.Where(Dic.Userid = 2));
  FDataSet.Open;
end;

procedure TUserHistoryModel.SaveHistory;
begin
  FManager.SaveOrUpdate(FRec);
  FManager.Flush;
  // SaveOrUpdate transfers ownership of FRec to the ObjectManager - stop
  // owning it so neither LoadHistory nor the destructor frees a
  // manager-owned entity.
  FOwnsRec := False;
end;

end.
