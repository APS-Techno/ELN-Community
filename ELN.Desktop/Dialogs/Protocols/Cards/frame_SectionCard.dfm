object frSectionCard: TfrSectionCard
  Left = 0
  Top = 0
  Width = 320
  Height = 240
  Align = alClient
  TabOrder = 0
  object lblTitle: TRzLabel
    Left = 8
    Top = 8
    Width = 62
    Height = 13
    Caption = 'Section Title:'
  end
  object edtTitle: TRzEdit
    Left = 8
    Top = 24
    Width = 300
    Height = 21
    TabOrder = 0
    OnChange = edtTitleChange
  end
end
