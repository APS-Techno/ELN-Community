unit unit_ELNDB_Dictionary;

interface

uses
  SysUtils,
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Blob,
  Aurelius.Types.DynamicProperties,
  Aurelius.Types.Nullable,
  Aurelius.Types.Proxy,
  Aurelius.Dictionary.Classes,
  Aurelius.Linq;

type
  TLabEntryDictionary = class;
  TProtocolDictionary = class;
  TActionTypeDictionary = class;
  TValueTypeDictionary = class;
  TValueDictionary = class;
  TItemDictionary = class;
  TEquipmentDictionary = class;
  TEquipmentTypeDictionary = class;
  TFileDictionary = class;
  TFileTypeDictionary = class;
  TFileTypeLinkDictionary = class;
  TFolderDictionary = class;
  TProjectDictionary = class;
  TProjectPermissionDictionary = class;
  TUserDictionary = class;
  TUserRoleDictionary = class;
  TTemplateDictionary = class;
  TUsersHistoryDictionary = class;
  TProtocolStatusChangeDictionary = class;
  TAuditLogDictionary = class;
  TSignatureDictionary = class;
  TFavoriteDictionary = class;
  TTagDictionary = class;
  TItemTagDictionary = class;
  TCommentDictionary = class;
  TExperimentTemplateDictionary = class;
  TItemLinkDictionary = class;
  TViewerStateDictionary = class;

  ITemplateDictionary = interface;
  ILabEntryDictionary = interface;
  IProtocolDictionary = interface;
  IActionTypeDictionary = interface;
  IValueTypeDictionary = interface;
  IValueDictionary = interface;
  IItemDictionary = interface;
  IEquipmentDictionary = interface;
  IEquipmentTypeDictionary = interface;
  IFileDictionary = interface;
  IFileTypeDictionary = interface;
  IFileTypeLinkDictionary = interface;
  IFolderDictionary = interface;
  IProjectDictionary = interface;
  IProjectPermissionDictionary = interface;
  IUserDictionary = interface;
  IUserRoleDictionary = interface;
  IUsersHistoryDictionary = interface;
  IProtocolStatusChangeDictionary = interface;
  IAuditLogDictionary = interface;
  ISignatureDictionary = interface;
  IFavoriteDictionary = interface;
  ITagDictionary = interface;
  IItemTagDictionary = interface;
  ICommentDictionary = interface;
  IExperimentTemplateDictionary = interface;
  IItemLinkDictionary = interface;

  ITemplateDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Name: TLinqProjection;
    function Description: TLinqProjection;
    function Category: TLinqProjection;
    function IsActive: TLinqProjection;
    function FormSchema: TLinqProjection;
    function Version: TLinqProjection;
    function ParentId: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
  end;

  ILabEntryDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Title: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  IProtocolDictionary = interface(ILabEntryDictionary)
    function TemplateId: TLinqProjection;
    function FormData: TLinqProjection;
    function ProtocolType: TLinqProjection;
    function ValidationStatus: TLinqProjection;
  end;

  IActionTypeDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Kind: TLinqProjection;
    function ItemType: TLinqProjection;
    function Title: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Equipmenttypeid: IEquipmentTypeDictionary;
  end;

  IValueTypeDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Title: TLinqProjection;
    function Units: TLinqProjection;
    function CatID: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  IValueDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Typeid: IValueTypeDictionary;
    function RecType: TLinqProjection;
    function Value: TLinqProjection;
    function Tol: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  IItemDictionary = interface(IAureliusEntityDictionary)
    function ID: TLinqProjection;
    function ProjectID: TLinqProjection;
    function FolderID: TLinqProjection;
    function Level: TLinqProjection;
    function Type_: TLinqProjection;
    function Title: TLinqProjection;
    function Description: TLinqProjection;
    function ParentID:  TLinqProjection;
    function ActionType: IActionTypeDictionary;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Expanded: TLinqProjection;
    function SortOrder: TLinqProjection;
    function IsDeleted: TLinqProjection;
    function DeletedDate: TLinqProjection;
    function DeletedBy: TLinqProjection;
  end;

  IEquipmentDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Model: TLinqProjection;
    function Manufacturer: TLinqProjection;
    function Location: TLinqProjection;
    function BookingUrl: TLinqProjection;
    function InfoUrl: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Equipmenttypeid: IEquipmentTypeDictionary;
  end;

  IEquipmentTypeDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Type_: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  IFileDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Description: TLinqProjection;
    function Title: TLinqProjection;
    function Hash: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Typeid: IFileTypeDictionary;
    function Itemid: IItemDictionary;
  end;

  IFileTypeDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Ext: TLinqProjection;
    function Icon: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  IFileTypeLinkDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function ActionType: IActionTypeDictionary;
    function FileType_: IFileTypeDictionary;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  IFolderDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function ParentFolderID: TLinqProjection;
    function Title: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Expanded: TLinqProjection;
  end;

  IProjectDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Owner: IUserDictionary;
    function Title: TLinqProjection;
    function FileFolder: TLinqProjection;
    function Description: TLinqProjection;
    function StartDate: TLinqProjection;
    function EndDate: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Expanded: TLinqProjection;
    function IsArchived: TLinqProjection;
  end;

  IUserDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Username: TLinqProjection;
    function Password: TLinqProjection;
    function FirstName: TLinqProjection;
    function LastName: TLinqProjection;
    function Email: TLinqProjection;
    function Role: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function IsArchived: TLinqProjection;
  end;

  IUserRoleDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Role: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function ProjectID: IProjectDictionary;
    function UserID: IUserDictionary;
  end;

  IUsersHistoryDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function LastProject: TLinqProjection;
    function LastFolder: TLinqProjection;
    function LastItem: TLinqProjection;
    function LastChild: TLinqProjection;
    function UserID: TLinqProjection;
  end;

  IProtocolStatusChangeDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function ProtocolId: TLinqProjection;
    function OldStatus: TLinqProjection;
    function NewStatus: TLinqProjection;
    function ChangedBy: TLinqProjection;
    function ChangedDate: TLinqProjection;
    function Comment: TLinqProjection;
  end;

  IAuditLogDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function EntityType: TLinqProjection;
    function EntityId: TLinqProjection;
    function Operation: TLinqProjection;
    function UserId: TLinqProjection;
    function Timestamp: TLinqProjection;
    function Description: TLinqProjection;
  end;

  ISignatureDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function ItemId: TLinqProjection;
    function UserId: TLinqProjection;
    function UserName: TLinqProjection;
    function SignedDate: TLinqProjection;
    function Meaning: TLinqProjection;
    function Comment: TLinqProjection;
    function ContentHash: TLinqProjection;
  end;

  IProjectPermissionDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Project: IProjectDictionary;
    function User: IUserDictionary;
    function AccessLevel: TLinqProjection;
    function GrantedBy: TLinqProjection;
    function GrantedDate: TLinqProjection;
  end;

  IFavoriteDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function UserId: TLinqProjection;
    function ProjectId: TLinqProjection;
    function FolderId: TLinqProjection;
    function ItemId: TLinqProjection;
    function FavoriteType: TLinqProjection;
    function Title: TLinqProjection;
    function CreatedDate: TLinqProjection;
  end;

  ITagDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Name: TLinqProjection;
    function Color: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function CreatedDate: TLinqProjection;
  end;

  IItemTagDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function ItemId: TLinqProjection;
    function TagId: TLinqProjection;
    function CreatedDate: TLinqProjection;
  end;

  ICommentDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function ItemId: TLinqProjection;
    function UserId: TLinqProjection;
    function UserName: TLinqProjection;
    function Text: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
  end;

  IExperimentTemplateDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function Name: TLinqProjection;
    function Description: TLinqProjection;
    function Category: TLinqProjection;
    function StructureJSON: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
  end;

  IItemLinkDictionary = interface(IAureliusEntityDictionary)
    function Id: TLinqProjection;
    function SourceItemId: TLinqProjection;
    function TargetItemId: TLinqProjection;
    function Label_: TLinqProjection;
    function Notes: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function CreatedDate: TLinqProjection;
  end;

  TTemplateDictionary = class(TAureliusEntityDictionary, ITemplateDictionary)
  public
    function Id: TLinqProjection;
    function Name: TLinqProjection;
    function Description: TLinqProjection;
    function Category: TLinqProjection;
    function IsActive: TLinqProjection;
    function FormSchema: TLinqProjection;
    function Version: TLinqProjection;
    function ParentId: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
  end;

  TLabEntryDictionary = class(TAureliusEntityDictionary, ILabEntryDictionary)
  public
    function Id: TLinqProjection;
    function Title: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  TProtocolDictionary = class(TLabEntryDictionary, IProtocolDictionary)
  public
    function TemplateId: TLinqProjection;
    function FormData: TLinqProjection;
    function ProtocolType: TLinqProjection;
    function ValidationStatus: TLinqProjection;
  end;

  TActionTypeDictionary = class(TAureliusEntityDictionary, IActionTypeDictionary)
  public
    function Id: TLinqProjection;
    function Kind: TLinqProjection;
    function ItemType: TLinqProjection;
    function Title: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Equipmenttypeid: IEquipmentTypeDictionary;
  end;

  TValueTypeDictionary = class(TAureliusEntityDictionary, IValueTypeDictionary)
  public
    function Id: TLinqProjection;
    function Title: TLinqProjection;
    function Units: TLinqProjection;
    function CatID: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  TValueDictionary = class(TAureliusEntityDictionary, IValueDictionary)
  public
    function Id: TLinqProjection;
    function Typeid: IValueTypeDictionary;
    function RecType: TLinqProjection;
    function Value: TLinqProjection;
    function Tol: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  TItemDictionary = class(TAureliusEntityDictionary, IItemDictionary)
  public
    function ID: TLinqProjection;
    function ProjectID: TLinqProjection;
    function FolderID: TLinqProjection;
    function Level: TLinqProjection;
    function Type_: TLinqProjection;
    function Title: TLinqProjection;
    function Description: TLinqProjection;
    function ParentID:  TLinqProjection;
    function ActionType: IActionTypeDictionary;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Expanded: TLinqProjection;
    function SortOrder: TLinqProjection;
    function IsDeleted: TLinqProjection;
    function DeletedDate: TLinqProjection;
    function DeletedBy: TLinqProjection;
  end;

  TEquipmentDictionary = class(TAureliusEntityDictionary, IEquipmentDictionary)
  public
    function Id: TLinqProjection;
    function Model: TLinqProjection;
    function Manufacturer: TLinqProjection;
    function Location: TLinqProjection;
    function BookingUrl: TLinqProjection;
    function InfoUrl: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Equipmenttypeid: IEquipmentTypeDictionary;
  end;

  TEquipmentTypeDictionary = class(TAureliusEntityDictionary, IEquipmentTypeDictionary)
  public
    function Id: TLinqProjection;
    function Type_: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  TFileDictionary = class(TAureliusEntityDictionary, IFileDictionary)
  public
    function Id: TLinqProjection;
    function Description: TLinqProjection;
    function Title: TLinqProjection;
    function Hash: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Typeid: IFileTypeDictionary;
    function Itemid: IItemDictionary;
  end;

  TFileTypeDictionary = class(TAureliusEntityDictionary, IFileTypeDictionary)
  public
    function Id: TLinqProjection;
    function Ext: TLinqProjection;
    function Icon: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  TFileTypeLinkDictionary = class(TAureliusEntityDictionary, IFileTypeLinkDictionary)
  public
    function Id: TLinqProjection;
    function ActionType: IActionTypeDictionary;
    function FileType_: IFileTypeDictionary;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
  end;

  TFolderDictionary = class(TAureliusEntityDictionary, IFolderDictionary)
  public
    function Id: TLinqProjection;
    function ParentFolderID: TLinqProjection;
    function Title: TLinqProjection;
    function Description: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Expanded: TLinqProjection;
  end;

  TProjectDictionary = class(TAureliusEntityDictionary, IProjectDictionary)
  public
    function Id: TLinqProjection;
    function Owner: IUserDictionary;
    function Title: TLinqProjection;
    function FileFolder: TLinqProjection;
    function Description: TLinqProjection;
    function StartDate: TLinqProjection;
    function EndDate: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function Expanded: TLinqProjection;
    function IsArchived: TLinqProjection;
  end;

  TUserDictionary = class(TAureliusEntityDictionary, IUserDictionary)
  public
    function Id: TLinqProjection;
    function Username: TLinqProjection;
    function Password: TLinqProjection;
    function FirstName: TLinqProjection;
    function LastName: TLinqProjection;
    function Email: TLinqProjection;
    function Role: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function IsArchived: TLinqProjection;
  end;

  TUserRoleDictionary = class(TAureliusEntityDictionary, IUserRoleDictionary)
  public
    function Id: TLinqProjection;
    function Role: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function ModifiedBy: TLinqProjection;
    function ProjectID: IProjectDictionary;
    function UserID: IUserDictionary;
  end;

  TUsersHistoryDictionary = class(TAureliusEntityDictionary, IUsersHistoryDictionary)
  public
    function Id: TLinqProjection;
    function LastProject: TLinqProjection;
    function LastFolder: TLinqProjection;
    function LastItem: TLinqProjection;
    function LastChild: TLinqProjection;
    function UserID: TLinqProjection;
  end;

  TProtocolStatusChangeDictionary = class(TAureliusEntityDictionary, IProtocolStatusChangeDictionary)
  public
    function Id: TLinqProjection;
    function ProtocolId: TLinqProjection;
    function OldStatus: TLinqProjection;
    function NewStatus: TLinqProjection;
    function ChangedBy: TLinqProjection;
    function ChangedDate: TLinqProjection;
    function Comment: TLinqProjection;
  end;

  TAuditLogDictionary = class(TAureliusEntityDictionary, IAuditLogDictionary)
  public
    function Id: TLinqProjection;
    function EntityType: TLinqProjection;
    function EntityId: TLinqProjection;
    function Operation: TLinqProjection;
    function UserId: TLinqProjection;
    function Timestamp: TLinqProjection;
    function Description: TLinqProjection;
  end;

  TSignatureDictionary = class(TAureliusEntityDictionary, ISignatureDictionary)
  public
    function Id: TLinqProjection;
    function ItemId: TLinqProjection;
    function UserId: TLinqProjection;
    function UserName: TLinqProjection;
    function SignedDate: TLinqProjection;
    function Meaning: TLinqProjection;
    function Comment: TLinqProjection;
    function ContentHash: TLinqProjection;
  end;

  TProjectPermissionDictionary = class(TAureliusEntityDictionary, IProjectPermissionDictionary)
  public
    function Id: TLinqProjection;
    function Project: IProjectDictionary;
    function User: IUserDictionary;
    function AccessLevel: TLinqProjection;
    function GrantedBy: TLinqProjection;
    function GrantedDate: TLinqProjection;
  end;

  TFavoriteDictionary = class(TAureliusEntityDictionary, IFavoriteDictionary)
  public
    function Id: TLinqProjection;
    function UserId: TLinqProjection;
    function ProjectId: TLinqProjection;
    function FolderId: TLinqProjection;
    function ItemId: TLinqProjection;
    function FavoriteType: TLinqProjection;
    function Title: TLinqProjection;
    function CreatedDate: TLinqProjection;
  end;

  TTagDictionary = class(TAureliusEntityDictionary, ITagDictionary)
  public
    function Id: TLinqProjection;
    function Name: TLinqProjection;
    function Color: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function CreatedDate: TLinqProjection;
  end;

  TItemTagDictionary = class(TAureliusEntityDictionary, IItemTagDictionary)
  public
    function Id: TLinqProjection;
    function ItemId: TLinqProjection;
    function TagId: TLinqProjection;
    function CreatedDate: TLinqProjection;
  end;

  TCommentDictionary = class(TAureliusEntityDictionary, ICommentDictionary)
  public
    function Id: TLinqProjection;
    function ItemId: TLinqProjection;
    function UserId: TLinqProjection;
    function UserName: TLinqProjection;
    function Text: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
  end;

  TExperimentTemplateDictionary = class(TAureliusEntityDictionary, IExperimentTemplateDictionary)
  public
    function Id: TLinqProjection;
    function Name: TLinqProjection;
    function Description: TLinqProjection;
    function Category: TLinqProjection;
    function StructureJSON: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function CreatedDate: TLinqProjection;
    function ModifiedDate: TLinqProjection;
  end;

  TItemLinkDictionary = class(TAureliusEntityDictionary, IItemLinkDictionary)
  public
    function Id: TLinqProjection;
    function SourceItemId: TLinqProjection;
    function TargetItemId: TLinqProjection;
    function Label_: TLinqProjection;
    function Notes: TLinqProjection;
    function CreatedBy: TLinqProjection;
    function CreatedDate: TLinqProjection;
  end;

  TViewerStateDictionary = class(TAureliusEntityDictionary)
  public
    function Id: TLinqProjection;
    function UserId: TLinqProjection;
    function FileId: TLinqProjection;
    function PluginName: TLinqProjection;
    function StateData: TLinqProjection;
    function UpdatedDate: TLinqProjection;
  end;

  IDictionary = interface(IAureliusDictionary)
    function Template: ITemplateDictionary;
    function LabEntry: ILabEntryDictionary;
    function Protocol: IProtocolDictionary;
    function ActionType: IActionTypeDictionary;
    function ValueType: IValueTypeDictionary;
    function Value_: IValueDictionary;
    function Item: IItemDictionary;
    function Equipment: IEquipmentDictionary;
    function EquipmentType: IEquipmentTypeDictionary;
    function File_: IFileDictionary;
    function FileType: IFileTypeDictionary;
    function FileTypeLink: IFileTypeLinkDictionary;
    function Folder: IFolderDictionary;
    function Project: IProjectDictionary;
    function User: IUserDictionary;
    function UserRole: IUserRoleDictionary;
    function UsersHistory: IUsersHistoryDictionary;
    function ProtocolStatusChange: IProtocolStatusChangeDictionary;
    function AuditLog: IAuditLogDictionary;
    function Signature: ISignatureDictionary;
    function ProjectPermission: IProjectPermissionDictionary;
    function Favorite: IFavoriteDictionary;
    function Tag: ITagDictionary;
    function ItemTag: IItemTagDictionary;
    function Comment: ICommentDictionary;
    function ExperimentTemplate: IExperimentTemplateDictionary;
    function ItemLink: IItemLinkDictionary;
  end;

  TDictionary = class(TAureliusDictionary, IDictionary)
  public
    function Template: ITemplateDictionary;
    function LabEntry: ILabEntryDictionary;
    function Protocol: IProtocolDictionary;
    function ActionType: IActionTypeDictionary;
    function ValueType: IValueTypeDictionary;
    function Value_: IValueDictionary;
    function Item: IItemDictionary;
    function Equipment: IEquipmentDictionary;
    function EquipmentType: IEquipmentTypeDictionary;
    function File_: IFileDictionary;
    function FileType: IFileTypeDictionary;
    function FileTypeLink: IFileTypeLinkDictionary;
    function Folder: IFolderDictionary;
    function Project: IProjectDictionary;
    function User: IUserDictionary;
    function UserRole: IUserRoleDictionary;
    function UsersHistory: IUsersHistoryDictionary;
    function ProtocolStatusChange: IProtocolStatusChangeDictionary;
    function AuditLog: IAuditLogDictionary;
    function Signature: ISignatureDictionary;
    function ProjectPermission: IProjectPermissionDictionary;
    function Favorite: IFavoriteDictionary;
    function Tag: ITagDictionary;
    function ItemTag: IItemTagDictionary;
    function Comment: ICommentDictionary;
    function ExperimentTemplate: IExperimentTemplateDictionary;
    function ItemLink: IItemLinkDictionary;
  end;

