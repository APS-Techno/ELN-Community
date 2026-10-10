unit unit_UserTreeState;

{
  NodeKind: 0 seeded marker (NodeId 0), 1 project, 2 folder, 3 group,
  4 user node, 5 item - TTreeNodeKind in unit_TreeStateModel, in that order.
  No foreign keys (the kinds live in different tables): DB Maintenance's
  orphan report removes rows whose node or user is gone.
}

interface

uses
  Aurelius.Mapping.Attributes;

type
  [Entity]
  [Table('UserTreeState')]
  [UniqueKey('UserId,NodeKind,NodeId')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TUserTreeState = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('UserId', [TColumnProp.Required])]
    FUserId: Integer;

    [Column('NodeKind', [TColumnProp.Required])]
    FNodeKind: Integer;

    [Column('NodeId', [TColumnProp.Required])]
    FNodeId: Integer;

    [Column('Expanded', [TColumnProp.Required])]
    FExpanded: Boolean;
  public
    property Id: Integer read FId write FId;
    property UserId: Integer read FUserId write FUserId;
    property NodeKind: Integer read FNodeKind write FNodeKind;
    property NodeId: Integer read FNodeId write FNodeId;
    property Expanded: Boolean read FExpanded write FExpanded;
  end;

implementation

initialization
  RegisterEntity(TUserTreeState);

end.
