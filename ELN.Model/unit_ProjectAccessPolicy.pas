unit unit_ProjectAccessPolicy;

interface

uses
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  unit_User,
  unit_Project,
  unit_Hypothesis;

type
  TProjectWriteVerdict = (
    pwAllowed, pwNoUser, pwUserArchived, pwRoleCannotWrite,
    pwProjectNotFound, pwProjectArchived, pwNoPermission);

  TProjectAccess = (paOwner, paReadWrite, paReadOnly);

  TGateEligibility = class abstract
  protected
    FManager: TObjectManager;
    FUser: TUser;
  public
    constructor Create(AManager: TObjectManager; AUser: TUser);
    function CanPassGate(AProjectId, AAuthorId: Integer; AGate: THypothesisGate;
      out AReason: string): Boolean; virtual; abstract;
    function PolicyInvalid: Boolean; virtual; abstract;
    function PolicyError: string; virtual; abstract;
    property Manager: TObjectManager read FManager;
    property User: TUser read FUser;
  end;

  IProjectAccessPolicy = interface
    ['{A1DF7329-7750-4889-B94C-9E757AE35F86}']
    function CheckWrite(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): TProjectWriteVerdict;
    function CanWrite(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): Boolean;
    function CanRead(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): Boolean;
    function RemoveProject(AManager: TObjectManager; AUser: TUser;
      AProject: TProject): Boolean;
    function CanPassGate(AManager: TObjectManager; AUser: TUser;
      AHypothesis: THypothesis; AGate: THypothesisGate;
      out AReason: string): Boolean;
    function CreateGateEligibility(AManager: TObjectManager;
      AUser: TUser): TGateEligibility;
    function ProjectList(AManager: TObjectManager; AUser: TUser): TList<TProject>;
    function GetProjectAccess(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): TProjectAccess;
    function ProjectDataSetCriteria(AManager: TObjectManager;
      AUser: TUser): TCriteria<TProject>;
    function VisibleProjectIds(AManager: TObjectManager;
      AUser: TUser): TDictionary<Integer, Boolean>;
    function CanReviewProtocol(AManager: TObjectManager; AUser: TUser;
      AProjectId, AAuthorId: Integer): Boolean;
    function CanBrowseAllProjects(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanCreateProjects(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanCreateTags(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanEditReferenceData(AManager: TObjectManager; AUser: TUser): Boolean;
  end;

implementation

constructor TGateEligibility.Create(AManager: TObjectManager; AUser: TUser);
begin
  inherited Create;
  FManager := AManager;
  FUser := AUser;
end;

end.