function ELNDB3_DICT: IDictionary;

implementation

var
  __ELNDB3_DICT: IDictionary;

function ELNDB3_DICT: IDictionary;
begin
  if not Assigned(__ELNDB3_DICT) then __ELNDB3_DICT := TDictionary.Create;
  result := __ELNDB3_DICT;
end;


function TTemplateDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TTemplateDictionary.Name: TLinqProjection;
begin
  Result := Prop('Name');
end;

function TTemplateDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TTemplateDictionary.Category: TLinqProjection;
begin
  Result := Prop('Category');
end;

function TTemplateDictionary.IsActive: TLinqProjection;
begin
  Result := Prop('IsActive');
end;

function TTemplateDictionary.FormSchema: TLinqProjection;
begin
  Result := Prop('FormSchema');
end;

function TTemplateDictionary.Version: TLinqProjection;
begin
  Result := Prop('Version');
end;

function TTemplateDictionary.ParentId: TLinqProjection;
begin
  Result := Prop('ParentId');
end;

function TTemplateDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TTemplateDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;


function TLabEntryDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TLabEntryDictionary.Title: TLinqProjection;
begin
  Result := Prop('Title');
end;

function TLabEntryDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TLabEntryDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TLabEntryDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TLabEntryDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;


function TProtocolDictionary.TemplateId: TLinqProjection;
begin
  Result := Prop('TemplateId');
