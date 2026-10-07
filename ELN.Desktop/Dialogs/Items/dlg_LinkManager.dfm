object dlgLinkManager: TdlgLinkManager
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Links'
  ClientHeight = 362
  ClientWidth = 700
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object lvLinks: TListView
    Left = 12
    Top = 12
    Width = 676
    Height = 288
    Anchors = [akLeft, akTop, akRight, akBottom]
    Columns = <
      item
        Caption = 'Relationship'
        Width = 130
      end
      item
        Caption = 'Item'
        Width = 170
      end
      item
        Caption = 'Project'
        Width = 120
      end
      item
        Caption = 'Notes'
        Width = 175
      end
      item
        Caption = 'Date'
        Width = 75
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
    OnDblClick = lvLinksDblClick
    OnSelectItem = lvLinksSelectItem
  end
  object btnAdd: TButton
    Left = 12
    Top = 313
    Width = 75
    Height = 25
    Anchors = [akLeft, akBottom]
    Caption = 'Add...'
    TabOrder = 1
    OnClick = btnAddClick
  end
  object btnEdit: TButton
    Left = 96
    Top = 313
    Width = 75
    Height = 25
    Anchors = [akLeft, akBottom]
    Caption = 'Edit...'
    Enabled = False
    TabOrder = 2
    OnClick = btnEditClick
  end
  object btnRemove: TButton
    Left = 180
    Top = 313
    Width = 75
    Height = 25
    Anchors = [akLeft, akBottom]
    Caption = 'Remove'
    Enabled = False
    TabOrder = 3
    OnClick = btnRemoveClick
  end
  object btnOpen: TButton
    Left = 264
    Top = 313
    Width = 75
    Height = 25
    Anchors = [akLeft, akBottom]
    Caption = 'Open'
    Enabled = False
    TabOrder = 4
    OnClick = btnOpenClick
  end
  object btnClose: TButton
    Left = 613
    Top = 313
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Close'
    ModalResult = 2
    TabOrder = 5
  end
end
