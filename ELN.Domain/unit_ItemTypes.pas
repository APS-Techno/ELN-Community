unit unit_ItemTypes;

interface

uses
  Aurelius.Mapping.Attributes;

type
  [Enumeration(TEnumMappingType.emInteger)]
  TItemType = (Synthesis, Treatment, Measurement, Testing, Characterization, Computing, Specimen, Model, Other, Wiki);

  [Enumeration(TEnumMappingType.emInteger)]
  TItemLevel = (Proc, Item, Action, Folder);

  TItemLevels = set of TItemLevel;

  [Enumeration(TEnumMappingType.emInteger)]
  TRecType = (EXP_CONDITION, TEST_RESULT);

  [Enumeration(TEnumMappingType.emInteger)]
  TValueSourceKind = (vskUnknown, vskReader, vskManual);

implementation

end.