end;

function TProtocolDictionary.FormData: TLinqProjection;
begin
  Result := Prop('FormData');
end;

function TProtocolDictionary.ProtocolType: TLinqProjection;
begin
  Result := Prop('ProtocolType');
end;

function TProtocolDictionary.ValidationStatus: TLinqProjection;
begin
  Result := Prop('ValidationStatus');
end;


function TActionTypeDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TActionTypeDictionary.Kind: TLinqProjection;
begin
  Result := Prop('Kind');
end;

function TActionTypeDictionary.ItemType: TLinqProjection;
begin
  Result := Prop('ItemType');
end;

function TActionTypeDictionary.Title: TLinqProjection;
begin
  Result := Prop('Title');
end;

function TActionTypeDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TActionTypeDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TActionTypeDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TActionTypeDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TActionTypeDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;

function TActionTypeDictionary.Equipmenttypeid: IEquipmentTypeDictionary;
begin
  Result := TEquipmentTypeDictionary.Create(PropName('EquipmentType'));
end;


function TValueTypeDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TValueTypeDictionary.Title: TLinqProjection;
begin
  Result := Prop('Title');
end;

function TValueTypeDictionary.Units: TLinqProjection;
begin
  Result := Prop('Units');
end;

function TValueTypeDictionary.CatID: TLinqProjection;
begin
  Result := Prop('CatID');
