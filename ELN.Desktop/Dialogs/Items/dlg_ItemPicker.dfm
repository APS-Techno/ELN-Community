object dlgItemPicker: TdlgItemPicker
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Select Item'
  ClientHeight = 393
  ClientWidth = 444
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object Tree: TVirtualStringTree
    Left = 12
    Top = 12
    Width = 420
    Height = 300
    Anchors = [akLeft, akTop, akRight, akBottom]
    TabOrder = 0
    TreeOptions.PaintOptions = [toShowButtons, toShowDropmark, toShowRoot, toShowTreeLines, toThemeAware, toUseBlendedImages, toUseBlendedSelection, toUseExplorerTheme]
    TreeOptions.SelectionOptions = [toFullRowSelect]
    OnChange = TreeChange
    OnGetText = TreeGetText
    OnGetNodeDataSize = TreeGetNodeDataSize
    Columns = <>
  end
  object cbLink: TCheckBox
    Left = 12
    Top = 326
    Width = 200
    Height = 20
    Anchors = [akLeft, akBottom]
    Caption = 'Link to original'
    Checked = True
    State = cbChecked
    TabOrder = 1
    Visible = False
    OnClick = cbLinkClick
  end
  object btnOK: TButton
    Left = 270
    Top = 352
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'OK'
    Default = True
    Enabled = False
    TabOrder = 2
    OnClick = btnOKClick
  end
  object btnCancel: TButton
    Left = 354
    Top = 352
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 3
  end
end
