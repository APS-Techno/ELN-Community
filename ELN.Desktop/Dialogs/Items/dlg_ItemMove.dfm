object dlgItemMove: TdlgItemMove
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Move Item'
  ClientHeight = 480
  ClientWidth = 400
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
    Width = 376
    Height = 420
    Anchors = [akLeft, akTop, akRight, akBottom]
    TabOrder = 0
    TreeOptions.PaintOptions = [toShowButtons, toShowDropmark, toShowRoot, toShowTreeLines, toThemeAware, toUseBlendedImages, toUseBlendedSelection, toUseExplorerTheme]
    TreeOptions.SelectionOptions = [toFullRowSelect]
    OnChange = TreeChange
    OnDblClick = TreeDblClick
    OnGetText = TreeGetText
    OnGetNodeDataSize = TreeGetNodeDataSize
    Columns = <>
  end
  object btnMove: TButton
    Left = 220
    Top = 444
    Width = 80
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'Move'
    Default = True
    Enabled = False
    ModalResult = 1
    TabOrder = 1
  end
  object btnCancel: TButton
    Left = 308
    Top = 444
    Width = 80
    Height = 25
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 2
  end
end
