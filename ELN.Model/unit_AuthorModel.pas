unit unit_AuthorModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_User;

type
  TUserList = TList<TUser>;

  TAuthorModel = class
  private
    function GetUserList: TUserList;
    function GetActiveUserList: TUserList;
    function GetDisplayName: string;
  protected
    FManager: TObjectManager;
    FUser: TUser;
  public
    constructor Create(Manager: TObjectManager; PrincipalId: Integer);
    property CurrentUser: TUser read FUser;
    property List: TUserList read GetUserList;
    property ActiveList: TUserList read GetActiveUserList;
    property DisplayName: string read GetDisplayName;
    function GetUser(const ID: Integer): TUser;
    procedure SaveCurrentProfile(const AFirstName, ALastName, AEmail: string);
    function ChangePassword(const ACurrentPassword, ANewPassword: string): Boolean;
  end;

implementation

uses
  Aurelius.Criteria.Base, Aurelius.Criteria.Linq,
  BCrypt, unit_TimeHelper;

constructor TAuthorModel.Create(Manager: TObjectManager; PrincipalId: Integer);
begin
  inherited Create;
  FManager := Manager;
  if PrincipalId > 0 then
    FUser := GetUser(PrincipalId);
end;

function TAuthorModel.GetUser(const ID: Integer): TUser;
begin
  Result := FManager.Find<TUser>(ID);
end;

function TAuthorModel.GetUserList: TUserList;
begin
  Result := FManager.Find<TUser>.OrderBy('SortOrder').OrderBy('ID').List;
end;

function TAuthorModel.GetActiveUserList: TUserList;
begin
  Result := FManager.Find<TUser>.Where(Linq['IsArchived'] = False)
    .OrderBy('SortOrder').OrderBy('ID').List;
end;

function TAuthorModel.GetDisplayName: string;
begin
  if Assigned(FUser) then
    Result := FUser.FirstName + ' ' + FUser.LastName
  else
    Result := 'nobody';
end;

procedure TAuthorModel.SaveCurrentProfile(const AFirstName, ALastName, AEmail: string);
begin
  if not Assigned(FUser) then Exit;
  FUser.FirstName := AFirstName;
  FUser.LastName := ALastName;
  FUser.Email := AEmail;
  FUser.ModifiedDate := UTCNow;
  FUser.ModifiedBy := FUser.Id;
  FManager.Flush;
end;

function TAuthorModel.ChangePassword(const ACurrentPassword, ANewPassword: string): Boolean;
var
  RehashNeeded: Boolean;
begin
  Result := False;
  if not Assigned(FUser) then Exit;
  if not TBCrypt.CheckPassword(ACurrentPassword, FUser.Password, RehashNeeded) then
    Exit;
  FUser.Password := TBCrypt.HashPassword(ANewPassword);
  FUser.ModifiedDate := UTCNow;
  FUser.ModifiedBy := FUser.Id;
  FManager.Flush;
  Result := True;
end;

end.