end;

function TValueTypeDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TValueTypeDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TValueTypeDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TValueTypeDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TValueTypeDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;


function TValueDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TValueDictionary.Typeid: IValueTypeDictionary;
begin
  Result := TValueTypeDictionary.Create(PropName('ValueType'));
end;

function TValueDictionary.RecType: TLinqProjection;
begin
  Result := Prop('RecType');
end;

function TValueDictionary.Value: TLinqProjection;
begin
  Result := Prop('Value');
end;

function TValueDictionary.Tol: TLinqProjection;
begin
  Result := Prop('Tol');
end;

function TValueDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TValueDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TValueDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TValueDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TValueDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;


function TItemDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TItemDictionary.ProjectID: TLinqProjection;
begin
  Result := Prop('ProjectID');
end;

function TItemDictionary.FolderID: TLinqProjection;
begin
  Result := Prop('FolderID');
end;

function TItemDictionary.Level: TLinqProjection;
begin
  Result := Prop('Level');
end;

function TItemDictionary.Type_: TLinqProjection;
begin
  Result := Prop('Type_');
end;

function TItemDictionary.Title: TLinqProjection;
begin
  Result := Prop('Title');
end;

function TItemDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TItemDictionary.ParentID: TLinqProjection;
begin
  Result := Prop('ParentID');
