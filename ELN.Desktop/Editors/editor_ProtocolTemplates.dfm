object edTemplates: TedTemplates
  Left = 0
  Top = 0
  Caption = 'Template Manager'
  ClientHeight = 374
  ClientWidth = 635
  Color = clBtnFace
  ParentFont = True
  Position = poMainFormCenter
  TextHeight = 15
  object pnlBottom: TRzPanel
    Left = 0
    Top = 329
    Width = 635
    Height = 45
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object btnAdd: TRzButton
      Left = 16
      Top = 10
      Caption = 'Add'
      TabOrder = 0
      OnClick = btnAddClick
    end
    object btnEdit: TRzButton
      Left = 100
      Top = 10
      Caption = 'Edit'
      TabOrder = 1
      OnClick = btnEditClick
    end
    object btnDelete: TRzButton
      Left = 184
      Top = 10
      Caption = 'Delete'
      TabOrder = 2
      OnClick = btnDeleteClick
    end
    object btnDuplicate: TRzButton
      Left = 268
      Top = 10
      Caption = 'Duplicate'
      TabOrder = 3
      OnClick = btnDuplicateClick
    end
    object btnReimport: TRzButton
      Left = 352
      Top = 10
      Width = 80
      Caption = 'Reimport'
      TabOrder = 4
      OnClick = btnReimportClick
    end
    object btnClose: TRzButton
      Left = 551
      Top = 10
      Cancel = True
      ModalResult = 2
      Caption = 'Close'
      TabOrder = 5
    end
  end
  object lstTemplates: TListView
    Left = 0
    Top = 22
    Width = 635
    Height = 307
    Align = alClient
    Columns = <
      item
        Caption = 'Name'
        Width = 100
      end
      item
        Caption = 'Category'
        Width = 60
      end
      item
        Caption = 'Description'
        Width = 125
      end
      item
        Alignment = taCenter
        Caption = 'Ver'
        Width = 30
      end
      item
        Alignment = taCenter
        Caption = 'Active'
        Width = 40
      end
      item
        Caption = 'Created'
        Width = 90
      end>
    ReadOnly = True
    RowSelect = True
    TabOrder = 1
    ViewStyle = vsReport
    OnDblClick = btnEditClick
  end
  object chkAllVersions: TCheckBox
    Left = 0
    Top = 0
    Width = 635
    Height = 22
    Align = alTop
    Caption = '  Show all versions (including inactive)'
    TabOrder = 2
    OnClick = chkAllVersionsClick
  end
end
