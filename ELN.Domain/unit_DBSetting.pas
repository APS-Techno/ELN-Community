unit unit_DBSetting;

interface

uses
  Aurelius.Mapping.Attributes;

type
  [Entity]
  [Table('DBSettings')]
  [Id('FSettingKey', TIdGenerator.None)]
  TDBSetting = class
  private
    [Column('SettingKey', [TColumnProp.Required], 100)]
    FSettingKey: string;

    [Column('SettingValue', [], 2000)]
    FSettingValue: string;
  public
    property SettingKey: string read FSettingKey write FSettingKey;
    property SettingValue: string read FSettingValue write FSettingValue;
  end;

implementation

initialization
  RegisterEntity(TDBSetting);

end.