end;

function TItemDictionary.ActionType: IActionTypeDictionary;
begin
  Result := TActionTypeDictionary.Create(PropName('ActionType'));
end;

function TItemDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TItemDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TItemDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TItemDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;

function TItemDictionary.Expanded: TLinqProjection;
begin
  Result := Prop('Expanded');
end;

function TItemDictionary.SortOrder: TLinqProjection;
begin
  Result := Prop('SortOrder');
end;

function TItemDictionary.IsDeleted: TLinqProjection;
begin
  Result := Prop('IsDeleted');
end;

function TItemDictionary.DeletedDate: TLinqProjection;
begin
  Result := Prop('DeletedDate');
end;

function TItemDictionary.DeletedBy: TLinqProjection;
begin
  Result := Prop('DeletedBy');
end;


function TEquipmentDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TEquipmentDictionary.Model: TLinqProjection;
begin
  Result := Prop('Model');
end;

function TEquipmentDictionary.Manufacturer: TLinqProjection;
begin
  Result := Prop('Manufacturer');
end;

function TEquipmentDictionary.Location: TLinqProjection;
begin
  Result := Prop('Location');
end;

function TEquipmentDictionary.BookingUrl: TLinqProjection;
begin
  Result := Prop('BookingUrl');
end;

function TEquipmentDictionary.InfoUrl: TLinqProjection;
begin
  Result := Prop('InfoUrl');
end;

function TEquipmentDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TEquipmentDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TEquipmentDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TEquipmentDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TEquipmentDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;

function TEquipmentDictionary.Equipmenttypeid: IEquipmentTypeDictionary;
begin
  Result := TEquipmentTypeDictionary.Create(PropName('EquipmentType'));
end;


function TEquipmentTypeDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TEquipmentTypeDictionary.Type_: TLinqProjection;
begin
  Result := Prop('Type_');
end;

function TEquipmentTypeDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TEquipmentTypeDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TEquipmentTypeDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TEquipmentTypeDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TEquipmentTypeDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;


function TFileDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TFileDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TFileDictionary.Title: TLinqProjection;
begin
  Result := Prop('Title');
end;

function TFileDictionary.Hash: TLinqProjection;
begin
  Result := Prop('Hash');
end;

function TFileDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TFileDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TFileDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TFileDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;

function TFileDictionary.Typeid: IFileTypeDictionary;
begin
  Result := TFileTypeDictionary.Create(PropName('FileType'));
end;

function TFileDictionary.Itemid: IItemDictionary;
begin
  Result := TItemDictionary.Create(PropName('Item'));
end;


function TFileTypeDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TFileTypeDictionary.Ext: TLinqProjection;
begin
  Result := Prop('Ext');
end;

function TFileTypeDictionary.Icon: TLinqProjection;
begin
  Result := Prop('Icon');
end;

function TFileTypeDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TFileTypeDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TFileTypeDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TFileTypeDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TFileTypeDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;


function TFileTypeLinkDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TFileTypeLinkDictionary.ActionType: IActionTypeDictionary;
begin
  Result := TActionTypeDictionary.Create(PropName('ActionType'));
end;

function TFileTypeLinkDictionary.FileType_: IFileTypeDictionary;
begin
  Result := TFileTypeDictionary.Create(PropName('FileType'));
end;

function TFileTypeLinkDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TFileTypeLinkDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TFileTypeLinkDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TFileTypeLinkDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;


function TFolderDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TFolderDictionary.ParentFolderID: TLinqProjection;
begin
  Result := Prop('ParentFolderID');
end;

function TFolderDictionary.Title: TLinqProjection;
begin
  Result := Prop('Title');
end;

function TFolderDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TFolderDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TFolderDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TFolderDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TFolderDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;

function TFolderDictionary.Expanded: TLinqProjection;
begin
  Result := Prop('Expanded');
end;


function TProjectDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TProjectDictionary.Owner: IUserDictionary;
begin
  Result := TUserDictionary.Create(PropName('Owner'));
end;

function TProjectDictionary.Title: TLinqProjection;
begin
  Result := Prop('Title');
end;

function TProjectDictionary.FileFolder: TLinqProjection;
begin
  Result := Prop('FileFolder');
end;

function TProjectDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TProjectDictionary.StartDate: TLinqProjection;
begin
  Result := Prop('StartDate');
end;

function TProjectDictionary.EndDate: TLinqProjection;
begin
  Result := Prop('EndDate');
end;

function TProjectDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TProjectDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TProjectDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TProjectDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;

function TProjectDictionary.Expanded: TLinqProjection;
begin
  Result := Prop('Expanded');
end;

function TProjectDictionary.IsArchived: TLinqProjection;
begin
  Result := Prop('IsArchived');
end;


function TUserDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TUserDictionary.Username: TLinqProjection;
begin
  Result := Prop('Username');
end;

function TUserDictionary.Password: TLinqProjection;
begin
  Result := Prop('Password');
end;

function TUserDictionary.FirstName: TLinqProjection;
begin
  Result := Prop('FirstName');
end;

function TUserDictionary.LastName: TLinqProjection;
begin
  Result := Prop('LastName');
end;

function TUserDictionary.Email: TLinqProjection;
begin
  Result := Prop('Email');
end;

function TUserDictionary.Role: TLinqProjection;
begin
  Result := Prop('Role');
end;

function TUserDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TUserDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TUserDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TUserDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;

function TUserDictionary.IsArchived: TLinqProjection;
begin
  Result := Prop('IsArchived');
end;


function TUserRoleDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TUserRoleDictionary.Role: TLinqProjection;
begin
  Result := Prop('Role');
end;

function TUserRoleDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TUserRoleDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;

function TUserRoleDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TUserRoleDictionary.ModifiedBy: TLinqProjection;
begin
  Result := Prop('ModifiedBy');
end;

function TUserRoleDictionary.ProjectID: IProjectDictionary;
begin
  Result := TProjectDictionary.Create(PropName('Project'));
end;

function TUserRoleDictionary.UserID: IUserDictionary;
begin
  Result := TUserDictionary.Create(PropName('User'));
end;


function TUsersHistoryDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TUsersHistoryDictionary.LastProject: TLinqProjection;
begin
  Result := Prop('LastProject');
end;

function TUsersHistoryDictionary.LastFolder: TLinqProjection;
begin
  Result := Prop('LastFolder');
end;

function TUsersHistoryDictionary.LastItem: TLinqProjection;
begin
  Result := Prop('LastItem');
end;

function TUsersHistoryDictionary.LastChild: TLinqProjection;
begin
  Result := Prop('LastChild');
