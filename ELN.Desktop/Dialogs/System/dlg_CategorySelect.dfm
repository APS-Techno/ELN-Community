object dlgCategorySelect: TdlgCategorySelect
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Select Categories to Import'
  ClientHeight = 380
  ClientWidth = 300
  Color = clBtnFace
  ParentFont = True
  Position = poMainFormCenter
  TextHeight = 15
  object chkCategories: TCheckListBox
    Left = 0
    Top = 0
    Width = 300
    Height = 300
    Align = alClient
    TabOrder = 0
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 300
    Width = 300
    Height = 80
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object btnSelectAll: TRzButton
      Left = 12
      Top = 10
      Caption = 'Select All'
      TabOrder = 0
      OnClick = btnSelectAllClick
    end
    object btnSelectNone: TRzButton
      Left = 92
      Top = 10
      Caption = 'Select None'
      TabOrder = 1
      OnClick = btnSelectNoneClick
    end
    object chkOverwrite: TCheckBox
      Left = 180
      Top = 10
      Width = 110
      Height = 17
      Caption = 'Overwrite existing'
      TabOrder = 2
    end
    object btnOK: TRzButton
      Left = 128
      Top = 44
      Default = True
      ModalResult = 1
      Caption = 'Import'
      TabOrder = 3
    end
    object btnCancel: TRzButton
      Left = 212
      Top = 44
      Cancel = True
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 4
    end
  end
end