end;

function TUsersHistoryDictionary.UserID: TLinqProjection;
begin
  Result := Prop('UserID');
end;


function TDictionary.Template: ITemplateDictionary;
begin
  Result := TTemplateDictionary.Create;
end;

function TDictionary.LabEntry: ILabEntryDictionary;
begin
  Result := TLabEntryDictionary.Create;
end;

function TDictionary.Protocol: IProtocolDictionary;
begin
  Result := TProtocolDictionary.Create;
end;

function TDictionary.ActionType: IActionTypeDictionary;
begin
  Result := TActionTypeDictionary.Create;
end;

function TDictionary.ValueType: IValueTypeDictionary;
begin
  Result := TValueTypeDictionary.Create;
end;

function TDictionary.Value_: IValueDictionary;
begin
  Result := TValueDictionary.Create;
end;

function TDictionary.Item: IItemDictionary;
begin
  Result := TItemDictionary.Create;
end;

function TDictionary.Equipment: IEquipmentDictionary;
begin
  Result := TEquipmentDictionary.Create;
end;

function TDictionary.EquipmentType: IEquipmentTypeDictionary;
begin
  Result := TEquipmentTypeDictionary.Create;
end;

function TDictionary.File_: IFileDictionary;
begin
  Result := TFileDictionary.Create;
end;

function TDictionary.FileType: IFileTypeDictionary;
begin
  Result := TFileTypeDictionary.Create;
end;

function TDictionary.FileTypeLink: IFileTypeLinkDictionary;
begin
  Result := TFileTypeLinkDictionary.Create;
end;

function TDictionary.Folder: IFolderDictionary;
begin
  Result := TFolderDictionary.Create;
end;

function TDictionary.Project: IProjectDictionary;
begin
  Result := TProjectDictionary.Create;
end;

function TDictionary.User: IUserDictionary;
begin
  Result := TUserDictionary.Create;
end;

function TDictionary.UserRole: IUserRoleDictionary;
begin
  Result := TUserRoleDictionary.Create;
end;

function TDictionary.UsersHistory: IUsersHistoryDictionary;
begin
  Result := TUsersHistoryDictionary.Create;
end;

function TDictionary.ProtocolStatusChange: IProtocolStatusChangeDictionary;
begin
  Result := TProtocolStatusChangeDictionary.Create;
end;


function TProtocolStatusChangeDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TProtocolStatusChangeDictionary.ProtocolId: TLinqProjection;
begin
  Result := Prop('ProtocolId');
end;

function TProtocolStatusChangeDictionary.OldStatus: TLinqProjection;
begin
  Result := Prop('OldStatus');
end;

function TProtocolStatusChangeDictionary.NewStatus: TLinqProjection;
begin
  Result := Prop('NewStatus');
end;

function TProtocolStatusChangeDictionary.ChangedBy: TLinqProjection;
begin
  Result := Prop('ChangedBy');
end;

function TProtocolStatusChangeDictionary.ChangedDate: TLinqProjection;
begin
  Result := Prop('ChangedDate');
end;

function TProtocolStatusChangeDictionary.Comment: TLinqProjection;
begin
  Result := Prop('Comment');
end;


function TAuditLogDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TAuditLogDictionary.EntityType: TLinqProjection;
begin
  Result := Prop('EntityType');
end;

function TAuditLogDictionary.EntityId: TLinqProjection;
begin
  Result := Prop('EntityId');
end;

function TAuditLogDictionary.Operation: TLinqProjection;
begin
  Result := Prop('Operation');
end;

function TAuditLogDictionary.UserId: TLinqProjection;
begin
  Result := Prop('UserId');
end;

function TAuditLogDictionary.Timestamp: TLinqProjection;
begin
  Result := Prop('Timestamp');
end;

function TAuditLogDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TDictionary.AuditLog: IAuditLogDictionary;
begin
  Result := TAuditLogDictionary.Create;
end;

function TDictionary.Signature: ISignatureDictionary;
begin
  Result := TSignatureDictionary.Create;
end;

function TDictionary.ProjectPermission: IProjectPermissionDictionary;
begin
  Result := TProjectPermissionDictionary.Create;
end;


function TSignatureDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TSignatureDictionary.ItemId: TLinqProjection;
begin
  Result := Prop('ItemId');
end;

function TSignatureDictionary.UserId: TLinqProjection;
begin
  Result := Prop('UserId');
end;

function TSignatureDictionary.UserName: TLinqProjection;
begin
  Result := Prop('UserName');
end;

function TSignatureDictionary.SignedDate: TLinqProjection;
begin
  Result := Prop('SignedDate');
end;

function TSignatureDictionary.Meaning: TLinqProjection;
begin
  Result := Prop('Meaning');
end;

function TSignatureDictionary.Comment: TLinqProjection;
begin
  Result := Prop('Comment');
end;

function TSignatureDictionary.ContentHash: TLinqProjection;
begin
  Result := Prop('ContentHash');
end;


function TProjectPermissionDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TProjectPermissionDictionary.Project: IProjectDictionary;
begin
  Result := TProjectDictionary.Create(PropName('Project'));
end;

function TProjectPermissionDictionary.User: IUserDictionary;
begin
  Result := TUserDictionary.Create(PropName('User'));
end;

function TProjectPermissionDictionary.AccessLevel: TLinqProjection;
begin
  Result := Prop('AccessLevel');
end;

function TProjectPermissionDictionary.GrantedBy: TLinqProjection;
begin
  Result := Prop('GrantedBy');
end;

function TProjectPermissionDictionary.GrantedDate: TLinqProjection;
begin
  Result := Prop('GrantedDate');
end;


function TFavoriteDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TFavoriteDictionary.UserId: TLinqProjection;
begin
  Result := Prop('UserId');
end;

function TFavoriteDictionary.ProjectId: TLinqProjection;
begin
  Result := Prop('ProjectId');
end;

function TFavoriteDictionary.FolderId: TLinqProjection;
begin
  Result := Prop('FolderId');
end;

function TFavoriteDictionary.ItemId: TLinqProjection;
begin
  Result := Prop('ItemId');
end;

function TFavoriteDictionary.FavoriteType: TLinqProjection;
begin
  Result := Prop('FavoriteType');
end;

function TFavoriteDictionary.Title: TLinqProjection;
begin
  Result := Prop('Title');
end;

function TFavoriteDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TDictionary.Favorite: IFavoriteDictionary;
begin
  Result := TFavoriteDictionary.Create;
end;

function TDictionary.Tag: ITagDictionary;
begin
  Result := TTagDictionary.Create;
end;

function TDictionary.ItemTag: IItemTagDictionary;
begin
  Result := TItemTagDictionary.Create;
end;

function TDictionary.Comment: ICommentDictionary;
begin
  Result := TCommentDictionary.Create;
end;

function TDictionary.ExperimentTemplate: IExperimentTemplateDictionary;
begin
  Result := TExperimentTemplateDictionary.Create;
end;


function TTagDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TTagDictionary.Name: TLinqProjection;
begin
  Result := Prop('Name');
end;

function TTagDictionary.Color: TLinqProjection;
begin
  Result := Prop('Color');
end;

function TTagDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TTagDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;


function TItemTagDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TItemTagDictionary.ItemId: TLinqProjection;
begin
  Result := Prop('ItemId');
end;

function TItemTagDictionary.TagId: TLinqProjection;
begin
  Result := Prop('TagId');
end;

function TItemTagDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;


function TCommentDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TCommentDictionary.ItemId: TLinqProjection;
begin
  Result := Prop('ItemId');
end;

function TCommentDictionary.UserId: TLinqProjection;
begin
  Result := Prop('UserId');
end;

function TCommentDictionary.UserName: TLinqProjection;
begin
  Result := Prop('UserName');
end;

function TCommentDictionary.Text: TLinqProjection;
begin
  Result := Prop('Text');
end;

function TCommentDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TCommentDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;


function TExperimentTemplateDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TExperimentTemplateDictionary.Name: TLinqProjection;
begin
  Result := Prop('Name');
end;

function TExperimentTemplateDictionary.Description: TLinqProjection;
begin
  Result := Prop('Description');
end;

function TExperimentTemplateDictionary.Category: TLinqProjection;
begin
  Result := Prop('Category');
end;

function TExperimentTemplateDictionary.StructureJSON: TLinqProjection;
begin
  Result := Prop('StructureJSON');
end;

function TExperimentTemplateDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TExperimentTemplateDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TExperimentTemplateDictionary.ModifiedDate: TLinqProjection;
begin
  Result := Prop('ModifiedDate');
end;


function TItemLinkDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TItemLinkDictionary.SourceItemId: TLinqProjection;
begin
  Result := Prop('SourceItemId');
end;

function TItemLinkDictionary.TargetItemId: TLinqProjection;
begin
  Result := Prop('TargetItemId');
end;

function TItemLinkDictionary.Label_: TLinqProjection;
begin
  Result := Prop('Label_');
end;

function TItemLinkDictionary.Notes: TLinqProjection;
begin
  Result := Prop('Notes');
end;

function TItemLinkDictionary.CreatedBy: TLinqProjection;
begin
  Result := Prop('CreatedBy');
end;

function TItemLinkDictionary.CreatedDate: TLinqProjection;
begin
  Result := Prop('CreatedDate');
end;

function TDictionary.ItemLink: IItemLinkDictionary;
begin
  Result := TItemLinkDictionary.Create;
end;


function TViewerStateDictionary.Id: TLinqProjection;
begin
  Result := Prop('Id');
end;

function TViewerStateDictionary.UserId: TLinqProjection;
begin
  Result := Prop('UserId');
end;

function TViewerStateDictionary.FileId: TLinqProjection;
begin
  Result := Prop('FileId');
end;

function TViewerStateDictionary.PluginName: TLinqProjection;
begin
  Result := Prop('PluginName');
end;

function TViewerStateDictionary.StateData: TLinqProjection;
begin
  Result := Prop('StateData');
end;

function TViewerStateDictionary.UpdatedDate: TLinqProjection;
begin
  Result := Prop('UpdatedDate');
end;

end.
